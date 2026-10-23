import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { continuousCorner, attachedSurfaceGeometry, evenDashPeriod, surfaceGeometry, surfaceLength } from "../../quickshell/logic/continuous-corners.mjs";

test("matches the shipped two-segment SVG contour", () => {
  const svg = readFileSync(new URL("../../quickshell/assets/shapes/continuous-corner-symbolic.svg", import.meta.url), "utf8");
  const segments = svg.match(/L 18 0 C ([^C]+) C ([^L]+)/).slice(1).map((segment) => segment.trim().split(/\s+/).map(Number));
  const actual = [];
  continuousCorner({ curveTo: (...points) => actual.push(points) }, [18, 0], 14, [1, 0], [0, 1]);
  assert.equal(actual.length, 2);
  actual.forEach((segment, index) => segment.forEach((value, coordinate) => assert.ok(Math.abs(value - segments[index][coordinate]) < 1e-8)));
});

test("preserves C2 continuity for mirrored attached shoulders", () => {
  const segments = [];
  const radius = attachedSurfaceGeometry.shoulder;
  continuousCorner({ curveTo: (...points) => segments.push(points) }, [radius, 0], radius, [-1, 0], [0, 1]);
  const [first, second] = segments;
  for (const axis of [0, 1]) {
    assert.ok(Math.abs((first[4 + axis] - first[2 + axis]) - (second[axis] - first[4 + axis])) < 1e-8);
    assert.ok(Math.abs((first[4 + axis] - 2 * first[2 + axis] + first[axis]) - (second[2 + axis] - 2 * second[axis] + first[4 + axis])) < 1e-8);
  }
  assert.deepEqual(second.slice(-2), [0, radius]);
});

test("rejects invalid corner geometry", () => {
  assert.throws(() => continuousCorner({}, [0, 0], 1, [1, 0], [0, 1]), TypeError);
  assert.throws(() => continuousCorner({ curveTo() {} }, [0, NaN], 1, [1, 0], [0, 1]), TypeError);
  assert.throws(() => continuousCorner({ curveTo() {} }, [0, 0], -1, [1, 0], [0, 1]), TypeError);
});

test("bar attachment fits shoulders and bottom corners below the bar", () => {
  const g = surfaceGeometry(360, 88, 32, 32, 40);
  assert.equal(g.join, 40);
  assert.equal(g.radius, 24);
  assert.equal(g.shoulder, 24);
  assert.equal(g.bodyWidth, 312);
  assert.ok(g.path.includes("L 360 40 C"));
});

test("attached contours never cross themselves at narrow or short sizes", () => {
  for (const width of [8, 24, 64, 360, 508]) {
    for (const height of [8, 24, 40, 88, 400]) {
      for (const join of [0, 20, 40, 120]) {
        const g = surfaceGeometry(width, height, 32, 32, join);
        assert.ok(g.bodyWidth >= 2 * g.radius - 1e-8);
        assert.ok(g.join + g.shoulder + g.radius <= height + 1e-8);
        assert.ok(Math.abs(g.radius - g.shoulder) < 1e-8);
        const values = g.path.match(/-?\d+(?:\.\d+)?(?:e[+-]?\d+)?/gi).map(Number);
        values.forEach((value, i) => assert.ok(value >= -1e-8 && value <= (i % 2 === 0 ? width : height) + 1e-8));
      }
    }
  }
});

test("empty and square surfaces retain valid geometry", () => {
  assert.equal(surfaceGeometry(0, 80, 32, 32).path, "");
  assert.equal(surfaceGeometry(80, 0, 32, 32).path, "");
  assert.equal(surfaceGeometry(80, 40, 0).radius, 0);
  assert.ok(surfaceGeometry(80, 40, 0).path.endsWith(" Z"));
  assert.throws(() => surfaceGeometry(80, NaN, 32, 32), TypeError);
});

test("measures the contour a dashed rim follows", () => {
  assert.equal(surfaceLength(100, 60, 0), 320);
  const rounded = surfaceLength(100, 60, 10);
  // A continuous corner runs a little longer than a circular quarter arc of the same radius.
  assert.ok(rounded > 320 - 80 + 4 * Math.PI * 10 / 2);
  assert.ok(rounded < 320);
  assert.equal(surfaceLength(40, 20, 30), surfaceLength(40, 20, 10));
  assert.equal(surfaceLength(0, 20, 4), 0);
});

test("stretches the dash period so whole dashes close the rim", () => {
  assert.equal(evenDashPeriod(100, 14), 100 / 7);
  assert.equal(evenDashPeriod(10, 14), 10);
  assert.equal(evenDashPeriod(0, 14), 14);
  assert.equal(evenDashPeriod(100, 0), 0);
});
