import test from 'node:test';
import assert from 'node:assert/strict';
import { actionCommand, cleanIdentity, createSessionController, parseAccount,
  parseCapability, validSessionId } from '../../quickshell/logic/session-actions.mjs';

function fixture() {
  const values = { writable: true, capabilities: { lock: 'yes', logout: 'yes', reboot: 'yes', poweroff: 'challenge' }, sessionId: '3' };
  const calls = [], completions = [], results = [];
  const controller = createSessionController({
    writable: () => values.writable,
    capabilities: () => values.capabilities,
    sessionId: () => values.sessionId,
    execute: (argv, done) => { calls.push(argv); completions.push(done); },
    finished: (action, ok) => results.push({ action, ok }),
  });
  return { controller, values, calls, completions, results };
}

test('identity and capabilities are parsed from bounded native reads', () => {
  assert.equal(parseAccount('user:x:1000:1000:User,Office:/home/user:/bin/zsh', 'user'), 'User');
  assert.equal(parseAccount('user:x:1000:1000::/home/user:/bin/zsh', 'user'), 'user');
  assert.equal(parseAccount('root:x:0:0:Root:/root:/bin/sh', 'max'), 'max');
  assert.equal(cleanIdentity('  pc\n\x00  '), 'pc');
  assert.equal(parseCapability('s "challenge"\n'), 'challenge');
  assert.equal(parseCapability('s "yes" extra'), 'unavailable');
});

test('only explicit actions and a valid current session can form command argv', () => {
  assert.equal(validSessionId('../other'), false);
  assert.equal(actionCommand('logout', ''), null);
  assert.equal(actionCommand('anything', '3'), null);
  assert.deepEqual(actionCommand('lock', '3'), ['loginctl', 'lock-session', '3']);
  assert.deepEqual(actionCommand('logout', '3').slice(-3), ['TerminateSession', 's', '3']);
  assert.deepEqual(actionCommand('reboot', '3').slice(-3), ['Reboot', 'b', 'true']);
  assert.deepEqual(actionCommand('poweroff', '3').slice(-3), ['PowerOff', 'b', 'true']);
});

test('logout/reboot/poweroff never dispatch before confirmation and cancellation clears them', () => {
  for (const action of ['logout', 'reboot', 'poweroff']) {
    const f = fixture();
    assert.equal(f.controller.request(action), true);
    assert.equal(f.controller.read().confirmation, action);
    assert.equal(f.calls.length, 0);
    f.controller.cancel();
    assert.equal(f.controller.confirm(), false);
    assert.equal(f.calls.length, 0);
  }
});

test('lock requests run immediately; pending actions and duplicate confirmations dispatch once', () => {
  const f = fixture();
  assert.equal(f.controller.request('lock'), true);
  assert.equal(f.controller.request('reboot'), false);
  f.completions[0](true);
  f.completions[0](true);
  assert.equal(f.results.length, 1);
  f.controller.request('reboot');
  assert.equal(f.controller.confirm(), true);
  assert.equal(f.controller.confirm(), false);
  assert.equal(f.calls.length, 2);
});

test('permission and capability changes are checked again at confirmation', () => {
  for (const change of ['permission', 'capability', 'session']) {
    const f = fixture();
    f.controller.request('logout');
    if (change === 'permission') f.values.writable = false;
    if (change === 'capability') f.values.capabilities.logout = 'no';
    if (change === 'session') f.values.sessionId = '';
    assert.equal(f.controller.confirm(), false);
    assert.equal(f.calls.length, 0);
    assert.equal(f.controller.read().confirmation, '');
    assert.notEqual(f.controller.read().error, '');
  }
});

test('preview/safe mode deny both requests and confirm; failures clear pending without claiming success', () => {
  const f = fixture();
  f.values.writable = false;
  assert.equal(f.controller.request('poweroff'), false);
  assert.equal(f.controller.confirm(), false);
  assert.equal(f.calls.length, 0);
  f.values.writable = true;
  f.controller.request('poweroff');
  f.controller.confirm();
  f.completions[0](false, 'timeout');
  assert.equal(f.controller.read().pending, '');
  assert.equal(f.controller.read().error, 'timeout');
  assert.deepEqual(f.results, [{ action: 'poweroff', ok: false }]);
});

test('disposing the service ignores a stale command completion', () => {
  const f = fixture();
  f.controller.request('lock');
  f.controller.dispose();
  f.completions[0](true);
  assert.equal(f.results.length, 0);
});
