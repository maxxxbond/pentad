import test from 'node:test';
import assert from 'node:assert/strict';
import {
  dpmsOffCommand, endTimestamp, inhibitCommand, isExpired, openrgbCommand, overnightEnds, parseRazer, parseState, razerReadCommand,
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

test('the sleep inhibitor blocks sleep only and clamps the length', () => {
  assert.deepEqual(inhibitCommand(3600), ['systemd-inhibit', '--what=sleep', '--mode=block', '--who=Pentad', '--why=Overnight mode', 'sleep', '3600']);
  for (const bad of [0, -1, 1.5, 86401, NaN, undefined]) assert.equal(inhibitCommand(bad).at(-1), 'infinity');
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
