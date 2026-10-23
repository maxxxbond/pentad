#!/usr/bin/env python3
"""Bounded Stash drop extraction and explicit image downloads. JSON in/out."""
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
import time
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

MAX_INPUT = 1024 * 1024
MAX_DOWNLOAD = 50 * 1024 * 1024

def web_url(value):
    if not isinstance(value, str) or len(value) > 8192 or re.search(r'[\s\x00-\x1f\x7f]', value):
        return ''
    try:
        parsed = urlsplit(value)
        if parsed.scheme.lower() in ('http', 'https') and parsed.hostname and not parsed.username and not parsed.password:
            _ = parsed.port
            return value
    except ValueError:
        pass
    return ''

def spotify_url(value):
    match = re.fullmatch(r'spotify:track:([a-zA-Z0-9]{22})', value.strip())
    return 'https://open.spotify.com/track/' + match[1] if match else ''

class DropHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.anchor = ''
        self.anchor_label = ''
        self.anchor_depth = 0
        self.anchor_text = []
        self.images = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'a' and not self.anchor:
            self.anchor = web_url(attrs.get('href', ''))
            self.anchor_label = attrs.get('aria-label', '')
            self.anchor_depth = 1
        elif tag == 'a' and self.anchor_depth:
            self.anchor_depth += 1
        if tag == 'img':
            self.images.append({key: attrs.get(key, '') for key in ('src', 'srcset', 'alt')})

    def handle_endtag(self, tag):
        if tag == 'a' and self.anchor_depth:
            self.anchor_depth -= 1

    def handle_data(self, data):
        if self.anchor_depth:
            self.anchor_text.append(data)

def image_candidates(srcset, base):
    candidates = []
    for chunk in srcset.split(','):
        parts = chunk.strip().split()
        if not parts or len(parts) > 2:
            continue
        url = web_url(urljoin(base, parts[0]))
        descriptor = parts[1] if len(parts) == 2 else '1x'
        match = re.fullmatch(r'(\d+(?:\.\d+)?)([wx])', descriptor)
        if url and match and float(match[1]) > 0:
            candidates.append((match[2], float(match[1]), url))
    if len({kind for kind, _, _ in candidates}) > 1:
        return []
    return sorted(candidates, key=lambda candidate: candidate[1], reverse=True)

def extract(offer):
    if not isinstance(offer, dict):
        raise ValueError('Invalid drop')
    html = DropHTML()
    html.feed(str(offer.get('html', '')))
    uri_lines = [line.strip() for line in str(offer.get('uris', '')).splitlines()
                 if line.strip() and not line.startswith('#')]
    netscape = str(offer.get('netscape', '')).splitlines()
    plain = str(offer.get('text', '')).strip()
    source = next((url for url in uri_lines if web_url(url)), '')
    source = source or html.anchor or (web_url(netscape[0]) if netscape else '') or web_url(plain)
    custom_spotify = str(offer.get('spotify', ''))
    if offer.get('spotifyHex'):
        custom_spotify = bytes.fromhex(offer['spotifyHex']).decode('utf-16-le').rstrip('\x00')
    source = source or spotify_url(custom_spotify) or spotify_url(plain)
    title = ' '.join(html.anchor_text).strip() or (netscape[1] if len(netscape) > 1 else '') or html.anchor_label
    for image in html.images:
        preview = web_url(urljoin(source, image['src']))
        candidates = image_candidates(image['srcset'], source)
        image_url = candidates[0][2] if candidates else preview
        preview = preview or image_url
        if preview and image_url:
            label = image['alt'].strip() or title or urlsplit(image_url).path.rsplit('/', 1)[-1] or 'Image'
            return {'ok': True, 'items': [{'kind': 'image', 'uri': source or image_url,
                    'label': label[:512], 'previewUrl': preview, 'imageUrl': image_url}]}
    if source:
        is_spotify = bool(re.fullmatch(r'https://open\.spotify\.com/track/[a-zA-Z0-9]{22}', source))
        label = title or ('Spotify track' if is_spotify else urlsplit(source).hostname)
        urls = [source] + [url for url in uri_lines if web_url(url) and url != source]
        return {'ok': True, 'items': [{'kind': 'spotify' if is_spotify and url == source else 'link',
                'uri': url, 'label': (label if url == source else urlsplit(url).hostname)[:512]}
                for url in dict.fromkeys(urls)]}
    if plain:
        if len(plain.encode('utf-8')) > 65536:
            raise ValueError('Text exceeds 64 KiB')
        return {'ok': True, 'items': [{'kind': 'text', 'uri': '', 'text': plain,
                'label': plain.splitlines()[0][:120]}]}
    raise ValueError('No supported content in this drop')

