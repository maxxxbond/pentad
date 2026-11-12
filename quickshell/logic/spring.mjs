// Damped springs described as "stiffness damping", stepped with the same semi-implicit Euler
// integration (four substeps, frame time capped at 1/30 s) as the motion studies the file drop
// was drawn from, so a spring with the same two numbers moves the same way here.

export const maxFrame = 1 / 30;
export const substeps = 4;

// The file drop's springs, as [stiffness, damping], copied from its source.
export const fileDropSprings = Object.freeze({
    zone: [380, 16],      // the zone squashing on a press or a drop
    hover: [300, 26],     // the zone lifting while something is dragged over it
    circle: [420, 14],    // the circle gulping the drop and settling when done
    arrow: [420, 30],     // the arrow leaving when work starts
    percent: [420, 30],   // the percentage appearing
    ring: [300, 30],      // the progress ring appearing
    flood: [260, 21],     // the success colour filling the circle
    check: [200, 26],     // the check drawing itself
    line: [360, 30],      // a text line rolling to its new text
});

// The toggle switch's springs, as [stiffness, damping], copied from its source. The knob's
// position lands with a small bounce; the stretch spring is kicked with `toggleStretchKick`
// (a velocity) on every flip so the knob grows long towards where it is going.
export const toggleSprings = Object.freeze({
    position: [320, 18],
    stretch: [300, 20],
});
export const toggleStretchKick = 60;

export function parseSpring(text) {
    const parts = String(text).trim().split(/\s+/).map(Number);
    if (parts.length !== 2 || !parts.every(n => Number.isFinite(n) && n >= 0))
        throw new TypeError("A spring is two non-negative numbers: stiffness damping");
    return parts;
}

// Advances {value, velocity} towards target over dt seconds and returns the new pair.
export function stepSpring(value, velocity, target, stiffness, damping, dt) {
    const frame = Math.min(Math.max(0, Number(dt) || 0), maxFrame);
    const h = frame / substeps;
    let x = value;
    let v = velocity;
    for (let i = 0; i < substeps; i++) {
        const a = -stiffness * (x - target) - damping * v;
        v += a * h;
        x += v * h;
    }
    return { value: x, velocity: v };
}

export function springSettled(value, velocity, target, epsilon = 0.0005) {
    return Math.abs(value - target) < epsilon && Math.abs(velocity) < epsilon * 10;
}

// Shown progress for real progress: the ring follows it as-is. For a demo or a step with no
// measurable progress, uploadPace maps elapsed/duration to a quick start, a stall around the
// middle and a run home, like the source.
export function uploadPace(x) {
    const t = Math.max(0, Math.min(1, Number(x) || 0));
    const p = t < 0.35 ? t * 1.4 : t < 0.6 ? 0.49 + (t - 0.35) * 0.4 : 0.59 + (t - 0.6) * 1.025;
    return Math.max(0, Math.min(1, p));
}

// The drawn part of the check mark (a polyline on a 24 grid) for a draw fraction 0..1.
export const checkPoints = Object.freeze([[5, 12.5], [9.5, 17], [19, 7.5]]);

export function partialPolyline(points, fraction) {
    const f = Math.max(0, Math.min(1, Number(fraction) || 0));
    if (f >= 1) return points.slice();
    const lengths = [];
    let total = 0;
    for (let i = 1; i < points.length; i++) {
        const l = Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
        lengths.push(l);
        total += l;
    }
    let left = total * f;
    const out = [points[0]];
    for (let i = 1; i < points.length; i++) {
        const l = lengths[i - 1];
        if (left >= l) {
            out.push(points[i]);
            left -= l;
            continue;
        }
        if (left > 0) {
            const k = left / l;
            out.push([points[i - 1][0] + (points[i][0] - points[i - 1][0]) * k,
                points[i - 1][1] + (points[i][1] - points[i - 1][1]) * k]);
        }
        break;
    }
    return out;
}
