import { utf8Length } from './tool-catalog.mjs';

export const SHELF_SCHEMA_VERSION = 2;
export const MAX_UNPINNED_ENTRIES = 300;
export const MAX_PINNED_ENTRIES = 50;
export const MAX_URI_LIST_BYTES = 1024 * 1024;
const MAX_LABEL_LENGTH = 512;
const MAX_TEXT_BYTES = 65536;
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

export function emptyShelfDocument() {
    return { schemaVersion: SHELF_SCHEMA_VERSION, entries: [] };
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
    if (input === undefined || input === null) return { ok: true, value: emptyShelfDocument(), migrated: false };
    let document = input;
    if (typeof document === 'string') {
        if (utf8Length(document) > MAX_URI_LIST_BYTES)
            return { ok: false, reason: 'invalid-document' };
        try { document = JSON.parse(document); }
        catch (error) { return { ok: false, reason: 'invalid-document' }; }
    }
    if (!document || typeof document !== 'object' || Array.isArray(document)
        || ![1, SHELF_SCHEMA_VERSION].includes(document.schemaVersion) || !Array.isArray(document.entries)
        || document.entries.length > MAX_UNPINNED_ENTRIES + MAX_PINNED_ENTRIES)
        return { ok: false, reason: 'invalid-document' };
    const migrated = document.schemaVersion !== SHELF_SCHEMA_VERSION;
    const ids = new Set();
    const uris = new Set();
    const entries = [];
    for (const entry of document.entries) {
        if (!entry || typeof entry !== 'object' || Array.isArray(entry)
            || typeof entry.id !== 'string' || !/^[\w.-]{1,64}$/.test(entry.id)
            || !validShelfContent(entry) || !validShelfLabel(entry.label)
            || (!migrated && !validShelfMeta(entry))
            || ids.has(entry.id) || uris.has(shelfEntryKey(entry)))
            return { ok: false, reason: 'invalid-entry' };
        ids.add(entry.id);
        uris.add(shelfEntryKey(entry));
        entries.push(copyShelfEntry(entry, migrated ? { addedAt: '', pinned: false } : entry));
    }
    const value = { schemaVersion: SHELF_SCHEMA_VERSION, entries };
    if (utf8Length(JSON.stringify(value)) > MAX_URI_LIST_BYTES) return { ok: false, reason: 'too-large' };
    return { ok: true, value, migrated };
}

export function isShelfWebUrl(value) {
    return typeof value === 'string' && value.length <= 8192
        && /^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(value)
        && !/[\x00-\x20\x7f]/.test(value);
}

function validShelfContent(entry) {
    if (!entry.kind) return isShelfFileUri(entry.uri);
    if (entry.kind === 'text') return entry.uri === '' && typeof entry.text === 'string'
        && entry.text.trim().length > 0 && utf8Length(entry.text) <= MAX_TEXT_BYTES;
    if (!['link', 'spotify', 'image'].includes(entry.kind) || !isShelfWebUrl(entry.uri)) return false;
    if (entry.kind === 'spotify' && !/^https:\/\/open\.spotify\.com\/track\/[a-zA-Z0-9]{22}$/.test(entry.uri)) return false;
    return entry.kind !== 'image' || (isShelfWebUrl(entry.imageUrl) && isShelfWebUrl(entry.previewUrl)
        && (!entry.localUri || isShelfFileUri(entry.localUri)));
}

function validShelfLabel(label) {
    return typeof label === 'string' && label.length <= MAX_LABEL_LENGTH;
}

function validAddedAt(value) {
    return value === '' || (typeof value === 'string' && ISO_TIME.test(value));
}

// v2 metadata: `owned` marks a file Pentad saved itself, so it is only allowed on file entries.
function validShelfMeta(entry) {
    return validAddedAt(entry.addedAt) && typeof entry.pinned === 'boolean'
        && (entry.owned === undefined || (entry.owned === true && !entry.kind));
}

function copyShelfEntry(entry, meta) {
    const copy = entry.kind ? { id: entry.id, kind: entry.kind, uri: entry.uri, label: entry.label }
        : { id: entry.id, uri: entry.uri, label: entry.label };
    copy.addedAt = meta.addedAt;
    copy.pinned = meta.pinned;
    if (!entry.kind && meta.owned === true) copy.owned = true;
    if (entry.kind === 'text') copy.text = entry.text;
    if (entry.kind === 'image') {
        copy.imageUrl = entry.imageUrl;
        copy.previewUrl = entry.previewUrl;
        if (entry.localUri) copy.localUri = entry.localUri;
    }
    return copy;
}

export function shelfEntryKey(entry) {
    return entry.kind === 'text' ? 'text:' + entry.text
        : entry.kind === 'image' ? entry.uri + '\n' + entry.imageUrl : entry.uri;
}

