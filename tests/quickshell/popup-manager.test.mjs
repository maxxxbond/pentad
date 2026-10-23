import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../quickshell/shell/PopupManager.qml', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
function fixture() {
  const deferred = [];
  const events = [];
  const m = vm.createContext({
    surfaces: [], children: [], hosts: [], visibleHosts: {}, capturePending: false,
    Qt: { callLater(callback) { deferred.push(callback); } },
    changed() { events.push('changed'); },
    capturePreparing() { events.push('preparing'); },
    captureReady() { events.push('ready'); },
  });
  for (const [property, get] of Object.entries({
    surface: () => m.surfaces.at(-1)?.name || '',
    outputId: () => m.surfaces.at(-1)?.output || '',
    instanceId: () => m.surfaces.at(-1)?.instance || '',
    childSurface: () => m.children.at(-1)?.child || null,
  })) Object.defineProperty(m, property, { get });
  vm.runInContext(methods, m, { timeout: 1000 });
  return { m, events, flush() { while (deferred.length) deferred.shift()(); } };
}
function child(ownerWindow) {
  return { ownerWindow, closed: 0, close() { this.closed++; } };
}

test('left, right and activity stay open, including across outputs', () => {
  const { m } = fixture();
  for (const name of ['left', 'right', 'activity']) m.open(name, 'DP-1');
  m.open('right', 'DP-2');
  assert.equal(m.surfaces.length, 4);
  for (const name of ['left', 'right', 'activity']) assert.equal(m.isOpen(name, 'DP-1'), true);
  m.toggle('right', 'DP-1');
  assert.equal(m.isOpen('right', 'DP-1'), false);
  assert.equal(m.isOpen('right', 'DP-2'), true);
  assert.equal(m.isOpen('left', 'DP-1'), true);
  assert.equal(m.isOpen('activity', 'DP-1'), true);
});

test('reopening updates one instance without duplicating it or closing another menu', () => {
  const { m } = fixture();
  m.open('activity', 'DP-1', 'timer');
  m.open('left', 'DP-1');
  m.toggle('activity', 'DP-1', 'media');
  assert.equal(m.surfaces.length, 2);
  assert.equal(m.instanceFor('activity', 'DP-1'), 'media');
  assert.equal(m.instanceFor('activity', 'DP-2'), '');
  m.toggle('activity', 'DP-1', 'media');
  assert.equal(m.surface, 'left');
});

test('children survive a main menu opening and close with their own surface', () => {
  const { m } = fixture();
  const host = { surfaceName: 'right', outputId: 'DP-1' };
  m.registerHost(host);
  m.open('right', 'DP-1');
  const a = child(host);
  m.registerChild(a);
  m.registerChild(a);
  m.open('left', 'DP-1');
  assert.equal(m.children.length, 1);
  assert.equal(a.closed, 0);
  m.closeSurface('left', 'DP-1');
  assert.equal(a.closed, 0);
  m.closeSurface('right', 'DP-1');
  assert.equal(a.closed, 1);
  assert.equal(m.children.length, 0);
});

test('opening an interactive menu closes the others, across bars and surfaces', () => {
  const { m } = fixture();
  const bar = { screen: { name: 'DP-1' } }, otherBar = { screen: { name: 'DP-2' } };
  const host = { surfaceName: 'right', outputId: 'DP-1' };
  m.registerHost(host);
  const tray = child(bar); tray.window = {};
  const submenu = child(tray.window);
  m.registerChild(tray); m.registerChild(submenu);
  const keyboard = child(bar);
  m.registerChild(keyboard);
  assert.equal(tray.closed, 1);
  assert.equal(submenu.closed, 1);
  assert.deepEqual(m.children.map(entry => entry.child), [keyboard]);
  const remote = child(otherBar);
  m.registerChild(remote);
  assert.equal(keyboard.closed, 1);
  const sidebar = child(host);
  m.registerChild(sidebar);
  assert.equal(remote.closed, 1);
  assert.equal(m.childSurface, sidebar);
});

test('a nested menu keeps its ancestors and replaces only its sibling branch', () => {
  const { m } = fixture();
  const root = child(null); root.window = {};
  const first = child(root.window); first.window = {};
  const leaf = child(first.window);
  m.registerChild(root); m.registerChild(first); m.registerChild(leaf);
  assert.equal(root.closed + first.closed, 0);
  const second = child(root.window);
  m.registerChild(second);
  assert.equal(root.closed, 0);
  assert.equal(first.closed, 1);
  assert.equal(leaf.closed, 1);
  assert.deepEqual(m.children.map(entry => entry.child), [root, second]);
});

test('passive hover popups neither close menus nor are closed by them', () => {
  const { m } = fixture();
  const passive = { ...child(null), grabFocus: false };
  const menu = child(null);
  m.registerChild(passive); m.registerChild(menu);
  assert.equal(passive.closed, 0);
  const hover = { ...child(null), grabFocus: false };
  m.registerChild(hover);
  assert.equal(menu.closed, 0);
  assert.equal(m.children.length, 3);
});

