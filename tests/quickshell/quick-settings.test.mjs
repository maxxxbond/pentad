import test from 'node:test';
import assert from 'node:assert/strict';
import { actionForTile, airplaneSnapshot, bluetoothNearby, bluetoothState, parseRadioState, parseVpnProfiles, wifiTileState,
  readbackResult, requestIsCurrent, restoreAirplaneRadios, setting, parseTailscaleStatus, tailscaleProfile,
  mergeVpnProfiles, tailscaleCommand, tailscaleStatusCommand } from '../../quickshell/logic/quick-settings.mjs';

test('Tailscale opens its app without toggling a VPN and blocks unavailable or pending launches', () => {
  assert.deepEqual(actionForTile('appearance', { available: true, active: true }), { kind: 'appearance', appearance: 'light' });
  assert.deepEqual(actionForTile('appearance', { available: true, active: false }), { kind: 'appearance', appearance: 'dark' });
  assert.equal(actionForTile('appearance', { available: true, pending: true }), null);
  assert.deepEqual(actionForTile('screenshot', { available: true }), { kind: 'screenshot' });
  assert.equal(actionForTile('screenshot', { available: false }), null);
  assert.deepEqual(actionForTile('tailscale', { available: true }), { kind: 'desktop', command: 'tailscale' });
  assert.equal(actionForTile('tailscale', { available: false }), null);
  assert.equal(actionForTile('tailscale', { available: true, pending: true }), null);
});

test('overnight mode toggles from its tile only when available and settled', () => {
  assert.deepEqual(actionForTile('overnight', { available: true, active: false }), { kind: 'overnight' });
  assert.deepEqual(actionForTile('overnight', { available: true, active: true }), { kind: 'overnight' });
  assert.equal(actionForTile('overnight', { available: false }), null);
  assert.equal(actionForTile('overnight', { available: true, pending: true }), null);
});

test('backend snapshots preserve missing services as unavailable', () => {
  assert.deepEqual(bluetoothState(null), { available: false, enabled: null, devices: [] });
  assert.deepEqual(setting(false, true, false, 'Unavailable'), {
    available: false, active: false, pending: false, subtitle: 'Unavailable', error: ''
  });
});

test('VPN parsing accepts only saved VPN profiles and marks active UUIDs', () => {
  assert.deepEqual(parseVpnProfiles('a:vpn:Work\\: west\nb:802-11-wireless:Home\nc:wireguard:WireGuard', 'c'), [
    { uuid: 'a', name: 'Work: west', active: false },
    { uuid: 'c', name: 'WireGuard', active: true }
  ]);
});

test('airplane mode snapshots and restores each known radio state', () => {
  const radios = parseRadioState('enabled:disabled');
  assert.deepEqual(airplaneSnapshot(radios, true), { wifi: true, wwan: false, bluetooth: true });
  assert.deepEqual(restoreAirplaneRadios(airplaneSnapshot(radios, true)), [
    ['nmcli', 'radio', 'wifi', 'on'], ['nmcli', 'radio', 'wwan', 'off'],
    ['bluetoothctl', 'power', 'on']
  ]);
  assert.equal(parseRadioState('enabled:unknown'), null);
  assert.equal(restoreAirplaneRadios(null), null);
});

test('stale replies after a new request or device generation are ignored', () => {
  const operation = { id: 'quick-settings-2' };
  assert.equal(requestIsCurrent(operation, 'quick-settings-2', 4, 4), true);
  assert.equal(requestIsCurrent(operation, 'quick-settings-1', 4, 4), false);
  assert.equal(requestIsCurrent(operation, 'quick-settings-2', 4, 5), false);
});

test('network icon toggles the Wi-Fi radio; unavailable and pending controls do nothing', () => {
  assert.deepEqual(actionForTile('network', { available: true, pending: false }),
    { kind: 'wifi', enabled: true });
  assert.equal(actionForTile('bluetooth', { available: false, pending: false }), null);
  assert.equal(actionForTile('vpn', { available: true, pending: true, vpns: [{ uuid: 'x' }] }), null);
});

