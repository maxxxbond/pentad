import { utf8Length } from './tool-catalog.mjs';

export const MAX_DROP_BYTES = 1024 * 1024;

export function offerMime(formats, filesOnly = false) {
    const offered = Array.from(formats || []);
    if (offered.includes('text/uri-list')) return 'text/uri-list';
    if (filesOnly) return '';
    return offered.find(mime => /^text\/plain(?:\s*;\s*charset=[\w-]+)?$/i.test(mime)) || '';
}

export function readOffer(event, filesOnly = false) {
    const formats = Array.from(event.formats || []);
    while (formats.length) {
        const mime = offerMime(formats, filesOnly);
        if (!mime) break;
        const value = event.getDataAsString(mime);
        if (typeof value !== 'string' || utf8Length(value) > MAX_DROP_BYTES)
            return { ok: false, reason: 'too-large', mime, value: '' };
        if (value.trim()) return { ok: true, mime, value };
        formats.splice(formats.indexOf(mime), 1);
    }
    return { ok: false, reason: 'unsupported', mime: '', value: '' };
}

export function supportsShelfOffer(formats) {
    return !!offerMime(formats) || Array.from(formats || []).some(format =>
        ['text/html', '_NETSCAPE_URL', 'text/x-spotify-tracks'].includes(format));
}

export function readShelfOffer(event) {
    const formats = Array.from(event.formats || []);
    const offer = {};
    let bytes = 0;
    for (const [key, format] of [['uris', 'text/uri-list'], ['html', 'text/html'],
        ['netscape', '_NETSCAPE_URL'], ['text', formats.find(mime => /^text\/plain(?:\s*;\s*charset=[\w-]+)?$/i.test(mime))]]) {
        if (!format || !formats.includes(format)) continue;
        const value = event.getDataAsString(format);
        if (typeof value !== 'string') return { ok: false, reason: 'unsupported' };
        bytes += utf8Length(value);
        if (bytes > MAX_DROP_BYTES) return { ok: false, reason: 'too-large' };
        offer[key] = value;
    }
    if (formats.includes('text/x-spotify-tracks')) {
        const buffer = event.getDataAsArrayBuffer('text/x-spotify-tracks');
        bytes += buffer.byteLength * 2;
        if (bytes > MAX_DROP_BYTES) return { ok: false, reason: 'too-large' };
        offer.spotifyHex = Array.from(new Uint8Array(buffer)).map(byte => byte.toString(16).padStart(2, '0')).join('');
    }
    return { ok: true, offer };
}
