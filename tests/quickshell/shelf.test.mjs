import test from 'node:test';
import assert from 'node:assert/strict';
import {
    MAX_PINNED_ENTRIES, MAX_UNPINNED_ENTRIES, MAX_URI_LIST_BYTES, SHELF_SCHEMA_VERSION,
    addShelfItems, composerItem, setShelfDownloadedFile, setShelfPinned, shelfDragUri, shelfLocalUri,
    shelfImagesToCache, shelfOwnedFile,
} from '../../quickshell/logic/shelf.mjs';
import {
    addShelfUris, emptyShelfDocument, isShelfFileUri, parseShelfDocument,
    parseUriList, removeShelfEntry, shelfLabel,
} from '../../quickshell/logic/shelf.mjs';

const NOW = '2026-10-23T12:00:00.000Z';
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

function fileUris(count, prefix = 'f') {
    return Array.from({ length: count }, (_, index) => `file:///tmp/${prefix}${index}`);
}

function shelfWith(count, id) {
    let doc = emptyShelfDocument();
    for (let start = 0; start < count; start += 100)
        doc = addShelfUris(doc, fileUris(count).slice(start, start + 100), id, NOW).document;
    return doc;
}

test('URI-list accepts local file URIs with encoded Unicode and spaces', () => {
    const result = parseUriList('# files\r\nfile:///tmp/Caf%C3%A9%20notes.txt\r\nfile://localhost/tmp/%E2%98%95.pdf\r\n');
    assert.equal(result.ok, true);
    assert.deepEqual(result.uris, ['file:///tmp/Caf%C3%A9%20notes.txt', 'file://localhost/tmp/%E2%98%95.pdf']);
    assert.equal(shelfLabel(result.uris[0]), 'Café notes.txt');
    assert.equal(isShelfFileUri('file://remote-host/tmp/a.txt'), false);
});

test('URI-list rejects invalid offers and empty drops leave shelf untouched', () => {
    assert.equal(parseUriList('# cancelled drop\r\n').reason, 'empty');
    assert.equal(parseUriList('https://example.test/a').reason, 'invalid-uri');
    assert.equal(parseUriList('file:///tmp/a\nhttps://example.test/b').reason, 'invalid-uri');
    const result = addShelfUris(undefined, [], () => 'unused', NOW);
    assert.equal(result.ok, false);
    assert.equal(SHELF_SCHEMA_VERSION, 2);
    assert.deepEqual(emptyShelfDocument(), { schemaVersion: 2, entries: [] });
});

test('adds deduplicate within a drop and against stored references without copying files', () => {
    const first = 'file:///tmp/report%20final.pdf';
    const second = 'file:///tmp/notes.txt';
    let serial = 0;
    const add = addShelfUris(undefined, [first, first, second], () => `shelf-${++serial}`, NOW);
    assert.equal(add.ok, true);
    assert.deepEqual(add.added.map(entry => entry.uri), [first, second]);
    assert.deepEqual(add.document.entries.map(entry => entry.label), ['report final.pdf', 'notes.txt']);
    const duplicate = addShelfUris(add.document, [first], () => `shelf-${++serial}`, NOW);
    assert.equal(duplicate.ok, true);
    assert.equal(duplicate.changed, false);
    assert.equal(duplicate.document.entries.length, 2);
    assert.equal(serial, 2);
});

test('shelf documents reject duplicate IDs or URIs and remove by ID', () => {
    const entry = { id: 'one', uri: 'file:///tmp/a', label: 'a' };
    assert.equal(parseShelfDocument({ schemaVersion: 1, entries: [entry, { ...entry, id: 'two' }] }).reason, 'invalid-entry');
    assert.equal(parseShelfDocument('{broken').reason, 'invalid-document');
    assert.deepEqual(removeShelfEntry({ schemaVersion: 1, entries: [entry] }, 'one').document.entries, []);
    assert.equal(removeShelfEntry({ schemaVersion: 1, entries: [entry] }, 'absent').reason, 'not-found');
});

