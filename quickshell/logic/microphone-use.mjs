// Pentad's own processes never count: its cava visualizer and tests would light the indicator forever.
const EXCLUDED_BINARIES = ['qs', 'quickshell'];
const HARDWARE_SOURCE_CLASSES = ['Audio/Source', 'Audio/Duplex'];
// ALSA clients that report no binary (Handy) name themselves "PipeWire ALSA [app]".
const ALSA_NAME = /^PipeWire ALSA \[(.+)\]$/;

function text(value) {
    return typeof value === 'string' ? value : '';
}

// Lower-cased application identity for a capture stream, or '' when nothing identifies it.
export function captureAppKey(props) {
    const p = props || {};
    const binary = text(p['application.process.binary']);
    if (binary) return binary.toLowerCase();
    const name = text(p['application.name']);
    const alsa = ALSA_NAME.exec(name);
    if (alsa) return alsa[1].toLowerCase();
    if (name) return name.toLowerCase();
    return text(p['node.name']).toLowerCase();
}

// Applications reading from a hardware microphone. A stream that is not linked yet is dropped, so a
// capture never flashes the indicator before it actually reads; monitors and stream-to-stream links
// are not microphones. An app is muted only when every mic it reads from is muted.
export function microphoneUsers(streams, links) {
    const byKey = new Map();
    for (const stream of streams || []) {
        const props = stream.props || {};
        if (props['media.class'] !== 'Stream/Input/Audio') continue;
        if (EXCLUDED_BINARIES.includes(text(props['application.process.binary']).toLowerCase())) continue;
        const key = captureAppKey(props);
        if (!key) continue;
        const mics = (links || []).filter(link => link.targetId === stream.id
            && link.sourceIsStream === false && HARDWARE_SOURCE_CLASSES.includes(link.sourceClass));
        if (mics.length === 0) continue;
        const muted = mics.every(link => link.sourceMuted === true);
        const known = byKey.get(key);
        byKey.set(key, { key, muted: known ? known.muted && muted : muted });
    }
    return [...byKey.values()].sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
}

export function newCaptureKeys(previousKeys, nextKeys) {
    const before = previousKeys || [];
    return (nextKeys || []).filter(key => !before.includes(key));
}
