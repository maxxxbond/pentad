#!/usr/bin/env python3
"""Native Spotlight ports; argv-only clipboard actions and the existing history.

One request on stdin by default. With --serve the helper stays alive and answers
line-delimited JSON (`{"id": n, "request": {...}}` -> `{"id": n, "result": {...}}`)
until stdin closes, so a Spotlight session pays for one interpreter start and one
emoji bundle parse instead of one per request.
"""
import argparse
import base64
import gzip
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

from pentad_files import StoreError, _locked, _read, _root, _write_locked

REQUEST_LIMIT = 1024 * 1024
REPLY_LIMIT = 32 * 1024 * 1024

def history_value(text):
    empty = {"version": 1, "pinned": [], "recent": []}
    try:
        value = json.loads(text or '{}')
    except ValueError:
        return empty
    if not isinstance(value, dict) or value.get('version') != 1:
        return empty
    valid = lambda value: isinstance(value, str) and value.startswith('app-') and len(value) < 512
    pinned = list(dict.fromkeys(v for v in value.get('pinned', []) if valid(v)))[:40] if isinstance(value.get('pinned'), list) else []
    recent = {}
    for item in value.get('recent', []) if isinstance(value.get('recent'), list) else []:
        if (isinstance(item, dict) and valid(item.get('id')) and type(item.get('count')) is int
                and item['count'] > 0 and type(item.get('used')) in (int, float) and 0 <= item['used'] < 1e16):
            recent[item['id']] = dict(id=item['id'], count=min(10000, item['count']), used=item['used'])
    return dict(version=1, pinned=pinned, recent=sorted(recent.values(), key=lambda v: -v['used'])[:100])

def command(argv, data=None):
    result = subprocess.run(argv, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3, check=True)
    if len(result.stdout) > 8 * 1024 * 1024:
        raise ValueError('Response is too large')
    return result.stdout

STEAM_ROOTS = ('.local/share/Steam', '.steam/steam', '.var/app/com.valvesoftware.Steam/.local/share/Steam')

def steam_icons():
    # Steam keeps each game's 32x32 client icon in its library cache as <40 hex digits>.jpg.
    icons = {}
    for root in STEAM_ROOTS:
        cache = Path.home() / root / 'appcache' / 'librarycache'
        try:
            games = [game for game in cache.iterdir() if game.name.isdigit()][:4096]
        except OSError:
            continue
        for game in games:
            if game.name in icons:
                continue
            try:
                icon = next((path for path in game.iterdir()
                             if re.fullmatch(r'[0-9a-f]{40}\.jpg', path.name) and path.is_file()), None)
            except OSError:
                continue
            if icon:
                icons[game.name] = str(icon)
    return icons

