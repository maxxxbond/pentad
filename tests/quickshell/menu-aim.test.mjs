import assert from "node:assert/strict";
import test from "node:test";
import {
  nearestEdgeTriangle,
  pointInRect,
  pointInTriangle,
  shouldDeferClose,
  anchorMenuCorridor,
  pointInCorridor,
  facingEdgeTriangle,
  isFreshFarFromBranch,
  safeCorridorPolygon,
} from "../../quickshell/logic/menu-aim.mjs";

test('safe corridor is the buffered convex hull of source and target rectangles', () => {
  const source = { x: 302, y: 134, width: 236, height: 30 };
  const target = { x: 42, y: 134, width: 260, height: 54 };
  const hull = safeCorridorPolygon(source, target, 4);
  assert.ok(hull.points.length >= 4);
  for (const point of [
    { x: 400, y: 150 }, { x: 400, y: 180 }, { x: 100, y: 190 },
    { x: 302, y: 134 }, { x: 538, y: 164 }, { x: 42, y: 188 },
  ]) assert.equal(pointInCorridor(point, hull), true, JSON.stringify(point));
  assert.equal(pointInCorridor({ x: 500, y: 190 }, hull), false);
  const translated = safeCorridorPolygon({ ...source, x: source.x - 1920 },
    { ...target, x: target.x - 1920 }, 4);
  assert.equal(pointInCorridor({ x: 400 - 1920, y: 180 }, translated), true);
});

test('safe corridor selects the correct facing space in each placement direction', () => {
  const source = { x: -100, y: -20, width: 80, height: 32 };
  const targets = [
    { x: 20, y: -18, width: 90, height: 100 },
    { x: -220, y: -18, width: 90, height: 100 },
    { x: -90, y: 50, width: 100, height: 80 },
    { x: -90, y: -110, width: 100, height: 80 },
  ];
  const probes = [
    { x: 0, y: 0 }, { x: -150, y: 0 }, { x: -40, y: 30 }, { x: -40, y: -60 },
  ];
  for (let index = 0; index < targets.length; index++) {
    const hull = safeCorridorPolygon(source, targets[index], 0);
    assert.equal(pointInCorridor(probes[index], hull), true, `direction ${index}`);
    assert.ok(hull.points.every(point => Number.isFinite(point.x) && Number.isFinite(point.y)));
  }
});

test('flipped submenu corridor preserves the diagonal wedge from its source row', () => {
  const source = { x: 302, y: 134, width: 236, height: 30 };
  const target = { x: 42, y: 134, width: 260, height: 54 };
  const corridor = facingEdgeTriangle(source, target, { x: 520, y: 160 }, 0);
  assert.equal(corridor.b.x, 302);
  assert.equal(corridor.c.x, 302);
  assert.equal(pointInCorridor({ x: 302, y: 150 }, corridor), true);
  assert.equal(pointInCorridor({ x: 320, y: 170 }, corridor), true);
  assert.equal(pointInCorridor({ x: 288, y: 175 }, corridor), false);
  assert.equal(pointInCorridor({ x: 100, y: 190 }, corridor), false);
});

test('facing edge follows separated rectangles in all directions and negative coordinates', () => {
  const source = { x: -100, y: -20, width: 80, height: 32 };
  const cases = [
    [{ x: 20, y: -18, width: 90, height: 100 }, 'left', 20],
    [{ x: -220, y: -18, width: 90, height: 100 }, 'right', -130],
    [{ x: -90, y: 50, width: 100, height: 80 }, 'top', 50],
    [{ x: -90, y: -110, width: 100, height: 80 }, 'bottom', -30],
  ];
  for (const [target, edge, edgeCoordinate] of cases) {
    const triangle = facingEdgeTriangle(source, target, { x: -40, y: -4 }, 0);
    const actual = edge === 'left' || edge === 'right' ? triangle.b.x : triangle.b.y;
    assert.equal(actual, edgeCoordinate, edge);
    assert.ok(Math.abs((triangle.b.x - triangle.a.x) * (triangle.c.y - triangle.a.y)
      - (triangle.b.y - triangle.a.y) * (triangle.c.x - triangle.a.x)) > 0);
  }
});

test('touching target falls back to a nondegenerate triangle and includes source', () => {
  const source = { x: 0, y: 0, width: 100, height: 30 };
  const target = { x: 100, y: 0, width: 80, height: 120 };
  const triangle = facingEdgeTriangle(source, target, { x: 100, y: 15 }, 0);
  assert.ok(Math.abs((triangle.b.x - triangle.a.x) * (triangle.c.y - triangle.a.y)
    - (triangle.b.y - triangle.a.y) * (triangle.c.x - triangle.a.x)) > 0);
  assert.equal(pointInCorridor({ x: 5, y: 5 }, triangle), true);
});