test('Wi-Fi tile ignores the active wired connection and uses the connected SSID', () => {
  const text = (_uk, en) => en;
  const wired = { kind: 'ready', value: { primary: 'wired', label: 'Ethernet', connected: true,
    wifiEnabled: true, wifiHardwareEnabled: true, devices: [{ type: 'wifi' }], accessPoints: [] } };
  assert.deepEqual(wifiTileState(wired, text),
    { available: true, active: true, subtitle: 'Not connected' });
  wired.value.accessPoints = [{ name: 'Studio', connected: true }];
  assert.equal(wifiTileState(wired, text).subtitle, 'Studio');
  wired.value.wifiEnabled = false;
  wired.value.accessPoints = [];
  assert.equal(wifiTileState(wired, text).subtitle, '');
  wired.value.devices = [{ type: 'wired' }];
  assert.deepEqual(wifiTileState(wired, text), { available: false, active: false, subtitle: 'No adapter' });
});

test('energy tile opens profile selection instead of changing the current profile', () => {
  assert.deepEqual(actionForTile('energy', { available: true, active: false }),
    { kind: 'details', section: 'energy' });
  assert.equal(actionForTile('energy', { available: false }), null);
});

test('Bluetooth selector includes paired devices and prioritizes connected devices', () => {
  const adapter = { enabled: true, devices: { values: [
    { address: 'a', name: 'Keyboard', paired: true, connected: false },
    { address: 'b', name: 'Headset', paired: true, connected: true },
    { address: 'c', name: 'Nearby', paired: false, connected: false }
  ] } };
  assert.deepEqual(bluetoothState(adapter).devices.map(({ id }) => id), ['b', 'a']);
});

test('Bluetooth selector orders devices of one state by name, whatever order the backend lists them', () => {
  const adapter = { enabled: true, devices: { values: [
    { address: 'z', name: 'Zeta', paired: true, connected: false },
    { address: 'm', name: 'Mouse', paired: true, connected: true },
    { address: 'a', name: 'Alpha', paired: true, connected: false },
    { address: 'h', name: 'Headset', paired: true, connected: true }
  ] } };
  assert.deepEqual(bluetoothState(adapter).devices.map(({ id }) => id), ['h', 'm', 'a', 'z']);
});

test('Bluetooth nearby ignores devices whose only name is their address', () => {
  const adapter = { enabled: true, devices: { values: [
    { address: '3E:72:BA:90:95:9C', name: '3E-72-BA-90-95-9C', paired: false, connected: false },
    { address: '44:80:0E:A0:10:88', name: '44-80-0E-A0-10-88', deviceName: '', paired: false, connected: false },
    { address: '46:D6:44:ED:F8:C1', name: '46-D6-44-ED-F8-C1', deviceName: 'JBL Flip', paired: false, connected: false },
    { address: '47:54:89:AE:11:A7', name: 'Pixel Buds', deviceName: 'Pixel Buds', paired: false, connected: false },
  ] } };
  assert.deepEqual(bluetoothNearby(adapter).map(({ id, label }) => [id, label]),
    [['46:D6:44:ED:F8:C1', 'JBL Flip'], ['47:54:89:AE:11:A7', 'Pixel Buds']]);
});

test('Bluetooth nearby lists named unpaired devices and devices report their battery', () => {
  const adapter = { enabled: true, devices: { values: [
    { address: 'a', name: 'Keyboard', paired: true, connected: false, batteryAvailable: true, battery: 0.426 },
    { address: 'z', name: 'Zeta speaker', paired: false, connected: false, pairing: true },
    { address: 'c', deviceName: 'Alpha mouse', paired: false, connected: false, batteryAvailable: false, battery: 0.9 },
    { address: 'd', paired: false, connected: false },
  ] } };
  assert.equal(bluetoothState(adapter).devices[0].battery, 43);
  assert.deepEqual(bluetoothNearby(adapter).map(({ id, label, pairing, battery }) => [id, label, pairing, battery]),
    [['c', 'Alpha mouse', false, null], ['z', 'Zeta speaker', true, null]]);
  assert.deepEqual(bluetoothNearby(null), []);
});

