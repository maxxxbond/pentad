import assert from 'node:assert/strict';
import test from 'node:test';
import { fromQtEvent, isShortcut, normalizeShortcut, shortcutError, shortcutParts } from '../../quickshell/logic/settings-shortcut.mjs';
import { normalizeColor, sameColor } from '../../quickshell/logic/settings-color.mjs';

const META = 0x10000000, CTRL = 0x04000000, ALT = 0x08000000, SHIFT = 0x02000000;

test('normalizeShortcut orders modifiers and capitalizes a letter', () => {
  assert.equal(normalizeShortcut({ key: 'Space', super: true }), 'Super+Space');
  assert.equal(normalizeShortcut({ key: 'l', shift: true, ctrl: true, super: true, alt: true }), 'Super+Ctrl+Alt+Shift+L');
  assert.equal(normalizeShortcut({ key: '' }), '');
  assert.equal(normalizeShortcut(null), '');
});
test('fromQtEvent maps Qt key codes and masks', () => {
  assert.equal(fromQtEvent(0x20, META), 'Super+Space');
  assert.equal(fromQtEvent(0x01000001, ALT), 'Alt+Tab');
  assert.equal(fromQtEvent(0x01000030, 0), 'F1');
  assert.equal(fromQtEvent(0x01000009, 0), 'Print');
  assert.equal(fromQtEvent(0x4c, META | SHIFT | CTRL), 'Super+Ctrl+Shift+L');
  assert.equal(fromQtEvent(0x01ffffff, 0), '');
});
test('a modifier is required unless the key is F-n or Print', () => {
  assert.equal(shortcutError('A'), 'modifier-required');
  assert.equal(shortcutError('Space'), 'modifier-required');
  assert.equal(shortcutError('F5'), '');
  assert.equal(shortcutError('Print'), '');
  assert.equal(shortcutError('Super+Space'), '');
});
test('invalid and empty shortcuts are rejected', () => {
  assert.equal(shortcutError(''), 'empty');
  assert.equal(shortcutError('Super+'), 'invalid');
  assert.equal(shortcutError('Super+Super'), 'invalid');
  assert.equal(shortcutError('Hyper+A'), 'invalid');
  assert.equal(shortcutError('Alt+Alt+A'), 'invalid');
  assert.equal(isShortcut('Super+Tab'), true);
  assert.equal(isShortcut(42), false);
});
test('shortcutParts splits for keycaps', () => {
  assert.deepEqual(shortcutParts('Super + Space'), ['Super', 'Space']);
  assert.deepEqual(shortcutParts(''), []);
});
test('normalizeColor reuses the resolveTheme #RRGGBB rule', () => {
  assert.equal(normalizeColor(' #869677 '), '#869677');
  assert.equal(normalizeColor('#abcdef'), '#ABCDEF');
  for (const bad of ['red', '#abc', '#12345g', '#1234567', '', null]) assert.equal(normalizeColor(bad), '');
  assert.equal(sameColor('#ABCDEF', '#abcdef'), true);
});
