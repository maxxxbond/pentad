// The maths of the wheel picker: a drum of rows turned by a continuous `position` (in rows).
// Geometry, drag, wheel and flick numbers follow the Kokonut UI wheel picker (MIT licence,
// https://kokonutui.com/docs/inputs/wheel-picker), so the drum moves like the source.

export const itemHeight = 36;        // one row, px
export const itemAngle = 20;         // degrees between neighbouring rows
export const perspective = 1000;     // px, the camera distance of the source's CSS perspective
export const tapSlop = 4;            // px of travel before a press becomes a drag
export const maxOverscroll = 1.2;    // rows a column that does not loop may be pulled past its ends
export const velocityWindow = 0.08;  // s of pointer samples that make the release velocity
export const flickThreshold = 2;     // rows/s; slower releases just settle
export const coast = 0.32;           // s of release velocity carried into the flick target
export const wheelGain = 0.4;        // rows per row-height of wheel travel
export const wheelEdge = 0.4;        // rows a wheel may pull a column that does not loop past its ends
export const wheelIdle = 120;        // ms without wheel input before the column settles on a row
export const pageRows = 5;           // PageUp / PageDown

// Rows drawn on each side of the centre: the ones inside 90 degrees.
export const windowRows = Math.ceil(90 / itemAngle);
// Drum radius that makes neighbouring rows touch: each row is a flat tile standing on the drum,
// so two tiles itemAngle apart meet when 2 * R * tan(itemAngle / 2) = itemHeight.
export const drumRadius = itemHeight / 2 / Math.tan((itemAngle / 2) * Math.PI / 180);
export const drumHeight = Math.round(drumRadius * 2) + itemHeight / 2;

// A duration-and-bounce spring (the source's settle) as [stiffness, damping] for mass 1.
export function durationSpring(duration, bounce) {
    const stiffness = Math.pow((2 * Math.PI) / duration, 2);
    return [stiffness, 2 * (1 - bounce) * Math.sqrt(stiffness)];
}

export const settleSpring = Object.freeze(durationSpring(0.4, 0.15));
export const flickSpring = Object.freeze([140, 24]);

export function wrapIndex(index, count) {
    if (!(count > 0)) return 0;
    return ((Math.round(index) % count) + count) % count;
}

// Where a row `offset` rows from the drum's centre sits: its y from the centre, the scale that
// turning away and the camera distance give it, and whether it faces us at all.
export function rowGeometry(offset) {
    const angle = offset * itemAngle * Math.PI / 180;
    const facing = Math.cos(angle);
    const depth = drumRadius * (1 - facing);
    const zoom = perspective / (perspective + depth);
    return {
        y: drumRadius * Math.sin(angle) * zoom,
        scaleX: zoom,
        scaleY: facing * zoom,
        visible: Math.abs(offset * itemAngle) < 90,
    };
}

// The source's edge mask: clear at the ends, solid from 34% to 66% of the drum's height.
export function edgeFade(fraction) {
    const f = Math.max(0, Math.min(1, fraction));
    if (f < 0.34) return f / 0.34;
    if (f > 0.66) return (1 - f) / 0.34;
    return 1;
}

export function positionBounds(count, loop, edge = 0) {
    return loop ? { min: -Infinity, max: Infinity } : { min: 0 - edge, max: Math.max(0, count - 1) + edge };
}

export function clampPosition(position, count, loop, edge = 0) {
    const { min, max } = positionBounds(count, loop, edge);
    return Math.max(min, Math.min(max, position));
}

// Rubber band past the ends of a column that does not loop: the pull eases towards `max`.
export function overscroll(distance, max = maxOverscroll) {
    return max * (1 - Math.exp(-Math.max(0, distance) / max));
}

// The position a drag shows: `start` moved by the pointer's travel, rubber-banded past the ends.
export function dragPosition(start, travel, count, loop) {
    const raw = start - travel / itemHeight;
    if (loop) return raw;
    const last = Math.max(0, count - 1);
    if (raw < 0) return -overscroll(-raw);
    if (raw > last) return last + overscroll(raw - last);
    return raw;
}

// Release velocity in rows/s from [{t (s), y (px)}] pointer samples. A pointer that rested for
// the whole window has no velocity.
export function releaseVelocity(samples, now) {
    const recent = samples.filter(sample => now - sample.t <= velocityWindow);
    if (recent.length < 2) return 0;
    const first = recent[0];
    const last = recent[recent.length - 1];
    const dt = last.t - first.t;
    if (dt <= 0 || now - last.t > velocityWindow) return 0;
    return -((last.y - first.y) / dt) / itemHeight;
}

// Where a release lands: the nearest row, or, for a fast flick, the row the coast would reach.
export function releaseTarget(position, velocity, count, loop) {
    const flick = Math.abs(velocity) >= flickThreshold;
    const target = Math.round(flick ? position + velocity * coast : position);
    return Math.round(clampPosition(target, count, loop)) + 0;
}

export function wheelStep(angleDeltaY) {
    // Browsers report about 100 per notch where Qt reports 120; scroll down is positive there.
    return (-angleDeltaY * 100 / 120 / itemHeight) * wheelGain;
}

// The row under a press `offsetY` px from the drum's centre; null off the drum.
export function rowAtOffset(offsetY) {
    const ratio = offsetY / drumRadius;
    if (Math.abs(ratio) >= 1) return null;
    return Math.round(Math.asin(ratio) * 180 / Math.PI / itemAngle) + 0;
}

// A keyboard move from `position`: arrows and pages are relative, Home/End go to the first and
// last option of the cycle the position is in (the only cycle for a column that does not loop).
export function keyTarget(key, position, count, loop) {
    const now = Math.round(position);
    let target;
    switch (key) {
    case "up": target = now - 1; break;
    case "down": target = now + 1; break;
    case "pageUp": target = now - pageRows; break;
    case "pageDown": target = now + pageRows; break;
    case "home": target = loop ? Math.floor(now / count) * count : 0; break;
    case "end": target = loop ? Math.floor(now / count) * count + count - 1 : count - 1; break;
    default: return null;
    }
    return Math.round(clampPosition(target, count, loop)) + 0;
}

// The nearest copy of `index` to `position` on a looping column, so a change from outside turns
// the short way round.
export function nearestCycle(index, position, count, loop) {
    if (!loop || !(count > 0)) return index;
    const base = wrapIndex(index, count);
    const cycle = Math.round((position - base) / count);
    return base + cycle * count;
}