test('mixed shelf persists old files, text and image metadata with stable deduplication', () => {
    let serial = 0;
    const legacy = { schemaVersion: 1, entries: [{ id: 'old', uri: 'file:///tmp/a', label: 'a' }] };
    const image = { kind: 'image', uri: 'https://example.test/pin', label: 'Photo',
        imageUrl: 'https://example.test/original.png', previewUrl: 'https://example.test/small.png' };
    const text = { kind: 'text', uri: '', label: 'Note', text: '<b>Keep as text</b>' };
    const added = addShelfItems(legacy, [image, text, image], () => 'new-' + ++serial, NOW);
    assert.equal(added.ok, true);
    assert.equal(added.document.entries.length, 3);
    assert.deepEqual(added.document.entries[0], { ...legacy.entries[0], addedAt: '', pinned: false });
    assert.deepEqual(added.document.entries[2], { id: 'new-2', ...text, addedAt: NOW, pinned: false });
    assert.deepEqual(parseShelfDocument(JSON.stringify(added.document)).value, added.document);
    assert.equal(addShelfItems(added.document, [text], () => 'unused', NOW).changed, false);
    const saved = setShelfDownloadedFile(added.document, 'new-1', 'file:///tmp/photo.png');
    assert.equal(saved.ok, true);
    assert.equal(saved.document.schemaVersion, 2);
    assert.equal(shelfLocalUri(saved.document.entries[1]), 'file:///tmp/photo.png');
    assert.equal(saved.document.entries[1].uri, image.uri);
    assert.equal(setShelfDownloadedFile(added.document, 'old', 'file:///tmp/photo.png').ok, false);
    assert.deepEqual(shelfImagesToCache(added.document.entries), ['new-1']);
    assert.deepEqual(shelfImagesToCache(saved.document.entries), []);
    // A copy the Stash saved itself is owned, survives a reload and is the file a removal deletes.
    const cached = setShelfDownloadedFile(added.document, 'new-1', 'file:///s/pentad/stash/photo.png', true);
    assert.equal(cached.ok, true);
    assert.equal(cached.document.entries[1].owned, true);
    assert.deepEqual(parseShelfDocument(JSON.stringify(cached.document)).value, cached.document);
    assert.equal(shelfOwnedFile(cached.document.entries[1]), 'file:///s/pentad/stash/photo.png');
    assert.equal(shelfOwnedFile(saved.document.entries[1]), '');
    assert.equal(shelfOwnedFile({ id: 'o', uri: 'file:///s/clip.png', label: 'clip.png', owned: true }), 'file:///s/clip.png');
    assert.equal(setShelfDownloadedFile(cached.document, 'new-1', 'file:///tmp/photo.png').document.entries[1].owned, undefined);
    // `owned` on an image needs the local copy it describes.
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: [{ id: 'i', ...image, addedAt: NOW, pinned: false, owned: true }] }).ok, false);
    assert.equal(addShelfItems(legacy, [{ ...image, imageUrl: 'javascript:alert(1)' }], () => 'bad', NOW).ok, false);
});

test('drag-out exports the local file, else the web image or the page, never a note', () => {
    const file = { id: 'f', uri: 'file:///tmp/report.pdf', label: 'report.pdf' };
    const image = { id: 'i', kind: 'image', uri: 'https://example.test/pin', label: 'Photo',
        imageUrl: 'https://example.test/original.png', previewUrl: 'https://example.test/small.png' };
    const saved = { ...image, localUri: 'file:///tmp/photo.png' };
    assert.equal(shelfDragUri(file), 'file:///tmp/report.pdf');
    assert.equal(shelfDragUri(file, { available: false }), '');
    assert.equal(shelfDragUri(image), 'https://example.test/original.png');
    assert.equal(shelfDragUri(saved, { available: true }), 'file:///tmp/photo.png');
    // A downloaded copy that went missing falls back to the image on the web.
    assert.equal(shelfDragUri(saved, { available: false }), 'https://example.test/original.png');
    assert.equal(shelfDragUri({ id: 'l', kind: 'link', uri: 'https://example.test/', label: 'Site' }), 'https://example.test/');
    assert.equal(shelfDragUri({ id: 's', kind: 'spotify', uri: 'https://open.spotify.com/track/' + 'a'.repeat(22), label: 'Song' }),
        'https://open.spotify.com/track/' + 'a'.repeat(22));
    assert.equal(shelfDragUri({ id: 't', kind: 'text', uri: '', label: 'Note', text: 'hi' }), '');
});

