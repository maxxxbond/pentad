import test from 'node:test';
import assert from 'node:assert/strict';
import { addShelfItems, setShelfDownloadedFile, shelfLocalUri } from '../../quickshell/logic/shelf.mjs';
import {
    addShelfUris, emptyShelfDocument, isShelfFileUri, parseShelfDocument,
    parseUriList, removeShelfEntry, shelfLabel,
} from '../../quickshell/logic/shelf.mjs';

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
    const result = addShelfUris(undefined, [], () => 'unused');
    assert.equal(result.ok, false);
    assert.deepEqual(emptyShelfDocument(), { schemaVersion: 1, entries: [] });
});

test('adds deduplicate within a drop and against stored references without copying files', () => {
    const first = 'file:///tmp/report%20final.pdf';
    const second = 'file:///tmp/notes.txt';
    let serial = 0;
    const add = addShelfUris(undefined, [first, first, second], () => `shelf-${++serial}`);
    assert.equal(add.ok, true);
    assert.deepEqual(add.added.map(entry => entry.uri), [first, second]);
    assert.deepEqual(add.document.entries.map(entry => entry.label), ['report final.pdf', 'notes.txt']);
    const duplicate = addShelfUris(add.document, [first], () => `shelf-${++serial}`);
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
    const added = addShelfItems(legacy, [image, text, image], () => 'new-' + ++serial);
    assert.equal(added.ok, true);
    assert.equal(added.document.entries.length, 3);
    assert.deepEqual(added.document.entries[0], legacy.entries[0]);
    assert.deepEqual(parseShelfDocument(JSON.stringify(added.document)).value, added.document);
    assert.equal(addShelfItems(added.document, [text], () => 'unused').changed, false);
    const saved = setShelfDownloadedFile(added.document, 'new-1', 'file:///tmp/photo.png');
    assert.equal(saved.ok, true);
    assert.equal(shelfLocalUri(saved.document.entries[1]), 'file:///tmp/photo.png');
    assert.equal(saved.document.entries[1].uri, image.uri);
    assert.equal(setShelfDownloadedFile(added.document, 'old', 'file:///tmp/photo.png').ok, false);
    assert.equal(addShelfItems(legacy, [{ ...image, imageUrl: 'javascript:alert(1)' }], () => 'bad').ok, false);
});

test('combined text entries cannot create an oversized unreadable shelf document', () => {
    const items = Array.from({ length: 17 }, (_, index) => ({ kind: 'text', uri: '', label: 'Note ' + index,
        text: index + ':' + 'a'.repeat(65520) }));
    let serial = 0;
    assert.equal(addShelfItems(undefined, items, () => 'note-' + ++serial).reason, 'too-large');
});