test('only a fresh sample far from every connected branch rectangle can close early', () => {
  const branch = [
    { x: 100, y: 100, width: 100, height: 40 },
    { x: 205, y: 100, width: 120, height: 180 },
  ];
  assert.equal(isFreshFarFromBranch({ x: 50, y: 100 }, branch, 900, 1000), false);
  assert.equal(isFreshFarFromBranch({ x: 50, y: 100 }, branch, 990, 1000), false);
  assert.equal(isFreshFarFromBranch({ x: 500, y: 400 }, branch, 990, 1000), true);
  assert.equal(isFreshFarFromBranch({ x: 500, y: 400 }, [], 990, 1000), false);
  assert.equal(isFreshFarFromBranch({ x: 500, y: 400 }, [null], 990, 1000), false);
});

test('dropdown corridor connects the two upper icon corners to the two upper menu corners', () => {
  const anchor = { x: 184, y: 4, width: 24, height: 28 };
  const menu = { x: 62, y: 40, width: 268, height: 278 };
  const corridor = anchorMenuCorridor(anchor, menu);
  assert.deepEqual(corridor, {
    a: { x: 184, y: 4 }, b: { x: 208, y: 4 },
    c: { x: 330, y: 40 }, d: { x: 62, y: 40 },
  });
  for (const point of Object.values(corridor)) assert.equal(pointInCorridor(point, corridor), true);
  assert.equal(pointInCorridor({ x: 250, y: 22 }, corridor), true);
  assert.equal(pointInCorridor({ x: 140, y: 22 }, corridor), true);
  assert.equal(pointInCorridor({ x: 260, y: 10 }, corridor), false);
  assert.equal(pointInCorridor({ x: 196, y: 3 }, corridor), false);
  assert.equal(pointInCorridor({ x: 196, y: 41 }, corridor), false);
  const shifted = anchorMenuCorridor({ ...anchor, x: anchor.x - 1920 }, { ...menu, x: menu.x - 1920 });
  assert.equal(pointInCorridor({ x: 250 - 1920, y: 22 }, shifted), true);
});

test('invalid dropdown corridor geometry fails closed', () => {
  const anchor = { x: 100, y: 4, width: 24, height: 28 };
  const menu = { x: 20, y: 40, width: 236, height: 240 };
  assert.equal(anchorMenuCorridor(null, menu), null);
  assert.equal(anchorMenuCorridor({ ...anchor, width: 0 }, menu), null);
  assert.equal(anchorMenuCorridor(anchor, { ...menu, y: 4 }), null);
  assert.equal(anchorMenuCorridor(anchor, { ...menu, y: -100 }), null);
  assert.equal(anchorMenuCorridor(anchor, menu, Infinity), null);
  assert.equal(pointInCorridor({ x: 112, y: 20 }, null), false);
  assert.equal(pointInCorridor({ x: 112, y: 20 }, { ...anchorMenuCorridor(anchor, menu), d: { x: NaN, y: 40 } }), false);
});

test("aim triangle selects the nearest edge in all four directions", () => {
  const rect = { x: 100, y: 100, width: 50, height: 50 };
  assert.deepEqual(nearestEdgeTriangle({ x: 50, y: 125 }, rect), {
    a: { x: 50, y: 125 }, b: { x: 96, y: 96 }, c: { x: 96, y: 154 },
  });
  assert.deepEqual(nearestEdgeTriangle({ x: 200, y: 125 }, rect), {
    a: { x: 200, y: 125 }, b: { x: 154, y: 96 }, c: { x: 154, y: 154 },
  });
  assert.deepEqual(nearestEdgeTriangle({ x: 125, y: 200 }, rect), {
    a: { x: 125, y: 200 }, b: { x: 96, y: 154 }, c: { x: 154, y: 154 },
  });
  assert.deepEqual(nearestEdgeTriangle({ x: 125, y: 50 }, rect), {
    a: { x: 125, y: 50 }, b: { x: 96, y: 96 }, c: { x: 154, y: 96 },
  });
});

test("geometry works in negative global coordinates and expands by its buffer", () => {
  const rect = { x: -300, y: -120, width: 80, height: 40 };
  const triangle = nearestEdgeTriangle({ x: -350, y: -100 }, rect, 4);
  assert.deepEqual(triangle, {
    a: { x: -350, y: -100 }, b: { x: -304, y: -124 }, c: { x: -304, y: -76 },
  });
  assert.equal(pointInRect({ x: -304, y: -100 }, rect), false);
  assert.equal(pointInRect({ x: -304, y: -100 }, rect, 4), true);
});

test("equidistant target edges use deterministic left-edge tie breaking", () => {
  assert.deepEqual(nearestEdgeTriangle({ x: 5, y: 5 }, { x: 0, y: 0, width: 10, height: 10 }, 0), {
    a: { x: 5, y: 5 }, b: { x: 0, y: 0 }, c: { x: 0, y: 10 },
  });
});

test("point containment includes triangle and rectangle boundaries", () => {
  const triangle = {
    a: { x: 0, y: 0 }, b: { x: 10, y: 0 }, c: { x: 10, y: 10 },
  };
  assert.equal(pointInTriangle({ x: 10, y: 5 }, triangle), true);
  assert.equal(pointInTriangle({ x: 4, y: 4 }, triangle), true);
  assert.equal(pointInTriangle({ x: 2, y: 8 }, triangle), false);
  assert.equal(pointInRect({ x: 2, y: 3 }, { x: 2, y: 3, width: 4, height: 5 }), true);
  assert.equal(pointInRect({ x: 6, y: 8 }, { x: 2, y: 3, width: 4, height: 5 }), true);
});