test('Escape closes latest children before main menus and tolerates empty state', () => {
  const { m } = fixture();
  m.dismissTop();
  m.open('left', 'DP-1');
  m.open('right', 'DP-1');
  const a = child(null); a.window = {};
  const b = child(a.window);
  m.registerChild(a); m.registerChild(b);
  m.dismissTop();
  assert.equal(b.closed, 1);
  assert.equal(a.closed, 0);
  assert.equal(m.surface, 'right');
  m.dismissTop(); m.dismissTop();
  assert.equal(m.surface, 'left');
  m.dismissTop(); m.dismissTop();
  assert.equal(m.surface, '');
});

test('tray branch Escape delegates without discarding its registered owner', () => {
  const { m } = fixture();
  const menu = child(null);
  menu.dismissTop = () => { menu.dismissed = true; };
  m.registerChild(menu);
  m.dismissTop();
  assert.equal(menu.dismissed, true);
  assert.equal(m.childSurface, menu);
});

test('output disposal closes only that output and its registered children', () => {
  const { m } = fixture();
  m.open('right', 'DP-1'); m.open('left', 'DP-2');
  const a = child({ screen: { name: 'DP-1' } });
  const b = { ...child({ screen: { name: 'DP-2' } }), grabFocus: false };
  m.registerChild(a); m.registerChild(b);
  m.disposeOutput('DP-1');
  assert.equal(a.closed, 1); assert.equal(b.closed, 0);
  assert.equal(m.surfaces.length, 1);
  assert.equal(m.outputId, 'DP-2');
  m.close();
  assert.equal(b.closed, 1);
  assert.equal(m.children.length, 0);
  assert.equal(m.surface, '');
});

test('capture waits for every independent host to hide', () => {
  const { m, events, flush } = fixture();
  m.open('left', 'DP-1'); m.open('right', 'DP-1');
  m.hostVisibility('DP-1/left', true); m.hostVisibility('DP-1/right', true);
  const a = child(null); m.registerChild(a);
  m.prepareCapture();
  assert.equal(a.closed, 1);
  assert.equal(m.surfaces.length, 0);
  m.hostVisibility('DP-1/left', false); flush();
  assert.equal(events.includes('ready'), false);
  m.hostVisibility('DP-1/right', false); flush();
  assert.equal(events.filter(event => event === 'ready').length, 1);
});

test('open settings windows are captured, not waited for', () => {
  const { m, events, flush } = fixture();
  m.hostVisibility('settings', true);
  m.hostVisibility('screenshot-settings', true);
  m.hostVisibility('DP-1/left', true);
  m.prepareCapture(); flush();
  assert.equal(events.includes('ready'), false, 'a menu still holds the gate');
  m.hostVisibility('DP-1/left', false); flush();
  assert.equal(events.filter(event => event === 'ready').length, 1);
  assert.equal(m.capturePending, false);
  assert.deepEqual(Object.keys(m.visibleHosts).sort(), ['screenshot-settings', 'settings']);
  m.prepareCapture(); flush();
  assert.equal(events.filter(event => event === 'ready').length, 2, 'settings alone never block a capture');
});

test('invalid requests preserve capture and menus; reopening cancels stale capture readiness', () => {
  const { m, events, flush } = fixture();
  m.open('right', 'DP-1');
  assert.equal(m.open('invalid', 'DP-1'), false);
  assert.equal(m.surface, 'right');
  m.prepareCapture();
  assert.equal(m.open('invalid', 'DP-1'), false);
  assert.equal(m.capturePending, true);
  m.open('left', 'DP-1'); flush();
  assert.equal(events.includes('ready'), false);
  assert.equal(m.surface, 'left');
});

test('shared focus includes all bars, visible hosts and every tray branch window', () => {
  const { m } = fixture();
  const bar = {}, otherBar = {};
  const left = { barWindow: bar, visible: true }, right = { barWindow: bar, visible: true };
  const hidden = { barWindow: otherBar, visible: false };
  m.registerHost(left); m.registerHost(right); m.registerHost(hidden); m.registerHost(left);
  const a = child(bar); a.window = {};
  const b = child(a.window); b.focusWindows = [{}, {}];
  m.registerChild(a); m.registerChild(b);
  const windows = m.focusWindowList();
  assert.equal(windows.length, 7);
  for (const window of [bar, otherBar, left, right, a.window, ...b.focusWindows]) assert.equal(windows.includes(window), true);
  assert.equal(windows.includes(hidden), false);
  m.unregisterHost(left);
  assert.equal(m.hosts.includes(left), false);
});

