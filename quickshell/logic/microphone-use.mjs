// Pentad's own processes never count: its cava visualizer and tests would light the indicator forever.
const EXCLUDED_BINARIES = ['qs', 'quickshell'];
// Virtual sources (echo cancel, noise suppression, EasyEffects) are microphones to the apps behind them.
const SOURCE_CLASSES = ['Audio/Source', 'Audio/Duplex', 'Audio/Source/Virtual'];
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

function clientId(value) {
    return value === undefined || value === null ? '' : String(value);
}

// Applications reading from a microphone, hardware or virtual. A stream that is not linked yet is
// dropped, so a capture never flashes the indicator before it actually reads; monitors and
// stream-to-stream links are not microphones. `sourceClients` lists the client.id of every source
// node: a filter creates its virtual source and its capture stream from one client, so a stream
// sharing a client with a source is the filter itself and would otherwise light the indicator
// forever. Hardware sources belong to the session manager, which owns no capture streams, so this
// never hides a real app. An app is muted only when every mic it reads from is muted.
export function microphoneUsers(streams, links, sourceClients = []) {
    const providers = new Set((sourceClients || []).map(clientId).filter(Boolean));
    const byKey = new Map();
    for (const stream of streams || []) {
        const props = stream.props || {};
        if (props['media.class'] !== 'Stream/Input/Audio') continue;
        if (EXCLUDED_BINARIES.includes(text(props['application.process.binary']).toLowerCase())) continue;
        const client = clientId(props['client.id']);
        if (client && providers.has(client)) continue;
        const key = captureAppKey(props);
        if (!key) continue;
        const mics = (links || []).filter(link => link.targetId === stream.id
            && link.sourceIsStream === false && SOURCE_CLASSES.includes(link.sourceClass));
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
