import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as Rules from '../../quickshell/logic/quick-settings.mjs';
import { controlDefinition } from '../../quickshell/logic/control-model.mjs';

const source = file => readFileSync(new URL('../../quickshell/' + file, import.meta.url), 'utf8');
function method(text, pattern) {
  const start = text.search(pattern);
  assert.ok(start >= 0, 'QML method exists');
  const body = text.indexOf('{', start);
  let depth = 1;
  let end = body + 1;
  for (; depth && end < text.length; end++) {
    if (text[end] === '{') depth++;
    if (text[end] === '}') depth--;
  }
  return text.slice(start, end);
}
const desktop = source('services/Desktop.qml');
const grid = source('features/system/QuickSettingsGrid.qml');
const control = source('components/PentadControl.qml');

function harness({ available = true, preview = false, safeMode = false } = {}) {
  const events = [];
  const later = [];
  const service = {
    preview, safeMode, serial: 0, tailscaleAvailable: available && !preview && !safeMode,
    tailscaleEntry: { execute: () => events.push('execute') },
    Qt: { callLater: fn => later.push(fn) },
  };
  service.root = service;
  const d = vm.createContext(service);
  vm.runInContext(method(desktop, /function openTailscale\(/) + '\n'
    + method(desktop, /function command\(/), d, { timeout: 1000 });

  const state = {
    Rules, tailscaleRequest: '', tailscaleError: '',
    services: { desktop: service, text: (uk, en) => en, popups: { close: () => events.push('close-menu') } },
  };
  state.root = state;
  const g = vm.createContext(state);
  vm.runInContext(method(grid, /function openTailscale\(/) + '\n' + method(grid, /function activate\(/) + '\n'
    + method(grid, /function onCommandFinished\(/), g, { timeout: 1000 });
  service.commandFinished = (id, result) => {
    events.push(result.reason);
    state.onCommandFinished(id, result);
  };
  const primary = {
    compatible: true, available: available && !preview && !safeMode, pending: false,
    capabilities: controlDefinition('tailscale').capabilities,
    controlState: {}, definition: controlDefinition('tailscale'),
    commandRequested: (action) => {
      events.push(action);
      const handler = method(grid, /function\(action, value\)/);
      vm.runInContext('(' + handler + ')', g, { timeout: 1000 })(action);
    },
  };
  state.info = { key: 'tailscale', available: primary.available };
  const c = vm.createContext(primary);
  vm.runInContext(method(control, /function activatePrimary\(/), c, { timeout: 1000 });
  return { events, state, service, click: () => primary.activatePrimary(), flush: () => {
    for (const fn of later.splice(0)) fn();
  } };
}

test('Tailscale primary action reaches native app execution after releasing menu focus', () => {
  const h = harness();
  h.click();
  assert.equal(h.state.tailscaleRequest, 'desktop-1');
  assert.deepEqual(h.events, ['tailscale.open']);
  h.flush();
  assert.deepEqual(h.events, ['tailscale.open', 'accepted', 'close-menu', 'execute']);
  assert.equal(h.state.tailscaleRequest, '');
  assert.equal(h.state.tailscaleError, '');
});

test('missing app, preview, and safe mode never launch an application', () => {
  for (const options of [{ available: false }, { preview: true }, { safeMode: true }]) {
    const h = harness(options);
    h.click(); h.flush();
    assert.deepEqual(h.events, []);
    h.service.command('tailscale'); h.flush();
    assert.equal(h.events.includes('execute'), false);
    assert.equal(h.events.includes('close-menu'), false);
  }
});

test('app disappearing before dispatch reports failure, retains menu, and permits retry', () => {
  const h = harness();
  h.click();
  h.service.tailscaleAvailable = false;
  h.flush();
  assert.deepEqual(h.events, ['tailscale.open', 'unavailable']);
  assert.equal(h.state.tailscaleError, 'Could not open Trayscale');
  assert.equal(h.state.tailscaleRequest, '');
  h.service.tailscaleAvailable = true;
  h.click(); h.flush();
  assert.equal(h.state.tailscaleError, '');
  assert.equal(h.events.at(-1), 'execute');
});
