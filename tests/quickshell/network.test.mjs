import test from 'node:test';
import assert from 'node:assert/strict';
import {
  connectionState, connectivityName, failureReason, requestIsCurrent, securityName, signalBars,
  sortAccessPoints, supportsPsk
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

test('sorts connected first, then saved, then by signal, then by name', () => {
  const list = [
    { name: 'weak', connected: false, known: false, signal: 20 },
    { name: 'strong', connected: false, known: false, signal: 90 },
    { name: 'saved', connected: false, known: true, signal: 40 },
    { name: 'home', connected: true, known: true, signal: 30 },
    { name: 'b-tie', connected: false, known: false, signal: 20 }
  ];
  assert.deepEqual(sortAccessPoints(list).map(item => item.name),
    ['home', 'saved', 'strong', 'b-tie', 'weak']);
  assert.equal(list[0].name, 'weak');
});

test('ignores stale completions and targets removed during a request', () => {
  const operation = { requestId: 'network-7', target: {} };
  assert.equal(requestIsCurrent(operation, 'network-7'), true);
  assert.equal(requestIsCurrent(operation, 'network-6'), false);
  assert.equal(requestIsCurrent(operation, 'network-7', false), false);
  assert.equal(requestIsCurrent(null, 'network-7'), false);
});
