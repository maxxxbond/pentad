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

// Connected first, then saved networks, then the strongest signal; ties by name.
export function sortAccessPoints(accessPoints) {
  return [...accessPoints].sort((a, b) =>
    (b.connected ? 1 : 0) - (a.connected ? 1 : 0)
    || (b.known ? 1 : 0) - (a.known ? 1 : 0)
    || b.signal - a.signal
    || String(a.name).localeCompare(String(b.name)));
}

export function requestIsCurrent(operation, requestId, targetPresent = true) {
  return !!operation && operation.requestId === requestId && targetPresent;
}
