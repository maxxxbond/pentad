import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../quickshell/features/bar/TrayMenuLevel.qml', import.meta.url), 'utf8');
const functions = [...source.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
const hoverTimer = source.match(/Timer \{\s+id: hoverOpenDelay([\s\S]*?)\n    \}/)[1];
const hoverCallback = hoverTimer.match(/onTriggered: \{([\s\S]*?)\n        \}/)[1];

function timer() {
  return { running: false, interval: 0, stop() { this.running = false; },
    start() { this.running = true; }, restart() { this.running = true; } };
}
function fixture({ mockOpen = true } = {}) {
  const submenu = { visible: true, rowEnabled: true, modelData: { hasChildren: true }, pointerHovered: true };
  const leaf = { visible: true, rowEnabled: true, modelData: { hasChildren: false }, pointerHovered: true };
  const c = vm.createContext({
    Date: { now: () => 10_000 },
    Qt: { Key_Up: 1, Key_Down: 2, Key_Right: 3, Key_Left: 4, Key_Escape: 5,
      Key_Return: 6, Key_Enter: 7, Key_Space: 8 },
    hoverOpenMs: 180, pendingRow: null, pendingClose: false,
    activeChild: null, submenuComponent: null,
    ownerMenu: null, parentLevel: null, services: null, menuHandle: null,
    entriesOverride: [], grabFocus: false,
    popup: { opened: true, pointerIntent: {} },
    rows: { count: 2, itemAt(index) { return [submenu, leaf][index] || null; } },
    hoverOpenDelay: timer(), submenu, leaf,
  });
  c.root = c; c.level = c;
  vm.runInContext(functions, c, { timeout: 1000 });
  c.openChildCalls = [];
  if (mockOpen) c.openChild = (row, skipAim) => c.openChildCalls.push({ row, skipAim });
  c.closeChildCalls = 0;
  c.closeChild = () => { c.closeChildCalls++; };
  c.rowIsCurrent = row => row === submenu || row === leaf;
  return { c, submenu, leaf };
}
function fire(context, body) {
  vm.runInContext(`(function() { ${body} })()`, context, { timeout: 1000 });
}

test('submenu hover waits 180 ms, then opens only while the same row remains hovered', () => {
  const { c, submenu } = fixture();
  c.hoverRow(submenu);
  assert.equal(c.hoverOpenDelay.running, true);
  assert.equal(c.hoverOpenDelay.interval, 180);
  fire(c, hoverCallback);
  assert.deepEqual(c.openChildCalls.map(call => call.skipAim), [false]);
  c.openChildCalls = [];
  c.hoverRow(submenu);
  submenu.pointerHovered = false;
  fire(c, hoverCallback);
  assert.deepEqual(c.openChildCalls, []);
});

test('leaf hover records pending close but leaves all timing to the sampled safe-hull controller', () => {
  const { c, leaf } = fixture();
  c.activeChild = { anchorItem: {} };
  c.hoverRow(leaf);
  assert.equal(c.pendingRow, leaf);
  assert.equal(c.pendingClose, true);
  assert.equal(c.hoverOpenDelay.running, false);
  assert.doesNotMatch(source, /id: switchDelay/);
});

test('sibling submenu replacement waits for the old child dismiss event after its hull exit', () => {
  const { c, submenu } = fixture({ mockOpen: false });
  const oldChild = { anchorItem: {}, dismissed: { callback: null, connect(callback) { this.callback = callback; } },
    close() {}, destroy() {} };
  c.activeChild = oldChild;
  submenu.button = {};
  submenu.modelData = { hasChildren: true, children: [] };
  c.openChild(submenu, false);
  assert.equal(c.pendingRow, submenu);
  assert.equal(c.pendingClose, false);
  const newChild = { dismissed: { connect() {} }, open() {}, close() {}, destroy() {}, focusFirst() {} };
  c.Component = { Ready: 1 };
  c.Qt = { createComponent: () => ({ status: 1, createObject: () => newChild }),
    resolvedUrl: value => value, callLater() {} };
  c.finishChildDismissal(oldChild);
  assert.equal(c.activeChild, newChild);
});

test('keyboard navigation cancels pending hover-open and close actions', () => {
  const { c, submenu } = fixture();
  c.pendingRow = submenu;
  c.pendingClose = true;
  c.hoverOpenDelay.start();
  c.previousEntry = () => null;
  c.nextEntry = () => null;
  assert.equal(c.handleRowKey(1, c.Qt.Key_Down), true);
  assert.equal(c.hoverOpenDelay.running, false);
  assert.equal(c.pendingRow, null);
  assert.equal(c.pendingClose, false);
});

test('row origin updates only from points inside the source row', () => {
  assert.match(source, /onPointChanged: if \(hovered && point\.position\.x >= 0/);
  assert.match(source, /point\.position\.y <= row\.height/);
  assert.match(source, /row\.lastInsideGlobalPoint/);
});

test('hover-open timer reads the popup by id, not as a missing level property', () => {
  assert.doesNotMatch(source, /level\.popup\./);
  assert.match(hoverCallback, /if \(popup\.opened && level\.rowIsCurrent\(row\)/);
});

test('first-row focus is painted only after keyboard open or navigation', () => {
  const { c } = fixture();
  c.anchorItem = {};
  c.popup.open = () => {};
  c.open();
  assert.equal(c.keyboardFocusVisible, false);
  c.open(true);
  assert.equal(c.keyboardFocusVisible, true);
  c.open();
  c.previousEntry = () => null;
  c.nextEntry = () => null;
  c.handleRowKey(0, c.Qt.Key_Down);
  assert.equal(c.keyboardFocusVisible, true);
  assert.match(source, /readonly property bool focusPainted: itemButton\.activeFocus && level\.keyboardFocusVisible/);
  assert.doesNotMatch(source, /itemButton\.hovered \|\| itemButton\.activeFocus/);
});
