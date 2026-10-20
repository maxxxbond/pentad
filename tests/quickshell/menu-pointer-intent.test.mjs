import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as MenuAim from '../../quickshell/logic/menu-aim.mjs';
import { surfaceGeometry } from '../../quickshell/logic/continuous-corners.mjs';

const source = readFileSync(new URL('../../quickshell/components/MenuPointerIntent.qml', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
function item(x, y, width, height) {
  return { width, height, Window: { window: {} },
    mapToGlobal(px, py) { return { x: x + px, y: y + py }; },
    mapToItem(target, px, py) {
      const origin = target.mapToGlobal(0, 0);
      return { x: x + px - origin.x, y: y + py - origin.y };
    },
  };
}
function fakeTimer() { return { running: false, stop() { this.running = false; }, restart() { this.running = true; } }; }
function fixture() {
  const events = [];
  const anchorItem = item(100, 4, 24, 28);
  const surfaceItem = item(20, 40, 236, 240);
  const c = vm.createContext({
    MenuAim, Qt: { NoButton: 0 },
    active: true, pointerDismissEnabled: true, armed: true,
    motionObserved: false,
    anchorHovered: true, surfaceHovered: false, draggingOutside: false,
    dismissedByPointer: false, targetReached: false, openChildren: 0, childIntents: [], legacyChildCount: 0,
    lastInsidePoint: { x: 112, y: 28 }, lastObservedAt: 0,
    parentIntent: null, registeredParent: null,
    anchorItem, surfaceItem, coordinateItem: null, useAnchorCorridor: false,
    lastPoint: { x: 112, y: 28 }, previousPoint: { x: 112, y: 20 },
    intentOrigin: null, aimTargetItem: null, startedAt: 0, graceMs: 350, buffer: 4,
    farDismissDistance: 80, freshPointMaxAge: 120,
    closeTimer: { running: false, interval: 0, stop() { this.running = false; },
      start() { this.running = true; }, restart() { this.running = true; } },
    dismissRequested() { events.push('dismiss'); }, aimDeferred() {},
  });
  c.root = c;
  vm.runInContext(methods, c, { timeout: 1000 });
  return { c, events };
}

const closeTimerBlock = source.match(/Timer \{\s+id: closeTimer([\s\S]*?)\n    \}/)[1];
const closeCallback = closeTimerBlock.match(/onTriggered: \{([\s\S]*?)\n        \}/)[1];
const cursorSocketBlock = source.match(/Socket \{\s+id: cursorSocket([\s\S]*?)\n    \}/)[1];
const connectionCallback = cursorSocketBlock.match(/onConnectionStateChanged: \{([\s\S]*?)\n        \}/)[1];

test('leaving the trigger into its safe hull does not start an outside timer', () => {
  const { c, events } = fixture();
  c.leaveItem(c.anchorItem, 0);
  assert.deepEqual(events, []);
  assert.equal(c.closeTimer.running, false);
});

test('mapping revokes stationary anchor hover without starting pointer dismissal', () => {
  const { c, events } = fixture();
  c.armed = false;
  c.lastPoint = null;
  c.previousPoint = null;
  c.observePoint(c.anchorItem, { x: 12, y: 14 }, undefined, 0);
  c.enterChain();
  c.observePoint(c.anchorItem, { x: 12, y: 14 }, undefined, 0);
  c.leaveItem(c.anchorItem, 0);
  assert.equal(c.armed, false);
  assert.equal(c.closeTimer.running, false);
  assert.deepEqual(events, []);
});

test('real pointer motion or menu entry arms dismissal after a stationary open', () => {
  const { c } = fixture();
  c.armed = false;
  c.lastPoint = null;
  c.observePoint(c.anchorItem, { x: 12, y: 14 }, undefined, 0);
  c.observePoint(c.anchorItem, { x: 12, y: 20 }, undefined, 0);
  assert.equal(c.armed, true);
  c.armed = false;
  c.motionObserved = false;
  c.surfaceHovered = true;
  c.enterChain();
  assert.equal(c.armed, true);
});

test('a point already inside the destination must not dismiss before its hover event arrives', () => {
  const { c, events } = fixture();
  c.observePoint(c.anchorItem, { x: 12, y: 40 }, undefined, 0);
  assert.equal(c.surfaceHovered, true);
  c.leaveItem(c.anchorItem, 0);
  assert.deepEqual(events, []);
  assert.equal(c.closeTimer.running, false);
});

test('the delayed source leave must not restart a timer after target entry was observed', () => {
  const { c, events } = fixture();
  c.leaveItem(c.anchorItem, 0);
  c.observePoint(c.surfaceItem, { x: 92, y: 0 }, undefined, 0);
  c.leaveItem(c.anchorItem, 0);
  assert.deepEqual(events, []);
  assert.equal(c.closeTimer.running, false);
});

test('a fresh point far from the whole menu branch dismisses immediately', () => {
  const { c, events } = fixture();
  c.previousPoint = { x: 112, y: 20 };
  c.lastPoint = { x: 500, y: 500 };
  c.lastObservedAt = Date.now();
  c.anchorHovered = false;
  c.surfaceHovered = false;
  c.leaveItem(c.anchorItem, 0);
  assert.deepEqual(events, ['dismiss']);
});

test('an observed point inside the safe hull can remain there beyond grace without closing', () => {
  const { c, events } = fixture();
  c.lastPoint = { x: 140, y: 36 };
  c.lastInsidePoint = { x: 112, y: 28 };
  c.previousPoint = { x: 112, y: 28 };
  c.lastObservedAt = 1000;
  c.anchorHovered = false;
  c.surfaceHovered = false;
  c.observeGlobalPoint({ x: 140, y: 36 }, 1000);
  c.observeGlobalPoint({ x: 140, y: 36 }, 2000);
  assert.equal(c.startedAt, 0);
  assert.equal(c.closeTimer.running, false);
  assert.deepEqual(c.intentOrigin, { x: 112, y: 28 });
  assert.deepEqual(events, []);
});

test('fresh outside samples start one grace interval; reentry into the hull cancels it', () => {
  const { c, events } = fixture();
  c.anchorHovered = false;
  c.surfaceHovered = false;
  c.aimTargetItem = c.surfaceItem;
  c.intentOrigin = { x: 112, y: 28 };
  c.observeGlobalPoint({ x: 258, y: 300 }, 1000);
  const began = c.startedAt;
  assert.equal(began, 1000);
  assert.equal(c.closeTimer.running, true);
  c.observeGlobalPoint({ x: 258, y: 300 }, 1300);
  assert.equal(c.startedAt, began);
  c.observeGlobalPoint({ x: 140, y: 36 }, 1400);
  assert.equal(c.startedAt, 0);
  assert.equal(c.closeTimer.running, false);
  assert.deepEqual(events, []);
});

test('attached menu aim excludes transparent shoulders but retains its full body', () => {
  const popover = readFileSync(new URL('../../quickshell/components/AttachedPopover.qml', import.meta.url), 'utf8');
  assert.match(popover, /surfaceItem: pointerField/);
  const field = popover.match(/Item \{\s+id: pointerField\n(.*?)\n            \}/s)[1];
  const contour = surfaceGeometry(332, 278, 32, 32);
  const bounds = vm.createContext({ popup: { barAttachment: true, surfaceWidth: 332, surfaceHeight: 278,
    geometry: { contentLeft: contour.shoulder, contentRight: 332 - contour.shoulder, bodyTop: 0 } } });
  for (const match of field.matchAll(/^                (x|y|width|height): (.*?)(?=^                \w+:|(?![\s\S]))/gms))
    vm.runInContext(`${match[1]} = (${match[2].trim()})`, bounds, { timeout: 1000 });
  const { c } = fixture();
  c.surfaceItem = item(48 + bounds.x, 40 + bounds.y, bounds.width, bounds.height);
  const rect = c.itemRect(c.surfaceItem);
  assert.deepEqual({ ...rect }, { x: 80, y: 40, width: 268, height: 278 });
  assert.equal(MenuAim.pointInRect({ x: 60, y: 100 }, rect), false);
  assert.equal(MenuAim.pointInRect({ x: 90, y: 100 }, rect), true);
  assert.deepEqual(MenuAim.nearestEdgeTriangle({ x: 214, y: 28 }, rect, 0), {
    a: { x: 214, y: 28 }, b: { x: 80, y: 40 }, c: { x: 348, y: 40 },
  });
});

test('menu content belongs to the hover field and retains its visible padding', () => {
  const popover = readFileSync(new URL('../../quickshell/components/AttachedPopover.qml', import.meta.url), 'utf8');
  const content = popover.match(/Item \{\s+id: contentHost\n(.*?)\n                focus:/s)[1];
  assert.match(content, /parent: pointerField/);
  for (const layout of [
    { attached: true, field: { x: 32, y: 0, width: 268, height: 278 }, expected: { x: 48, y: 16, width: 236, height: 246 } },
    { attached: false, field: { x: 0, y: 22, width: 280, height: 98 }, expected: { x: 12, y: 34, width: 256, height: 74 } },
  ]) {
    const context = vm.createContext({ popup: { barAttachment: layout.attached }, pointerField: layout.field });
    for (const match of content.matchAll(/^                (x|y|width|height): ([^\n]+)/gm))
      vm.runInContext(`${match[1]} = (${match[2]})`, context, { timeout: 1000 });
    assert.deepEqual({ x: layout.field.x + context.x, y: layout.field.y + context.y,
      width: context.width, height: context.height }, layout.expected);
  }
});

test('layer surfaces with synthetic Qt origins map through their declared screen positions', () => {
  for (const screenX of [0, -1920]) {
    const { c } = fixture();
    c.coordinateItem = item(0, 0, 800, 40);
    c.coordinateOrigin = { x: screenX, y: 0 };
    const surface = item(0, 0, 332, 278);
    surface.pointerGlobalOrigin = { x: screenX + 46, y: 40 };
    c.surfaceItem = item(32, 0, 268, 278);
    c.surfaceItem.parent = surface;
    assert.deepEqual({ ...c.itemRect(c.surfaceItem) }, { x: 78, y: 40, width: 268, height: 278 });
    assert.deepEqual({ ...c.globalPoint(c.surfaceItem, { x: 60, y: 15 }) }, { x: 138, y: 55 });
    const row = item(48, 16, 236, 30);
    row.parent = c.surfaceItem;
    assert.deepEqual({ ...c.itemRect(row) }, { x: 94, y: 56, width: 236, height: 30 });
  }
});

test('debug field and corridor map known screen coordinates without Qt layer origins', () => {
  const overlay = readFileSync(new URL('../../quickshell/components/MenuPointerIntentOverlay.qml', import.meta.url), 'utf8');
  const functions = [...overlay.matchAll(/^        function local[XY]\([^\n]+/gm)].map(match => match[0]).join('\n');
  for (const origin of [{ x: 0, y: 40 }, { x: -1920, y: 80 }]) {
    const context = vm.createContext({ root: { targetScreen: origin, contentItem: {
      mapFromGlobal() { throw new Error('native Qt layer origins are not reliable'); },
    } } });
    vm.runInContext(functions, context, { timeout: 1000 });
    assert.equal(context.localX(origin.x + 80), 80);
    assert.equal(context.localY(origin.y + 40), 40);
  }
});

test('a mapping child protects its parent without arming keyboard-opened menus', () => {
  const { c, events } = fixture();
  c.armed = false;
  c.addChild();
  assert.equal(c.openChildren, 1);
  assert.equal(c.armed, false);
  c.removeChild(false);
  assert.equal(c.openChildren, 0);
  assert.equal(c.closeTimer.running, false);
  assert.deepEqual(events, []);
});

test('a child checks early dismissal against its full branch but cancels only on its own branch surfaces', () => {
  const { c: parent } = fixture();
  const { c: child } = fixture();
  child.anchorItem = item(300, 100, 100, 30);
  child.surfaceItem = item(400, 100, 120, 180);
  child.parentIntent = parent;
  child.active = true;
  parent.addChild(child);
  const pointInOtherParentArea = { x: 30, y: 200 };
  assert.equal(child.pointInBranch(pointInOtherParentArea), false);
  child.lastObservedAt = Date.now();
  assert.equal(child.freshPointIsFar(pointInOtherParentArea, Date.now()), false);
});

test('tray coordinates stay on the visible field when native bar coordinates include a 40px offset', () => {
  const overlay = readFileSync(new URL('../../quickshell/components/MenuPointerIntentOverlay.qml', import.meta.url), 'utf8');
  const functions = [...overlay.matchAll(/^        function local[XY]\([^\n]+/gm)].map(match => match[0]).join('\n');
  for (const offset of [{ x: 0, y: 40 }, { x: -1920, y: 40 }]) {
    const { c, events } = fixture();
    c.coordinateItem = item(offset.x, offset.y, 1920, 40);
    c.anchorItem = item(offset.x + 184, offset.y + 4, 24, 28);
    c.surfaceItem = item(offset.x + 62, offset.y + 40, 268, 278);
    assert.deepEqual({ ...c.itemRect(c.anchorItem) }, { x: 184, y: 4, width: 24, height: 28 });
    const field = c.itemRect(c.surfaceItem);
    assert.deepEqual({ ...field }, { x: 62, y: 40, width: 268, height: 278 });
    c.observePoint(c.anchorItem, { x: 12, y: 20 }, undefined, 0);
    c.observePoint(c.anchorItem, { x: 12, y: 28 }, undefined, 0);
    c.leaveItem(c.anchorItem, 0);
    assert.equal(c.closeTimer.running, false);
    assert.deepEqual(events, []);
    const hull = c.aimCorridor(c.surfaceItem, c.intentOrigin);
    assert.equal(MenuAim.pointInCorridor({ x: 196, y: 32 }, hull), true);
    const diagnostic = vm.createContext({ root: { intent: c, contentItem: {
      mapFromGlobal() { throw new Error('must not mix in the overlay native origin'); },
    } } });
    vm.runInContext(functions, diagnostic, { timeout: 1000 });
    assert.equal(diagnostic.localY(field.y), 40);
    assert.equal(diagnostic.localY(field.y + field.height), 318);
    assert.equal(diagnostic.localX(field.x), 62);
    assert.equal(diagnostic.localY(32), 32);
    c.observePoint(c.surfaceItem, { x: 134, y: 1 }, undefined, 0);
    assert.equal(c.closeTimer.running, false);
    assert.deepEqual(events, []);
  }
});

test('menu corridor uses source and target rectangles, including a touching flipped submenu', () => {
  const { c, events } = fixture();
  const origin = { x: 123, y: 16 };
  const expected = MenuAim.safeCorridorPolygon(
    { x: 100, y: 4, width: 24, height: 28 },
    { x: 20, y: 40, width: 236, height: 240 }, 4);
  const corridor = c.aimCorridor(c.surfaceItem, origin);
  assert.ok(corridor.points.length >= 4);
  assert.equal(MenuAim.pointInCorridor({ x: 150, y: 36 }, corridor), true);
  assert.equal(MenuAim.pointInCorridor({ x: 110, y: 20 }, corridor), true);
  assert.equal(c.pointAimingAt(c.surfaceItem, origin, { x: 150, y: 36 }), true);
  c.aimTargetItem = c.surfaceItem;
  c.intentOrigin = origin;
  c.requestDismiss();
  assert.deepEqual(c.debugDismissedGeometry.corridor.points.map(point => ({ ...point })),
    expected.points.map(point => ({ ...point })));
  assert.deepEqual(events, ['dismiss']);
  const row = item(302, 134, 236, 30);
  const submenu = item(42, 134, 260, 54);
  const flipped = c.aimCorridor(submenu, { x: 520, y: 160 }, row);
  assert.equal(MenuAim.pointInCorridor({ x: 300, y: 160 }, flipped), true);
});

test('diagnostic overlay covers the reservation without relying on the scaled Ignore sentinel', () => {
  const overlay = readFileSync(new URL('../../quickshell/components/MenuPointerIntentOverlay.qml', import.meta.url), 'utf8');
  assert.match(overlay, /^    exclusionMode: ExclusionMode.Normal$/m);
  assert.match(overlay, /^    exclusiveZone: 0$/m);
  assert.match(overlay, /margins\.top: intent \? -intent\.topReservation : 0/);
  assert.match(overlay, /corridor\.points/);
  assert.match(overlay, /visible: debugEnabled && debugActive/);
  assert.doesNotMatch(overlay, /retainTimer|frozen 1\.8s/);
});

test('after the pointer reaches the menu, leaving it ignores the corridor and reentry resets grace', () => {
  const { c, events } = fixture();
  c.anchorHovered = false;
  c.observeGlobalPoint({ x: 140, y: 100 }, 1000);
  assert.equal(c.targetReached, true);
  c.observeGlobalPoint({ x: 140, y: 36 }, 1100);
  c.observeGlobalPoint({ x: 140, y: 36 }, 1150);
  assert.equal(c.startedAt, 1150);
  assert.equal(c.closeTimer.running, true);
  assert.equal(c.aimCorridor(c.surfaceItem, c.intentOrigin), null);
  c.observeGlobalPoint({ x: 140, y: 100 }, 1300);
  assert.equal(c.startedAt, 0);
  assert.equal(c.closeTimer.running, false);
  assert.deepEqual(events, []);
});

test('a parent stops protecting a child corridor once the child surface was reached', () => {
  const { c: parent } = fixture();
  const { c: child } = fixture();
  child.parentIntent = parent;
  child.surfaceItem = item(42, 134, 260, 188);
  child.anchorItem = item(302, 134, 236, 30);
  child.active = true;
  child.targetReached = true;
  parent.childIntents = [child];
  assert.equal(parent.pointInDescendantCorridor({ x: 280, y: 180 }), false);
});

test('root protects the child hull before the child receives its first gap sample', () => {
  const { c: parent } = fixture();
  const { c: child } = fixture();
  child.parentIntent = parent;
  child.surfaceItem = item(42, 134, 260, 188);
  child.anchorItem = item(302, 134, 236, 30);
  child.active = true;
  parent.childIntents = [child];
  assert.equal(child.aimTargetItem, null);
  assert.equal(parent.pointInDescendantCorridor({ x: 280, y: 180 }), true);
});

test('cursor request parses fragmented data, normalizes once, and rejects timed-out generations', () => {
  const { c } = fixture();
  const observed = [];
  c.observeGlobalPoint = (point, now) => observed.push({ ...point, now });
  c.samplerRoot = true;
  c.active = true;
  c.pointerDismissEnabled = true;
  c.coordinateItem = {};
  c.coordinateOrigin = { x: -1920, y: 40 };
  c.cursorRequestInFlight = false;
  c.cursorRequestSent = false;
  c.cursorGeneration = 0;
  c.cursorAwaitingDisconnect = false;
  c.cursorReplyBuffer = '';
  c.socketGeneration = -1;
  c.cursorSocket = { connected: false };
  c.requestTimeout = fakeTimer();
  c.Hyprland = { requestSocketPath: '/private/mock.sock' };
  c.startCursorRequest();
  const generation = c.cursorGeneration;
  assert.equal(c.cursorRequestInFlight, true);
  c.startCursorRequest();
  assert.equal(c.cursorGeneration, generation);
  c.socketGeneration = generation;
  assert.equal(c.acceptCursorReply('{"x":12,', generation), false);
  assert.equal(c.acceptCursorReply('"y":34}', generation), true);
  assert.deepEqual(observed.map(({ x, y }) => ({ x, y })), [{ x: 1932, y: -6 }]);
  assert.equal(c.cursorSocket.connected, false);

  c.cursorAwaitingDisconnect = false;
  c.startCursorRequest();
  const expired = c.cursorGeneration;
  c.finishCursorRequest();
  assert.equal(c.acceptCursorReply('{"x":2,"y":3}', expired), false);
  assert.equal(observed.length, 1);
});

test('socket connection sends one cursor request and captures its request generation', () => {
  const { c } = fixture();
  const writes = [];
  c.root = c;
  c.cursorRequestInFlight = true;
  c.cursorRequestSent = false;
  c.cursorGeneration = 9;
  c.socketGeneration = -1;
  c.cursorAwaitingDisconnect = false;
  c.connected = true;
  c.write = value => writes.push(value);
  c.flush = () => { c.flushed = true; };
  vm.runInContext(`(function() { ${connectionCallback} })()`, c, { timeout: 1000 });
  assert.deepEqual(writes, ['j/cursorpos']);
  assert.equal(c.flushed, true);
  assert.equal(c.cursorRequestSent, true);
  assert.equal(c.socketGeneration, 9);
  vm.runInContext(`(function() { ${connectionCallback} })()`, c, { timeout: 1000 });
  assert.equal(writes.length, 1);
});

test('invalid cursor coordinates are ignored and disabled replies are discarded', () => {
  const { c } = fixture();
  c.observeGlobalPoint = () => assert.fail('invalid or disabled sample must not be observed');
  Object.assign(c, { samplerRoot: true, active: true, pointerDismissEnabled: true,
    cursorRequestInFlight: true, cursorGeneration: 3, socketGeneration: 3,
    cursorSocket: { connected: true }, cursorReplyBuffer: '', requestTimeout: fakeTimer() });
  assert.equal(c.acceptCursorReply('{"x":null,"y":12}', 3), false);
  Object.assign(c, { cursorRequestInFlight: true, cursorGeneration: 4, socketGeneration: 4,
    cursorReplyBuffer: '', cursorSocket: { connected: true }, pointerDismissEnabled: false });
  assert.equal(c.acceptCursorReply('{"x":12,"y":34}', 4), false);
});

test('close callback requires a fresh outside sample and never dismisses inside the hull or during drag', () => {
  const { c, events } = fixture();
  c.root = c;
  c.anchorHovered = false;
  c.surfaceHovered = false;
  c.aimTargetItem = c.surfaceItem;
  c.intentOrigin = { x: 112, y: 28 };
  c.lastPoint = { x: 140, y: 36 };
  c.lastObservedAt = 2000;
  c.draggingOutside = false;
  c.Date = { now: () => 2050 };
  vm.runInContext(`(function() { ${closeCallback} })()`, c, { timeout: 1000 });
  assert.deepEqual(events, []);
  c.lastPoint = { x: 258, y: 300 };
  c.lastObservedAt = 2050;
  c.draggingOutside = true;
  c.Date.now = () => 2100;
  vm.runInContext(`(function() { ${closeCallback} })()`, c, { timeout: 1000 });
  assert.deepEqual(events, []);
  c.draggingOutside = false;
  c.lastObservedAt = 2150;
  c.Date.now = () => 2150;
  vm.runInContext(`(function() { ${closeCallback} })()`, c, { timeout: 1000 });
  assert.deepEqual(events, ['dismiss']);
});
