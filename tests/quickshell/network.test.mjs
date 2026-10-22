import test from 'node:test';
import assert from 'node:assert/strict';
import {
  connectionState, connectivityName, failureReason, mergeAccessPoints, ownerProbeInterval, requestIsCurrent,
  securityName, signalBars, sortAccessPoints, supportsPsk, wifiReadbackInterval, networkIndicator
} from '../../quickshell/logic/network.mjs';

test('maps native network enums to stable UI labels', () => {
  assert.equal(connectionState(1), 'connecting');
  assert.equal(connectionState(4), 'disconnected');
  assert.equal(connectivityName(2), 'portal');
  assert.equal(securityName(3), 'WPA2');
  assert.equal(securityName(10), 'Open');
  assert.equal(failureReason(4), 'authentication-timeout');
  assert.equal(failureReason(99), 'connection-failed');
  assert.equal(supportsPsk(1), true);
  assert.equal(supportsPsk(3), true);
  assert.equal(supportsPsk(5), true);
  assert.equal(supportsPsk(2), false);
});

test('turns signal strength into zero to four bars', () => {
  assert.equal(signalBars(0), 0);
  assert.equal(signalBars(NaN), 0);
  assert.equal(signalBars(10), 1);
  assert.equal(signalBars(25), 2);
  assert.equal(signalBars(60), 3);
  assert.equal(signalBars(75), 4);
  assert.equal(signalBars(100), 4);
});

test('sorts connected first, then by signal, then saved, then by name', () => {
  const list = [
    { name: 'weak', connected: false, known: false, signal: 20 },
    { name: 'strong', connected: false, known: false, signal: 90 },
    { name: 'far-saved', connected: false, known: true, signal: 10 },
    { name: 'home', connected: true, known: true, signal: 30 },
    { name: 'saved-tie', connected: false, known: true, signal: 20 },
    { name: 'b-tie', connected: false, known: false, signal: 20 }
  ];
  assert.deepEqual(sortAccessPoints(list).map(item => item.name),
    ['home', 'strong', 'saved-tie', 'b-tie', 'weak', 'far-saved']);
  assert.equal(list[0].name, 'weak');
});

test('keeps networks seen earlier once scanning stops, and drops them while scanning', () => {
  const a = { device: 'wlan0', name: 'a', connected: true, known: true, signal: 80, network: {} };
  const b = { device: 'wlan0', name: 'b', connected: false, known: false, signal: 50, network: {} };
  const liveA = { ...a, signal: 70 };
  const stopped = mergeAccessPoints([a, b], [liveA], false);
  assert.deepEqual(stopped.map(item => item.name), ['a', 'b']);
  assert.equal(stopped[0].signal, 70);
  assert.equal(stopped[1].stale, true);
  assert.equal(stopped[1].network, null);
  assert.deepEqual(mergeAccessPoints([a, b], [liveA], true).map(item => item.name), ['a']);
  assert.deepEqual(mergeAccessPoints([a, b], [], true), [a, b]);
  assert.deepEqual(mergeAccessPoints([a, b], [], false).map(item => item.connected), [false, false]);
});

test('ignores stale completions and targets removed during a request', () => {
  const operation = { requestId: 'network-7', target: {} };
  assert.equal(requestIsCurrent(operation, 'network-7'), true);
  assert.equal(requestIsCurrent(operation, 'network-6'), false);
  assert.equal(requestIsCurrent(operation, 'network-7', false), false);
  assert.equal(requestIsCurrent(null, 'network-7'), false);
});

test('owner probe is quick only while a request waits and backs off while the daemon is missing', () => {
  const base = { fastMs: 2500, idleMs: 60000 };
  assert.equal(ownerProbeInterval({ ...base, busy: true, present: true, misses: 0 }), 2500);
  assert.equal(ownerProbeInterval({ ...base, busy: true, present: false, misses: 5 }), 2500);
  assert.equal(ownerProbeInterval({ ...base, busy: false, present: true, misses: 0 }), 60000);
  assert.equal(ownerProbeInterval({ ...base, busy: false, present: false, misses: 0 }), 2500);
  assert.equal(ownerProbeInterval({ ...base, busy: false, present: false, misses: 1 }), 5000);
  assert.equal(ownerProbeInterval({ ...base, busy: false, present: false, misses: 3 }), 20000);
  assert.equal(ownerProbeInterval({ ...base, busy: false, present: false, misses: 99 }), 60000);
  assert.equal(ownerProbeInterval({ busy: false, present: true, misses: 0, fastMs: 10, idleMs: 5 }), 100);
});

test('wifi readback polls during a toggle and otherwise only while unknown or diverged', () => {
  const base = { fallbackMs: 30000 };
  assert.equal(wifiReadbackInterval({ ...base, pending: true, confirmed: true, native: true }), 250);
  assert.equal(wifiReadbackInterval({ ...base, pending: false, confirmed: true, native: true }), 0);
  assert.equal(wifiReadbackInterval({ ...base, pending: false, confirmed: false, native: false }), 0);
  assert.equal(wifiReadbackInterval({ ...base, pending: false, confirmed: true, native: false }), 30000);
  assert.equal(wifiReadbackInterval({ ...base, pending: false, confirmed: null, native: true }), 30000);
  assert.equal(wifiReadbackInterval({ pending: false, confirmed: null, native: true, fallbackMs: 0 }), 100);
});

test('bar indicator flags only known bad network states and prefers the wired link', () => {
  const ready = (value) => ({ kind: 'ready', value: { devices: [{ type: 'wifi', connected: false }], ...value } });
  const wifi = (connectivity) => ready({ primary: 'wifi', connected: true, connectivity,
    devices: [{ type: 'wifi', connected: true }] });
  assert.deepEqual(networkIndicator({ kind: 'unavailable', reason: 'service-missing' }),
    { icon: 'material/wifi-off-symbolic.svg', problem: false, reason: 'unavailable' });
  assert.deepEqual(networkIndicator(ready({ primary: 'none', connected: false, connectivity: 'none' })),
    { icon: 'material/wifi-off-symbolic.svg', problem: true, reason: 'disconnected' });
  assert.deepEqual(networkIndicator(ready({ primary: 'none', connected: false, devices: [{ type: 'wired', connected: false }] })),
    { icon: 'material/status/lan-symbolic.svg', problem: true, reason: 'disconnected' });
  assert.deepEqual(networkIndicator(wifi('full')), { icon: 'material/wifi-symbolic.svg', problem: false, reason: 'online' });
  // Connectivity checks are often disabled; an unknown result is not reported as an outage.
  assert.equal(networkIndicator(wifi('unknown')).problem, false);
  assert.deepEqual(networkIndicator(wifi('limited')),
    { icon: 'material/status/signal-wifi-bad-symbolic.svg', problem: true, reason: 'no-internet' });
  assert.equal(networkIndicator(wifi('none')).reason, 'no-internet');
  assert.equal(networkIndicator(wifi('portal')).reason, 'portal');
  assert.deepEqual(networkIndicator(ready({ primary: 'wired', connected: true, connectivity: 'limited' })),
    { icon: 'material/status/lan-symbolic.svg', problem: true, reason: 'no-internet' });
  // Wi-Fi and Ethernet at once used to show a slashed Wi-Fi glyph while online.
  assert.deepEqual(networkIndicator(ready({ primary: 'unknown', connected: true, connectivity: 'full',
    devices: [{ type: 'wifi', connected: true }, { type: 'wired', connected: true }] })),
  { icon: 'material/status/lan-symbolic.svg', problem: false, reason: 'online' });
});
