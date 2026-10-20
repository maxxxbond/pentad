import { utf8Length } from './tool-catalog.mjs';

export const MAX_SHELF_ENTRIES = 50;
export const MAX_URI_LIST_BYTES = 1024 * 1024;

export function emptyShelfDocument() {
    return { schemaVersion: 1, entries: [] };
}

export function isShelfFileUri(uri) {
    return typeof uri === 'string' && uri.length > 0 && uri.length <= 8192
        && /^file:\/\/(?:localhost)?\//i.test(uri)
        && ![...uri].some(character => {
            const code = character.codePointAt(0) || 0;
            return code <= 0x1f || code === 0x7f;
        });
}

export function parseUriList(text) {
    if (typeof text !== 'string' || utf8Length(text) > MAX_URI_LIST_BYTES)
        return { ok: false, reason: 'too-large', uris: [] };
    const uris = text.split(/\r?\n/).map(line => line.trim())
        .filter(line => line.length > 0 && !line.startsWith('#'));
    if (!uris.length) return { ok: false, reason: 'empty', uris: [] };
    if (uris.length > 100) return { ok: false, reason: 'too-many', uris: [] };
    if (!uris.every(isShelfFileUri)) return { ok: false, reason: 'invalid-uri', uris: [] };
    return { ok: true, uris: Array.from(new Set(uris)) };
}

