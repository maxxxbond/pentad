import assert from 'node:assert/strict';
import test from 'node:test';
import * as Net from '../../quickshell/logic/network-settings.mjs';

const t = (uk, en) => en;
const device = (fields) => Object.assign({ id: 'eth0', kind: 'ethernet', type: 'ethernet', state: 'disconnected', external: false,
  label: 'eth0', hwaddr: '', mtu: 1500, speed: null, carrier: null, driver: '', connection: '', uuid: '',
  ipv4: [], gateway4: '', ipv6: [], gateway6: '', dns: [], mobile: null }, fields);
const status = (fields) => Object.assign({ ok: true, available: true, version: '1.58', networking: true, connectivity: 'full',
  radios: { wifi: true, wifiHardware: true, wwan: false, wwanHardware: false }, devices: [], connections: [],
  hotspot: null, vpnPlugins: [], modemManager: false }, fields);

test('the overview names the wired link that holds the default route', () => {
  const value = Net.overview(status({ devices: [
    device({ id: 'wlan0', kind: 'wifi', state: 'connected', connection: 'Home', ipv4: ['10.0.0.5/24'] }),
    device({ state: 'connected', speed: 1000, ipv4: ['192.168.1.20/24'], gateway4: '192.168.1.1' }),
  ] }), t);
  assert.equal(value.tone, 'online');
  assert.equal(value.title, 'Ethernet');
  assert.equal(value.subtitle, 'Connected to the internet · 1 Gbit/s · 192.168.1.20');
  assert.equal(value.icon, Net.kindIcon('ethernet'));
});

test('the overview covers loading, missing NetworkManager, offline and a captive portal', () => {
  assert.equal(Net.overview(null, t).tone, 'loading');
  assert.equal(Net.overview({ ok: false, reason: 'nmcli-missing' }, t).title, 'NetworkManager is not installed');
  assert.equal(Net.overview(status({ available: false }), t).tone, 'unavailable');
  assert.equal(Net.overview(status({}), t).title, 'Not connected');
  const portal = Net.overview(status({ connectivity: 'portal', devices: [device({ id: 'wlan0', kind: 'wifi', state: 'connected', connection: 'Cafe', gateway4: '10.0.0.1' })] }), t);
  assert.equal(portal.tone, 'limited');
  assert.equal(portal.title, 'Cafe');
  assert.match(portal.subtitle, /^Sign-in required/);
});

test('active VPNs include links another app manages', () => {
  const value = status({
    connections: [{ uuid: 'a', name: 'Office', kind: 'vpn', active: true }, { uuid: 'b', name: 'Off', kind: 'vpn', active: false }],
    devices: [device({ id: 'tailscale0', kind: 'vpn', type: 'tun', state: 'connected', external: true, label: 'tailscale0' })],
  });
  assert.deepEqual(Net.activeVpns(value), ['Office', 'tailscale0']);
  assert.equal(Net.externalVpns(value).length, 1);
});

test('device subtitles stay short and honest', () => {
  assert.equal(Net.deviceSubtitle(device({ state: 'unavailable' }), t), 'Cable unplugged');
  assert.equal(Net.deviceSubtitle(device({ kind: 'usb', state: 'unavailable' }), t), 'Not connected');
  assert.equal(Net.deviceSubtitle(device({ state: 'connected', speed: 100, ipv4: ['10.1.1.2/8'] }), t), 'Connected · 100 Mbit/s · 10.1.1.2');
  assert.equal(Net.deviceSubtitle(device({ kind: 'vpn', external: true, state: 'connected' }), t), 'Managed by another app');
  assert.equal(Net.formatSpeed(2500, t), '2.5 Gbit/s');
  assert.equal(Net.formatSpeed(-1, t), '');
});

test('saved Wi-Fi puts the connected network first, then the most recent', () => {
  const value = status({ connections: [
    { uuid: '1', name: 'Old', kind: 'wifi', active: false, timestamp: 10 },
    { uuid: '2', name: 'Now', kind: 'wifi', active: true, timestamp: 5 },
    { uuid: '3', name: 'Recent', kind: 'wifi', active: false, timestamp: 20 },
    { uuid: '4', name: 'Hotspot', kind: 'hotspot', active: false, timestamp: 30 },
  ] });
  assert.deepEqual(Net.savedWifi(value).map(item => item.name), ['Now', 'Recent', 'Old']);
});

test('DNS choice recognises presets and builds update settings', () => {
  assert.equal(Net.dnsChoice({ ipv4: { dns: [] }, ipv6: { dns: [] } }), 'auto');
  assert.equal(Net.dnsChoice({ ipv4: { dns: ['1.1.1.1', '1.0.0.1'] }, ipv6: { dns: [] } }), 'cloudflare');
  assert.equal(Net.dnsChoice({ ipv4: { dns: ['192.168.1.2'] }, ipv6: { dns: [] } }), 'custom');
  assert.deepEqual(Net.dnsSettings('auto', '').ipv4, { dns: [], ignoreAutoDns: false });
  assert.deepEqual(Net.dnsSettings('quad9', '').ipv4.dns, ['9.9.9.9', '149.112.112.112']);
  const custom = Net.dnsSettings('custom', '192.168.1.2, 2001:db8::1');
  assert.deepEqual(custom.ipv4, { dns: ['192.168.1.2'], ignoreAutoDns: true });
  assert.deepEqual(custom.ipv6, { dns: ['2001:db8::1'], ignoreAutoDns: true });
  assert.equal(Net.dnsSettings('custom', 'example.com').error, 'dns-invalid');
  assert.equal(Net.dnsSettings('custom', ' ').error, 'dns-empty');
});

