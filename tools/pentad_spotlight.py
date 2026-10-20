#!/usr/bin/env python3
"""Native Spotlight ports; argv-only clipboard actions and the existing history."""
import argparse
import base64
import gzip
import json
import re
import subprocess
import sys
import time
from pathlib import Path

from pentad_files import StoreError, _locked, _read, _root, _write_locked

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

def handle(request, state_root, emoji_path):
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
        data = json.loads(Path(emoji_path).read_text())
        languages = request.get('languages', [])
        if not isinstance(languages, list) or len(languages) > 28:
            raise ValueError('Invalid languages')
        records = {lang: json.loads(gzip.decompress(base64.b64decode(data['locales'][lang])))
                   for lang in languages if isinstance(lang, str) and lang in data['locales']}
        return dict(ok=True, records=records)
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
    if operation == 'clipboard-list':
        return dict(ok=True, text=command(['cliphist', 'list']).decode('utf-8', errors='replace')[:1024 * 1024])
    if operation == 'copy-text':
        text = request.get('text')
        if not isinstance(text, str) or len(text.encode()) > 1024 * 1024:
            raise ValueError('Invalid text')
        command(['wl-copy'], text.encode())
        return dict(ok=True)
    if operation in ('copy-clip', 'delete-clip', 'preview-clip'):
        identity = request.get('id')
        if not isinstance(identity, str) or not re.fullmatch(r'\d{1,20}', identity):
            raise ValueError('Invalid clipboard identity')
        if operation == 'delete-clip':
            command(['cliphist', 'delete', identity])
        else:
            data = command(['cliphist', 'decode', identity])
            if operation == 'copy-clip':
                command(['wl-copy'], data)
            else:
                mime = image_mime(data)
                if not mime:
                    raise ValueError('Unsupported image')
                return dict(ok=True, image='data:' + mime + ';base64,' + base64.b64encode(data).decode())
        return dict(ok=True)
    raise ValueError('Unsupported operation')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-root', required=True)
    parser.add_argument('--emoji-data', required=True)
    args = parser.parse_args()
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
