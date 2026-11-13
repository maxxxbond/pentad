import test from 'node:test';
import assert from 'node:assert/strict';
import {
  addedMonitor, ddcDetectCommand, ddcPowerCommand, dpmsOffCommand, endTimestamp, inhibitCommand, inhibitReady, isExpired, lockCommand, openrgbCommand, overnightEnds, parseRazer, parseState, parseDdcBus, razerReadCommand,
  razerSetCommand, remainingSeconds, restorePlan, serializeState, userCommand,
} from '../../quickshell/logic/overnight.mjs';

const at = (day, hours, minutes) => new Date(2026, 10, day, hours, minutes, 0, 0).getTime();
const config = { openrgb: { start: 'Night', end: 'Day' }, commands: { start: '', end: 'fanctl auto' } };
const state = {
  version: 1, startedAt: 1000, endsAt: 2000,
  prior: { profile: 'balanced', muted: false, dnd: false, razer: [{ serial: 'PM1', brightness: 60 }] },
  applied: { profile: 'power-saver', muted: true, dnd: true, razer: true, openrgb: true, command: true },
};

test('the end moves to the next occurrence across midnight', () => {
  assert.deepEqual(overnightEnds, ['07:00', '08:00', '09:00', 'none']);
  assert.equal(endTimestamp('08:00', at(9, 23, 40)), at(10, 8, 0));
  assert.equal(endTimestamp('08:00', at(10, 6, 0)), at(10, 8, 0));
  assert.equal(endTimestamp('08:00', at(10, 8, 0)), at(11, 8, 0));
  assert.equal(endTimestamp('07:00', at(10, 7, 30)), at(11, 7, 0));
});

test('no end and invalid choices', () => {
  assert.equal(endTimestamp('none', at(9, 23, 0)), 0);
  assert.equal(endTimestamp('06:30', at(9, 23, 0)), at(10, 8, 0));
  assert.equal(endTimestamp(undefined, at(9, 23, 0)), at(10, 8, 0));
});

test('remaining seconds and expiry', () => {
  assert.equal(remainingSeconds(0, 5000), 0);
  assert.equal(remainingSeconds(10500, 5000), 6);
  assert.equal(remainingSeconds(5000, 5000), 1);
  assert.equal(remainingSeconds(1000, 5000), 1);
  assert.equal(isExpired(0, 5000), false);
  assert.equal(isExpired(5000, 4999), false);
  assert.equal(isExpired(5000, 5000), true);
});

test('the sleep inhibitor blocks sleep only, reports readiness and clamps the length', () => {
  const argv = inhibitCommand(3600);
  assert.deepEqual(argv.slice(0, 2), ['sh', '-c']);
  assert.match(argv[2], /command -v setpriv/);
  assert.match(argv[2], /exec setpriv --pdeathsig KILL "\$@"; fi; exec "\$@"$/);
  assert.deepEqual(argv.slice(3), ['overnight', 'systemd-inhibit', '--what=sleep', '--mode=block', '--who=Pentad', '--why=Overnight mode',
    'sh', '-c', `echo ${inhibitReady}; exec sleep "$1"`, 'overnight', '3600']);
  for (const bad of [0, -1, 1.5, 86401, NaN, undefined]) assert.equal(inhibitCommand(bad).at(-1), 'infinity');
});

test('the inhibitor command runs as written in a shell', { skip: process.platform !== 'linux' }, async () => {
  const { spawnSync } = await import('node:child_process');
  const { mkdtempSync, writeFileSync, rmSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const path = await import('node:path');
  // A stand-in systemd-inhibit runs its child; without setpriv the wrapper runs it directly.
  const bin = mkdtempSync(path.join(tmpdir(), 'pentad-inhibit-'));
  try {
    writeFileSync(path.join(bin, 'systemd-inhibit'), '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n', { mode: 0o700 });
    const argv = inhibitCommand(1);
    const result = spawnSync(argv[0], argv.slice(1), { encoding: 'utf8', timeout: 5000,
      env: { PATH: `${bin}:/usr/bin:/bin` } });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `${inhibitReady}\n`);
  } finally { rmSync(bin, { recursive: true, force: true }); }
});

