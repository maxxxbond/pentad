import test from 'node:test';
import assert from 'node:assert/strict';
import { screenshotDefaults, parseScreenshotSettings, normalizeShortcut, hyprlandScreenshotBindings, matchesScreenshotShortcut } from '../../quickshell/logic/screenshot-settings.mjs';
import { parseDocument } from '../../quickshell/logic/config.mjs';

test('screenshot settings merge missing fields without mutating defaults', () => {
  const result = parseScreenshotSettings({localKeys: {brush: 'ctrl + shift + b'}});
  assert.equal(result.localKeys.brush, 'Ctrl+Shift+B');
  assert.equal(result.localKeys.copy, 'Ctrl+C');
  result.localKeys.copy = '';
  assert.equal(screenshotDefaults.localKeys.copy, 'Ctrl+C');
  assert.equal(normalizeShortcut('shift+control+z'), 'Ctrl+Shift+Z');
  assert.equal(normalizeShortcut(''), '');
});

test('conflicting shortcuts, malformed paths and invalid visual settings are rejected', () => {
  for (const value of [
    {localKeys: {brush: 'v'}}, {globalKeys: {copy: 'shift+super+s'}},
    {localKeys: {brush: 'Ctrl+Ctrl+B'}}, {directory: '~/Screenshots'}, {directory: '/tmp/\nno'},
    {color: 'red'}, {strokeWidth: 0}, {fontSize: 1000}, {autoSave: 'yes'}, {localKeys: []},
    {globalKeys: {edit: 'S"); os.execute("bad")'}},
  ]) assert.throws(() => parseScreenshotSettings(value));
});

test('configuration validates screenshots and exports only enabled inert bindings', () => {
  const parsed = parseDocument('screenshots', JSON.stringify({globalKeys: {monitor: ''}}));
  assert.equal(parsed.ok, true, parsed.message);
  const fragment = hyprlandScreenshotBindings(parsed.value);
  assert.match(fragment, /hl\.bind\("SUPER \+ SHIFT \+ S", hl\.dsp\.global\("pentad:screenshot-edit"\)\)/);
  assert.match(fragment, /hl\.unbind\("SUPER \+ SHIFT \+ S"\)\nhl\.bind\("SUPER \+ SHIFT \+ S"/);
  assert.equal((fragment.match(/hl\.bind\(/g) || []).length, 3);
  assert.doesNotMatch(fragment, /hl\.unbind\("Print"\)/);
  assert.doesNotMatch(fragment, /pentad:screenshot-monitor/);
  assert.equal(parseDocument('screenshots', '{"localKeys":{"brush":"V"}}').ok, false);
});

test('editor shortcuts match modifiers, disabled actions, function keys and keypad Enter', () => {
  assert.equal(matchesScreenshotShortcut(66, 0, 'B'), true);
  assert.equal(matchesScreenshotShortcut(66, 0x04000000, 'B'), false);
  assert.equal(matchesScreenshotShortcut(90, 0x06000000, 'Ctrl+Shift+Z'), true);
  assert.equal(matchesScreenshotShortcut(0x01000005, 0x20000000, 'Return'), true);
  assert.equal(matchesScreenshotShortcut(0x0100003b, 0, 'F12'), true);
  assert.equal(matchesScreenshotShortcut(0x01000002, 0x02000000, 'Shift+Tab'), true);
  assert.equal(matchesScreenshotShortcut(0x01000000, 0, ''), false);
});

test('export replaces conflicting modifier orders in Hyprland literal-string unbind API', () => {
  const bindings = new Map([
    ['CTRL + SUPER + S', 'scratchpad'],
    ['SHIFT+SUPER+S', 'old editor'],
    ['SUPER + X', 'unrelated'],
    ['CTRL + Print', 'unconfigured screenshot'],
  ]);
  for (const line of hyprlandScreenshotBindings(screenshotDefaults).split('\n')) {
    if (!line || line.startsWith('--')) continue;
    const unbind = /^hl\.unbind\(("[^"]+")\)$/.exec(line);
    const bind = /^hl\.bind\(("[^"]+"), hl\.dsp\.global\(("[^"]+")\)\)$/.exec(line);
    if (unbind) bindings.delete(JSON.parse(unbind[1]));
    else if (bind) bindings.set(JSON.parse(bind[1]), JSON.parse(bind[2]));
    else assert.fail('Unexpected Lua binding statement: ' + line);
  }
  assert.equal(bindings.has('CTRL + SUPER + S'), false);
  assert.equal(bindings.has('SHIFT+SUPER+S'), false);
  assert.equal(bindings.get('SUPER + CTRL + S'), 'pentad:screenshot-copy');
  assert.equal(bindings.get('SUPER + SHIFT + S'), 'pentad:screenshot-edit');
  assert.equal(bindings.get('SUPER + X'), 'unrelated');
  assert.equal(bindings.get('CTRL + Print'), 'unconfigured screenshot');
  assert.equal(bindings.size, 6);
});
