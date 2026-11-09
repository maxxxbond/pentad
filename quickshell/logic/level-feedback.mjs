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

// WirePlumber moves a stream to another source (a default-mic change, a Bluetooth profile switch, an
// unplugged mic) by dropping its link and adding a new one. A key that comes back within this window was
// relinked, not started; a push-to-talk release and the next press are much further apart.
export const CAPTURE_RELINK_GRACE_MS = 300;

// Names the applications that just started capturing the microphone. Returns null unless at least one
// new capture appeared in a ready state that follows another ready one; an application that stops is
// silent. On a cold start or PipeWire restart the first ready state has no apps yet (node properties
// fill in only after binding), so an application already capturing flashes once; hot reloads do not.
// recentlyGone lists keys that left the capture set within CAPTURE_RELINK_GRACE_MS; their return is not new.
export function captureFeedback(previous, next, recentlyGone = []) {
    if (!previous || previous.kind !== 'ready' || !next || next.kind !== 'ready') return null;
    const before = previous.value && previous.value.microphone;
    const after = next.value && next.value.microphone;
    if (!before || !after) return null;
    const apps = after.apps || [];
    const fresh = newCaptureKeys((before.apps || []).map(a => a.key), apps.map(a => a.key))
        .filter(key => !(recentlyGone || []).includes(key));
    if (fresh.length === 0) return null;
    const added = apps.filter(a => fresh.includes(a.key));
    return { apps: added.map(a => a.label), muted: added.every(a => a.muted) };
}
