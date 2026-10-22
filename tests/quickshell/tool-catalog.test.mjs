import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyText, cleanText, compatibleTools, convertUnit, formatJson, mergeDraft, mimeMatches, parseUriList, searchTools, toolEntries, utf8Length } from '../../quickshell/logic/tool-catalog.mjs';

test('classifies JSON, URL, color, and plain text while retaining the source value', () => {
  for (const [value, kind] of [[' {"a":1} ', 'json'], ['https://example.test/a', 'url'], ['#12abef', 'color'], ['hello', 'text']]) {
    assert.equal(classifyText(value).kind, kind);
    assert.equal(classifyText(value).value, value);
    assert.ok(classifyText(value).compatibleTypes.includes('text/plain'));
  }
});

test('keeps local file URIs separate from remote URLs and rejects unsupported schemes', () => {
  const local = parseUriList('# comment\nfile:///tmp/a%20b.txt\n');
  assert.equal(local.ok, true);
  assert.equal(local.items[0].kind, 'file');
  assert.equal(parseUriList('https://example.test').items[0].kind, 'url');
  assert.equal(parseUriList('sftp://example.test').reason, 'unsupported-uri');
});

test('matches wildcard MIME types and filters mixed payloads, item counts, and bytes', () => {
  const tool = { manifest: { id: 'x', name: 'Text', tool: { accepts: ['text/*'], multiple: true, maxItems: 2, maxBytes: 8 } } };
  assert.equal(mimeMatches(['image/*'], 'image/png'), true);
  assert.equal(compatibleTools([tool], [{ mimeType: 'text/plain', value: 'ok' }, { mimeType: 'text/uri-list', value: 'url' }]).length, 1);
  assert.equal(compatibleTools([tool], [{ mimeType: 'text/plain', value: 'ok' }, { mimeType: 'image/png', value: 'x' }]).length, 0);
  assert.equal(compatibleTools([tool], [{ mimeType: 'text/plain', value: 'too long!' }]).length, 0);
  const files = { manifest: { id: 'f', name: 'Files', tool: { accepts: ['video/*'], multiple: false, maxItems: 1, maxBytes: 64 } } };
  assert.equal(compatibleTools([files], [{ kind: 'file', mimeType: 'video/mp4', uri: 'file:///a.mp4', sizeBytes: 5e9 }]).length, 1);
  assert.equal(compatibleTools([files], [{ kind: 'file', mimeType: 'video/mp4', uri: 'file:///' + 'a'.repeat(80) }]).length, 0);
});

test('requires explicit replace or append for existing drafts', () => {
  assert.deepEqual(mergeDraft('', 'next'), { ok: true, value: 'next' });
  assert.equal(mergeDraft('old', 'new').ok, false);
  assert.deepEqual(mergeDraft('old', 'new', 'append'), { ok: true, value: 'oldnew' });
  assert.deepEqual(mergeDraft('old', 'new', 'replace'), { ok: true, value: 'new' });
});

test('runs deterministic local text and unit conversions with clear invalid input errors', () => {
  assert.equal(cleanText(' a  \r\nb\t\n\n'), ' a\nb');
  assert.deepEqual(formatJson('{"x":1}'), { ok: true, value: '{\n  "x": 1\n}', mimeType: 'application/json' });
  assert.equal(formatJson('{').ok, false);
  assert.equal(convertUnit('1', 'km', 'm').value, 1000);
  assert.equal(convertUnit('0', 'C', 'F', 'temperature').value, 32);
  assert.equal(convertUnit('nope', 'km', 'm').ok, false);
  assert.equal(convertUnit(' ', 'km', 'm').ok, false);
  assert.equal(convertUnit('1e308', 'km', 'mm').ok, false);
  assert.equal(utf8Length('a😀'), 5);
});

test('searches catalog names/keywords and sorts favorites then recent tools', () => {
  const entries = ['a', 'b', 'c'].map(id => ({ manifest: { id, name: id.toUpperCase(), tool: { category: 'Text', keywords: [id] } } }));
  assert.deepEqual(searchTools(entries, 'b').map(entry => entry.manifest.id), ['b']);
  assert.deepEqual(searchTools(entries, '', { favorites: ['c'], recent: ['b', 'a'] }).map(entry => entry.manifest.id), ['c', 'b', 'a']);
});

test('only exposes tool modules installable in the sidebar slot', () => {
  const catalog = {
    available: { manifest: { id: 'available', name: 'Available', allowedSlots: ['sidebar-left'], tool: {} } },
    unavailable: { manifest: { id: 'unavailable', name: 'Unavailable', allowedSlots: ['system'], tool: {} } },
  };
  assert.deepEqual(toolEntries(catalog).map(entry => entry.manifest.id), ['available']);
});

test('catalog search ranks name matches ahead of favorites and matches words across fields', () => {
  const entries = [
    { manifest: { id: 'chat', name: 'Chat', tool: { category: 'AI', keywords: ['json', 'format'] } } },
    { manifest: { id: 'json', name: 'JSON formatter', tool: { category: 'Data', keywords: ['validate'] } } },
    { manifest: { id: 'exact', name: 'JSON', tool: { category: 'Data', keywords: [] } } },
  ];
  const ids = (query, options) => searchTools(entries, query, options).map(entry => entry.manifest.id);
  assert.deepEqual(ids('json', { favorites: ['chat'] }), ['exact', 'json', 'chat']);
  assert.deepEqual(ids(' DATA validate '), ['json']);
  assert.deepEqual(ids('json', { favorites: ['chat'], view: 'favorites', category: 'Data' }), []);
  assert.deepEqual(ids('', { favorites: ['chat'], recent: ['json', 'chat'], view: 'recent' }), ['json', 'chat']);
  assert.deepEqual(ids('', { category: 'Data' }), ['exact', 'json']);
});
