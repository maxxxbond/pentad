const states = new Map([[0, 'unknown'], [1, 'connecting'], [2, 'connected'], [3, 'disconnecting'], [4, 'disconnected']]);
const security = new Map([
  [0, 'WPA3 Enterprise'], [1, 'WPA3'], [2, 'WPA2 Enterprise'], [3, 'WPA2'],
  [4, 'WPA Enterprise'], [5, 'WPA'], [6, 'WEP'], [7, 'WEP'], [8, 'LEAP'],
  [9, 'Enhanced Open'], [10, 'Open'], [11, 'Unknown']
]);
const connectivity = new Map([[0, 'unknown'], [1, 'none'], [2, 'portal'], [3, 'limited'], [4, 'full']]);
const failures = new Map([
  [0, 'connection-failed'], [1, 'secrets-required'], [2, 'wifi-disconnected'],
  [3, 'wifi-failed'], [4, 'authentication-timeout'], [5, 'network-lost']
]);

export function connectionState(value) { return states.get(value) ?? 'unknown'; }
export function securityName(value) { return security.get(value) ?? 'Unknown'; }
export function connectivityName(value) { return connectivity.get(value) ?? 'unknown'; }
export function failureReason(value) { return failures.get(value) ?? 'connection-failed'; }
export function supportsPsk(value) { return value === 1 || value === 3 || value === 5; }

// 0 means no usable signal; 1..4 are the bars drawn in the network list.
export function signalBars(percent) {
  if (!(percent > 0)) return 0;
  if (percent >= 75) return 4;
  if (percent >= 50) return 3;
  if (percent >= 25) return 2;
  return 1;
}

// Connected first, then the strongest signal; ties prefer saved networks, then name.
export function sortAccessPoints(accessPoints) {
  return accessPoints.slice().sort((a, b) =>
    (b.connected ? 1 : 0) - (a.connected ? 1 : 0)
    || b.signal - a.signal
    || (b.known ? 1 : 0) - (a.known ? 1 : 0)
    || String(a.name).localeCompare(String(b.name)));
}

const accessPointKey = item => `${item.device}\n${item.name}`;

// The backend only lists networks while it scans, so a stopped scan would empty the list.
// While scanning the live list wins; once stopped, networks seen earlier stay (marked stale).
export function mergeAccessPoints(previous, live, scanning) {
  if (scanning && live.length === 0) return previous;
  const next = live.slice();
  if (!scanning) {
    // Quickshell's QML JS engine has no object spread, so copy with Object.assign.
    const seen = {};
    live.forEach(item => { seen[accessPointKey(item)] = true; });
    for (const item of previous) {
      if (seen[accessPointKey(item)]) continue;
      next.push(Object.assign({}, item, { connected: false, stale: true, network: null }));
    }
  }
  return sortAccessPoints(next);
}

// Bar indicator. `reason` is 'unavailable', 'disconnected', 'no-internet', 'portal' or 'online';
// only a known bad state is a problem, so a missing network service stays neutral.
export function networkIndicator(state) {
  if (!state || state.kind !== 'ready') return { icon: 'material/wifi-off-symbolic.svg', problem: false, reason: 'unavailable' };
  const value = state.value;
  const devices = value.devices || [];
  if (!value.connected) {
    const wiredOnly = devices.length > 0 && devices.every((device) => device.type === 'wired');
    return { icon: wiredOnly ? 'material/status/lan-symbolic.svg' : 'material/wifi-off-symbolic.svg',
      problem: true, reason: 'disconnected' };
  }
  const reason = value.connectivity === 'portal' ? 'portal'
    : value.connectivity === 'none' || value.connectivity === 'limited' ? 'no-internet' : 'online';
  const problem = reason !== 'online';
  if (value.primary === 'wired' || devices.some((device) => device.type === 'wired' && device.connected))
    return { icon: 'material/status/lan-symbolic.svg', problem, reason };
  return { icon: problem ? 'material/status/signal-wifi-bad-symbolic.svg' : 'material/wifi-symbolic.svg', problem, reason };
}

export function requestIsCurrent(operation, requestId, targetPresent = true) {
  return !!operation && operation.requestId === requestId && targetPresent;
}

// Delay before the next read-only NetworkManager owner probe. The native backend has no signal for the
// daemon leaving or rejoining the bus, so ownership is polled: quickly while a request waits on it, slowly
// while it is known present, and with backoff from the quick rate while it is missing or unreadable.
export function ownerProbeInterval({ busy, present, misses, fastMs, idleMs }) {
  const fast = Math.max(100, Number(fastMs) || 0);
  const idle = Math.max(fast, Number(idleMs) || 0);
  if (busy) return fast;
  if (present) return idle;
  const steps = Math.max(0, Math.min(16, Math.floor(Number(misses) || 0)));
  return Math.min(idle, fast * 2 ** steps);
}

// Delay before the next WirelessEnabled readback, or 0 for none. The native property signals daemon-side
// changes, but its setter is optimistic, so a write is confirmed by polling while it is pending. Outside a
// request the readback only repeats while its value is unknown or disagrees with the native one: after a
// refused write the native value can stay wrong without ever signalling again.
export function wifiReadbackInterval({ pending, confirmed, native, fallbackMs }) {
  if (pending) return 250;
  if ((confirmed === true || confirmed === false) && confirmed === native) return 0;
  return Math.max(100, Number(fallbackMs) || 0);
}
