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

export function requestIsCurrent(operation, requestId, targetPresent = true) {
  return !!operation && operation.requestId === requestId && targetPresent;
}
