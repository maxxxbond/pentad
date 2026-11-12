import test from "node:test";
import assert from "node:assert/strict";
import {
    checkPoints, dropdownFoldSeconds, dropdownRowDelay, dropdownSprings, dropdownTiming, fileDropSprings, highlightSpan, maxFrame, menuWidthScale, parseSpring, partialPolyline, sharedSprings, springSettled, stepSpring, uploadPace,
} from "../../quickshell/logic/spring.mjs";

// The source engine, verbatim: S/step from motion.js and its four-substep loop.
function reference(k, c, from, to, frames, dt) {
    const s = { x: from, v: 0, t: to, k, c };
    const out = [];
    for (let f = 0; f < frames; f++) {
        const d = Math.min(dt, 1 / 30);
        for (let i = 0; i < 4; i++) {
            const a = -s.k * (s.x - s.t) - s.c * s.v;
            s.v += a * (d / 4);
            s.x += s.v * (d / 4);
        }
        out.push(s.x);
    }
    return out;
}

test("steps match the source spring engine frame for frame", () => {
    for (const [k, c] of Object.values(fileDropSprings)) {
        for (const dt of [1 / 60, 1 / 144, 1 / 20]) {
            const expected = reference(k, c, 0, 1, 90, dt);
            let state = { value: 0, velocity: 0 };
            expected.forEach((x, frame) => {
                state = stepSpring(state.value, state.velocity, 1, k, c, dt);
                assert.ok(Math.abs(state.value - x) < 1e-12, `${k} ${c} frame ${frame}`);
            });
        }
    }
});

test("the file drop keeps the source's stiffness and damping", () => {
    assert.deepEqual(fileDropSprings.zone, [380, 16]);
    assert.deepEqual(fileDropSprings.hover, [300, 26]);
    assert.deepEqual(fileDropSprings.circle, [420, 14]);
    assert.deepEqual(fileDropSprings.flood, [260, 21]);
    assert.deepEqual(fileDropSprings.check, [200, 26]);
    assert.deepEqual(fileDropSprings.line, [360, 30]);
});

test("a long frame is capped and bad time is ignored", () => {
    const capped = stepSpring(0, 0, 1, 400, 30, 1);
    const once = stepSpring(0, 0, 1, 400, 30, maxFrame);
    assert.deepEqual(capped, once);
    assert.deepEqual(stepSpring(0.5, 0, 1, 400, 30, NaN), { value: 0.5, velocity: 0 });
    assert.deepEqual(stepSpring(0.5, 0, 1, 400, 30, -1), { value: 0.5, velocity: 0 });
});

test("springs settle on their target", () => {
    let s = { value: 0, velocity: 0 };
    for (let i = 0; i < 300; i++) s = stepSpring(s.value, s.velocity, 1, ...fileDropSprings.circle, 1 / 60);
    assert.ok(springSettled(s.value, s.velocity, 1));
    assert.equal(springSettled(0, 0, 1), false);
});

test("parseSpring reads the token format and rejects junk", () => {
    assert.deepEqual(parseSpring("420 32"), [420, 32]);
    assert.deepEqual(parseSpring("  280   22 "), [280, 22]);
    assert.throws(() => parseSpring("fast"), TypeError);
    assert.throws(() => parseSpring("1 2 3"), TypeError);
});

test("upload pace starts quick, stalls in the middle and ends at one", () => {
    assert.equal(uploadPace(0), 0);
    assert.equal(uploadPace(1), 1);
    assert.ok(uploadPace(0.5) - uploadPace(0.4) < uploadPace(0.2) - uploadPace(0.1));
    for (let x = 0.01; x <= 1; x += 0.01) assert.ok(uploadPace(x) >= uploadPace(x - 0.01));
    assert.equal(uploadPace(2), 1);
});

test("the check draws along its two strokes", () => {
    assert.deepEqual(partialPolyline(checkPoints, 0), [[5, 12.5]]);
    assert.deepEqual(partialPolyline(checkPoints, 1), checkPoints);
    const half = partialPolyline(checkPoints, 0.5);
    assert.equal(half.length, 3);
    assert.deepEqual(half[1], [9.5, 17]);
    assert.ok(half[2][0] > 9.5 && half[2][0] < 19);
});

