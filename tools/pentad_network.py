#!/usr/bin/env python3
"""Network settings through NetworkManager: status, profile details and edits, Wi-Fi, hotspot, tethering, VPN import.

Reads one JSON request on stdin and prints one JSON reply. Every external program gets an argument array.
Identifiers from a request (a UUID, a device, a Bluetooth address) must match what nmcli listed first.
Secrets never go into argv, where /proc/*/cmdline would show them: they are piped to `nmcli connection edit`.
"""
import argparse
import ipaddress
import json
import os
import re
import secrets
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

NM = ['nmcli', '-t', '-e', 'yes']
UUID = re.compile(r'^[0-9a-fA-F-]{36}$')
MAC = re.compile(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$')
APN = re.compile(r'^[A-Za-z0-9.\-_]{0,62}$')
WG_NAME = re.compile(r'^[A-Za-z0-9_=+.-]{1,15}$')
CONTROL = re.compile(r'[\x00-\x1f\x7f]')
ADDED = re.compile(r"\(([0-9a-fA-F-]{36})\) successfully added")
TETHER_DRIVERS = {'rndis_host', 'cdc_ether', 'cdc_ncm', 'cdc_eem', 'ipheth'}
SKIP_PREFIXES = ('docker', 'br-', 'veth', 'virbr')
DEVICE_KINDS = {'ethernet': 'ethernet', 'wifi': 'wifi', 'bt': 'bluetooth', 'gsm': 'mobile', 'cdma': 'mobile',
                'modem': 'mobile', 'wireguard': 'vpn', 'tun': 'vpn', 'vpn': 'vpn', 'ip-tunnel': 'vpn'}
CONNECTION_KINDS = {'802-3-ethernet': 'ethernet', '802-11-wireless': 'wifi', 'bluetooth': 'bluetooth',
                    'gsm': 'mobile', 'cdma': 'mobile', 'vpn': 'vpn', 'wireguard': 'vpn'}
SECURITY = {'': 'none', 'none': 'wep', 'ieee8021x': 'wep', 'wpa-psk': 'wpa-psk', 'sae': 'sae',
            'wpa-eap': 'wpa-eap', 'wpa-eap-suite-b-192': 'wpa-eap', 'owe': 'owe'}
METHODS = {'ipv4': ('auto', 'manual', 'disabled', 'shared', 'link-local'),
           'ipv6': ('auto', 'dhcp', 'manual', 'ignore', 'disabled', 'link-local', 'shared')}
MAC_MODES = ('permanent', 'random', 'stable', 'preserve', '')
VPN_DIRS = ('usr/lib/NetworkManager/VPN', 'etc/NetworkManager/VPN')
NM_SERVICE = 'org.freedesktop.NetworkManager.'
PROFILE_READS = 64


class Refuse(Exception):
    """A request this helper turns down; carries the reply's reason."""


def run(argv, timeout=10, stdin=None):
    # nmcli translates states; the C locale keeps them parseable. With stdin, stderr joins stdout for checks.
    env = dict(os.environ, LC_ALL='C')
    return subprocess.run(argv, input=stdin, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT if stdin is not None else subprocess.PIPE,
                          text=True, timeout=timeout, check=True, env=env).stdout


def split_terse(line):
    """Split one `nmcli -t -e yes` tabular line on ':' while honouring `\\:` and `\\\\`."""
    fields, current, escaped = [], [], False
    for char in line:
        if escaped:
            current.append(char)
            escaped = False
        elif char == '\\':
            escaped = True
        elif char == ':':
            fields.append(''.join(current))
            current = []
        else:
            current.append(char)
    fields.append(''.join(current))
    return fields


def rows(text, width):
    return [(split_terse(line) + [''] * width)[:width] for line in text.splitlines() if line]


def show_fields(text):
    """`key:value` lines of a `show` command; indexed keys (IP4.ADDRESS[1]) collect into lists."""
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.partition(':')
        if not sep:
            continue
        value = '' if value == '--' else value
        base, bracket, _ = key.partition('[')
        if bracket:
            fields.setdefault(base, []).append(value)
        else:
            fields[key] = value
    return fields


def items(value):
    return [part.strip() for part in (value or '').split(',') if part.strip()]


def read(root, path):
    try:
        return (Path(root) / path).read_text(encoding='utf-8', errors='replace').strip()
    except OSError:
        return ''


def as_int(value, default=None):
    try:
        return int(str(value).split()[0])
    except (ValueError, IndexError):
        return default


def vpn_plugins(root):
    found = []
    for folder in VPN_DIRS:
        base = Path(root) / folder
        for path in sorted(base.glob('*.name')) if base.is_dir() else ():
            match = re.search(r'^service=\s*(\S+)', path.read_text(encoding='utf-8', errors='replace'), re.M)
            name = match.group(1).removeprefix(NM_SERVICE) if match else ''
            if name and name not in found:
                found.append(name)
    return found


def modem_manager():
    try:
        run(['mmcli', '-L'])
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def connection_rows():
    text = run(NM + ['-f', 'NAME,UUID,TYPE,DEVICE,ACTIVE,STATE,AUTOCONNECT,AUTOCONNECT-PRIORITY,TIMESTAMP', 'connection', 'show'])
    return [dict(name=r[0], uuid=r[1], type=r[2], device=r[3], active=r[4] == 'yes',
                 state=r[5] if r[5] in ('activated', 'activating', 'deactivating') else '',
                 autoconnect=r[6] == 'yes', priority=as_int(r[7], 0), timestamp=as_int(r[8], 0))
            for r in rows(text, 9)]


def device_rows():
    return [dict(id=r[0], type=r[1], state=r[2], connection=r[3], uuid=r[4])
            for r in rows(run(NM + ['-f', 'DEVICE,TYPE,STATE,CONNECTION,CON-UUID', 'device']), 5)]


def profile_fields(uuid, fields=None):
    return show_fields(run(NM + (['-f', fields] if fields else []) + ['connection', 'show', 'uuid', uuid]))


def connections():
    """Profiles the UI handles, with their kind; the first hotspot (an active one wins)."""
    result, hotspot, reads = [], None, 0
    for row in connection_rows():
        kind = CONNECTION_KINDS.get(row['type'])
        if not kind:
            continue
        vpn_type = 'wireguard' if row['type'] == 'wireguard' else ''
        if row['type'] in ('802-11-wireless', 'vpn') and reads < PROFILE_READS:
            reads += 1
            fields = profile_fields(row['uuid'], 'vpn.service-type' if kind == 'vpn' else
                                    '802-11-wireless.mode,802-11-wireless.ssid,connection.interface-name')
            if kind == 'vpn':
                vpn_type = fields.get('vpn.service-type', '').removeprefix(NM_SERVICE)
            elif fields.get('802-11-wireless.mode') == 'ap':
                kind = 'hotspot'
                if hotspot is None or (row['active'] and not hotspot['active']):
                    hotspot = dict(uuid=row['uuid'], ssid=fields.get('802-11-wireless.ssid', ''), active=row['active'],
                                   device=row['device'] or fields.get('connection.interface-name', ''))
        result.append(dict(row, kind=kind, vpnType=vpn_type))
    return result, hotspot


def device_state(raw):
    word = raw.split(' ')[0]
    state = {'deactivating': 'disconnecting'}.get(word, word)
    known = ('connected', 'connecting', 'disconnecting', 'disconnected', 'unavailable', 'unmanaged', 'failed')
    return (state if state in known else 'unknown'), 'externally' in raw


def driver(root, interface):
    try:
        return os.path.basename(os.readlink(Path(root) / 'sys/class/net' / interface / 'device/driver'))
    except OSError:
        return ''


def mobile_info(udi):
    if not udi.startswith('/org/freedesktop/ModemManager1/Modem/'):
        return None
    try:
        modem = json.loads(run(['mmcli', '-m', udi, '-J'])).get('modem', {})
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    generic, gpp = modem.get('generic') or {}, modem.get('3gpp') or {}
    clean = lambda value: '' if value in (None, '--') else str(value)
    return dict(operator=clean(gpp.get('operator-name')),
                signal=as_int((generic.get('signal-quality') or {}).get('value')),
                technology=', '.join(clean(t) for t in generic.get('access-technologies') or [] if clean(t)))


def bluetooth_name(address):
    try:
        match = re.search(r'^\s*Name:\s*(.+)$', run(['bluetoothctl', 'info', address]), re.M)
    except (OSError, subprocess.SubprocessError):
        return ''
    return match.group(1).strip() if match else ''


def devices(root):
    result = []
    for row in device_rows():
        name, kind = row['id'], DEVICE_KINDS.get(row['type'])
        state, external = device_state(row['state'])
        if not kind or not name or name.startswith(SKIP_PREFIXES) or '/' in name or name in ('.', '..'):
            continue
        if kind == 'vpn' and state == 'unmanaged':
            continue
        info = show_fields(run(NM + ['-f', 'GENERAL,WIRED-PROPERTIES,IP4,IP6', 'device', 'show', name]))
        drv = driver(root, name) if kind != 'bluetooth' else ''
        if kind == 'ethernet' and drv in TETHER_DRIVERS:
            kind = 'usb'
        label = info.get('GENERAL.PRODUCT') or info.get('GENERAL.VENDOR') or ''
        if kind == 'bluetooth':
            label = bluetooth_name(name) or label
        speed = as_int(read(root, f'sys/class/net/{name}/speed')) if kind != 'bluetooth' else None
        carrier = info.get('WIRED-PROPERTIES.CARRIER')
        ipv6 = sorted(info.get('IP6.ADDRESS', []), key=lambda value: value.lower().startswith('fe80'))
        result.append(dict(
            id=name, kind=kind, type=row['type'], state=state, external=external, label=label or name,
            hwaddr=info.get('GENERAL.HWADDR', ''), mtu=as_int(info.get('GENERAL.MTU')),
            speed=speed if speed and speed > 0 else None,
            carrier=None if carrier in (None, '') else carrier == 'on', driver=drv,
            connection=row['connection'], uuid=row['uuid'],
            ipv4=info.get('IP4.ADDRESS', []), gateway4=info.get('IP4.GATEWAY', ''),
            ipv6=ipv6, gateway6=info.get('IP6.GATEWAY', ''), dns=info.get('IP4.DNS', []) + info.get('IP6.DNS', []),
            mobile=mobile_info(info.get('GENERAL.UDI', '')) if kind == 'mobile' else None))
    return result


def status(root):
    try:
        general = split_terse(run(NM + ['-f', 'RUNNING,VERSION,CONNECTIVITY,NETWORKING', 'general']).strip()) + [''] * 4
    except subprocess.CalledProcessError:
        general = [''] * 4
    available = general[0] == 'running'
    reply = dict(ok=True, available=available, version=general[1] if available else '',
                 networking=available and general[3] == 'enabled',
                 connectivity=general[2] if available and general[2] in ('full', 'limited', 'portal', 'none') else 'unknown',
                 radios=dict(wifi=False, wifiHardware=False, wwan=False, wwanHardware=False),
                 devices=[], connections=[], hotspot=None, vpnPlugins=vpn_plugins(root), modemManager=modem_manager())
    if not available:
        return reply
    radio = rows(run(NM + ['-f', 'WIFI-HW,WIFI,WWAN-HW,WWAN', 'radio']), 4)
    if radio:
        on = [value == 'enabled' for value in radio[0]]
        reply['radios'] = dict(wifiHardware=on[0], wifi=on[1], wwanHardware=on[2], wwan=on[3])
    reply['connections'], reply['hotspot'] = connections()
    reply['devices'] = devices(root)
    return reply


# --- validation -------------------------------------------------------------------------------------------

def text_value(value, limit):
    if not isinstance(value, str) or not value or CONTROL.search(value) or len(value) > limit:
        raise Refuse('invalid-request')
    return value


def ssid_value(value):
    if not isinstance(value, str) or not value or CONTROL.search(value) or len(value.encode('utf-8')) > 32:
        raise Refuse('invalid-request')
    return value


def psk_value(value):
    # nmcli's editor strips the value, so surrounding spaces would silently change the key.
    if not isinstance(value, str) or CONTROL.search(value) or value != value.strip():
        raise Refuse('invalid-password')
    if re.fullmatch(r'[0-9A-Fa-f]{64}', value) or (8 <= len(value) <= 63 and value.isascii() and value.isprintable()):
        return value
    raise Refuse('invalid-password')


def plain_secret(value):
    if not isinstance(value, str) or CONTROL.search(value) or len(value) > 256 or value != value.strip():
        raise Refuse('invalid-password')
    return value


def known_connection(request):
    uuid = request.get('uuid')
    if not isinstance(uuid, str) or not UUID.match(uuid):
        raise Refuse('invalid-request')
    for row in connection_rows():
        if row['uuid'].lower() == uuid.lower():
            return row
    raise Refuse('unknown-connection')


def known_device(request):
    device = request.get('device')
    if not isinstance(device, str) or not device or CONTROL.search(device):
        raise Refuse('invalid-request')
    for row in device_rows():
        if row['id'] == device:
            return row
    raise Refuse('unknown-device')


def ip_section(family, value, current):
    """Validated `nmcli connection modify` pairs for one ipv4/ipv6 object."""
    version = 4 if family == 'ipv4' else 6
    if not isinstance(value, dict) or set(value) - {'method', 'addresses', 'gateway', 'dns', 'ignoreAutoDns'}:
        raise Refuse('invalid-request')
    pairs = []

    def ips(key, limit, parse):
        listed = value[key]
        if not isinstance(listed, list) or len(listed) > limit or not all(isinstance(item, str) for item in listed):
            raise Refuse('invalid-request')
        try:
            parsed = [parse(item.strip()) for item in listed]
        except ValueError:
            raise Refuse('invalid-request') from None
        if any(item.version != version for item in parsed):
            raise Refuse('invalid-request')
        return [str(item) for item in parsed]

    method = value.get('method', current['method'])
    if method not in METHODS[family]:
        raise Refuse('invalid-request')
    if 'method' in value:
        pairs += [f'{family}.method', method]
    # Leaving Manual drops its static addresses; methods without IP config also take no DNS.
    bare = method in ('disabled', 'link-local', 'ignore')
    if bare and value.get('dns'):
        raise Refuse('invalid-request')
    if 'method' in value and method != 'manual' and method != 'shared':
        value = dict(value, addresses=value.get('addresses', []), gateway=value.get('gateway', ''))
        if bare:
            value.update(dns=[], ignoreAutoDns=False)
    addresses = ips('addresses', 8, ipaddress.ip_interface) if 'addresses' in value else current['addresses']
    if 'addresses' in value:
        pairs += [f'{family}.addresses', ','.join(addresses)]
    if method == 'manual' and not addresses:
        raise Refuse('invalid-request')
    if 'gateway' in value:
        gateway = value['gateway']
        if not isinstance(gateway, str):
            raise Refuse('invalid-request')
        pairs += [f'{family}.gateway', ips_one(gateway.strip(), version) if gateway.strip() else '']
    elif not addresses and current['gateway']:
        pairs += [f'{family}.gateway', '']  # NM rejects a gateway without addresses
    if 'dns' in value:
        pairs += [f'{family}.dns', ','.join(ips('dns', 4, ipaddress.ip_address))]
    if 'ignoreAutoDns' in value:
        if not isinstance(value['ignoreAutoDns'], bool):
            raise Refuse('invalid-request')
        pairs += [f'{family}.ignore-auto-dns', 'yes' if value['ignoreAutoDns'] else 'no']
    return pairs


def ips_one(text, version):
    try:
        address = ipaddress.ip_address(text)
    except ValueError:
        raise Refuse('invalid-request') from None
    if address.version != version:
        raise Refuse('invalid-request')
    return str(address)


# --- profiles ---------------------------------------------------------------------------------------------

def details_of(uuid):
    fields = profile_fields(uuid)
    kind_type = fields.get('connection.type', '')
    wifi = kind_type == '802-11-wireless'
    kind = CONNECTION_KINDS.get(kind_type, '')
    if wifi and fields.get('802-11-wireless.mode') == 'ap':
        kind = 'hotspot'
    key_mgmt = fields.get('802-11-wireless-security.key-mgmt', '')

    def section(family):
        return dict(method=fields.get(f'{family}.method', ''), addresses=items(fields.get(f'{family}.addresses')),
                    gateway=fields.get(f'{family}.gateway', ''), dns=items(fields.get(f'{family}.dns')),
                    ignoreAutoDns=fields.get(f'{family}.ignore-auto-dns') == 'yes')

    metered = fields.get('connection.metered', 'unknown')
    return dict(ok=True, uuid=fields.get('connection.uuid', uuid), name=fields.get('connection.id', ''),
                kind=kind, type=kind_type, autoconnect=fields.get('connection.autoconnect') == 'yes',
                priority=as_int(fields.get('connection.autoconnect-priority'), 0),
                metered=metered if metered in ('yes', 'no') else 'unknown',
                ipv4=section('ipv4'), ipv6=section('ipv6'),
                mac=fields.get('802-3-ethernet.cloned-mac-address') or fields.get('802-11-wireless.cloned-mac-address') or '',
                ssid=fields.get('802-11-wireless.ssid', '') if wifi else '',
                hidden=wifi and fields.get('802-11-wireless.hidden') == 'yes',
                security=SECURITY.get(key_mgmt, '') if wifi else '',
                hasSecret=wifi and key_mgmt in ('wpa-psk', 'sae') and bool(fields.get('802-11-wireless-security.psk')),
                # Flag 1 = the user's secret agent (a keyring) keeps the key; NetworkManager cannot show it.
                secretInKeyring=wifi and as_int(fields.get('802-11-wireless-security.psk-flags', '0').split()[0], 0) & 1 == 1,
                apn=fields.get('gsm.apn', '') if kind == 'mobile' else '')


def modify(uuid, pairs):
    if pairs:
        run(['nmcli', 'connection', 'modify', 'uuid', uuid] + pairs, timeout=60)


def save_secret(uuid, key, secret):
    """Store a secret through nmcli's editor on stdin; the profile must have autoconnect off meanwhile."""
    def scrub(text):
        return (text or '').replace(secret, '***')
    try:
        output = run(['nmcli', 'connection', 'edit', 'uuid', uuid], timeout=60,
                     stdin=f'set {key} {secret}\nsave persistent\nquit\n')
    except subprocess.CalledProcessError as error:
        raise subprocess.CalledProcessError(error.returncode, ['nmcli', 'connection', 'edit'],
                                            stderr=scrub(error.stdout or error.stderr)) from None
    failure = re.search(r'\bError:.*$', output or '', re.M)  # the editor reports errors and still exits 0
    if failure:
        raise subprocess.CalledProcessError(4, ['nmcli', 'connection', 'edit'], stderr=scrub(failure.group(0)))


def up(uuid, extra=()):
    run(['nmcli', 'connection', 'up', 'uuid', uuid] + list(extra), timeout=45)


def add(argv):
    """`nmcli connection add …` and the new profile's UUID (from its message, else from a re-list)."""
    before = {row['uuid'] for row in connection_rows()}
    match = ADDED.search(run(['nmcli', 'connection', 'add'] + argv, timeout=60))
    if match:
        return match.group(1)
    fresh = [row['uuid'] for row in connection_rows() if row['uuid'] not in before]
    if not fresh:
        raise subprocess.CalledProcessError(4, ['nmcli', 'connection', 'add'], stderr='New profile not found')
    return fresh[0]


def finish_new(uuid, key, secret):
    """Secret, autoconnect, activation for a profile created with autoconnect off; it stays if activation fails."""
    try:
        if secret:
            save_secret(uuid, key, secret)
        modify(uuid, ['connection.autoconnect', 'yes'])
    except subprocess.CalledProcessError:
        # A profile without its secret would only fail later and pile up on retries.
        run(['nmcli', 'connection', 'delete', 'uuid', uuid], timeout=30)
        raise
    try:
        up(uuid)
    except subprocess.CalledProcessError as error:
        return dict(ok=False, reason='failed', message=first_line(error), uuid=uuid)
    return dict(ok=True, uuid=uuid)


def update(request):
    row = known_connection(request)
    settings = request.get('settings')
    allowed = {'name', 'autoconnect', 'priority', 'metered', 'ipv4', 'ipv6', 'mac', 'hidden', 'password', 'apn'}
    if not isinstance(settings, dict) or set(settings) - allowed:
        raise Refuse('invalid-request')
    current = details_of(row['uuid'])
    kind, pairs = current['kind'], []
    if 'name' in settings:
        pairs += ['connection.id', text_value(settings['name'], 64)]
    autoconnect = settings.get('autoconnect', current['autoconnect'])
    if not isinstance(autoconnect, bool):
        raise Refuse('invalid-request')
    if 'priority' in settings:
        priority = settings['priority']
        if not isinstance(priority, int) or isinstance(priority, bool) or not -999 <= priority <= 999:
            raise Refuse('invalid-request')
        pairs += ['connection.autoconnect-priority', str(priority)]
    if 'metered' in settings:
        if settings['metered'] not in ('yes', 'no', 'unknown'):
            raise Refuse('invalid-request')
        pairs += ['connection.metered', settings['metered']]
    for family in ('ipv4', 'ipv6'):
        if family in settings:
            pairs += ip_section(family, settings[family], current[family])
    if 'mac' in settings:
        mac = settings['mac']
        setting = {'ethernet': '802-3-ethernet', 'wifi': '802-11-wireless', 'hotspot': '802-11-wireless'}.get(kind)
        literal = isinstance(mac, str) and MAC.match(mac) and not int(mac[:2], 16) & 1
        if not setting or not (mac in MAC_MODES or literal):
            raise Refuse('invalid-request')
        pairs += [f'{setting}.cloned-mac-address', mac.upper() if literal else mac]
    if 'hidden' in settings:
        if kind != 'wifi' or not isinstance(settings['hidden'], bool):
            raise Refuse('invalid-request')
        pairs += ['802-11-wireless.hidden', 'yes' if settings['hidden'] else 'no']
    if 'apn' in settings:
        if kind != 'mobile' or not isinstance(settings['apn'], str) or not APN.match(settings['apn']):
            raise Refuse('invalid-request')
        pairs += ['gsm.apn', settings['apn']]
    password = None
    if 'password' in settings:
        if kind not in ('wifi', 'hotspot') or current['security'] not in ('wpa-psk', 'sae'):
            raise Refuse('invalid-request')
        password = psk_value(settings['password'])
        pairs += ['802-11-wireless-security.psk-flags', '0']
    if password is not None:
        modify(row['uuid'], pairs + ['connection.autoconnect', 'no'])
        try:
            save_secret(row['uuid'], '802-11-wireless-security.psk', password)
        finally:
            if autoconnect:
                modify(row['uuid'], ['connection.autoconnect', 'yes'])
    else:
        if 'autoconnect' in settings:
            pairs += ['connection.autoconnect', 'yes' if autoconnect else 'no']
        modify(row['uuid'], pairs)
    return dict(ok=True, reapplied=apply_live(row, settings))


def apply_live(row, settings):
    """Bring a change to an active link with the least disruption; name, priority and auto-connect need nothing."""
    if not row['active']:
        return False
    if set(settings) & {'mac', 'hidden', 'password', 'apn'}:
        up(row['uuid'])
        return True
    if set(settings) & {'ipv4', 'ipv6', 'metered'}:
        try:
            if not row['device']:
                raise subprocess.CalledProcessError(4, ['nmcli', 'device', 'reapply'])
            run(['nmcli', 'device', 'reapply', row['device']], timeout=30)
        except subprocess.CalledProcessError:
            up(row['uuid'])  # some changes cannot be reapplied in place
        return True
    return False


def wifi_devices():
    return [row['id'] for row in device_rows() if row['type'] == 'wifi']


def hotspot(request):
    enabled = request.get('enabled')
    if not isinstance(enabled, bool):
        raise Refuse('invalid-request')
    _, current = connections()
    if not enabled:
        if current and current['active']:
            run(['nmcli', 'connection', 'down', 'uuid', current['uuid']], timeout=30)
        return dict(ok=True, uuid=current['uuid'] if current else '')
    ssid = ssid_value(request['ssid']) if request.get('ssid') is not None else None
    password = psk_value(request['password']) if request.get('password') is not None else None
    radios = wifi_devices()
    if 'device' in request and request['device'] is not None:
        device = known_device(request)['id']
        if device not in radios:
            raise Refuse('no-wifi')
    elif radios:
        device = radios[0]
    else:
        raise Refuse('no-wifi')
    if current:
        uuid = current['uuid']
        details = details_of(uuid)
        modify(uuid, (['802-11-wireless.ssid', ssid] if ssid else []) +
               (['connection.autoconnect', 'no'] if password and details['autoconnect'] else []))
        if password:
            try:
                save_secret(uuid, '802-11-wireless-security.psk', password)
            finally:
                if details['autoconnect']:
                    modify(uuid, ['connection.autoconnect', 'yes'])
    else:
        ssid = ssid or ssid_value((socket.gethostname() or 'Pentad')[:32])
        password = password or secrets.token_urlsafe(12)  # readable later through the `secret` operation
        uuid = add(['type', 'wifi', 'con-name', 'Hotspot', 'ifname', device, 'ssid', ssid,
                    '802-11-wireless.mode', 'ap', '802-11-wireless.band', 'bg', 'ipv4.method', 'shared',
                    'ipv6.method', 'ignore', 'wifi-sec.key-mgmt', 'wpa-psk', 'connection.autoconnect', 'no'])
        save_secret(uuid, '802-11-wireless-security.psk', password)
    up(uuid, ['ifname', device])
    return dict(ok=True, uuid=uuid)


def bluetooth_tether(request):
    address, enabled = request.get('address'), request.get('enabled')
    if not isinstance(address, str) or not MAC.match(address) or not isinstance(enabled, bool):
        raise Refuse('invalid-request')
    address = address.upper()
    if address not in {row['id'].upper() for row in device_rows() if row['type'] == 'bt'}:
        raise Refuse('unknown-device')
    profiles = [row for row in connection_rows() if row['type'] == 'bluetooth']
    found = next((row for row in profiles[:PROFILE_READS]
                  if profile_fields(row['uuid'], 'bluetooth.bdaddr').get('bluetooth.bdaddr', '').upper() == address), None)
    if not enabled:
        if found and found['active']:
            run(['nmcli', 'connection', 'down', 'uuid', found['uuid']], timeout=30)
        return dict(ok=True, uuid=found['uuid'] if found else '')
    if found:
        uuid = found['uuid']
    else:
        label = CONTROL.sub('', bluetooth_name(address))[:56] or address
        uuid = add(['type', 'bluetooth', 'con-name', f'{label} Network', 'bluetooth.type', 'panu',
                    'bluetooth.bdaddr', address, 'connection.autoconnect', 'no'])
    up(uuid)
    return dict(ok=True, uuid=uuid)


def mobile_add(request):
    apn = request.get('apn')
    if not isinstance(apn, str) or not APN.match(apn):
        raise Refuse('invalid-request')
    username = request.get('username') or ''
    password = plain_secret(request['password']) if request.get('password') else ''
    argv = ['type', 'gsm', 'ifname', '*', 'con-name', 'Mobile broadband', 'gsm.apn', apn]
    if username:
        argv += ['gsm.username', text_value(username, 64)]
    uuid = add(argv + ['connection.autoconnect', 'no'])
    return finish_new(uuid, 'gsm.password', password)


def join_hidden(request):
    ssid, security = ssid_value(request.get('ssid')), request.get('security')
    if security not in ('none', 'wpa-psk', 'sae'):
        raise Refuse('invalid-request')
    password = psk_value(request.get('password')) if security != 'none' else ''
    argv = ['type', 'wifi', 'con-name', ssid, 'ssid', ssid, '802-11-wireless.hidden', 'yes', 'connection.autoconnect', 'no']
    uuid = add(argv + (['wifi-sec.key-mgmt', security] if security != 'none' else []))
    return finish_new(uuid, '802-11-wireless-security.psk', password)


def vpn_file(request, root):
    """Validated import type and real path of a VPN file."""
    path, kind = request.get('path'), request.get('type', 'auto')
    if not isinstance(path, str) or not os.path.isabs(path) or '\x00' in path or kind not in ('auto', 'wireguard', 'openvpn'):
        raise Refuse('invalid-request')
    real = os.path.realpath(path)
    try:
        info = os.stat(real)
    except OSError:
        raise Refuse('invalid-file') from None
    extension = os.path.splitext(real)[1].lower()
    if not stat.S_ISREG(info.st_mode) or info.st_size > 256 * 1024 or extension not in ('.conf', '.ovpn'):
        raise Refuse('invalid-file')
    if kind == 'auto':
        text = Path(real).read_text(encoding='utf-8', errors='replace') if extension == '.conf' else ''
        interface = re.search(r'^\s*\[Interface\]\s*$(.*?)(?=^\s*\[|\Z)', text, re.M | re.S)
        kind = 'wireguard' if interface and re.search(r'^\s*PrivateKey\s*=', interface.group(1), re.M) else 'openvpn'
    if kind == 'wireguard' and extension != '.conf':
        raise Refuse('invalid-file')
    if kind == 'openvpn' and 'openvpn' not in vpn_plugins(root):
        raise Refuse('plugin-missing')
    return kind, real


def import_vpn(request, root):
    kind, real = vpn_file(request, root)
    with tempfile.TemporaryDirectory() as folder:
        stem = os.path.splitext(os.path.basename(real))[0]
        if kind == 'wireguard' and not WG_NAME.match(stem):
            # NetworkManager names the WireGuard interface after the file.
            safe = re.sub(r'[^A-Za-z0-9_=+.-]', '', stem)[:12] or 'vpn'
            copy = os.path.join(folder, f'wg-{safe}.conf')
            shutil.copyfile(real, copy)
            real = copy
        output = run(['nmcli', 'connection', 'import', 'type', kind, 'file', real], timeout=60)
    match = re.search(r"Connection '(.*)' \(([0-9a-fA-F-]{36})\) successfully added", output)
    if not match:
        raise subprocess.CalledProcessError(4, ['nmcli', 'connection', 'import'], stderr='Imported profile not found')
    name, uuid = match.group(1), match.group(2)
    # Imported profiles stay down until the user connects them.
    modify(uuid, ['connection.autoconnect', 'no'])
    if any(row['uuid'] == uuid and row['active'] for row in connection_rows()):
        run(['nmcli', 'connection', 'down', 'uuid', uuid], timeout=30)
    return dict(ok=True, uuid=uuid, name=name)


def handle(request, root='/'):
    try:
        return dispatch(request, root)
    except Refuse as refusal:
        return dict(ok=False, reason=str(refusal))


def dispatch(request, root):
    operation = request.get('operation')
    if operation == 'status':
        return status(root)
    if operation == 'details':
        return details_of(known_connection(request)['uuid'])
    if operation == 'secret':
        row = known_connection(request)
        if row['type'] != '802-11-wireless':
            raise Refuse('invalid-request')
        # Showing secrets may ask polkit; leave time for the user to answer.
        output = run(['nmcli', '-s', '-t', '-e', 'yes', '-g', '802-11-wireless-security.psk',
                      'connection', 'show', 'uuid', row['uuid']], timeout=60)
        return dict(ok=True, secret=re.sub(r'\\(.)', r'\1', output.rstrip('\n')))
    if operation == 'update':
        return update(request)
    if operation in ('activate', 'deactivate', 'forget'):
        uuid = known_connection(request)['uuid']
        verb, timeout = {'activate': ('up', 45), 'deactivate': ('down', 30), 'forget': ('delete', 60)}[operation]
        run(['nmcli', 'connection', verb, 'uuid', uuid], timeout=timeout)
        return dict(ok=True)
    if operation in ('connect-device', 'disconnect-device'):
        device = known_device(request)['id']
        run(['nmcli', 'device', operation.split('-')[0], device], timeout=45)
        return dict(ok=True)
    if operation == 'radio':
        if request.get('radio') not in ('wifi', 'wwan') or not isinstance(request.get('enabled'), bool):
            raise Refuse('invalid-request')
        run(['nmcli', 'radio', request['radio'], 'on' if request['enabled'] else 'off'], timeout=30)
        return dict(ok=True)
    if operation == 'join-hidden':
        return join_hidden(request)
    if operation == 'hotspot':
        return hotspot(request)
    if operation == 'bluetooth-tether':
        return bluetooth_tether(request)
    if operation == 'mobile-add':
        return mobile_add(request)
    if operation == 'import-vpn':
        return import_vpn(request, root)
    raise ValueError('Unsupported operation')


def first_line(error):
    lines = (error.stderr or error.stdout or '').strip().splitlines()
    return lines[0][:300] if lines else ''


def main():
    parser = argparse.ArgumentParser()
    # Tests point this at a fake tree; the shell leaves it at its default.
    parser.add_argument('--fs-root', default='/')
    args = parser.parse_args()
    try:
        raw = sys.stdin.buffer.read(64 * 1024 + 1)
        if len(raw) > 64 * 1024:
            raise ValueError('Request is too large')
        request = json.loads(raw)
        if not isinstance(request, dict):
            raise ValueError('Invalid request')
        result = handle(request, args.fs_root)
    except subprocess.CalledProcessError as error:
        if error.returncode == 3:
            result = dict(ok=False, reason='timeout')
        elif error.returncode == 10:
            result = dict(ok=False, reason='not-found')
        else:
            result = dict(ok=False, reason='failed', message=first_line(error))
    except subprocess.TimeoutExpired:
        result = dict(ok=False, reason='timeout')
    except FileNotFoundError as error:
        missing = error.filename == 'nmcli' or (not error.filename and str(error) == 'nmcli')
        result = dict(ok=False, reason='nmcli-missing') if missing else dict(ok=False, reason='io', message=type(error).__name__)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        result = dict(ok=False, reason='io', message=type(error).__name__)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
