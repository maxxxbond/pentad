import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import test from 'node:test';
import { batterySummary, bluetoothAction, bluetoothError, bluetoothKindIcon, brightnessOutputs, profileOptions } from '../../quickshell/logic/settings-devices.mjs';

const en = (uk, value) => value;
const uk = value => value;
const devicesPack = new URL('../../quickshell/assets/icons/material/devices/', import.meta.url).href;

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

test('Bluetooth failures read as sentences in both languages', () => {
  assert.equal(bluetoothError('pairing-failed', en), 'Pairing failed. The device may ask for a PIN');
  assert.equal(bluetoothError('timeout', uk), 'Пристрій не відповів вчасно');
  assert.equal(bluetoothError('weird', en), 'Bluetooth action failed (weird)');
  assert.equal(bluetoothError(undefined, en), 'Bluetooth action failed (failed)');
});

test('brightness rows follow Hyprland outputs by name, once each', () => {
  const state = { kind: 'ready', value: { outputs: [{ id: '0', name: 'eDP-1' }, { id: '1', name: 'DP-2' }, { id: '2', name: 'DP-2' }, { id: '3' }] } };
  assert.deepEqual(brightnessOutputs(state), ['eDP-1', 'DP-2']);
  assert.deepEqual(brightnessOutputs({ kind: 'unavailable' }), []);
});

test('every Bluetooth device kind has its own bundled icon, unknown kinds fall back to the Bluetooth mark', () => {
  const kinds = ['earbuds', 'headphones', 'headset', 'speaker', 'phone', 'tablet', 'laptop', 'desktop',
    'keyboard', 'mouse', 'gamepad', 'watch', 'tv', 'printer', 'camera'];
  const files = kinds.map(bluetoothKindIcon);
  for (const file of [...files, bluetoothKindIcon('other')]) assert.ok(existsSync(new URL(devicesPack + file)), file);
  assert.equal(new Set(files).size, files.length);
  assert.equal(bluetoothKindIcon('computer'), bluetoothKindIcon('laptop'));
  assert.equal(bluetoothKindIcon('other'), 'bluetooth-symbolic.svg');
  assert.equal(bluetoothKindIcon(undefined), 'bluetooth-symbolic.svg');
  assert.ok(!files.includes('bluetooth-symbolic.svg'));
});

test('a Bluetooth device row offers one main action that fits its state', () => {
  assert.equal(bluetoothAction({ paired: false, pairing: false, connected: false }).id, 'pair');
  assert.equal(bluetoothAction({ paired: false, pairing: true, connected: false }).id, 'pairing');
  assert.equal(bluetoothAction({ paired: true, connected: false }).id, 'connect');
  assert.equal(bluetoothAction({ paired: true, connected: true }).id, 'disconnect');
  const action = bluetoothAction({ paired: true, connected: false });
  assert.equal(action.icon, 'link-symbolic.svg');
  for (const state of [{ paired: false }, { paired: true }, { paired: true, connected: true }])
    assert.ok(existsSync(new URL(devicesPack + bluetoothAction(state).icon)));
  assert.equal(action.label(en), 'Connect');
  assert.equal(action.label(uk), 'Підключити');
});
