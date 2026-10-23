#!/usr/bin/env python3
"""System facts and settings for the settings window: about, date and time, default applications.

Reads one JSON request on stdin and prints one JSON reply. Every external program gets an argument
array; values that reach a program (a time zone, a desktop id) are checked against the lists this
helper produced first.
"""
import argparse
import configparser
import json
import os
import platform
import re
import socket
import subprocess
import sys
from pathlib import Path

# Each category is set for all of its MIME types at once and read back from the first one.
DEFAULT_APP_CATEGORIES = (
    ('web', ('x-scheme-handler/https', 'x-scheme-handler/http', 'text/html')),
    ('mail', ('x-scheme-handler/mailto',)),
    ('files', ('inode/directory',)),
    ('text', ('text/plain',)),
    ('pdf', ('application/pdf',)),
    ('image', ('image/png', 'image/jpeg', 'image/webp', 'image/gif')),
    ('audio', ('audio/mpeg', 'audio/flac', 'audio/ogg', 'audio/x-wav')),
    ('video', ('video/mp4', 'video/x-matroska', 'video/webm')),
)
TIMEZONE = re.compile(r'^[A-Za-z0-9_+\-]+(/[A-Za-z0-9_+\-]+)*$')
DESKTOP_ID = re.compile(r'^[A-Za-z0-9_.\-]+\.desktop$')


def run(argv, timeout=5):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout, check=True).stdout


def read(root, path):
    try:
        return (Path(root) / path.lstrip('/')).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return ''


def os_release(text):
    values = {}
    for line in text.splitlines():
        key, sep, value = line.partition('=')
        if sep and key.strip():
            values[key.strip()] = value.strip().strip('"\'')
    return values.get('PRETTY_NAME') or ' '.join(filter(None, (values.get('NAME'), values.get('VERSION')))) or ''


def about(root):
    cpu = ''
    for line in read(root, '/proc/cpuinfo').splitlines():
        if line.lower().startswith('model name'):
            cpu = re.sub(r'\s+', ' ', line.split(':', 1)[1]).strip()
            break
    memory = None
    match = re.search(r'^MemTotal:\s+(\d+)\s+kB', read(root, '/proc/meminfo'), re.M)
    if match:
        memory = int(match.group(1)) * 1024
    uptime = read(root, '/proc/uptime').split()
    return dict(ok=True, hostname=socket.gethostname(), os=os_release(read(root, '/etc/os-release')),
                kernel=platform.release(), cpu=cpu, memory=memory,
                desktop=os.environ.get('XDG_CURRENT_DESKTOP', ''),
                uptime=int(float(uptime[0])) if uptime else None)


def time_state(root):
    try:
        values = dict(line.split('=', 1) for line in run(
            ['timedatectl', 'show', '-p', 'Timezone', '-p', 'NTP', '-p', 'NTPSynchronized', '-p', 'CanNTP']).splitlines() if '=' in line)
        return dict(ok=True, timezone=values.get('Timezone', ''), ntp=values.get('NTP') == 'yes',
                    synchronized=values.get('NTPSynchronized') == 'yes', canNtp=values.get('CanNTP') == 'yes', canSet=True)
    except (OSError, subprocess.SubprocessError):
        # Without timedatectl the zone still shows from /etc/localtime; nothing can be changed.
        link = Path(root) / 'etc/localtime'
        zone = ''
        try:
            target = os.readlink(link)
            zone = target.split('zoneinfo/', 1)[1] if 'zoneinfo/' in target else ''
        except OSError:
            pass
        return dict(ok=True, timezone=zone, ntp=None, synchronized=None, canNtp=False, canSet=False)


def timezones():
    try:
        zones = [line.strip() for line in run(['timedatectl', 'list-timezones']).splitlines()]
    except (OSError, subprocess.SubprocessError):
        return []
    return [zone for zone in zones if TIMEZONE.match(zone)]


def data_dirs():
    home = os.environ.get('XDG_DATA_HOME') or os.path.join(os.path.expanduser('~'), '.local/share')
    others = os.environ.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share'
    return [home] + [path for path in others.split(':') if path]


