function splitEscaped(line) {
  const fields = [];
  let value = '', escaped = false;
  for (const char of String(line)) {
    if (escaped) { value += char; escaped = false; }
    else if (char === '\\') escaped = true;
    else if (char === ':') { fields.push(value); value = ''; }
    else value += char;
  }
  if (escaped) value += '\\';
  fields.push(value);
  return fields;
}

export function parseVpnProfiles(profilesText, activeText) {
  const active = new Set(String(activeText || '').split(/\r?\n/).filter(Boolean));
  const byUuid = new Map();
  for (const line of String(profilesText || '').split(/\r?\n/)) {
    if (!line) continue;
    const fields = splitEscaped(line);
    const uuid = fields[0], type = fields[1], name = fields[2];
    if (!uuid || !['vpn', 'wireguard'].includes(type)) continue;
    byUuid.set(uuid, { uuid: uuid, name: name || 'VPN', active: active.has(uuid) });
  }
  return Array.from(byUuid.values());
}

export const tailscaleUuid = 'tailscale';
export const tailscaleStatusCommand = Object.freeze(['tailscale', 'status', '--json', '--peers=false']);

export function parseTailscaleStatus(text) {
  let value;
  try { value = JSON.parse(String(text || '')); } catch (error) { return null; }
  if (!value || typeof value !== 'object' || typeof value.BackendState !== 'string') return null;
  const states = { Running: 'running', Stopped: 'stopped', Starting: 'starting',
    NeedsLogin: 'needs-login', NeedsMachineAuth: 'needs-login' };
  const state = states[value.BackendState] || 'unknown';
  const tailnet = value.CurrentTailnet && typeof value.CurrentTailnet.Name === 'string'
    ? value.CurrentTailnet.Name : '';
  return { state, active: state === 'running', tailnet };
}

export function tailscaleProfile(status) {
  if (!status) return null;
  return { uuid: tailscaleUuid, kind: 'tailscale', name: 'Tailscale', detail: status.tailnet,
    active: status.active, needsLogin: status.state === 'needs-login' };
}

export function mergeVpnProfiles(profiles, tailscale) {
  const list = Array.isArray(profiles) ? profiles : [];
  return tailscale ? list.concat([tailscale]) : list;
}

export function tailscaleCommand(profile) {
  if (!profile || profile.kind !== 'tailscale') return null;
  if (profile.needsLogin) return { kind: 'login' };
  return { kind: 'run', argv: ['tailscale', profile.active ? 'down' : 'up'] };
}

export function parseRadioState(text) {
  const fields = splitEscaped(String(text || '').trim());
  if (fields.length < 2 || !['enabled', 'disabled'].includes(fields[0])
      || !['enabled', 'disabled'].includes(fields[1])) return null;
  return { wifi: fields[0] === 'enabled', wwan: fields[1] === 'enabled' };
}

export function airplaneSnapshot(radio, bluetoothEnabled) {
  if (!radio || typeof radio.wifi !== 'boolean' || typeof radio.wwan !== 'boolean') return null;
  return { wifi: radio.wifi, wwan: radio.wwan,
    bluetooth: typeof bluetoothEnabled === 'boolean' ? bluetoothEnabled : null };
}

export function restoreAirplaneRadios(snapshot) {
  if (!snapshot || typeof snapshot.wifi !== 'boolean' || typeof snapshot.wwan !== 'boolean') return null;
  const commands = [
    ['nmcli', 'radio', 'wifi', snapshot.wifi ? 'on' : 'off'],
    ['nmcli', 'radio', 'wwan', snapshot.wwan ? 'on' : 'off'],
  ];
  if (snapshot.bluetooth === true) commands.push(['bluetoothctl', 'power', 'on']);
  else if (snapshot.bluetooth === false) commands.push(['bluetoothctl', 'power', 'off']);
  return commands;
}

export function requestIsCurrent(operation, requestId, generation, currentGeneration) {
  return !!operation && operation.id === requestId && generation === currentGeneration;
}

export function readbackResult(kind, expected, actual) {
  if (kind === 'vpn') {
    const ok = typeof actual === 'boolean' && actual === expected;
    return { ok, reason: ok ? 'ok' : 'readback-mismatch' };
  }
  if (kind === 'airplane' && expected && actual) {
    const radioMatch = typeof expected.wifi === 'boolean' && expected.wifi === actual.wifi
      && typeof expected.wwan === 'boolean' && expected.wwan === actual.wwan;
    const bluetoothMatch = expected.bluetooth === null || expected.bluetooth === undefined
      || expected.bluetooth === actual.bluetooth;
    const ok = radioMatch && bluetoothMatch;
    return { ok, reason: ok ? 'ok' : 'readback-mismatch' };
  }
  return { ok: false, reason: 'readback-unavailable' };
}