test('combined text entries cannot create an oversized unreadable shelf document', () => {
    const items = Array.from({ length: 17 }, (_, index) => ({ kind: 'text', uri: '', label: 'Note ' + index,
        text: index + ':' + 'a'.repeat(65520) }));
    let serial = 0;
    assert.equal(addShelfItems(undefined, items, () => 'note-' + ++serial, NOW).reason, 'too-large');
});

test('v1 document migrates with empty addedAt and unpinned entries', () => {
    const v1 = { schemaVersion: 1, entries: [
        { id: 'a', uri: 'file:///tmp/a.pdf', label: 'a.pdf' },
        { id: 'b', kind: 'image', uri: 'https://e.test/p', label: 'p', imageUrl: 'https://e.test/p.png',
            previewUrl: 'https://e.test/p.png', localUri: 'file:///tmp/p.png' },
        { id: 'c', kind: 'spotify', uri: 'https://open.spotify.com/track/' + 'a'.repeat(22), label: 's' }] };
    const parsed = parseShelfDocument(v1);
    assert.equal(parsed.ok, true);
    assert.equal(parsed.migrated, true);
    assert.equal(parsed.value.schemaVersion, 2);
    assert.deepEqual(parsed.value.entries.map(entry => [entry.addedAt, entry.pinned]), [['', false], ['', false], ['', false]]);
    assert.equal(parsed.value.entries[1].localUri, 'file:///tmp/p.png');
    assert.equal(parseShelfDocument(parsed.value).migrated, false);
    assert.equal(parseShelfDocument(JSON.stringify(v1)).migrated, true);
    assert.equal(parseShelfDocument(undefined).migrated, false);
});

test('a v1 document just under 1 MiB still loads after migration', () => {
    const entries = Array.from({ length: 50 }, (_, index) => ({ kind: 'text', uri: '', id: 'n' + index, label: 'n' + index,
        text: index + ':' + 'a'.repeat(20900) }));
    const v1 = { schemaVersion: 1, entries };
    entries[49].text = 'b'.repeat(entries[49].text.length + MAX_URI_LIST_BYTES - 10 - JSON.stringify(v1).length);
    const inputSize = JSON.stringify(v1).length;
    assert.equal(inputSize, MAX_URI_LIST_BYTES - 10);
    const parsed = parseShelfDocument(v1);
    assert.equal(parsed.ok, true);
    assert.equal(parsed.migrated, true);
    assert.equal(parsed.value.entries.length, 50);
    assert.ok(JSON.stringify(parsed.value).length > MAX_URI_LIST_BYTES, 'the migrated form is over the cap');
    assert.equal(parseShelfDocument(JSON.stringify(v1)).ok, true);
    assert.equal(addShelfItems(parsed.value, [{ kind: 'text', uri: '', label: 'x', text: 'x' }], () => 'x', NOW).reason, 'too-large');
    assert.equal(parseShelfDocument(parsed.value).reason, 'too-large');
});

test('a migrated near-cap v1 document can still be trimmed and pinned', () => {
    const entries = Array.from({ length: 50 }, (_, index) => ({ kind: 'text', uri: '', id: 'n' + index, label: 'n' + index,
        text: index + ':' + 'a'.repeat(20900) }));
    const v1 = { schemaVersion: 1, entries };
    entries[49].text = 'b'.repeat(entries[49].text.length + MAX_URI_LIST_BYTES - 10 - JSON.stringify(v1).length);
    const migrated = parseShelfDocument(v1).value;
    assert.ok(JSON.stringify(migrated).length > MAX_URI_LIST_BYTES, 'the migrated form is over the cap');
    // Removing shrinks the document, so it is allowed even though the input is over the cap.
    const removed = removeShelfEntry(migrated, 'n0');
    assert.equal(removed.ok, true);
    assert.equal(removed.document.schemaVersion, 2);
    assert.equal(removed.document.entries.length, 49);
    assert.ok(JSON.stringify(removed.document).length <= MAX_URI_LIST_BYTES, 'the trimmed document fits the cap');
    assert.equal(parseShelfDocument(removed.document).ok, true);
    // Pinning does not grow the document either.
    const pinned = setShelfPinned(migrated, 'n1', true);
    assert.equal(pinned.ok, true);
    assert.equal(pinned.document.entries[1].pinned, true);
    assert.equal(setShelfPinned(pinned.document, 'n1', false).ok, true);
    // Growth is still refused at the cap.
    assert.equal(addShelfItems(migrated, [{ kind: 'text', uri: '', label: 'x', text: 'x' }], () => 'x', NOW).reason, 'too-large');
    assert.equal(parseShelfDocument(migrated, { enforceSize: false }).ok, true);
    assert.equal(parseShelfDocument(migrated).reason, 'too-large');
});

