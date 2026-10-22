import test from 'node:test';
import assert from 'node:assert/strict';
import { numberOr, previewOverviewForScreens, previewStateForScreens } from '../../quickshell/logic/hyprland-preview.mjs';

test('numberOr keeps finite numbers and falls back otherwise', () => {
  assert.equal(numberOr(5, 1), 5);
  assert.equal(numberOr('7.5', 1), 7.5);
  assert.equal(numberOr(0, 1), 0);
  assert.equal(numberOr(null, 1), 0);
  assert.equal(numberOr(undefined, 9), 9);
  assert.equal(numberOr(NaN, 9), 9);
  assert.equal(numberOr('abc', 9), 9);
  assert.equal(numberOr(Infinity, 9), 9);
  assert.equal(numberOr({}, 9), 9);
});

test('preview state without screens falls back to a single 1920x1080 output', () => {
  for (const screens of [undefined, null, [], {}, [{ name: '' }, null]]) {
    const state = previewStateForScreens(screens);
    assert.deepEqual(state.outputs, [{ id: 'preview', name: 'preview', x: 0, y: 0, width: 1920, height: 1080,
      scale: 1, transform: 0, reserved: [0, 0, 0, 0], activeWorkspaceId: '1' }]);
    assert.equal(state.focusedOutputId, 'preview');
    assert.deepEqual(state.workspaces.map(item => item.id), ['1', '2', '3', '4', '5']);
  }
});

test('preview state for one screen builds five workspaces on it', () => {
  const state = previewStateForScreens([{ name: 'DP-1', x: 10, y: 20, width: 2560, height: 1440, devicePixelRatio: 1.5 }]);
  assert.deepEqual(state.outputs, [{ id: 'DP-1', name: 'DP-1', x: 10, y: 20, width: 2560, height: 1440,
    scale: 1.5, transform: 0, reserved: [0, 0, 0, 0], activeWorkspaceId: '1' }]);
  assert.equal(state.focusedOutputId, 'DP-1');
  assert.equal(state.activeTitle, '');
  assert.equal(state.activeClass, '');
  assert.deepEqual(state.workspaces[0], { id: '1', name: '1', monitor: 'DP-1', special: false, active: true,
    occupied: false, apps: [] });
  assert.deepEqual(state.workspaces.map(item => item.active), [true, false, false, false, false]);
  assert.ok(state.workspaces.every(item => item.monitor === 'DP-1' && !item.special && !item.occupied));
});

test('preview state for two screens numbers workspaces per output and skips unnamed screens', () => {
  const state = previewStateForScreens([
    { name: 'A', width: 1000, height: 500 },
    { name: '' },
    { name: 'B', virtualX: 3000, virtualY: 40, devicePixelRatio: 0 },
  ]);
  assert.deepEqual(state.outputs.map(item => item.id), ['A', 'B']);
  assert.deepEqual(state.outputs.map(item => item.activeWorkspaceId), ['1', '6']);
  // A has no coordinates and sits at index 0; B uses its virtual coordinates.
  assert.deepEqual(state.outputs.map(item => [item.x, item.y]), [[0, 0], [3000, 40]]);
  assert.deepEqual(state.outputs.map(item => [item.width, item.height]), [[1000, 500], [1920, 1080]]);
  assert.deepEqual(state.outputs.map(item => item.scale), [1, 1]);
  assert.equal(state.focusedOutputId, 'A');
  assert.deepEqual(state.workspaces.map(item => item.id), ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10']);
  assert.deepEqual(state.workspaces.map(item => item.monitor), ['A', 'A', 'A', 'A', 'A', 'B', 'B', 'B', 'B', 'B']);
  assert.deepEqual(state.workspaces.filter(item => item.active).map(item => item.id), ['1', '6']);
});

test('preview state offsets screens without coordinates by their list index', () => {
  const state = previewStateForScreens([{ name: 'A' }, { name: 'B' }]);
  assert.deepEqual(state.outputs.map(item => item.x), [0, 1920]);
});

test('preview overview puts one preview window on each output active workspace', () => {
  const overview = previewOverviewForScreens([
    { name: 'A', x: 0, y: 0 }, { name: 'B', x: 1920, y: 100 },
  ]);
  assert.equal(overview.revision, 1);
  assert.deepEqual(overview.clients.map(item => item.address), ['0x1000', '0x1001']);
  assert.deepEqual(overview.clients[1], { address: '0x1001', instanceId: 'preview:0x1001',
    appId: 'preview.desktop', workspaceId: '6', monitorId: 'B', title: 'Preview window', appClass: 'preview',
    x: 1968, y: 148, width: 960, height: 600, mapped: true, hidden: false, pinned: false,
    floating: true, fullscreen: false, grouped: [] });
  assert.equal(overview.activeAddress, '0x1000');
  assert.deepEqual(overview.mru, ['preview:0x1000']);
  assert.equal(overview.desktop.activeTitle, 'Preview window');
  assert.equal(overview.desktop.activeClass, 'preview');
  const occupied = overview.desktop.workspaces.filter(item => item.occupied);
  assert.deepEqual(occupied.map(item => item.id), ['1', '6']);
  assert.deepEqual(occupied[0].apps, [{ appId: 'preview.desktop', appClass: 'preview', width: 960, height: 600, pinned: false }]);
});

test('preview overview leaves the plain preview state untouched and handles no screens', () => {
  const before = previewStateForScreens([{ name: 'A' }]);
  previewOverviewForScreens([{ name: 'A' }]);
  assert.deepEqual(previewStateForScreens([{ name: 'A' }]), before);
  assert.equal(previewOverviewForScreens(undefined).clients[0].monitorId, 'preview');
});