test("diagonal movement through the aim corridor defers close", () => {
  assert.equal(shouldDeferClose({
    origin: { x: 50, y: 100 },
    previousPoint: { x: 60, y: 95 },
    point: { x: 80, y: 85 },
    targetRect: { x: 100, y: 50, width: 60, height: 100 },
    startedAt: 1000,
    now: 1100,
  }), true);
});

test("buffered target edge keeps the menu alive through the final gap", () => {
  assert.equal(shouldDeferClose({
    origin: { x: 50, y: 100 },
    previousPoint: { x: 95, y: 100 },
    point: { x: 98, y: 100 },
    targetRect: { x: 100, y: 50, width: 60, height: 100 },
    startedAt: 1000,
    now: 1100,
  }), true);
});

test("movement toward a sibling outside the target corridor permits switching", () => {
  assert.equal(shouldDeferClose({
    origin: { x: 50, y: 100 },
    previousPoint: { x: 65, y: 80 },
    point: { x: 82, y: 20 },
    targetRect: { x: 100, y: 50, width: 60, height: 100 },
    startedAt: 1000,
    now: 1100,
  }), false);
});

test("movement away beyond the jitter tolerance permits close", () => {
  assert.equal(shouldDeferClose({
    origin: { x: 50, y: 100 },
    previousPoint: { x: 75, y: 100 },
    point: { x: 65, y: 100 },
    targetRect: { x: 100, y: 50, width: 60, height: 100 },
    startedAt: 1000,
    now: 1100,
  }), false);
});

test("stationary pointer gets one fixed grace interval", () => {
  const request = {
    origin: { x: 50, y: 100 },
    point: { x: 50, y: 100 },
    targetRect: { x: 100, y: 50, width: 60, height: 100 },
    startedAt: 1000,
    graceMs: 300,
  };
  assert.equal(shouldDeferClose({ ...request, now: 1299 }), true);
  assert.equal(shouldDeferClose({ ...request, now: 1300 }), false);
  assert.equal(shouldDeferClose({ ...request, now: 1400 }), false);
});

test("entering the target transfers hover ownership", () => {
  assert.equal(shouldDeferClose({
    origin: { x: 50, y: 100 },
    point: { x: 110, y: 100 },
    targetRect: { x: 100, y: 50, width: 60, height: 100 },
    startedAt: 1000,
    now: 1100,
  }), false);
});

test("invalid and degenerate geometry never defers close", () => {
  const invalidPoints = [
    { x: NaN, y: 1 }, { x: Infinity, y: 1 }, null,
  ];
  const invalidRects = [
    { x: NaN, y: 0, width: 10, height: 10 },
    { x: 0, y: Infinity, width: 10, height: 10 },
    { x: 0, y: 0, width: 0, height: 10 },
    { x: 0, y: 0, width: 10, height: 0 },
    { x: Number.MAX_VALUE, y: 0, width: Number.MAX_VALUE, height: 10 },
  ];
  const validPoint = { x: 0, y: 0 };
  const validRect = { x: 10, y: 10, width: 10, height: 10 };

  for (const point of invalidPoints) {
    assert.equal(pointInTriangle(point, { a: validPoint, b: { x: 1, y: 0 }, c: { x: 0, y: 1 } }), false);
    assert.equal(pointInRect(point, validRect), false);
    assert.equal(nearestEdgeTriangle(point, validRect), null);
    assert.equal(shouldDeferClose({ origin: point, point, targetRect: validRect, startedAt: 0, now: 0 }), false);
  }
  for (const rect of invalidRects) {
    assert.equal(pointInRect(validPoint, rect), false);
    assert.equal(nearestEdgeTriangle(validPoint, rect), null);
    assert.equal(shouldDeferClose({ origin: validPoint, point: validPoint, targetRect: rect, startedAt: 0, now: 0 }), false);
  }
  assert.equal(pointInTriangle({ x: 0, y: 0 }, {
    a: { x: 0, y: 0 }, b: { x: 1, y: 1 }, c: { x: 2, y: 2 },
  }), false);
});

test("invalid timing, buffers, and grace intervals fail closed", () => {
  const input = {
    origin: { x: 0, y: 0 },
    point: { x: 0, y: 0 },
    targetRect: { x: 10, y: 0, width: 20, height: 20 },
    startedAt: 0,
    now: 10,
  };
  assert.equal(shouldDeferClose({ ...input, now: Infinity }), false);
  assert.equal(shouldDeferClose({ ...input, startedAt: NaN }), false);
  assert.equal(shouldDeferClose({ ...input, graceMs: -1 }), false);
  assert.equal(shouldDeferClose({ ...input, buffer: -1 }), false);
  assert.equal(nearestEdgeTriangle(input.origin, input.targetRect, NaN), null);
  assert.equal(pointInRect(input.point, input.targetRect, Infinity), false);
  assert.equal(nearestEdgeTriangle(input.origin, input.targetRect, Number.MAX_VALUE), null);
});