test('VPN tile selects the active profile and DND asks for the opposite state', () => {
  assert.deepEqual(actionForTile('vpn', { available: true, vpns: [
    { uuid: 'one', active: false }, { uuid: 'two', active: true }
  ] }), { kind: 'vpn', uuid: 'two' });
  assert.deepEqual(actionForTile('dnd', { available: true, active: false }),
    { kind: 'dnd', enabled: true });
});

test('a successful setter stays pending until delayed native readback confirms it', async () => {
  const operation = { pending: true, result: null };
  let resolveReadback;
  const nativeFixture = {
    setRadio: async () => ({ ok: true }),
    readRadio: () => new Promise((resolve) => { resolveReadback = resolve; })
  };
  await nativeFixture.setRadio();
  const readback = nativeFixture.readRadio().then((actual) => {
    operation.result = readbackResult('airplane', { wifi: false, wwan: false, bluetooth: false }, actual);
    operation.pending = false;
  });
  assert.equal(operation.pending, true);
  resolveReadback({ wifi: false, wwan: false, bluetooth: true });
  await readback;
  assert.equal(operation.pending, false);
  assert.deepEqual(operation.result, { ok: false, reason: 'readback-mismatch' });
});

const status = (backend, extra = {}) => JSON.stringify(Object.assign({ BackendState: backend }, extra));

test('Tailscale status maps backend states and tolerates malformed or foreign JSON', () => {
  assert.deepEqual(parseTailscaleStatus(status('Running', { CurrentTailnet: { Name: 'home.ts.net' } })),
    { state: 'running', active: true, tailnet: 'home.ts.net' });
  assert.equal(parseTailscaleStatus(status('Stopped')).active, false);
  assert.equal(parseTailscaleStatus(status('NeedsLogin')).state, 'needs-login');
  assert.equal(parseTailscaleStatus(status('NeedsMachineAuth')).state, 'needs-login');
  assert.equal(parseTailscaleStatus(status('Starting')).state, 'starting');
  assert.equal(parseTailscaleStatus(status('Whatever')).state, 'unknown');
  for (const bad of ['', 'not json', '[]', 'null', '{"BackendState":5}', undefined])
    assert.equal(parseTailscaleStatus(bad), null);
  assert.equal(parseTailscaleStatus(status('Running', { CurrentTailnet: { Name: 7 } })).tailnet, '');
});

test('Tailscale is one more VPN profile only when its status was readable', () => {
  assert.equal(tailscaleProfile(null), null);
  const running = tailscaleProfile(parseTailscaleStatus(status('Running')));
  assert.deepEqual(running, { uuid: 'tailscale', kind: 'tailscale', name: 'Tailscale', detail: '',
    active: true, needsLogin: false });
  const nm = parseVpnProfiles('a:vpn:Work', '');
  assert.deepEqual(mergeVpnProfiles(nm, null), nm);
  assert.deepEqual(mergeVpnProfiles(nm, running).map(item => item.uuid), ['a', 'tailscale']);
  assert.deepEqual(mergeVpnProfiles([], running).map(item => item.uuid), ['tailscale']);
  assert.deepEqual(actionForTile('vpn', { available: true, vpns: mergeVpnProfiles(nm, running) }),
    { kind: 'vpn', uuid: 'tailscale' });
});

test('Tailscale commands switch with up/down and defer to the app when sign-in is needed', () => {
  const profile = (state) => tailscaleProfile(parseTailscaleStatus(status(state)));
  assert.deepEqual(tailscaleCommand(profile('Stopped')), { kind: 'run', argv: ['tailscale', 'up'] });
  assert.deepEqual(tailscaleCommand(profile('Running')), { kind: 'run', argv: ['tailscale', 'down'] });
  assert.deepEqual(tailscaleCommand(profile('NeedsLogin')), { kind: 'login' });
  assert.equal(tailscaleCommand({ kind: 'vpn', uuid: 'a' }), null);
  assert.equal(tailscaleCommand(null), null);
  assert.deepEqual([...tailscaleStatusCommand], ['tailscale', 'status', '--json', '--peers=false']);
  assert.equal(Object.isFrozen(tailscaleStatusCommand), true);
});