test('addresses parse with default prefixes and reject garbage', () => {
  assert.equal(Net.parseCidr('192.168.1.20', 'ipv4'), '192.168.1.20/24');
  assert.equal(Net.parseCidr('10.0.0.2/8', 'ipv4'), '10.0.0.2/8');
  assert.equal(Net.parseCidr('2001:db8::5', 'ipv6'), '2001:db8::5/64');
  assert.equal(Net.parseCidr('256.1.1.1', 'ipv4'), null);
  assert.equal(Net.parseCidr('10.0.0.1/33', 'ipv4'), null);
  assert.equal(Net.parseCidr('10.0.0.1/', 'ipv4'), null);
  assert.equal(Net.parseCidr('2001:db8::5', 'ipv4'), null);
  assert.equal(Net.isIPv6('::1'), true);
  assert.equal(Net.isIPv6('1:2:3:4:5:6:7:8'), true);
  assert.equal(Net.isIPv6('1:2:3:4:5:6:7:8:9'), false);
  assert.equal(Net.isIPv6('::ffff:192.0.2.1'), true);
  assert.equal(Net.isIPv6('1::2::3'), false);
  assert.equal(Net.isIPv4('01.2.3.4'), false);
});

test('manual IP settings need an address and a valid gateway', () => {
  assert.deepEqual(Net.ipSettings('ipv4', { method: 'auto' }), { ok: true, value: { method: 'auto', addresses: [], gateway: '' } });
  assert.deepEqual(Net.ipSettings('ipv4', { method: 'manual', addresses: '192.168.1.20', gateway: '192.168.1.1' }).value,
    { method: 'manual', addresses: ['192.168.1.20/24'], gateway: '192.168.1.1' });
  assert.equal(Net.ipSettings('ipv4', { method: 'manual', addresses: '' }).error, 'address-empty');
  assert.equal(Net.ipSettings('ipv4', { method: 'manual', addresses: '1.2.3', gateway: '' }).error, 'address-invalid');
  assert.equal(Net.ipSettings('ipv6', { method: 'manual', addresses: '2001:db8::2', gateway: '10.0.0.1' }).error, 'gateway-invalid');
});

test('passwords, SSIDs and APNs are checked before they reach the helper', () => {
  assert.equal(Net.passwordProblem('short', 'wpa-psk'), 'password-short');
  assert.equal(Net.passwordProblem('long enough', 'sae'), '');
  assert.equal(Net.passwordProblem('a'.repeat(64), 'wpa-psk'), '');
  assert.equal(Net.passwordProblem('x'.repeat(64), 'wpa-psk'), 'password-long');
  assert.equal(Net.passwordProblem('bad\npassword', 'wpa-psk'), 'invalid-password');
  assert.equal(Net.passwordProblem('', 'none'), '');
  // The helper refuses what NetworkManager's editor would mangle; the page says so before sending.
  assert.equal(Net.passwordProblem('пароль-кирилицею', 'wpa-psk'), 'invalid-password');
  assert.equal(Net.passwordProblem(' padded secret', 'wpa-psk'), 'password-spaces');
  assert.equal(Net.secretProblem('carrier pass'), '');
  assert.equal(Net.secretProblem('trailing '), 'password-spaces');
  assert.equal(Net.secretProblem('a\tb'), 'invalid-password');
  assert.equal(Net.ssidProblem(''), 'ssid-empty');
  assert.equal(Net.ssidProblem('Кав’ярня'), '');
  assert.equal(Net.ssidProblem('ї'.repeat(17)), 'ssid-long');
  assert.equal(Net.utf8Length('ї'), 2);
  assert.equal(Net.apnProblem('internet.kyivstar.net'), '');
  assert.equal(Net.apnProblem('bad apn'), 'apn-invalid');
});

test('leaving Manual sends empty addresses and router', () => {
  assert.deepEqual(Net.ipSettings('ipv6', { method: 'ignore' }).value, { method: 'ignore', addresses: [], gateway: '' });
});

test('lists from a delegate (Qt sequences) still read as arrays', () => {
  const qtList = { length: 2, 0: '192.168.1.5/24', 1: 'fe80::1/64' };
  assert.deepEqual(Net.listOf(qtList), ['192.168.1.5/24', 'fe80::1/64']);
  assert.equal(Net.joinAddresses(qtList), '192.168.1.5/24');
  assert.deepEqual(Net.listOf('text'), []);
});

test('a literal MAC address stays selectable', () => {
  assert.equal(Net.macChoices({ mac: 'random' }, t).length, 4);
  assert.equal(Net.macChoices({ mac: '02:00:00:00:00:01' }, t).at(-1).value, '02:00:00:00:00:01');
});

test('every reason has a message in both languages', () => {
  const both = (uk, en) => uk + '|' + en;
  for (const reason of ['preview', 'safe-mode', 'nmcli-missing', 'denied', 'timeout', 'not-found', 'unknown-device', 'plugin-missing',
    'no-wifi', 'invalid-password', 'password-short', 'ssid-empty', 'apn-invalid', 'address-invalid', 'dns-invalid', 'invalid-file']) {
    const [uk, en] = Net.errorText(reason, both).split('|');
    assert.ok(/[а-яіїєґ]/i.test(uk) || /NetworkManager/.test(uk), reason);
    assert.notEqual(uk, en, reason);
  }
  assert.equal(Net.errorText('failed', t, 'Secrets were required'), 'Failed: Secrets were required');
});

test('bluetooth tethers carry their state', () => {
  const value = Net.bluetoothTethers(status({ devices: [device({ id: 'AA:BB:CC:DD:EE:FF', kind: 'bluetooth', label: 'Pixel', state: 'connected' })] }), t);
  assert.deepEqual(value.map(item => [item.label, item.active]), [['Pixel', true]]);
});