export function shelfLabel(uri) {
    const path = uri.slice(uri.indexOf('/', 'file://'.length)).split(/[?#]/, 1)[0] || '';
    const base = path.slice(path.lastIndexOf('/') + 1);
    try { return decodeURIComponent(base) || uri; }
    catch (error) { return base || uri; }
}

export function localFilePaths(uris) {
    if (!Array.isArray(uris) || !uris.length || uris.length > 100 || !uris.every(isShelfFileUri))
        return { ok: false, reason: 'invalid-uri', paths: [] };
    try {
        const paths = uris.map(uri => {
            const path = uri.slice(uri.indexOf('/', 'file://'.length));
            if (/[?#]/.test(path)) throw new Error('invalid-uri');
            const decoded = decodeURIComponent(path);
            if (/[\x00-\x1f\x7f]/.test(decoded)) throw new Error('invalid-uri');
            return decoded;
        });
        return { ok: true, paths };
    } catch (error) { return { ok: false, reason: 'invalid-uri', paths: [] }; }
}

export function parseShelfDocument(input) {
    if (input === undefined || input === null) return { ok: true, value: emptyShelfDocument() };
    let document = input;
    if (typeof document === 'string') {
        if (utf8Length(document) > MAX_URI_LIST_BYTES)
            return { ok: false, reason: 'invalid-document' };
        try { document = JSON.parse(document); }
        catch (error) { return { ok: false, reason: 'invalid-document' }; }
    }
    if (!document || typeof document !== 'object' || Array.isArray(document)
        || document.schemaVersion !== 1 || !Array.isArray(document.entries)
        || document.entries.length > MAX_SHELF_ENTRIES)
        return { ok: false, reason: 'invalid-document' };
    const ids = new Set();
    const uris = new Set();
    const entries = [];
    for (const entry of document.entries) {
        if (!entry || typeof entry !== 'object' || Array.isArray(entry)
            || typeof entry.id !== 'string' || !/^[\w.-]{1,64}$/.test(entry.id)
            || !validShelfContent(entry) || typeof entry.label !== 'string' || entry.label.length > 512
            || ids.has(entry.id) || uris.has(shelfEntryKey(entry)))
            return { ok: false, reason: 'invalid-entry' };
        ids.add(entry.id);
        uris.add(shelfEntryKey(entry));
        entries.push(entry.kind ? Object.assign({ id: entry.id, kind: entry.kind, uri: entry.uri, label: entry.label },
            entry.kind === 'text' ? { text: entry.text } : {},
            entry.kind === 'image' ? Object.assign({ imageUrl: entry.imageUrl, previewUrl: entry.previewUrl },
                entry.localUri ? { localUri: entry.localUri } : {}) : {})
            : { id: entry.id, uri: entry.uri, label: entry.label });
    }
    const value = { schemaVersion: 1, entries };
    if (utf8Length(JSON.stringify(value)) > MAX_URI_LIST_BYTES) return { ok: false, reason: 'too-large' };
    return { ok: true, value };
}

export function isShelfWebUrl(value) {
    return typeof value === 'string' && value.length <= 8192
        && /^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(value)
        && !/[\x00-\x20\x7f]/.test(value);
}

function validShelfContent(entry) {
    if (!entry.kind) return isShelfFileUri(entry.uri);
    if (entry.kind === 'text') return entry.uri === '' && typeof entry.text === 'string'
        && entry.text.trim().length > 0 && utf8Length(entry.text) <= 65536;
    if (!['link', 'spotify', 'image'].includes(entry.kind) || !isShelfWebUrl(entry.uri)) return false;
    if (entry.kind === 'spotify' && !/^https:\/\/open\.spotify\.com\/track\/[a-zA-Z0-9]{22}$/.test(entry.uri)) return false;
    return entry.kind !== 'image' || (isShelfWebUrl(entry.imageUrl) && isShelfWebUrl(entry.previewUrl)
        && (!entry.localUri || isShelfFileUri(entry.localUri)));
}

export function shelfEntryKey(entry) {
    return entry.kind === 'text' ? 'text:' + entry.text
        : entry.kind === 'image' ? entry.uri + '\n' + entry.imageUrl : entry.uri;
}

export function shelfLocalUri(entry) { return entry.kind ? entry.localUri || '' : entry.uri; }

export function addShelfItems(documentInput, items, createId) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    if (!Array.isArray(items) || !items.length || items.length > 100 || typeof createId !== 'function')
        return { ok: false, reason: 'invalid-entry' };
    const existing = new Set(parsed.value.entries.map(shelfEntryKey));
    const added = [];
    for (const item of items) {
        if (!item || !validShelfContent(item) || typeof item.label !== 'string' || item.label.length > 512)
            return { ok: false, reason: 'invalid-entry' };
        const key = shelfEntryKey(item);
        if (existing.has(key)) continue;
        existing.add(key);
        added.push(Object.assign({}, item, { id: createId() }));
    }
    if (parsed.value.entries.length + added.length > MAX_SHELF_ENTRIES) return { ok: false, reason: 'limit' };
    const checked = parseShelfDocument({ schemaVersion: 1, entries: parsed.value.entries.concat(added) });
    return checked.ok ? { ok: true, changed: !!added.length, document: checked.value, added } : checked;
}

export function setShelfDownloadedFile(documentInput, id, uri) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    if (!isShelfFileUri(uri)) return { ok: false, reason: 'invalid-uri' };
    const entry = parsed.value.entries.find(item => item.id === id && item.kind === 'image');
    if (!entry) return { ok: false, reason: 'not-found' };
    return { ok: true, changed: entry.localUri !== uri, document: { schemaVersion: 1,
        entries: parsed.value.entries.map(item => item.id === id ? Object.assign({}, item, { localUri: uri }) : item) } };
}

export function addShelfUris(documentInput, inputUris, createId) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    if (!Array.isArray(inputUris) || inputUris.length === 0 || inputUris.length > 100
        || !inputUris.every(isShelfFileUri) || typeof createId !== 'function')
        return { ok: false, reason: inputUris && inputUris.length === 0 ? 'empty' : 'invalid-uri' };
    const existing = new Set(parsed.value.entries.map(entry => entry.uri));
    const batch = new Set();
    const additions = [];
    for (const uri of inputUris) {
        if (existing.has(uri) || batch.has(uri)) continue;
        batch.add(uri);
        additions.push({ id: createId(), uri, label: shelfLabel(uri) });
    }
    if (parsed.value.entries.length + additions.length > MAX_SHELF_ENTRIES)
        return { ok: false, reason: 'limit' };
    const checked = parseShelfDocument({ schemaVersion: 1, entries: parsed.value.entries.concat(additions) });
    return checked.ok ? { ok: true, changed: additions.length > 0, document: checked.value, added: additions } : checked;
}

export function removeShelfEntry(documentInput, id) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    const entries = parsed.value.entries.filter(entry => entry.id !== id);
    if (entries.length === parsed.value.entries.length) return { ok: false, reason: 'not-found' };
    return { ok: true, changed: true, document: { schemaVersion: 1, entries } };
}
