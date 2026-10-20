import test from 'node:test';
import assert from 'node:assert/strict';
import { MAX_DROP_BYTES, offerMime, readOffer, readShelfOffer } from '../../quickshell/logic/drag-drop.mjs';
import { localFilePaths, parseUriList } from '../../quickshell/logic/shelf.mjs';

test('file offers win over text fallback and charset variants reach text tools', () => {
    assert.equal(offerMime(['text/plain', 'text/uri-list']), 'text/uri-list');
    assert.equal(offerMime(['text/plain;charset=utf-8']), 'text/plain;charset=utf-8');
    assert.equal(offerMime(['text/plain;charset=utf-8'], true), '');
    assert.equal(offerMime(['image/png', 'text/html']), '');
});

test('bounded drops count UTF-8 bytes, including surrogate pairs', () => {
    const event = value => ({ formats: ['text/plain'], getDataAsString: () => value });
    assert.equal(readOffer(event('☕'.repeat(Math.floor(MAX_DROP_BYTES / 3)))).ok, true);
    assert.equal(readOffer(event('☕'.repeat(Math.floor(MAX_DROP_BYTES / 3) + 1))).reason, 'too-large');
    assert.equal(readOffer(event('😀'.repeat(MAX_DROP_BYTES / 4 + 1))).reason, 'too-large');
});

test('shelf URI decoder runs without browser TextEncoder', () => {
    const encoder = globalThis.TextEncoder;
    try {
        globalThis.TextEncoder = undefined;
        assert.deepEqual(parseUriList('# files\r\nfile:///tmp/Caf%C3%A9%20notes.txt\r\n').uris,
            ['file:///tmp/Caf%C3%A9%20notes.txt']);
        assert.equal(parseUriList('file:///tmp/' + '☕'.repeat(MAX_DROP_BYTES / 3)).reason, 'too-large');
    } finally { globalThis.TextEncoder = encoder; }
});

test('LocalSend gets absolute decoded paths as separate arguments', () => {
    assert.deepEqual(localFilePaths(['file:///tmp/Caf%C3%A9%20notes.txt', 'file://localhost/tmp/a%23b%3Fc.txt']).paths,
        ['/tmp/Café notes.txt', '/tmp/a#b?c.txt']);
    for (const uri of ['https://example.test/a', 'file://remote/tmp/a', 'file:///tmp/%00a', 'file:///tmp/%zz', 'file:///tmp/a?query'])
        assert.equal(localFilePaths([uri]).ok, false);
});

test('Spotify empty URI offer falls back to plain text and preserves HTML for Shelf', () => {
    const url = 'https://open.spotify.com/track/7h2ABjmIKKbT7VBWFM2nZD';
    const data = { 'text/uri-list': '', 'text/plain': url, 'text/html': '<a href="' + url + '">Track</a>' };
    const event = { formats: Object.keys(data), getDataAsString: mime => data[mime] };
    assert.equal(readOffer(event).value, url);
    assert.equal(readOffer(event, true).ok, false);
    assert.equal(readShelfOffer(event).offer.html, data['text/html']);
});