test("the dropdown keeps the source's stiffness, damping and timing", () => {
    assert.deepEqual(dropdownSprings.menu, [300, 23]);
    assert.deepEqual(dropdownSprings.lift, [260, 24]);
    assert.deepEqual(dropdownSprings.chevron, [300, 18]);
    assert.deepEqual(dropdownSprings.fade, [400, 34]);
    assert.deepEqual(dropdownSprings.press, [500, 18]);
    assert.deepEqual(dropdownSprings.roll, [340, 26]);
    assert.deepEqual(dropdownSprings.row, [300, 24]);
    assert.deepEqual(dropdownSprings.check, [260, 26]);
    assert.deepEqual(dropdownSprings.highlightLead, [620, 36]);
    assert.deepEqual(dropdownSprings.highlightTrail, [200, 20]);
    assert.deepEqual(dropdownSprings.highlightFade, [400, 32]);
    assert.equal(dropdownTiming.stagger, 0.045);
    assert.equal(dropdownTiming.closeAfterPick, 0.24);
});

test("dropdown springs step like the source engine", () => {
    for (const [k, c] of Object.values(dropdownSprings)) {
        const expected = reference(k, c, 0, 1, 60, 1 / 60);
        let state = { value: 0, velocity: 0 };
        expected.forEach((x, frame) => {
            state = stepSpring(state.value, state.velocity, 1, k, c, 1 / 60);
            assert.ok(Math.abs(state.value - x) < 1e-12, `${k} ${c} frame ${frame}`);
        });
    }
});

test("the menu height overshoots once, like the source", () => {
    let s = { value: 0, velocity: 0 };
    let peak = 0;
    for (let i = 0; i < 120; i++) {
        s = stepSpring(s.value, s.velocity, 160, ...dropdownSprings.menu, 1 / 60);
        peak = Math.max(peak, s.value);
    }
    assert.ok(peak > 160 && peak < 160 * 1.15, `peak ${peak}`);
});

test("rows fall in top first and leave bottom first", () => {
    assert.equal(dropdownRowDelay(0, 4, true), 0.05);
    assert.ok(Math.abs(dropdownRowDelay(3, 4, true) - (0.05 + 3 * 0.045)) < 1e-12);
    assert.equal(dropdownRowDelay(3, 4, false), 0);
    assert.ok(Math.abs(dropdownRowDelay(0, 4, false) - 0.06) < 1e-12);
});

test("the highlight stays inside the menu and keeps a minimum height", () => {
    assert.deepEqual(highlightSpan(6, 42, 6, 156), { top: 6, height: 36 });
    // stretched between two rows
    assert.deepEqual(highlightSpan(6, 78, 6, 156), { top: 6, height: 72 });
    // crossed edges never invert
    const crossed = highlightSpan(60, 50, 6, 156);
    assert.equal(crossed.height, 16);
    // overshoot past the padding is clamped
    assert.deepEqual(highlightSpan(-4, 170, 6, 156), { top: 6, height: 144 });
});

test("the menu narrows while short and caps its overshoot", () => {
    assert.equal(menuWidthScale(0, 156), 0.9);
    assert.equal(menuWidthScale(156, 156), 1);
    assert.ok(Math.abs(menuWidthScale(400, 156) - 1.006) < 1e-12);
    assert.equal(menuWidthScale(10, 0), 0.9);
});

test("shared presets keep the motion studies' token values", () => {
    assert.deepEqual(sharedSprings.soft, [260, 24]);
    assert.deepEqual(sharedSprings.settle, [280, 22]);
    assert.deepEqual(sharedSprings.follow, [900, 50]);
    assert.ok(Object.isFrozen(sharedSprings));
});

test("the fold time covers the menu collapsing and grows with its height", () => {
    assert.equal(dropdownFoldSeconds(0), 0);
    assert.equal(dropdownFoldSeconds(0.5), 0);
    const short = dropdownFoldSeconds(80);
    const tall = dropdownFoldSeconds(320);
    assert.ok(short > 0.05 && short < 0.4, `short ${short}`);
    assert.ok(tall >= short && tall < 0.5, `tall ${tall}`);
    let s = { value: 320, velocity: 0 };
    for (let t = 0; t + 1e-9 < tall - 1 / 60; t += 1 / 60) s = stepSpring(s.value, s.velocity, 0, ...dropdownSprings.menu, 1 / 60);
    assert.ok(s.value >= 1, "not folded a frame early");
    assert.equal(dropdownFoldSeconds(NaN), 0);
});

test("the fold time counts a list still moving up from its opening", () => {
    const still = dropdownFoldSeconds(200);
    const rising = dropdownFoldSeconds(200, 3000);
    assert.ok(rising > still, `${rising} > ${still}`);
});
