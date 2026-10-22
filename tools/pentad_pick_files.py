#!/usr/bin/env python3
"""Ask the desktop's own file chooser for local files to hand to a sidebar tool.

Uses the xdg-desktop-portal FileChooser (a regular top-level dialog styled by the desktop),
falling back to zenity when no portal answers. Request JSON on stdin:
{"title": str, "multiple": bool, "filters": ["PDF documents (*.pdf *.PDF)", ...]}
Result JSON on stdout: {"ok": true, "uris": [...]}, {"ok": false, "cancelled": true} or
{"ok": false, "reason": str}. SIGTERM closes an open portal dialog.
"""
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
from urllib.parse import quote, urlsplit

MAX_REQUEST = 64 * 1024


class PickError(Exception):
    pass


def parse_filter(text):
    """'PDF documents (*.pdf *.PDF)' -> ('PDF documents', ['*.pdf', '*.PDF'])."""
    match = re.fullmatch(r'\s*(.*?)\s*\(([^()]*)\)\s*', str(text))
    if not match:
        return None
    patterns = [pattern for pattern in match.group(2).split() if re.fullmatch(r'[\w*?.\[\]-]{1,32}', pattern)]
    return (match.group(1) or 'Files', patterns) if patterns else None


def validate(request):
    if not isinstance(request, dict):
        raise PickError('Expected a request object')
    title = request.get('title') or 'Choose files'
    if not isinstance(title, str) or len(title) > 200:
        raise PickError('Invalid title')
    filters = [item for item in (parse_filter(text) for text in (request.get('filters') or [])[:16]) if item]
    return {'title': title, 'multiple': request.get('multiple') is not False, 'filters': filters}


def local_uris(values):
    """Keep only local file URIs, normalised to file:///absolute/path."""
    uris = []
    for value in values:
        parsed = urlsplit(value)
        if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or not parsed.path.startswith('/'):
            continue
        uris.append('file://' + parsed.path)
    return uris[:100]


def path_uris(paths):
    return [('file://' + quote(path, safe='/')) for path in paths if path.startswith('/')][:100]


def pick_portal(spec):
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = 'pentad_' + secrets.token_hex(8)
    sender = bus.get_unique_name()[1:].replace('.', '_')
    handle = f'/org/freedesktop/portal/desktop/request/{sender}/{token}'
    loop = GLib.MainLoop()
    outcome = {}

    def on_response(connection, sender_name, path, interface, name, parameters):
        code, results = parameters.unpack()
        outcome['code'] = code
        outcome['uris'] = list(results.get('uris', []))
        loop.quit()

    def close(*_):
        outcome.setdefault('code', 1)
        try:
            bus.call_sync('org.freedesktop.portal.Desktop', handle, 'org.freedesktop.portal.Request', 'Close',
                          None, None, Gio.DBusCallFlags.NONE, 2000, None)
        except GLib.Error:
            pass
        loop.quit()

    subscription = bus.signal_subscribe('org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request', 'Response',
                                        handle, None, Gio.DBusSignalFlags.NONE, on_response)
    options = {
        'handle_token': GLib.Variant('s', token),
        'multiple': GLib.Variant('b', spec['multiple']),
        'modal': GLib.Variant('b', False),
    }
    if spec['filters']:
        options['filters'] = GLib.Variant('a(sa(us))', [(name, [(0, pattern) for pattern in patterns]) for name, patterns in spec['filters']])
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, close)
    try:
        bus.call_sync('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop', 'org.freedesktop.portal.FileChooser',
                      'OpenFile', GLib.Variant('(ssa{sv})', ('', spec['title'], options)), GLib.VariantType('(o)'),
                      Gio.DBusCallFlags.NONE, 10000, None)
        loop.run()
    finally:
        bus.signal_unsubscribe(subscription)
    if outcome.get('code') == 0:
        return local_uris(outcome.get('uris', []))
    if outcome.get('code') == 1:
        return None
    raise PickError('The file chooser failed')


def pick_zenity(spec):
    zenity = shutil.which('zenity')
    if not zenity:
        raise PickError('No file chooser is available (install xdg-desktop-portal or zenity)')
    argv = [zenity, '--file-selection', '--title', spec['title'], '--separator', '\n']
    if spec['multiple']:
        argv.append('--multiple')
    for name, patterns in spec['filters']:
        argv += ['--file-filter', f'{name} | {" ".join(patterns)}']
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    signal.signal(signal.SIGTERM, lambda *_: process.terminate())
    out, _ = process.communicate()
    if process.returncode == 1:
        return None
    if process.returncode != 0:
        raise PickError('The file chooser failed')
    return path_uris([line for line in out.decode('utf-8', 'replace').splitlines() if line])


def main():
    try:
        raw = sys.stdin.buffer.read(MAX_REQUEST + 1)
        if len(raw) > MAX_REQUEST:
            raise PickError('Request is too large')
        spec = validate(json.loads(raw.decode('utf-8') or '{}'))
        if os.environ.get('DBUS_SESSION_BUS_ADDRESS'):
            try:
                uris = pick_portal(spec)
            except PickError:
                raise
            except Exception:  # no gi bindings, no portal service, or the call failed (GLib.Error)
                uris = pick_zenity(spec)
        else:
            uris = pick_zenity(spec)
        result = {'ok': False, 'cancelled': True} if uris is None else {'ok': True, 'uris': uris}
    except PickError as error:
        result = {'ok': False, 'reason': str(error)}
    except (UnicodeError, json.JSONDecodeError):
        result = {'ok': False, 'reason': 'Invalid request'}
    sys.stdout.write(json.dumps(result) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
