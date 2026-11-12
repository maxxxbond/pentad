import test from "node:test";
import assert from "node:assert/strict";
import {
    checkPoints, fileDropSprings, maxFrame, parseSpring, partialPolyline, springSettled, stepSpring, toggleSprings, toggleStretchKick, uploadPace,
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

test("the toggle springs keep the source values and the knob lands with one bounce", () => {
    assert.deepEqual(toggleSprings.position, [320, 18]);
    assert.deepEqual(toggleSprings.stretch, [300, 20]);
    let x = 0;
    let v = 0;
    let peak = 0;
    for (let i = 0; i < 120; i++) {
        ({ value: x, velocity: v } = stepSpring(x, v, 1, ...toggleSprings.position, 1 / 60));
        peak = Math.max(peak, x);
    }
    assert.ok(peak > 1 && peak < 1.2);
    assert.ok(springSettled(x, v, 1));
    // the stretch kick swells the knob past full length, then it comes back to rest at zero
    let w = 0;
    let wv = toggleStretchKick;
    let wPeak = 0;
    for (let i = 0; i < 240; i++) {
        ({ value: w, velocity: wv } = stepSpring(w, wv, 0, ...toggleSprings.stretch, 1 / 60));
        wPeak = Math.max(wPeak, w);
    }
    assert.ok(wPeak > 1);
    assert.ok(springSettled(w, wv, 0));
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
