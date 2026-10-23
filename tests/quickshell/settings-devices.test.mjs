import assert from 'node:assert/strict';
import test from 'node:test';
import { batterySummary, brightnessOutputs, profileOptions } from '../../quickshell/logic/settings-devices.mjs';

const en = (uk, value) => value;
const uk = value => value;

test('power profiles keep their order and get readable names', () => {
  assert.deepEqual(profileOptions(['power-saver', 'balanced', 'performance'], en).map(option => option.label),
    ['Power saver', 'Balanced', 'Performance']);
  assert.deepEqual(profileOptions(['balanced', 'custom', '', 3], uk), [
    { value: 'balanced', label: 'Збалансований' }, { value: 'custom', label: 'custom' }]);
  assert.deepEqual(profileOptions(undefined, en), []);
});

test('battery summary shows the rounded charge and the state', () => {
  assert.equal(batterySummary({ percent: 63.6, state: 'discharging' }, en), '64 % · Discharging');
  assert.equal(batterySummary({ percent: 100, state: 'full' }, uk), '100 % · Заряджено');
  assert.equal(batterySummary({ percent: null, state: 'unknown' }, en), 'Unknown');
  assert.equal(batterySummary(null, en), null);
});

test('brightness rows follow Hyprland outputs by name, once each', () => {
  const state = { kind: 'ready', value: { outputs: [{ id: '0', name: 'eDP-1' }, { id: '1', name: 'DP-2' }, { id: '2', name: 'DP-2' }, { id: '3' }] } };
  assert.deepEqual(brightnessOutputs(state), ['eDP-1', 'DP-2']);
  assert.deepEqual(brightnessOutputs({ kind: 'unavailable' }), []);
});