def image_mime(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return 'image/png'
    if data.startswith(b'\xff\xd8\xff'):
        return 'image/jpeg'
    if data.startswith((b'GIF87a', b'GIF89a')):
        return 'image/gif'
    if data.startswith(b'BM'):
        return 'image/bmp'
    if data.startswith((b'II*\x00', b'MM\x00*')):
        return 'image/tiff'
    if len(data) >= 12 and data[:4] == b'RIFF' and data[8:12] == b'WEBP':
        return 'image/webp'
    if len(data) >= 12 and data[4:8] == b'ftyp' and data[8:12] in (b'avif', b'avis'):
        return 'image/avif'
    return ''

USER_DIRS = ('DESKTOP', 'DOCUMENTS', 'DOWNLOAD', 'MUSIC', 'PICTURES', 'VIDEOS')
USER_DIR_DEFAULTS = ('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')
MAX_FILES = 60

def user_dirs(home, config_home):
    """XDG user directories from user-dirs.dirs, never the home directory itself."""
    found = {}
    try:
        text = (Path(config_home) / 'user-dirs.dirs').read_text(errors='replace')
    except OSError:
        text = ''
    for line in text.splitlines()[:200]:
        match = re.fullmatch(r'\s*XDG_([A-Z]+)_DIR="([^"]*)"\s*', line)
        if match and match.group(1) in USER_DIRS:
            found[match.group(1)] = match.group(2).replace('$HOME', str(home), 1)
    paths = [Path(found.get(key) or Path(home) / name) for key, name in zip(USER_DIRS, USER_DIR_DEFAULTS)]
    return list(dict.fromkeys(str(path) for path in paths if path != Path(home) and path.is_dir()))

def search_paths(argv):
    """NUL-separated paths from a search tool; a missing tool or no match is an empty list."""
    try:
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b''
    except OSError:
        return []
    else:
        output = result.stdout
    return [path for path in output[:4 * 1024 * 1024].decode('utf-8', errors='replace').split('\0') if path]

def visible_under(path, home):
    try:
        parts = Path(path).relative_to(home).parts
    except ValueError:
        return False
    return bool(parts) and not any(part.startswith('.') for part in parts)

def find_files(query, home, config_home):
    terms = [term.casefold() for term in query.split()][:8]
    if not terms or len(query) > 256 or len(''.join(terms)) < 2:
        raise ValueError('Invalid file query')
    roots = user_dirs(home, config_home)
    candidates = []
    if roots:
        candidates = search_paths(['fd', '--ignore-case', '--fixed-strings', '--max-depth', '6', '--max-results', '400',
                                   '--absolute-path', '--print0', '--color', 'never', '--', terms[0], *roots])
        if not candidates and not shutil.which('fd'):
            pattern = '*' + re.sub(r'([*?\[\]\\])', r'\\\1', terms[0]) + '*'
            candidates = search_paths(['find', *roots, '-maxdepth', '6', '-not', '-path', '*/.*', '-iname', pattern, '-print0'])[:400]
    candidates += search_paths(['plocate', '--ignore-case', '--basename', '--limit', '400', '--null', '--', *terms])
    files = []
    for path in dict.fromkeys(candidates):
        name = Path(path).name
        if not visible_under(path, home) or not all(term in name.casefold() for term in terms):
            continue
        try:
            info = os.stat(path)
        except OSError:
            continue
        parent = Path(path).parent.relative_to(home)
        files.append(dict(path=path, name=name, folder='~' if str(parent) == '.' else '~/' + str(parent),
                          directory=stat.S_ISDIR(info.st_mode), size=info.st_size, modified=int(info.st_mtime * 1000)))
        if len(files) >= MAX_FILES:
            break
    return files

def emoji_records(emoji_path, languages, cache=None):
    """Decode the requested locales. A serving helper passes its own `cache` dict, which keeps the
    parsed bundle and the decoded locales until the bundle file changes on disk."""
    if cache is None:
        locales, decoded = json.loads(Path(emoji_path).read_text())['locales'], {}
    else:
        info = Path(emoji_path).stat()
        key = (str(emoji_path), info.st_ino, info.st_size, info.st_mtime_ns)
        if cache.get('key') != key:
            cache.clear()
            cache.update(key=key, locales=json.loads(Path(emoji_path).read_bytes())['locales'], decoded={})
        locales, decoded = cache['locales'], cache['decoded']
    records = {}
    for lang in languages:
        if isinstance(lang, str) and lang in locales:
            if lang not in decoded:
                decoded[lang] = json.loads(gzip.decompress(base64.b64decode(locales[lang])))
            records[lang] = decoded[lang]
    return records

def handle(request, state_root, emoji_path, cache=None):
    operation = request.get('operation')
    if operation in ('history', 'record', 'pin'):
        root = _root(state_root, create=operation != 'history')
        if operation == 'history':
            text, _ = _read(root / 'spotlight.json')
            return dict(ok=True, history=history_value(text))
        identity = request.get('id')
        if not isinstance(identity, str) or not identity.startswith('app-') or len(identity) >= 512:
            raise ValueError('Invalid app identity')
        with _locked(root):
            text, revision = _read(root / 'spotlight.json')
            history = history_value(text)
            if operation == 'pin':
                history['pinned'] = ([v for v in history['pinned'] if v != identity] if identity in history['pinned']
                                     else (history['pinned'] + [identity])[-40:])
            else:
                count = next((v['count'] for v in history['recent'] if v['id'] == identity), 0)
                history['recent'] = [dict(id=identity, count=min(10000, count + 1), used=int(time.time() * 1000))] + [v for v in history['recent'] if v['id'] != identity][:99]
            _write_locked(root, 'spotlight', json.dumps(history, ensure_ascii=False), revision)
        return dict(ok=True, history=history)
    if operation == 'emoji':
        languages = request.get('languages', [])
        if not isinstance(languages, list) or len(languages) > 28:
            raise ValueError('Invalid languages')
        return dict(ok=True, records=emoji_records(emoji_path, languages, cache))
    if operation == 'keyboard-layouts':
        layouts = []
        try:
            devices = json.loads(command(['hyprctl', '-j', 'devices']))
            layouts = [item.get('layout', item.get('xkb_layout', ''))
                       for item in devices.get('keyboards', [])[:64] if isinstance(item, dict)]
        except (ValueError, OSError, subprocess.SubprocessError):
            pass
        layouts = list(dict.fromkeys(layout for layout in layouts if isinstance(layout, str) and layout.strip()))
        if not layouts:
            try:
                option = json.loads(command(['hyprctl', '-j', 'getoption', 'input:kb_layout']))
                layout = option.get('str', '') if isinstance(option, dict) else ''
                if isinstance(layout, str) and layout.strip():
                    layouts = [layout]
            except (ValueError, OSError, subprocess.SubprocessError):
                pass
        return dict(ok=True, layouts=layouts)
    if operation == 'files':
        query = request.get('query')
        if not isinstance(query, str):
            raise ValueError('Invalid file query')
        home = Path.home()
        config_home = os.environ.get('XDG_CONFIG_HOME') or str(home / '.config')
        return dict(ok=True, files=find_files(query, home, config_home))
    if operation == 'steam-icons':
        return dict(ok=True, icons=steam_icons())
    if operation == 'clipboard-list':
        return dict(ok=True, text=command(['cliphist', 'list']).decode('utf-8', errors='replace')[:1024 * 1024])
    if operation == 'copy-text':
        text = request.get('text')
        if not isinstance(text, str) or len(text.encode()) > 1024 * 1024:
            raise ValueError('Invalid text')
        command(['wl-copy'], text.encode())
        return dict(ok=True)
    if operation in ('copy-clip', 'delete-clip', 'preview-clip', 'text-clip'):
        identity = request.get('id')
        if not isinstance(identity, str) or not re.fullmatch(r'\d{1,20}', identity):
            raise ValueError('Invalid clipboard identity')
        if operation == 'delete-clip':
            command(['cliphist', 'delete', identity])
        else:
            data = command(['cliphist', 'decode', identity])
            if operation == 'copy-clip':
                command(['wl-copy'], data)
            elif operation == 'text-clip':
                # cliphist list folds an entry into one 100-character line; the preview pane shows the
                # real text, cut to a screenful. Counts describe the whole entry.
                text = data.decode('utf-8', errors='replace')
                return dict(ok=True, text=text[:4096], length=len(text), lines=len(text.splitlines()))
            else:
                mime = image_mime(data)
                if not mime:
                    raise ValueError('Unsupported image')
                return dict(ok=True, image='data:' + mime + ';base64,' + base64.b64encode(data).decode())
        return dict(ok=True)
    raise ValueError('Unsupported operation')

def serve(state_root, emoji_path, stdin, stdout):
    """Answer one JSON line per request line until stdin closes. Requests run in order; a bad
    request fails alone and never ends the loop. Replies echo the request id so the client can
    drop a reply it no longer waits for."""
    cache = {}
    while True:
        line = stdin.readline(REQUEST_LIMIT + 1)
        if not line:
            return
        identity = None
        if len(line) > REQUEST_LIMIT and not line.endswith(b'\n'):
            # Oversized: recover the id the client writes first, then skip to the next line.
            match = re.match(rb'\{"id":(\d{1,15})[,}]', line)
            identity = int(match.group(1)) if match else None
            while line and not line.endswith(b'\n'):
                line = stdin.readline(REQUEST_LIMIT + 1)
            result = dict(ok=False, reason='io', message='ValueError')
        elif not line.strip():
            continue
        else:
            try:
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError('Invalid message')
                if type(message.get('id')) is int:
                    identity = message['id']
                if identity is None or not isinstance(message.get('request'), dict):
                    raise ValueError('Invalid request')
                result = handle(message['request'], state_root, emoji_path, cache)
            except Exception as error:  # one broken request must not end the session
                result = dict(ok=False, reason='io', message=type(error).__name__)
        try:
            reply = json.dumps(dict(id=identity, result=result), ensure_ascii=False).encode()
        except ValueError as error:  # e.g. a lone surrogate read from a damaged state file
            reply = json.dumps(dict(id=identity, result=dict(ok=False, reason='io', message=type(error).__name__))).encode()
        if len(reply) > REPLY_LIMIT:
            reply = json.dumps(dict(id=identity, result=dict(ok=False, reason='io', message='TooLarge'))).encode()
        try:
            stdout.write(reply + b'\n')
            stdout.flush()
        except BrokenPipeError:
            return

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-root', required=True)
    parser.add_argument('--emoji-data', required=True)
    parser.add_argument('--serve', action='store_true')
    args = parser.parse_args()
    if args.serve:
        serve(args.state_root, args.emoji_data, sys.stdin.buffer, sys.stdout.buffer)
        return
    try:
        raw = sys.stdin.buffer.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            raise ValueError('Request is too large')
        request = json.loads(raw)
        if not isinstance(request, dict):
            raise ValueError('Invalid request')
        result = handle(request, args.state_root, args.emoji_data)
    except (ValueError, OSError, StoreError, subprocess.SubprocessError) as error:
        result = dict(ok=False, reason='io', message=type(error).__name__)
    print(json.dumps(result, ensure_ascii=False))

if __name__ == '__main__':
    main()
