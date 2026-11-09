import { newCaptureKeys } from './microphone-use.mjs';

// A pending write's target wins over the last readback, so wheel steps never show a stale level.
function level(device) {
    return Number.isFinite(device.requestedVolume) ? device.requestedVolume : device.volume;
}

export function audioFeedback(previous, next) {
    if (!previous || previous.kind !== 'ready' || !next || next.kind !== 'ready') return null;
    for (const kind of ['input', 'output']) {
        const before = previous.value[kind];
        const device = next.value[kind];
        if (!device) continue;
        const switched = !before || before.id !== device.id;
        if (switched || level(before) !== level(device) || before.muted !== device.muted)
            return { kind, switched, value: level(device), muted: device.muted, label: device.label };
    }
    return null;
}

// The keyboard layout is a discrete indicator, so there is no level: the OSD shows the new layout's
// short code with its human name. Returns null unless an actual switch happened after the shell was up,
// so the first reading (the initial layout) and unrelated desktop-state updates never flash.
export function layoutFeedback(previous, next) {
    if (!previous || previous.kind !== 'ready' || !next || next.kind !== 'ready') return null;
    const before = previous.value, after = next.value;
    if (!after || !after.keyboardLayout) return null;
    // Without a previous layout this is the initial reading, not a change the user made.
    if (!before || !before.keyboardLayout) return null;
    if (before.keyboardLayout === after.keyboardLayout && before.keyboardLayoutIndex === after.keyboardLayoutIndex)
        return null;
    const label = String(after.keyboardLayout).toUpperCase();
    const name = after.keyboardLayoutName && String(after.keyboardLayoutName).toUpperCase() !== label
        ? String(after.keyboardLayoutName) : '';
    return { label, name };
}

// Names the applications that just started capturing the microphone. Returns null unless at least one
// new capture appeared after the shell was up: an application already capturing at startup has no
// previous state to compare with, so it never flashes, and an application that stops is silent.
export function captureFeedback(previous, next) {
    if (!previous || previous.kind !== 'ready' || !next || next.kind !== 'ready') return null;
    const before = previous.value && previous.value.microphone;
    const after = next.value && next.value.microphone;
    if (!before || !after) return null;
    const apps = after.apps || [];
    const fresh = newCaptureKeys((before.apps || []).map(a => a.key), apps.map(a => a.key));
    if (fresh.length === 0) return null;
    const added = apps.filter(a => fresh.includes(a.key));
    return { apps: added.map(a => a.label), muted: added.every(a => a.muted) };
}
