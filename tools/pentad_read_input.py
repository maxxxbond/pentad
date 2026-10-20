#!/usr/bin/env python3
"""Read explicitly selected local text files with strict per-request byte bounds."""
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
        mime_type, _ = mimetypes.guess_type(path)
        mime_type = mime_type or 'application/octet-stream'
        item = {'kind': 'file', 'mimeType': mime_type, 'uri': uri, 'name': os.path.basename(path), 'sizeBytes': info.st_size}
        if mime_type.startswith('image/') or mime_type == 'application/pdf':
            os.close(descriptor)
            items.append(item)
            continue
        try:
            prefix = os.read(descriptor, min(info.st_size, 32))
            signatures = ((b'\x89PNG\r\n\x1a\n', 'image/png'), (b'\xff\xd8\xff', 'image/jpeg'),
                (b'GIF87a', 'image/gif'), (b'GIF89a', 'image/gif'), (b'%PDF-', 'application/pdf'),
                (b'BM', 'image/bmp'))
            detected = next((kind for signature, kind in signatures if prefix.startswith(signature)), None)
            if prefix.startswith(b'RIFF') and prefix[8:12] == b'WEBP': detected = 'image/webp'
            if detected:
                items.append(dict(item, mimeType=detected))
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
        if not (mime_type.startswith('text/') or mime_type == 'application/json'):
            consumed += info.st_size
            items.append(item)
            continue
        if b'\0' in raw:
            raise ValueError('Selected file is binary data')
        value = raw.decode('utf-8')
        consumed += len(raw)
        compatible = [mime_type, 'text/plain']
        if mime_type == 'application/json':
            compatible.insert(0, 'application/json')
        items.append({'kind': 'text', 'mimeType': mime_type, 'value': value, 'compatibleTypes': list(dict.fromkeys(compatible)), 'name': item['name'], 'sizeBytes': len(raw)})
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