def downloads_directory():
    home = Path.home()
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config'))) / 'user-dirs.dirs'
    try:
        match = re.search(r'^XDG_DOWNLOAD_DIR="([^"\n]+)"\s*$', config.read_text(), re.MULTILINE)
        if match:
            directory = Path(match[1].replace('${HOME}', str(home)).replace('$HOME', str(home)))
            if directory.is_absolute():
                return directory / 'Pentad'
    except OSError:
        pass
    return home / 'Downloads' / 'Pentad'

class WebRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not web_url(newurl):
            raise ValueError('Unsupported download redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)

def image_extension(path):
    import gi
    gi.require_version('GdkPixbuf', '2.0')
    from gi.repository import GdkPixbuf
    info = GdkPixbuf.Pixbuf.get_file_info(str(path))
    if not info or not info[0] or info[1] <= 0 or info[2] <= 0:
        raise ValueError('The downloaded content is not an image')
    extensions = {'png': '.png', 'jpeg': '.jpg', 'gif': '.gif', 'webp': '.webp',
                  'bmp': '.bmp', 'avif': '.avif', 'heif': '.heif', 'tiff': '.tiff'}
    extension = extensions.get(info[0].get_name())
    if not extension:
        raise ValueError('Unsupported image format')
    if info[1] * info[2] > 100_000_000:
        raise ValueError('Image dimensions exceed the supported limit')
    GdkPixbuf.Pixbuf.new_from_file_at_scale(str(path), 256, 256, True)
    return extension

def download(url, label, directory=None):
    if not web_url(url):
        raise ValueError('Invalid image URL')
    directory = Path(directory) if directory else downloads_directory()
    directory.mkdir(parents=True, exist_ok=True)
    temporary = None
    deadline = time.monotonic() + 60
    try:
        request = Request(url, headers={'User-Agent': 'Pentad/0.1', 'Accept': 'image/*'})
        with build_opener(WebRedirects()).open(request, timeout=10) as response:
            length = response.headers.get('Content-Length')
            if length and int(length) > MAX_DOWNLOAD:
                raise ValueError('Image exceeds 50 MiB')
            with tempfile.NamedTemporaryFile(dir=directory, prefix='.pentad-', suffix='.part', delete=False) as output:
                temporary = Path(output.name)
                size = 0
                while True:
                    if time.monotonic() >= deadline:
                        raise TimeoutError('Download timed out')
                    chunk = response.read(65536)
                    if not chunk:
                        break
                    size += len(chunk)
                    if size > MAX_DOWNLOAD:
                        raise ValueError('Image exceeds 50 MiB')
                    output.write(chunk)
                output.flush()
                os.fsync(output.fileno())
        extension = image_extension(temporary)
        name = re.sub(r'[^\w .-]', '_', str(label), flags=re.UNICODE).strip(' .')[:100] or 'image'
        name = re.sub(r'\.(png|jpe?g|webp|gif|bmp|avif|heif|tiff)$', '', name, flags=re.I)
        for number in range(10000):
            destination = directory / (name + (f' ({number})' if number else '') + extension)
            try:
                os.link(temporary, destination)
                return {'ok': True, 'uri': destination.as_uri(), 'bytes': size}
            except FileExistsError:
                continue
        raise ValueError('Too many files with this name')
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)

def main():
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise ValueError('Drop exceeds 1 MiB')
        request = json.loads(raw)
        if request.get('operation') == 'extract':
            result = extract(request.get('offer'))
        elif request.get('operation') == 'download':
            def timeout(signum, frame):
                raise TimeoutError('Download timed out')
            signal.signal(signal.SIGALRM, timeout)
            signal.alarm(60)
            result = download(request.get('url'), request.get('label', 'image'))
        else:
            raise ValueError('Unknown operation')
    except Exception as error:
        result = {'ok': False, 'reason': 'content', 'message': str(error)}
    finally:
        signal.alarm(0)
    print(json.dumps(result, ensure_ascii=False), flush=True)

if __name__ == '__main__':
    main()
