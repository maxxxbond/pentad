#!/usr/bin/env python3
"""Stash clipboard bridge: paste from and copy to the Wayland clipboard, and delete owned clipboard images.

One JSON object on stdin, one JSON line on stdout, exit 0. Errors are {"ok": false, "reason", "message"}.

  {"operation": "paste", "stashDir"?: str}
  {"operation": "copy", "mode": "text"|"uris"|"image", "value"?: str, "path"?: str}
  {"operation": "delete", "stashDir"?: str, "path": str}

`delete` is the only destructive operation: it removes a single regular file whose real parent is the real
stash directory and refuses everything else (outside paths, directories, symlinks) with `outside-stash`.
"""
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import threading
import time
from urllib.parse import unquote, urlsplit

MAX_INPUT = 1024 * 1024
MAX_IMAGE = 32 * 1024 * 1024
MAX_TEXT = 64 * 1024
MAX_URI_LIST = 256 * 1024
MAX_URIS = 350
MAX_URI = 8192
MAX_LABEL = 512
TIMEOUT = 5

TEXT_TYPES = ('text/plain;charset=utf-8', 'text/plain', 'UTF8_STRING', 'TEXT')
MIME_PATTERN = re.compile(r'[A-Za-z0-9][\w.+-]*/[A-Za-z0-9][\w.+-]*')
EXTENSIONS = {'jpeg': 'jpg', 'svg+xml': 'svg', 'x-icon': 'ico', 'vnd.microsoft.icon': 'ico', 'tiff': 'tif'}


class HelperError(Exception):
    def __init__(self, reason, message):
        super().__init__(message)
        self.reason = reason


def default_stash_dir():
    state = os.environ.get('XDG_STATE_HOME', '')
    if not state or not os.path.isabs(state):
        state = os.path.join(os.path.expanduser('~'), '.local', 'state')
    return os.path.join(state, 'pentad', 'stash')


def stash_dir(request):
    value = request.get('stashDir')
    if value is None:
        return default_stash_dir()
    if not isinstance(value, str) or not os.path.isabs(value) or '\0' in value or len(value) > 4096:
        raise HelperError('invalid', 'Invalid stash directory')
    return os.path.abspath(value)


def run_wl(args, **options):
    try:
        return subprocess.run(args, timeout=TIMEOUT, **options)
    except (OSError, subprocess.TimeoutExpired):
        raise HelperError('clipboard-unavailable', 'The clipboard is not available')


