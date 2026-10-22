#!/usr/bin/env python3
"""Read explicitly selected local text files with strict per-request byte bounds; describe other files by reference."""
import json
import mimetypes
import os
import stat
import sys
from urllib.parse import urlsplit
from urllib.request import url2pathname

def _file_path(uri):
    parsed = urlsplit(uri)
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or not parsed.path.startswith('/') or parsed.query or parsed.fragment:
        raise ValueError('Only local file URIs are supported')
    path = url2pathname(parsed.path)
    if '\0' in path:
        raise ValueError('Invalid file URI')
    return path

LOCAL_FILE = 'application/x-pentad-local-file'
COMPRESSED = {'gzip': 'application/gzip', 'xz': 'application/x-xz', 'bzip2': 'application/x-bzip2', 'br': 'application/x-brotli'}
SIGNATURES = ((b'\x89PNG\r\n\x1a\n', 'image/png'), (b'\xff\xd8\xff', 'image/jpeg'),
    (b'GIF87a', 'image/gif'), (b'GIF89a', 'image/gif'), (b'%PDF-', 'application/pdf'), (b'BM', 'image/bmp'),
    (b'PK\x03\x04', 'application/zip'), (b"7z\xbc\xaf\x27\x1c", 'application/x-7z-compressed'),
    (b'\x1f\x8b', 'application/gzip'), (b'\xfd7zXZ\x00', 'application/x-xz'), (b'\x28\xb5\x2f\xfd', 'application/zstd'),
    (b'Rar!\x1a\x07', 'application/vnd.rar'), (b'\x1a\x45\xdf\xa3', 'video/x-matroska'), (b'OggS', 'audio/ogg'),
    (b'fLaC', 'audio/flac'), (b'ID3', 'audio/mpeg'))
BRANDS = {b'heic': 'image/heic', b'heix': 'image/heic', b'mif1': 'image/heif', b'avif': 'image/avif',
    b'qt  ': 'video/quicktime', b'M4A ': 'audio/mp4'}

def sniff(prefix):
    """Recognise common binary formats from their first bytes, so renamed files reach the right tools."""
    detected = next((kind for signature, kind in SIGNATURES if prefix.startswith(signature)), None)
    if prefix.startswith(b'RIFF'):
        detected = {b'WEBP': 'image/webp', b'WAVE': 'audio/x-wav', b'AVI ': 'video/x-msvideo'}.get(prefix[8:12], detected)
    if prefix[4:8] == b'ftyp':
        detected = BRANDS.get(prefix[8:12], 'video/mp4')
    return detected

def read_inputs(request):
    if not isinstance(request, dict) or not isinstance(request.get('uris'), list):
        raise ValueError('Expected a list of file URIs')
    limit = request.get('maxBytes')
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 10 * 1024 * 1024:
        raise ValueError('Invalid input byte limit')
    uris = request['uris']
    if not 1 <= len(uris) <= 100 or any(not isinstance(uri, str) or len(uri) > 4096 for uri in uris):
        raise ValueError('Invalid file URI list')
    items = []
    consumed = 0
    for uri in uris:
        path = _file_path(uri)
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_CLOEXEC', 0))
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            os.close(descriptor)
            raise ValueError('Folders cannot be opened as tool input')
        mime_type, encoding = mimetypes.guess_type(path)
        if encoding and not mime_type:
            mime_type = COMPRESSED.get(encoding)
        mime_type = mime_type or 'application/octet-stream'
        item = {'kind': 'file', 'mimeType': mime_type, 'uri': uri, 'name': os.path.basename(path), 'sizeBytes': info.st_size}
        if mime_type.startswith('image/') or mime_type == 'application/pdf':
            os.close(descriptor)
            items.append(item)
            continue
        try:
            prefix = os.read(descriptor, min(info.st_size, 32))
            detected = sniff(prefix)
            if detected:
                items.append(dict(item, mimeType=detected))
                continue
            if not (mime_type.startswith('text/') or mime_type == 'application/json'):
                # Binary files stay references; tools read them from disk, so they do not count toward the inline limit.
                items.append(item)
                continue
            if info.st_size > limit - consumed:
                raise ValueError('Selected files exceed this tool input limit')
            os.lseek(descriptor, 0, os.SEEK_SET)
            chunks = []
            remaining = min(limit - consumed + 1, info.st_size + 1)
            while remaining:
                chunk = os.read(descriptor, min(65536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            raw = b''.join(chunks)
        finally:
            os.close(descriptor)
        if len(raw) > limit - consumed:
            raise ValueError('Selected text files exceed this tool input limit')
        if b'\0' in raw:
            raise ValueError('Selected file is binary data')
        value = raw.decode('utf-8')
        consumed += len(raw)
        compatible = [mime_type, 'text/plain']
        if mime_type == 'application/json':
            compatible.insert(0, 'application/json')
        items.append({'kind': 'text', 'mimeType': mime_type, 'value': value, 'compatibleTypes': list(dict.fromkeys(compatible)), 'name': item['name'], 'uri': uri, 'sizeBytes': len(raw)})
    for item in items:
        # Tools that work on any local file (archives, checksums) accept this marker instead of every MIME type.
        item['compatibleTypes'] = list(dict.fromkeys(item.get('compatibleTypes') or [item['mimeType']])) + [LOCAL_FILE]
    return {'ok': True, 'items': items}

def main():
    try:
        raw = sys.stdin.buffer.read(512 * 1024 + 1)
        if len(raw) > 512 * 1024:
            raise ValueError('Input request is too large')
        request = json.loads(raw.decode('utf-8'))
        result = read_inputs(request)
    except (OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError) as error:
        result = {'ok': False, 'reason': str(error)[:200]}
    sys.stdout.write(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