test('v1 entries never carry ownership, so a crafted v1 file is a plain reference', () => {
    const v1 = { schemaVersion: 1, entries: [{ id: 'a', uri: 'file:///tmp/a.png', label: 'a.png', owned: true, pinned: true }] };
    const parsed = parseShelfDocument(v1);
    assert.equal(parsed.ok, true);
    assert.deepEqual(parsed.value.entries[0], { id: 'a', uri: 'file:///tmp/a.png', label: 'a.png', addedAt: '', pinned: false });
});

test('additions stamp addedAt and pinning toggles', () => {
    const add = addShelfUris(undefined, ['file:///tmp/a.pdf'], () => 'id1', NOW);
    assert.equal(add.document.entries[0].addedAt, NOW);
    assert.equal(add.document.entries[0].pinned, false);
    const pinned = setShelfPinned(add.document, 'id1', true);
    assert.equal(pinned.ok, true);
    assert.equal(pinned.changed, true);
    assert.equal(pinned.document.entries[0].pinned, true);
    assert.equal(setShelfPinned(pinned.document, 'id1', true).changed, false);
    assert.equal(setShelfPinned(pinned.document, 'nope', true).reason, 'not-found');
    const unpinned = setShelfPinned(pinned.document, 'id1', false);
    assert.equal(unpinned.changed, true);
    assert.equal(unpinned.document.entries[0].pinned, false);
    assert.equal(unpinned.document.entries[0].addedAt, NOW);
});

test('additions without an explicit time stamp the current time', () => {
    const add = addShelfUris(undefined, ['file:///tmp/a.pdf'], () => 'id1');
    assert.match(add.document.entries[0].addedAt, ISO_TIME);
    const items = addShelfItems(undefined, [{ kind: 'text', uri: '', label: 'n', text: 'note' }], () => 'id2');
    assert.match(items.document.entries[0].addedAt, ISO_TIME);
    assert.equal(addShelfUris(undefined, ['file:///tmp/a.pdf'], () => 'id3', 'yesterday').ok, false);
});

test('limits count unpinned and pinned separately', () => {
    let n = 0;
    const id = () => 'e' + (++n);
    assert.equal(MAX_UNPINNED_ENTRIES, 300);
    let doc = shelfWith(300, id);
    assert.equal(doc.entries.length, 300);
    assert.equal(addShelfUris(doc, ['file:///tmp/x'], id, NOW).reason, 'limit');
    assert.equal(addShelfItems(doc, [{ kind: 'text', uri: '', label: 'n', text: 'note' }], id, NOW).reason, 'limit');
    doc = setShelfPinned(doc, 'e1', true).document;
    assert.equal(addShelfUris(doc, ['file:///tmp/x'], id, NOW).ok, true);
    assert.equal(parseShelfDocument(doc).ok, true);
});

test('pin limit is 50', () => {
    let n = 0;
    const id = () => 'e' + (++n);
    assert.equal(MAX_PINNED_ENTRIES, 50);
    let doc = shelfWith(51, id);
    for (let index = 1; index <= 50; index++) doc = setShelfPinned(doc, 'e' + index, true).document;
    assert.equal(doc.entries.filter(entry => entry.pinned).length, 50);
    const over = setShelfPinned(doc, 'e51', true);
    assert.equal(over.ok, false);
    assert.equal(over.reason, 'pin-limit');
    assert.equal(setShelfPinned(doc, 'e1', true).changed, false);
    doc = setShelfPinned(doc, 'e1', false).document;
    assert.equal(setShelfPinned(doc, 'e51', true).ok, true);
});

