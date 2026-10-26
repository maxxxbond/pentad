import test from "node:test";
import assert from "node:assert/strict";
import { helpBubbleGeometry, helpBubblePlacement } from "../../quickshell/logic/help-bubble.mjs";

const area = { width: 800, height: 600 };

test("help bubble sits above its trigger, centred, with the tail on the trigger", () => {
  assert.deepEqual(helpBubblePlacement({ x: 388, y: 300, width: 24, height: 24 }, area, 240, 80),
    { x: 280, y: 216, side: "above", tailX: 120 });
});

test("help bubble drops below when the window has no room above", () => {
  const placed = helpBubblePlacement({ x: 388, y: 20, width: 24, height: 24 }, area, 240, 80);
  assert.equal(placed.side, "below");
  assert.equal(placed.y, 48);
});

test("help bubble stays inside the window and keeps the tail on an edge trigger", () => {
  const left = helpBubblePlacement({ x: 0, y: 300, width: 24, height: 24 }, area, 240, 80);
  assert.equal(left.x, 8);
  assert.equal(left.tailX, 4);
  const right = helpBubblePlacement({ x: 776, y: 300, width: 24, height: 24 }, area, 240, 80);
  assert.equal(right.x, 552);
  assert.equal(right.tailX, 236);
});

test("help bubble picks the roomier side when neither fits", () => {
  const short = { width: 800, height: 120 };
  assert.equal(helpBubblePlacement({ x: 388, y: 90, width: 24, height: 24 }, short, 240, 100).side, "above");
  assert.equal(helpBubblePlacement({ x: 388, y: 10, width: 24, height: 24 }, short, 240, 100).side, "below");
});

test("help bubble contour keeps the tail clear of the rounded corners", () => {
  const centred = helpBubbleGeometry(240, 80, 120);
  assert.equal(centred.tailX, 120);
  assert.equal(centred.bodyTop, 8);
  assert.match(centred.path, /^M 0 24 /);
  assert.match(centred.path, / 120 0 C /);
  assert.ok(centred.path.endsWith(" Z"));
  assert.equal(helpBubbleGeometry(240, 80, 2).tailX, 26);
  assert.equal(helpBubbleGeometry(240, 80, 999).tailX, 214);
});

test("help bubble contour rejects bad input and collapses when empty", () => {
  assert.throws(() => helpBubbleGeometry(NaN, 80, 10), TypeError);
  assert.equal(helpBubbleGeometry(0, 80, 10).path, "");
  assert.equal(helpBubbleGeometry(100, 6, 10).path, "");
});
