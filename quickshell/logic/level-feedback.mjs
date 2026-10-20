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
