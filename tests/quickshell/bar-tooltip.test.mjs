import test from "node:test";
import assert from "node:assert/strict";
import { barTooltipGeometry } from "../../quickshell/logic/bar-tooltip.mjs";
import { surfaceGeometry } from "../../quickshell/logic/continuous-corners.mjs";

test("bar tooltip geometry rejects invalid dimensions", () => {
  for (const args of [[-1, 20], [20, -1], [20, 20, -1], [NaN, 20], [20, Infinity], [20, 20, NaN], [20, 20, 16, -1]]) {
    assert.throws(() => barTooltipGeometry(...args), TypeError);
  }
});

test("bar tooltip geometry returns an empty path for a zero dimension", () => {
  assert.deepEqual(barTooltipGeometry(0, 20), {
    path: "", contentLeft: 0, contentRight: 0, bodyTop: 0,
  });
  assert.deepEqual(barTooltipGeometry(20, 0), {
    path: "", contentLeft: 0, contentRight: 0, bodyTop: 0,
  });
});

test("bar tooltip shoulders clamp to the available size and keep content inside", () => {
  for (const width of [36, 80, 96, 440]) {
    const height = 28;
    const geometry = barTooltipGeometry(width, height);
    const coordinates = [...geometry.path.matchAll(/-?(?:\d+\.?\d*|\.\d+)/g)].map(match => Number(match[0]));
    assert.match(geometry.path, /^M 0 0 L /);
    assert.ok(geometry.path.endsWith(" Z"));
    assert.equal(geometry.bodyTop, 0);
    assert.ok(geometry.contentLeft <= Math.min(16, width / 2));
    assert.equal(geometry.contentRight, width - geometry.contentLeft);
    assert.ok(geometry.contentLeft >= 0);
    assert.ok(geometry.contentRight <= width);
    assert.ok(geometry.contentRight >= geometry.contentLeft);
    assert.ok(coordinates.every(value => value >= 0));
    assert.ok(coordinates.filter((_, index) => index % 2 === 0).every(value => value <= width));
    assert.ok(coordinates.filter((_, index) => index % 2 === 1).every(value => value <= height));
  }
});

test("bar tooltip uses continuous shoulders and soft bottom corners for every preset", () => {
  for (const [width, height] of [[96, 28], [160, 28], [240, 48]]) {
    const geometry = barTooltipGeometry(width, height);
    const surface = surfaceGeometry(width, height, 16, 16);
    assert.equal(geometry.path, surface.path);
    assert.equal(geometry.path.match(/ C /g).length, 8);
    assert.ok(surface.radius >= 14 && surface.shoulder >= 14);
    assert.ok(surface.radius + surface.shoulder <= height);
    assert.equal(geometry.contentLeft, surface.shoulder);
    assert.equal(geometry.contentRight, width - surface.shoulder);
  }
});