export function shelfLocalUri(entry) { return entry.kind ? entry.localUri || '' : entry.uri; }

function unpinnedCount(entries) { return entries.filter(entry => !entry.pinned).length; }

function cutLabel(value, max) {
    const cut = value.slice(0, max);
    return /[\ud800-\udbff]$/.test(cut) ? cut.slice(0, -1) : cut;
}

export function composerItem(input) {
    // Drop leading blank lines and trailing whitespace, but keep the first line's own indent.
    const text = typeof input === 'string' ? input.replace(/^(?:[ \t]*\r?\n)+|\s+$/g, '') : '';
    if (!text.trim()) return { ok: false, reason: 'empty' };
    if (utf8Length(text) > MAX_TEXT_BYTES) return { ok: false, reason: 'too-large' };
    const trimmed = text.trim();
    if (isShelfWebUrl(trimmed)) return { ok: true, item: { kind: 'link', uri: trimmed, label: cutLabel(trimmed, MAX_LABEL_LENGTH) } };
    const line = text.split(/\r?\n/).map(part => part.trim()).find(part => part.length > 0);
    return { ok: true, item: { kind: 'text', uri: '', text, label: cutLabel(line, 80) } };
}

export function addShelfItems(documentInput, items, createId, now = new Date().toISOString()) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    if (!Array.isArray(items) || !items.length || items.length > 100 || typeof createId !== 'function')
        return { ok: false, reason: 'invalid-entry' };
    const existing = new Set(parsed.value.entries.map(shelfEntryKey));
    const added = [];
    for (const item of items) {
        if (!item || !validShelfContent(item) || !validShelfLabel(item.label))
            return { ok: false, reason: 'invalid-entry' };
        const key = shelfEntryKey(item);
        if (existing.has(key)) continue;
        existing.add(key);
        added.push(Object.assign({}, item, { id: createId(), addedAt: now, pinned: false }));
    }
    if (unpinnedCount(parsed.value.entries) + added.length > MAX_UNPINNED_ENTRIES) return { ok: false, reason: 'limit' };
    const checked = parseShelfDocument({ schemaVersion: SHELF_SCHEMA_VERSION, entries: parsed.value.entries.concat(added) });
    return checked.ok ? { ok: true, changed: !!added.length, document: checked.value, added } : checked;
}

export function setShelfDownloadedFile(documentInput, id, uri) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    if (!isShelfFileUri(uri)) return { ok: false, reason: 'invalid-uri' };
    const entry = parsed.value.entries.find(item => item.id === id && item.kind === 'image');
    if (!entry) return { ok: false, reason: 'not-found' };
    return { ok: true, changed: entry.localUri !== uri, document: { schemaVersion: SHELF_SCHEMA_VERSION,
        entries: parsed.value.entries.map(item => item.id === id ? Object.assign({}, item, { localUri: uri }) : item) } };
}

export function setShelfPinned(documentInput, id, pinned) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    const target = pinned === true;
    const entry = parsed.value.entries.find(item => item.id === id);
    if (!entry) return { ok: false, reason: 'not-found' };
    if (entry.pinned === target) return { ok: true, changed: false, document: parsed.value };
    if (target && parsed.value.entries.length - unpinnedCount(parsed.value.entries) >= MAX_PINNED_ENTRIES)
        return { ok: false, reason: 'pin-limit' };
    return { ok: true, changed: true, document: { schemaVersion: SHELF_SCHEMA_VERSION,
        entries: parsed.value.entries.map(item => item.id === id ? Object.assign({}, item, { pinned: target }) : item) } };
}

export function addShelfUris(documentInput, inputUris, createId, now = new Date().toISOString()) {
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
        additions.push({ id: createId(), uri, label: shelfLabel(uri), addedAt: now, pinned: false });
    }
    if (unpinnedCount(parsed.value.entries) + additions.length > MAX_UNPINNED_ENTRIES)
        return { ok: false, reason: 'limit' };
    const checked = parseShelfDocument({ schemaVersion: SHELF_SCHEMA_VERSION, entries: parsed.value.entries.concat(additions) });
    return checked.ok ? { ok: true, changed: additions.length > 0, document: checked.value, added: additions } : checked;
}

export function removeShelfEntry(documentInput, id) {
    const parsed = parseShelfDocument(documentInput);
    if (!parsed.ok) return parsed;
    const removed = parsed.value.entries.find(entry => entry.id === id);
    if (!removed) return { ok: false, reason: 'not-found' };
    return { ok: true, changed: true, removed,
        document: { schemaVersion: SHELF_SCHEMA_VERSION, entries: parsed.value.entries.filter(entry => entry !== removed) } };
}