def clipboard_types():
    result = run_wl(['wl-paste', '--list-types'], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode != 0:
        raise HelperError('clipboard-unavailable', 'The clipboard is not available')
    return [line.strip() for line in result.stdout.decode('utf-8', errors='replace').splitlines() if line.strip()]


def read_type(mime, limit):
    """Returns the clipboard content for one type, or None when it exceeds `limit` bytes."""
    try:
        process = subprocess.Popen(['wl-paste', '--no-newline', '--type', mime],
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        raise HelperError('clipboard-unavailable', 'The clipboard is not available')
    expired = threading.Event()

    def expire():
        expired.set()
        process.kill()
    timer = threading.Timer(TIMEOUT, expire)
    timer.start()
    try:
        data = process.stdout.read(limit + 1)
        if len(data) > limit:
            process.kill()
            return None
        process.wait()
    finally:
        timer.cancel()
        process.stdout.close()
        if process.poll() is None:
            process.kill()
        process.wait()
    if expired.is_set() or process.returncode != 0:
        raise HelperError('clipboard-unavailable', 'The clipboard is not available')
    return data


def local_file_uri(value):
    """Normalizes a local file:// URI to (uri, path), or returns None for anything else."""
    if not isinstance(value, str) or len(value) > MAX_URI or re.search(r'[\x00-\x1f\x7f\s]', value):
        return None
    try:
        parsed = urlsplit(value)
        if parsed.scheme.lower() != 'file' or parsed.netloc.lower() not in ('', 'localhost') or parsed.query or parsed.fragment:
            return None
        path = unquote(parsed.path, errors='strict')
    except ValueError:
        return None
    if not path.startswith('/') or path.startswith('//') or any(ord(c) < 32 or ord(c) == 127 for c in path):
        return None
    path = os.path.normpath(path)
    uri = Path(path).as_uri()
    return (uri, path) if len(uri) <= MAX_URI else None


def parse_uri_list(text):
    """Every non-comment line must be a local file URI; returns [(uri, path)] or None."""
    entries = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        entry = local_file_uri(line)
        if entry is None:
            return None
        entries[entry[0]] = entry
    return list(entries.values()) or None


def item_label(path):
    return (os.path.basename(path) or path)[:MAX_LABEL]


def image_extension(mime):
    subtype = mime.split('/', 1)[1].lower()
    subtype = EXTENSIONS.get(subtype, subtype)
    return subtype if re.fullmatch(r'[a-z0-9]{1,8}', subtype) else 'img'


def save_image(directory, mime, data):
    os.makedirs(directory, mode=0o700, exist_ok=True)
    extension = image_extension(mime)
    for _ in range(8):
        name = f"clip-{time.strftime('%Y%m%d-%H%M%S')}-{secrets.token_hex(2)}.{extension}"
        path = os.path.join(directory, name)
        try:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            continue
        try:
            with os.fdopen(descriptor, 'wb') as handle:
                handle.write(data)
        except BaseException:
            try:
                os.unlink(path)
            except OSError:
                pass
            raise
        return {'uri': Path(path).as_uri(), 'label': name, 'owned': True}
    raise HelperError('content', 'Could not choose a file name')


def paste(request):
    directory = stash_dir(request)
    types = clipboard_types()
    images = [t for t in types if t.lower().startswith('image/') and MIME_PATTERN.fullmatch(t)]
    if images:
        mime = 'image/png' if 'image/png' in images else images[0]
        data = read_type(mime, MAX_IMAGE)
        if data is None:
            raise HelperError('too-large', 'The image is larger than 32 MiB')
        if data:
            return {'ok': True, 'items': [save_image(directory, mime, data)]}
    if 'text/uri-list' in types:
        data = read_type('text/uri-list', MAX_URI_LIST)
        entries = parse_uri_list(data.decode('utf-8', errors='replace')) if data else None
        if entries:
            if len(entries) > MAX_URIS:
                raise HelperError('too-large', 'Too many files')
            return {'ok': True, 'items': [{'uri': uri, 'label': item_label(path)} for uri, path in entries]}
    for mime in TEXT_TYPES:
        if mime not in types:
            continue
        data = read_type(mime, MAX_TEXT)
        if data is None:
            raise HelperError('too-large', 'The text is larger than 64 KiB')
        text = data.decode('utf-8', errors='replace')
        if text.strip():
            return {'ok': True, 'text': text}
    return {'ok': False, 'reason': 'empty', 'message': 'The clipboard has nothing to paste'}


def copy(request):
    mode = request.get('mode')
    if mode in ('text', 'uris'):
        value = request.get('value')
        if not isinstance(value, str) or not value or len(value.encode()) > MAX_TEXT:
            raise HelperError('invalid', 'Invalid value')
        if mode == 'text':
            return send_copy('text/plain;charset=utf-8', value.encode())
        entries = parse_uri_list(value)
        if not entries or len(entries) > MAX_URIS:
            raise HelperError('invalid', 'Only local file URIs can be copied')
        return send_copy('text/uri-list', ''.join(uri + '\r\n' for uri, _ in entries).encode())
    if mode == 'image':
        path = request.get('path')
        if not isinstance(path, str) or not os.path.isabs(path) or '\0' in path:
            raise HelperError('invalid', 'Invalid image path')
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
        except OSError:
            raise HelperError('invalid', 'The image is not a readable file')
        with os.fdopen(descriptor, 'rb') as handle:
            info = os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise HelperError('invalid', 'The image is not a regular file')
            if info.st_size > MAX_IMAGE:
                raise HelperError('too-large', 'The image is larger than 32 MiB')
            return send_copy('image/png', handle.read(MAX_IMAGE + 1))
    raise HelperError('invalid', 'Unknown copy mode')


def send_copy(mime, payload):
    result = run_wl(['wl-copy', '--type', mime], input=payload, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode != 0:
        raise HelperError('clipboard-unavailable', 'The clipboard is not available')
    return {'ok': True}


def delete(request):
    outside = {'ok': False, 'reason': 'outside-stash', 'message': 'The file is not inside the stash'}
    path = request.get('path')
    if not isinstance(path, str) or not os.path.isabs(path) or '\0' in path or len(path) > 4096:
        return outside
    stash = os.path.realpath(stash_dir(request))
    target = os.path.realpath(path)
    name = os.path.basename(target)
    if stash == os.sep or target == stash or os.path.dirname(target) != stash or name in ('', '.', '..'):
        return outside
    if os.path.islink(path):
        return outside
    try:
        directory = os.open(stash, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    except FileNotFoundError:
        return {'ok': True}
    try:
        try:
            info = os.stat(name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            return {'ok': True}
        if not stat.S_ISREG(info.st_mode):
            return outside
        try:
            os.unlink(name, dir_fd=directory)
        except FileNotFoundError:
            pass
        return {'ok': True}
    finally:
        os.close(directory)


def main():
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise HelperError('invalid', 'Request exceeds 1 MiB')
        request = json.loads(raw)
        if not isinstance(request, dict):
            raise HelperError('invalid', 'Request must be an object')
        operation = request.get('operation')
        if operation == 'paste':
            result = paste(request)
        elif operation == 'copy':
            result = copy(request)
        elif operation == 'delete':
            result = delete(request)
        else:
            raise HelperError('invalid', 'Unknown operation')
    except HelperError as error:
        result = {'ok': False, 'reason': error.reason, 'message': str(error)}
    except Exception as error:
        result = {'ok': False, 'reason': 'content', 'message': str(error)}
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