def applications(dirs):
    """Desktop id -> (name, MIME types) for visible applications; earlier directories win."""
    found = {}
    for base in dirs:
        folder = Path(base) / 'applications'
        if not folder.is_dir():
            continue
        for path in sorted(folder.rglob('*.desktop')):
            desktop_id = str(path.relative_to(folder)).replace('/', '-')
            if desktop_id in found or not DESKTOP_ID.match(desktop_id):
                continue
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                parser.read(path, encoding='utf-8')
            except (configparser.Error, UnicodeDecodeError, OSError):
                continue
            if not parser.has_section('Desktop Entry'):
                continue
            entry = parser['Desktop Entry']
            hidden = entry.get('NoDisplay', 'false').lower() == 'true' or entry.get('Hidden', 'false').lower() == 'true'
            found[desktop_id] = None if hidden or entry.get('Type', 'Application') != 'Application' else (
                entry.get('Name', desktop_id[:-8])[:120], [mime for mime in entry.get('MimeType', '').split(';') if mime])
    return {key: value for key, value in found.items() if value is not None}


def candidates(apps, mimes):
    return sorted(({'id': key, 'name': name} for key, (name, types) in apps.items() if mimes[0] in types),
                  key=lambda item: item['name'].lower())


def default_apps(dirs):
    apps = applications(dirs)
    result = []
    for category, mimes in DEFAULT_APP_CATEGORIES:
        try:
            current = run(['xdg-mime', 'query', 'default', mimes[0]]).strip()
        except (OSError, subprocess.SubprocessError):
            return dict(ok=False, reason='xdg-mime-missing')
        result.append(dict(category=category, current=current if DESKTOP_ID.match(current) else '',
                           candidates=candidates(apps, mimes)))
    return dict(ok=True, categories=result)


def handle(request, root, dirs):
    operation = request.get('operation')
    if operation == 'about':
        return about(root)
    if operation == 'time':
        return time_state(root)
    if operation == 'timezones':
        return dict(ok=True, timezones=timezones())
    if operation == 'set-timezone':
        zone = request.get('timezone')
        if not isinstance(zone, str) or not TIMEZONE.match(zone) or zone not in timezones():
            return dict(ok=False, reason='invalid-timezone')
        # Changing the zone asks polkit; leave time for the user to answer the prompt.
        run(['timedatectl', 'set-timezone', zone], timeout=60)
        return dict(ok=True)
    if operation == 'set-ntp':
        if not isinstance(request.get('enabled'), bool):
            return dict(ok=False, reason='invalid-request')
        run(['timedatectl', 'set-ntp', 'true' if request['enabled'] else 'false'], timeout=60)
        return dict(ok=True)
    if operation == 'default-apps':
        return default_apps(dirs)
    if operation == 'set-default-app':
        mimes = dict(DEFAULT_APP_CATEGORIES).get(request.get('category'))
        desktop_id = request.get('desktopId')
        if not mimes or not isinstance(desktop_id, str) or not DESKTOP_ID.match(desktop_id):
            return dict(ok=False, reason='invalid-request')
        if desktop_id not in {item['id'] for item in candidates(applications(dirs), mimes)}:
            return dict(ok=False, reason='unknown-application')
        run(['xdg-mime', 'default', desktop_id] + list(mimes))
        return dict(ok=True)
    raise ValueError('Unsupported operation')


def main():
    parser = argparse.ArgumentParser()
    # Tests point these at a fake tree; the shell leaves them at their defaults.
    parser.add_argument('--fs-root', default='/')
    args = parser.parse_args()
    try:
        raw = sys.stdin.buffer.read(64 * 1024 + 1)
        if len(raw) > 64 * 1024:
            raise ValueError('Request is too large')
        request = json.loads(raw)
        if not isinstance(request, dict):
            raise ValueError('Invalid request')
        result = handle(request, args.fs_root, data_dirs())
    except subprocess.CalledProcessError as error:
        result = dict(ok=False, reason='denied' if error.returncode in (1, 4) else 'failed',
                      message=(error.stderr or '').strip()[:300])
    except subprocess.TimeoutExpired:
        result = dict(ok=False, reason='timeout')
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        result = dict(ok=False, reason='io', message=type(error).__name__)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
