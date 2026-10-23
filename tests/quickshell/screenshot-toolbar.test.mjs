import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TOOLBAR_GAP, TOOLBAR_MARGIN, defaultDock, defaultSideDock, dockFromPointer, dockGeometry, normalizeDock,
} from '../../quickshell/logic/screenshot-toolbar.mjs';

const bounds = { width: 1920, height: 1080 };
const rect = { x: 600, y: 300, width: 700, height: 400 };

test('default dock prefers outside below, then above, then inside the bottom edge', () => {
  assert.deepEqual(defaultDock(rect, bounds, 560, 40), { edge: 'bottom', t: 0.5, inside: false });
  assert.deepEqual(defaultDock({ ...rect, y: 640 }, bounds, 560, 40), { edge: 'top', t: 0.5, inside: false });
  assert.deepEqual(defaultDock({ x: 0, y: 0, width: 1920, height: 1080 }, bounds, 560, 40),
    { edge: 'bottom', t: 0.5, inside: true });
});

test('geometry hugs each edge from the requested side', () => {
  const below = dockGeometry(rect, bounds, 560, 40, { edge: 'bottom', t: 0.5, inside: false });
  assert.deepEqual(below, { x: 670, y: 700 + TOOLBAR_GAP, width: 560, height: 40, horizontal: true, edge: 'bottom', inside: false });
  const insideTop = dockGeometry(rect, bounds, 560, 40, { edge: 'top', t: 0, inside: true });
  assert.equal(insideTop.y, 300 + TOOLBAR_GAP);
  assert.equal(insideTop.x, 600 - 280);
  const right = dockGeometry(rect, bounds, 560, 40, { edge: 'right', t: 1, inside: false });
  assert.deepEqual([right.x, right.width, right.height, right.horizontal], [1300 + TOOLBAR_GAP, 40, 560, false]);
  assert.equal(right.y, 700 - 280);
  const insideLeft = dockGeometry(rect, bounds, 560, 40, { edge: 'left', t: 0.5, inside: true });
  assert.deepEqual([insideLeft.x, insideLeft.y], [600 + TOOLBAR_GAP, 500 - 280]);
});

test('outside docks without room flip inside and everything stays on screen', () => {
  const full = { x: 0, y: 0, width: 1920, height: 1080 };
  const geometry = dockGeometry(full, bounds, 560, 40, { edge: 'left', t: 0, inside: false });
  assert.equal(geometry.inside, true);
  assert.deepEqual([geometry.x, geometry.y], [TOOLBAR_GAP, TOOLBAR_MARGIN]);
  const tooLong = dockGeometry(rect, { width: 300, height: 200 }, 560, 40, { edge: 'bottom', t: 1, inside: false });
  assert.equal(tooLong.x, TOOLBAR_MARGIN);
});

test('pointer projection picks the nearest edge inside and the passed edge outside', () => {
  assert.deepEqual(dockFromPointer(rect, { x: 950, y: 690 }, 0, 0), { edge: 'bottom', t: 0.5, inside: true });
  assert.deepEqual(dockFromPointer(rect, { x: 610, y: 500 }, 0, 0), { edge: 'left', t: 0.5, inside: true });
  assert.deepEqual(dockFromPointer(rect, { x: 950, y: 100 }, 0, 0), { edge: 'top', t: 0.5, inside: false });
  assert.deepEqual(dockFromPointer(rect, { x: 1500, y: 250 }, 0, 0), { edge: 'right', t: 0, inside: false });
  assert.deepEqual(dockFromPointer(rect, { x: 1350, y: 100 }, 0, 0), { edge: 'top', t: 1, inside: false });
});

test('the grabbed point stays under the pointer along the edge', () => {
  const dock = dockFromPointer(rect, { x: 700, y: 760 }, 400, 10);
  assert.equal(dock.edge, 'bottom');
  const geometry = dockGeometry(rect, bounds, 400, 40, dock);
  assert.equal(geometry.x + 10, 700);
});

test('degenerate input falls back to a centred bottom dock', () => {
  assert.deepEqual(normalizeDock(null), { edge: 'bottom', t: 0.5, inside: false });
  assert.deepEqual(normalizeDock({ edge: 'diagonal', t: 4, inside: 'yes' }), { edge: 'bottom', t: 1, inside: false });
  assert.equal(dockFromPointer({ x: 10, y: 10, width: 0, height: 0 }, { x: 10, y: 30 }, 0, 0).t, 0.5);
});

test('side dock prefers the right edge outside, then the left, then inside', () => {
  assert.deepEqual(defaultSideDock(rect, bounds, 300, 200), { edge: 'right', t: 0.5, inside: false });
  assert.deepEqual(defaultSideDock({ ...rect, x: 1400 }, bounds, 300, 200), { edge: 'left', t: 0.5, inside: false });
  assert.deepEqual(defaultSideDock({ x: 0, y: 0, width: 1920, height: 1080 }, bounds, 300, 200),
    { edge: 'right', t: 0.5, inside: true });
});