test('commands for razer, openrgb, user script and displays', () => {
  const read = razerReadCommand();
  assert.deepEqual(read.slice(0, 2), ['python3', '-c']);
  assert.match(read[2], /openrazer\.client/);
  assert.match(read[2], /sys\.exit\(7\)/);
  const set = razerSetCommand([{ serial: 'A', brightness: 150 }, { serial: 'B', brightness: -5 }]);
  assert.equal(set.length, 4);
  assert.deepEqual(JSON.parse(set[3]), [{ serial: 'A', brightness: 100 }, { serial: 'B', brightness: 0 }]);
  assert.deepEqual(openrgbCommand('Night'), ['openrgb', '--profile', 'Night']);
  assert.equal(openrgbCommand('a;b'), null);
  assert.equal(openrgbCommand(''), null);
  assert.deepEqual(userCommand('echo hi'), ['timeout', '10', 'sh', '-c', 'echo hi']);
  assert.equal(userCommand('  \n'), null);
  assert.equal(userCommand(''), null);
  assert.deepEqual(dpmsOffCommand(), ['hyprctl', 'dispatch', 'hl.dsp.dpms({ action = "disable" })']);
  assert.deepEqual(lockCommand('3'), ['loginctl', 'lock-session', '3']);
  assert.deepEqual(lockCommand(''), ['loginctl', 'lock-session']);
  assert.deepEqual(lockCommand('a b'), ['loginctl', 'lock-session']);
});

test('razer output parses to entries or null', () => {
  assert.deepEqual(parseRazer('[{"serial":"PM1","brightness":60.0}]'), [{ serial: 'PM1', brightness: 60 }]);
  assert.deepEqual(parseRazer('[]'), []);
  for (const bad of ['', 'oops', '{}', '[{"serial":1,"brightness":2}]', '[{"serial":"a"}]']) assert.equal(parseRazer(bad), null, bad);
});

test('state round-trips and bad input is reported', () => {
  assert.deepEqual(parseState(serializeState(state)), { ok: true, value: state });
  assert.deepEqual(parseState(''), { ok: true, value: null });
  assert.deepEqual(parseState(null), { ok: true, value: null });
  assert.equal(parseState('{oops').ok, false);
  assert.equal(parseState('[]').ok, false);
  assert.equal(parseState(JSON.stringify({ ...state, version: 2 })).ok, false);
  assert.equal(parseState(JSON.stringify({ ...state, endsAt: 'x' })).ok, false);
  assert.equal(parseState(JSON.stringify({ ...state, prior: null })).ok, false);
  assert.equal(parseState(JSON.stringify({ ...state, applied: { ...state.applied, razer: 1 } })).ok, false);
});

test('restore runs in reverse order', () => {
  const plan = restorePlan(state, { profile: 'power-saver', muted: true, dnd: true }, config);
  assert.deepEqual(plan, [
    { step: 'command', value: 'fanctl auto' }, { step: 'openrgb', value: 'Day' }, { step: 'razer', value: [{ serial: 'PM1', brightness: 60 }] },
    { step: 'dnd', value: false }, { step: 'muted', value: false }, { step: 'profile', value: 'balanced' },
  ]);
});

test('restore skips what the user changed during the night', () => {
  const plan = restorePlan(state, { profile: 'performance', muted: false, dnd: true }, config);
  assert.deepEqual(plan.map(item => item.step), ['command', 'openrgb', 'razer', 'dnd']);
});

test('restore leaves untouched steps alone', () => {
  const untouched = { ...state, applied: { profile: '', muted: null, dnd: null, razer: false, openrgb: false, command: true } };
  assert.deepEqual(restorePlan(untouched, { profile: '', muted: null, dnd: null }, config).map(item => item.step), ['command']);
  assert.deepEqual(restorePlan(untouched, {}, { ...config, commands: { start: '', end: ' ' } }), []);
});

test('an output that reconnects while dark is named only by monitoradded', () => {
  assert.equal(addedMonitor('monitoradded', 'DP-1'), 'DP-1');
  assert.equal(addedMonitor('monitoraddedv2', '1,DP-1,KTC H27E6'), '');
  assert.equal(addedMonitor('monitorremoved', 'DP-1'), '');
  for (const bad of ['', 'DP 1', 'DP-1;rm', undefined, 'x'.repeat(33)]) assert.equal(addedMonitor('monitoradded', bad), '');
});

test('DDC powers a monitor off and on by its bus without reading it back', () => {
  assert.deepEqual(ddcDetectCommand(), ['ddcutil', 'detect', '--brief']);
  assert.deepEqual(ddcPowerCommand('9', false), ['ddcutil', '--bus', '9', '--noverify', 'setvcp', 'D6', '4']);
  assert.deepEqual(ddcPowerCommand(9, true), ['ddcutil', '--bus', '9', '--noverify', 'setvcp', 'D6', '1']);
  for (const bad of ['', '9; reboot', '1234', null, undefined]) assert.equal(ddcPowerCommand(bad, false), null);
  const detect = 'Display 1\n   I2C bus:          /dev/i2c-7\n   DRM connector:    card1-HDMI-A-1\n\n'
    + 'Display 2\n   I2C bus:          /dev/i2c-9\n   DRM connector:    card1-DP-1\n';
  assert.equal(parseDdcBus(detect, 'DP-1'), '9');
  assert.equal(parseDdcBus(detect, 'DP-2'), null);
});
