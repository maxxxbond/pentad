import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as Rules from '../../quickshell/logic/quick-settings.mjs';

const text = readFileSync(new URL('../../quickshell/services/QuickSettings.qml', import.meta.url), 'utf8');
function method(pattern) {
  const start = text.search(pattern);
  assert.ok(start >= 0, 'QML method exists');
  let depth = 0;
  let end = text.indexOf('{', start);
  for (; end < text.length; end++) {
    if (text[end] === '{') depth++;
    if (text[end] === '}' && --depth === 0) return text.slice(start, end + 1);
  }
  throw new Error('unterminated method');
}

function harness(profile, statusAfter) {
  const events = [];
  const ctx = {
    Rules, Array,
    operation: { id: 'op-1', kind: 'vpn' },
    vpnProfiles: [profile],
    error: '', errorSetting: '',
    bluetoothDeadline: { stop() {} }, bluetoothDeviceTarget: null,
    commands: [],
    commandFinished: (id, result) => events.push(['finished', id, result.ok, result.reason]),
    tailscaleFallbackRequested: () => events.push(['fallback']),
    refresh: () => events.push(['refresh']),
    runCommands(id, commands, success) { ctx.commands.push(commands); ctx.pending = success; },
  };
  const vmCtx = vm.createContext(ctx);
  vm.runInContext([method(/function finishOperation\(/), method(/function switchTailscale\(/),
    method(/function verifyTailscale\(/)].join('\n'), vmCtx, { timeout: 1000 });
  const finishRead = (output) => {
    const success = ctx.pending;
    success(['', output]);
  };
  return { ctx, events, finishRead, statusAfter };
}

const plain = (value) => JSON.parse(JSON.stringify(value));
const running = (backend) => JSON.stringify({ BackendState: backend });
const profile = (backend) => Rules.tailscaleProfile(Rules.parseTailscaleStatus(running(backend)));

test('a profile that needs sign-in runs no command and asks the UI to open Trayscale', () => {
  const h = harness(profile('NeedsLogin'));
  h.ctx.switchTailscale('op-1', h.ctx.vpnProfiles[0]);
  assert.deepEqual(plain(h.ctx.commands), []);
  assert.deepEqual(h.events, [['finished', 'op-1', false, 'login-required'], ['fallback']]);
  assert.equal(h.ctx.errorSetting, 'vpn');
});

test('starting runs `tailscale up`, waits, and confirms by reading the backend state', () => {
  const h = harness(profile('Stopped'));
  h.ctx.switchTailscale('op-1', h.ctx.vpnProfiles[0]);
  assert.deepEqual(plain(h.ctx.commands), [[['tailscale', 'up']]]);
  h.ctx.pending([]);
  assert.deepEqual(plain(h.ctx.commands[1]), [['sleep', '1'], ['tailscale', 'status', '--json', '--peers=false']]);
  h.finishRead(running('Running'));
  assert.equal(h.ctx.vpnProfiles[0].active, true);
  assert.deepEqual(h.events, [['finished', 'op-1', true, 'ok'], ['refresh']]);
});

test('stopping runs `tailscale down` and reads the state immediately', () => {
  const h = harness(profile('Running'));
  h.ctx.switchTailscale('op-1', h.ctx.vpnProfiles[0]);
  assert.deepEqual(plain(h.ctx.commands), [[['tailscale', 'down']]]);
  h.ctx.pending([]);
  assert.deepEqual(plain(h.ctx.commands[1]), [['tailscale', 'status', '--json', '--peers=false']]);
  h.finishRead(running('Stopped'));
  assert.equal(h.ctx.vpnProfiles[0].active, false);
  assert.deepEqual(h.events.at(0), ['finished', 'op-1', true, 'ok']);
});

test('a readback that disagrees, or an unreadable status, reports failure and offers Trayscale', () => {
  const mismatch = harness(profile('Stopped'));
  mismatch.ctx.switchTailscale('op-1', mismatch.ctx.vpnProfiles[0]);
  mismatch.ctx.pending([]);
  mismatch.finishRead(running('Stopped'));
  assert.deepEqual(mismatch.events, [['finished', 'op-1', false, 'readback-mismatch'], ['fallback']]);

  const unreadable = harness(profile('Running'));
  unreadable.ctx.switchTailscale('op-1', unreadable.ctx.vpnProfiles[0]);
  unreadable.ctx.pending([]);
  unreadable.finishRead('');
  assert.deepEqual(unreadable.events, [['finished', 'op-1', false, 'readback-mismatch'], ['fallback']]);
});

test('a failed command (no permission, timeout) offers Trayscale only for the Tailscale profile', () => {
  const h = harness(profile('Stopped'));
  h.ctx.switchTailscale('op-1', h.ctx.vpnProfiles[0]);
  h.ctx.finishOperation(false, 'unavailable');
  assert.deepEqual(h.events, [['finished', 'op-1', false, 'unavailable'], ['fallback']]);

  const other = harness(profile('Stopped'));
  other.ctx.finishOperation(false, 'unavailable');
  assert.deepEqual(other.events, [['finished', 'op-1', false, 'unavailable']]);
});
