import test from "node:test";
import assert from "node:assert/strict";
import {
    clampPosition, dragPosition, drumHeight, drumRadius, durationSpring, edgeFade, flickSpring, itemHeight, keyTarget,
    nearestCycle, overscroll, releaseTarget, releaseVelocity, rowAtOffset, rowGeometry, settleSpring, windowRows,
    wheelStep, wrapIndex,
} from "../../quickshell/logic/wheel-picker.mjs";

const close = (a, b, eps = 0.01) => assert.ok(Math.abs(a - b) < eps, `${a} is not near ${b}`);

test("the drum matches the source geometry", () => {
    close(drumRadius, 102.08, 0.01);
    assert.equal(drumHeight, 222);
    assert.equal(windowRows, 5);
});

test("neighbouring rows touch: flat tiles on the drum are one row apart", () => {
    close(2 * drumRadius * Math.tan(10 * Math.PI / 180), itemHeight, 1e-9);
});

test("rows turn away and vanish past 90 degrees", () => {
    const centre = rowGeometry(0);
    assert.equal(centre.y, 0);
    assert.equal(centre.scaleY, 1);
    assert.ok(rowGeometry(2).scaleY < rowGeometry(1).scaleY);
    assert.ok(rowGeometry(-2).y < 0);
    assert.equal(rowGeometry(4.4).visible, true);
    assert.equal(rowGeometry(4.5).visible, false);
});

test("the edge fade is clear at the ends and solid in the middle", () => {
    assert.equal(edgeFade(0), 0);
    assert.equal(edgeFade(1), 0);
    assert.equal(edgeFade(0.5), 1);
    assert.equal(edgeFade(0.34), 1);
    close(edgeFade(0.17), 0.5);
});

test("the settle spring is the source's 0.4 s duration with 0.15 bounce", () => {
    close(settleSpring[0], 246.74, 0.01);
    close(settleSpring[1], 26.7, 0.05);
    assert.deepEqual([...flickSpring], [140, 24]);
    const [k, c] = durationSpring(1, 0);
    close(k, 39.478, 0.001);
    close(c, 2 * Math.sqrt(k), 1e-9);
});

test("indexes wrap both ways", () => {
    assert.equal(wrapIndex(-1, 12), 11);
    assert.equal(wrapIndex(12, 12), 0);
    assert.equal(wrapIndex(25.4, 12), 1);
    assert.equal(wrapIndex(3, 0), 0);
});

test("a column that does not loop stops at its ends, a loop never does", () => {
    assert.equal(clampPosition(5, 3, false), 2);
    assert.equal(clampPosition(-1, 3, false), 0);
    assert.equal(clampPosition(-30, 3, true), -30);
    close(clampPosition(5, 3, false, 0.4), 2.4);
});

test("overscroll eases towards 1.2 rows and never reaches it", () => {
    assert.equal(overscroll(0), 0);
    assert.ok(overscroll(0.5) < 0.5);
    assert.ok(overscroll(100) <= 1.2);
    close(overscroll(100), 1.2, 1e-6);
});

test("dragging down moves the position up the list, with a rubber band at the ends", () => {
    close(dragPosition(5, 36, 12, true), 4);
    close(dragPosition(5, -72, 12, true), 7);
    assert.equal(dragPosition(0, 0, 3, false), 0);
    assert.ok(dragPosition(0, 72, 3, false) < 0);
    assert.ok(dragPosition(0, 72, 3, false) > -1.2);
    assert.ok(dragPosition(2, -720, 3, false) > 2);
    assert.ok(dragPosition(2, -720, 3, false) <= 3.2);
});

test("release velocity reads the last 80 ms and a resting pointer has none", () => {
    const now = 1;
    const moving = [{ t: 0.93, y: 100 }, { t: 0.97, y: 64 }, { t: 1, y: 28 }];
    // 72 px up in 70 ms moves the position forward: 72 / 0.07 / 36 rows/s.
    close(releaseVelocity(moving, now), 28.57, 0.01);
    assert.equal(releaseVelocity([{ t: 0.5, y: 0 }, { t: 0.6, y: 90 }], now), 0);
    assert.equal(releaseVelocity([{ t: 0.99, y: 0 }], now), 0);
    assert.equal(releaseVelocity([{ t: 0.9, y: 0 }, { t: 0.92, y: 40 }], now), 0);
});

test("a slow release settles on the nearest row, a fast one coasts", () => {
    assert.equal(releaseTarget(4.4, 0.5, 12, true), 4);
    assert.equal(releaseTarget(4.6, -1.9, 12, true), 5);
    assert.equal(releaseTarget(4, 10, 12, true), 7);
    assert.equal(releaseTarget(4, -10, 12, true), 1);
    assert.equal(releaseTarget(1, 10, 3, false), 2);
    assert.equal(releaseTarget(-0.8, 0, 3, false), 0);
});

test("wheel travel is a fraction of a row, down moves forward", () => {
    close(wheelStep(-120), (100 / 36) * 0.4);
    assert.ok(wheelStep(120) < 0);
});

test("a press finds its row from the drum's curve", () => {
    assert.equal(rowAtOffset(0), 0);
    assert.equal(rowAtOffset(drumRadius * Math.sin(20 * Math.PI / 180)), 1);
    assert.equal(rowAtOffset(-drumRadius * Math.sin(40 * Math.PI / 180)), -2);
    assert.equal(rowAtOffset(drumRadius), null);
});

test("keys step by one or five rows and Home/End stay inside the cycle", () => {
    assert.equal(keyTarget("down", 3, 12, true), 4);
    assert.equal(keyTarget("up", 0, 12, true), -1);
    assert.equal(keyTarget("pageDown", 3, 12, true), 8);
    assert.equal(keyTarget("home", 15, 12, true), 12);
    assert.equal(keyTarget("end", 15, 12, true), 23);
    assert.equal(keyTarget("home", -3, 12, true), -12);
    assert.equal(keyTarget("end", 1, 3, false), 2);
    assert.equal(keyTarget("down", 2, 3, false), 2);
    assert.equal(keyTarget("x", 2, 3, false), null);
});

test("an outside change turns the short way round a loop", () => {
    assert.equal(nearestCycle(11, 12, 12, true), 11);
    assert.equal(nearestCycle(1, 11, 12, true), 13);
    assert.equal(nearestCycle(1, 2, 3, false), 1);
});