export function setting(available, active, pending, subtitle, error) {
  return { available: available === true, active: available === true && active === true,
    pending: pending === true, subtitle: String(subtitle || ''), error: String(error || '') };
}

export function actionForTile(key, snapshot) {
  const state = snapshot || {};
  if (state.available !== true || state.pending === true) return null;
  if (key === 'tailscale') return { kind: 'desktop', command: 'tailscale' };
  if (key === 'network') return { kind: 'wifi', enabled: state.active !== true };
  if (key === 'bluetooth' || key === 'airplane' || key === 'night')
    return { kind: 'toggle', setting: key };
  if (key === 'vpn') {
    const profiles = Array.isArray(state.vpns) ? state.vpns : [];
    const profile = profiles.find((item) => item.active) || profiles[0];
    return profile ? { kind: 'vpn', uuid: profile.uuid } : null;
  }
  if (key === 'inhibit') return { kind: 'inhibit' };
  if (key === 'dnd') return { kind: 'dnd', enabled: state.active !== true };
  if (key === 'energy') return { kind: 'details', section: 'energy' };
  if (key === 'appearance') return { kind: 'appearance', appearance: state.active === true ? 'light' : 'dark' };
  if (key === 'screenshot') return { kind: 'screenshot' };
  return null;
}

export function wifiTileState(networkState, text) {
  if (!networkState || networkState.kind !== 'ready')
    return { available: false, active: false, subtitle: text('Недоступно', 'Unavailable') };
  const value = networkState.value || {};
  if (!(value.devices || []).some((device) => device.type === 'wifi'))
    return { available: false, active: false, subtitle: text('Немає адаптера', 'No adapter') };
  if (value.wifiHardwareEnabled !== true)
    return { available: false, active: false, subtitle: text('Заблоковано апаратно', 'Hardware blocked') };
  const active = value.wifiEnabled === true;
  const connected = (value.accessPoints || []).find((point) => point.connected);
  return {
    available: value.wifiHardwareEnabled === true && typeof value.wifiEnabled === 'boolean',
    active,
    subtitle: value.wifiEnabled === false ? '' : connected ? connected.name : value.wifiEnabled === null
      ? text('Стан невідомий', 'State unknown') : text('Не підключено', 'Not connected')
  };
}

// BlueZ aliases a device that has no name to its own address ("3E-72-BA-90-95-9C"), so a name
// that is only the address is not a name.
const hexOnly = (value) => String(value).replace(/[^0-9a-f]/gi, '').toLowerCase();
function realName(device) {
  const address = device.address ? hexOnly(device.address) : '';
  const isName = (value) => !!value && (!address || hexOnly(value) !== address);
  if (isName(device.name)) return device.name;
  if (isName(device.deviceName)) return device.deviceName;
  return '';
}

// Battery is 0..1 in Quickshell.Bluetooth; it is reported as a whole percent, or null when unknown.
function bluetoothDevice(device) {
  return {
    id: device.address || device.dbusPath, label: realName(device) || device.name || device.deviceName || 'Bluetooth device',
    connected: device.connected === true, paired: device.paired === true, pairing: device.pairing === true,
    battery: device.batteryAvailable === true && Number.isFinite(device.battery)
      ? Math.round(Math.max(0, Math.min(1, device.battery)) * 100) : null,
  };
}
const adapterDevices = (adapter) => adapter && adapter.devices && adapter.devices.values ? adapter.devices.values : [];

export function bluetoothState(adapter) {
  if (!adapter) return { available: false, enabled: null, devices: [] };
  return { available: true, enabled: adapter.enabled === true,
    devices: adapterDevices(adapter).filter((device) => device.paired || device.connected).map(bluetoothDevice)
      .sort((a, b) => Number(b.connected) - Number(a.connected) || a.label.localeCompare(b.label)) };
}

// Unpaired devices found by a scan; nameless ones are skipped because only an address is not a choice.
export function bluetoothNearby(adapter) {
  return adapterDevices(adapter).filter((device) => !device.paired && !device.connected && !!realName(device))
    .map(bluetoothDevice).sort((a, b) => a.label.localeCompare(b.label));
}