test('closing a child closes its descendants while retaining unrelated popups', () => {
  const { m } = fixture();
  const a = child(null); a.window = {};
  const nested = child(a.window); nested.window = {};
  const leaf = child(nested.window);
  const sibling = { ...child(null), grabFocus: false };
  m.registerChild(a); m.registerChild(nested); m.registerChild(leaf); m.registerChild(sibling);
  m.unregisterChild(a);
  assert.equal(nested.closed, 1);
  assert.equal(leaf.closed, 1);
  assert.equal(sibling.closed, 0);
  assert.equal(m.children.length, 1);
  assert.equal(m.childSurface, sibling);
});

test('opening a sibling does not stop an entrance; reopening reverses a running exit', () => {
  const host = readFileSync(new URL('../../quickshell/shell/SurfaceHost.qml', import.meta.url), 'utf8');
  const handler = host.match(/function onChanged\(\) \{(.*?)\n        \}/s)[1];
  function animation(running) {
    return { running, stops: 0, starts: 0,
      stop() { this.running = false; this.stops++; },
      restart() { this.running = true; this.starts++; } };
  }
  const slideIn = animation(true), slideOut = animation(false);
  const popup = { surface: 'left', shownSurface: 'left', visible: true, slideProgress: 0.4,
    surfaceComponent: {}, prepareSide() {} };
  const context = vm.createContext({ popup, slideIn, slideOut, Qt: { callLater() {} } });
  vm.runInContext(`(function() { ${handler} })()`, context, { timeout: 1000 });
  assert.equal(slideIn.stops, 0);
  assert.equal(popup.slideProgress, 0.4);
  slideOut.running = true;
  vm.runInContext(`(function() { ${handler} })()`, context, { timeout: 1000 });
  assert.equal(slideOut.running, false);
  assert.equal(slideIn.starts, 1);
  assert.equal(popup.slideProgress, 0.4, 'reverse from current position');
});

test('deferred surface focus belongs only to the current opening', () => {
  const host = readFileSync(new URL('../../quickshell/shell/SurfaceHost.qml', import.meta.url), 'utf8');
  const handler = host.match(/function onChanged\(\) \{(.*?)\n        \}/s)[1];
  const deferred = [];
  let focuses = 0;
  const popup = { surface: 'left', shownSurface: '', visible: false, focusGeneration: 0,
    surfaceComponent: {}, prepareSide() {} };
  const animation = () => ({ running: false,
    stop() { this.running = false; }, restart() { this.running = true; } });
  const context = vm.createContext({ popup, slideIn: animation(), slideOut: animation(),
    Qt: { callLater(callback) { deferred.push(callback); } },
    keyOwner: { forceActiveFocus() { focuses++; } } });
  const change = () => vm.runInContext(`(function() { ${handler} })()`, context, { timeout: 1000 });
  const flush = () => { while (deferred.length) deferred.shift()(); };

  change();
  popup.surface = ''; change(); flush();
  assert.equal(focuses, 0, 'closing during entrance must cancel focus before the window hides');

  popup.surface = 'left'; change();
  popup.surface = ''; change();
  popup.surface = 'left'; change(); flush();
  assert.equal(focuses, 1, 'rapid reopening must not run focus callbacks from an older opening');

  popup.surface = ''; change();
  popup.surface = 'left'; change(); change(); flush();
  assert.equal(focuses, 2, 'unrelated manager changes must retain the pending opening focus');

  popup.surface = ''; change();
  popup.surface = 'left'; change(); popup.visible = false; flush();
  assert.equal(focuses, 2, 'a hidden surface must not request focus');
});

test('passive telemetry children do not enable the global focus grab or join its windows', () => {
  const { m } = fixture();
  const bar = {}, popup = {};
  m.registerHost({ barWindow: bar, visible: false });
  const passive = { ...child(bar), grabFocus: false, window: popup };
  m.registerChild(passive);
  assert.equal(m.needsFocusGrab(), false);
  assert.equal(m.focusWindowList().includes(popup), false);
  assert.equal(m.children.length, 1, 'passive child retains lifecycle tracking');
  m.closeChild();
  assert.equal(passive.closed, 1);
});

test('interactive children and visible menus still own focus alongside passive telemetry', () => {
  const { m } = fixture();
  const host = { barWindow: {}, visible: true };
  m.registerHost(host);
  m.hostVisibility('right', true);
  const passive = { ...child(host), grabFocus: false, window: {} };
  const interactive = { ...child(host), grabFocus: true, window: {} };
  m.registerChild(passive); m.registerChild(interactive);
  assert.equal(m.needsFocusGrab(), true);
  assert.equal(m.focusWindowList().includes(interactive.window), true);
  assert.equal(m.focusWindowList().includes(passive.window), false);
  m.unregisterChild(interactive);
  assert.equal(m.needsFocusGrab(), true, 'visible main menu retains focus');
  m.hostVisibility('right', false);
  assert.equal(m.needsFocusGrab(), false, 'only passive hover content remains');
});