test('a document past both limits together is invalid', () => {
    const entries = fileUris(351).map((uri, index) => ({ id: 'e' + index, uri, label: 'f', addedAt: NOW, pinned: index < 50 }));
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries }).reason, 'invalid-document');
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: entries.slice(0, 350) }).ok, true);
});

test('rejects additions past 1 MiB without changing the document', () => {
    let n = 0;
    const id = () => 't' + (++n);
    let doc = emptyShelfDocument();
    for (let i = 0; i < 17; i++)
        doc = addShelfItems(doc, [{ kind: 'text', uri: '', label: 'n' + i, text: 'x'.repeat(60000) + i }], id, NOW).document;
    assert.equal(doc.entries.length, 17);
    const before = JSON.stringify(doc);
    const result = addShelfItems(doc, [{ kind: 'text', uri: '', label: 'big', text: 'y'.repeat(60000) }], id, NOW);
    assert.equal(result.ok, false);
    assert.equal(result.reason, 'too-large');
    assert.equal(JSON.stringify(doc), before);
});

test('removal returns the removed entry including owned flag', () => {
    const add = addShelfItems(undefined, [{ uri: 'file:///s/clip.png', label: 'clip.png', owned: true }], () => 'o', NOW);
    assert.equal(add.ok, true);
    assert.deepEqual(add.document.entries[0], { id: 'o', uri: 'file:///s/clip.png', label: 'clip.png', addedAt: NOW, pinned: false, owned: true });
    assert.deepEqual(parseShelfDocument(JSON.stringify(add.document)).value, add.document);
    const removed = removeShelfEntry(add.document, 'o');
    assert.equal(removed.ok, true);
    assert.equal(removed.changed, true);
    assert.equal(removed.removed.owned, true);
    assert.equal(removed.removed.id, 'o');
    assert.equal(removed.document.entries.length, 0);
    assert.equal(removed.document.schemaVersion, 2);
});

test('owned is rejected on non-file entries', () => {
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: [{ id: 'x', kind: 'text', uri: '', label: 'l', text: 't',
        addedAt: NOW, pinned: false, owned: true }] }).ok, false);
    assert.equal(addShelfItems(undefined, [{ kind: 'link', uri: 'https://e.test/', label: 'l', owned: true }], () => 'x', NOW).ok, false);
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: [{ id: 'x', uri: 'file:///tmp/a', label: 'l',
        addedAt: NOW, pinned: false, owned: 'yes' }] }).ok, false);
});

test('composer turns URLs into links and other text into notes', () => {
    assert.deepEqual(composerItem('  https://quickshell.outfoxxed.me/docs  ').item,
        { kind: 'link', uri: 'https://quickshell.outfoxxed.me/docs', label: 'https://quickshell.outfoxxed.me/docs' });
    const note = composerItem('\n Купити: кабель USB-C\nтермопасту');
    assert.equal(note.ok, true);
    assert.equal(note.item.kind, 'text');
    assert.equal(note.item.uri, '');
    assert.equal(note.item.label, 'Купити: кабель USB-C');
    assert.equal(note.item.text, ' Купити: кабель USB-C\nтермопасту');
    assert.equal(composerItem('x'.repeat(100) + '\nmore').item.label, 'x'.repeat(80));
    assert.equal(composerItem('   ').reason, 'empty');
    assert.equal(composerItem(undefined).reason, 'empty');
    assert.equal(composerItem('z'.repeat(70000)).reason, 'item-too-large');
    const long = composerItem('https://e.test/' + 'p'.repeat(600));
    assert.equal(long.item.uri.length, 615);
    assert.equal(long.item.label.length, 512);
    let serial = 0;
    assert.equal(addShelfItems(undefined, [long.item, note.item], () => 'c' + ++serial, NOW).ok, true);
});

test('v2 rejects malformed addedAt and pinned', () => {
    const base = { id: 'a', uri: 'file:///tmp/a', label: 'a', pinned: false };
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: [{ ...base, addedAt: 'yesterday' }] }).ok, false);
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: [{ ...base, addedAt: NOW, pinned: 'yes' }] }).ok, false);
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: [{ ...base }] }).ok, false);
    assert.equal(parseShelfDocument({ schemaVersion: 2, entries: [{ ...base, addedAt: '' }] }).ok, true);
    assert.equal(parseShelfDocument({ schemaVersion: 3, entries: [] }).ok, false);
});
