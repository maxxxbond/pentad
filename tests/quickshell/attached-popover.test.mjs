import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { attachedPopoverGeometry, popoverPlacement } from "../../quickshell/logic/attached-popover.mjs";

test("layer popover placement joins the bar and clamps both horizontal edges", () => {
  const screen = { x: 0, y: 0, width: 800, height: 600 };
  assert.deepEqual(popoverPlacement({ x: 200, y: 6, width: 24, height: 28 }, screen, 332, 278, "below", 40),
    { x: 46, y: 40, width: 332, height: 278 });
  assert.equal(popoverPlacement({ x: 0, y: 6, width: 24, height: 28 }, screen, 332, 278, "below", 40).x, 0);
  assert.equal(popoverPlacement({ x: 776, y: 6, width: 24, height: 28 }, screen, 332, 278, "below", 40).x, 468);
});

test("layer submenu flips left and remains inside short and negative-coordinate outputs", () => {
  const screen = { x: -800, y: -100, width: 800, height: 600 };
  assert.deepEqual(popoverPlacement({ x: -100, y: 450, width: 80, height: 30 }, screen, 260, 100, "right"),
    { x: -360, y: 400, width: 260, height: 100 });
  assert.deepEqual(popoverPlacement({ x: -700, y: -90, width: 24, height: 28 }, screen, 900, 700),
    { x: -800, y: -100, width: 800, height: 600 });
});

test("popover contour keeps the neck at the requested trigger after the body shifts", () => {
  const left = attachedPopoverGeometry(280, 120, 28);
  const shifted = attachedPopoverGeometry(280, 120, 252);
  const centered = attachedPopoverGeometry(280, 120, 140);
  assert.equal(left.neckCenter, 28);
  assert.equal(shifted.neckCenter, 252);
  assert.match(left.path, /^M 0 /);
  assert.match(left.path, / C /);
  assert.ok(left.bodyTop > 0);
  assert.match(centered.path, /L 260 22 C 262\.4 22 271\.2 22 275\.6 26\.4 C 280 30\.8 280 39\.6 280 42 L 280 100/);
});

test("popover contour clamps neck placement and handles narrow surfaces", () => {
  const narrow = attachedPopoverGeometry(36, 56, 999, 48);
  assert.ok(narrow.neckCenter <= 36);
  assert.ok(narrow.neckWidth <= 36);
  assert.ok(narrow.path.endsWith(" Z"));
});

test("popover geometry rejects invalid dimensions", () => {
  assert.throws(() => attachedPopoverGeometry(100, -1, 50), /finite nonnegative/);
});

const component = readFileSync(new URL('../../quickshell/components/AttachedPopover.qml', import.meta.url), 'utf8');
const anchorBinding = component.match(/readonly property rect anchorRect: \{(.*?)^        \}/ms)[1];
const seamBinding = component.match(/readonly property real seamY: \{(.*?)^        \}/ms)[1];
function geometryFixture() {
  let position = 10;
  let reads = 0;
  const anchor = { width: 24, height: 28, parent: null, Window: { window: { x: 0, y: 0 } },
    get x() { reads++; return position; }, get y() { reads++; return position; } };
  const context = vm.createContext({
    root: { anchorItem: anchor, ownerWindow: null, decoratedBar: null, barItem: null },
    popup: { visible: false },
    pointerIntent: { coordinateItem: null, globalPoint(item, point) {
      return { x: item.x + point.x, y: item.y + point.y };
    } },
    Qt: { rect: (x, y, width, height) => ({ x, y, width, height }) },
  });
  return { context, move(value) { position = value; }, reads: () => reads,
    anchor: () => vm.runInContext('(function() {' + anchorBinding + '})()', context),
    seam: () => vm.runInContext('(function() {' + seamBinding + '})()', context) };
}
test('closed popovers do not read moving anchor geometry', () => {
  const f = geometryFixture();
  for (let i = 0; i < 30; i++) { f.move(i); f.anchor(); f.seam(); }
  assert.equal(f.reads(), 0);
});
test('opening and reopening map the latest anchor while open menus follow motion', () => {
  const f = geometryFixture();
  f.context.popup.visible = true;
  assert.equal(f.anchor().x, 10);
  assert.equal(f.seam(), 38);
  f.move(30);
  assert.equal(f.anchor().x, 30);
  assert.equal(f.seam(), 58);
  f.context.popup.visible = false;
  f.move(90);
  const reads = f.reads();
  f.anchor(); f.seam();
  assert.equal(f.reads(), reads);
  f.context.popup.visible = true;
  assert.equal(f.anchor().x, 90);
  assert.equal(f.seam(), 118);
});
