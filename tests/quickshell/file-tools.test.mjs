import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { LOCAL_FILE, actionsFor, availableActions, defaultOptions, findAction, formatBytes, languageChoices, mergeFiles,
  outputItems, parentUri, pickAction, requestFor, runLabel, validate } from '../../quickshell/logic/file-tools.mjs';

const pdf = (name = 'a.pdf') => ({ kind: 'file', uri: `file:///tmp/${encodeURIComponent(name)}`, name, mimeType: 'application/pdf', sizeBytes: 10 });
const video = { kind: 'file', uri: 'file:///tmp/v.mkv', name: 'v.mkv', mimeType: 'video/x-matroska', sizeBytes: 5e9 };
const song = { kind: 'file', uri: 'file:///tmp/s.flac', name: 's.flac', mimeType: 'audio/flac', sizeBytes: 9 };

test('every action maps to an operation the helper implements', async () => {
  const helper = await readFile(new URL('../../tools/pentad_file_tool.py', import.meta.url), 'utf8');
  for (const tool of ['pentad.pdf', 'pentad.images', 'pentad.image-text', 'pentad.media', 'pentad.archive', 'pentad.checksum'])
    for (const action of actionsFor(tool)) assert.match(helper, new RegExp(`'${action.id.replace('.', '\\.')}': \\(`), action.id);
});

test('filters actions by file count and type and keeps a still-valid choice', () => {
  assert.deepEqual(availableActions('pentad.pdf', [pdf()]).map(action => action.id).includes('pdf.merge'), false);
  assert.equal(availableActions('pentad.pdf', [pdf(), pdf('b.pdf')]).some(action => action.id === 'pdf.extract'), false);
  assert.deepEqual(availableActions('pentad.media', [song]).map(action => action.id), ['media.audio', 'media.trim']);
  assert.equal(pickAction('pentad.media', [video], 'media.gif'), 'media.gif');
  assert.equal(pickAction('pentad.media', [song], 'media.gif'), 'media.audio');
  assert.equal(pickAction('pentad.archive', [{ ...pdf(), mimeType: 'application/zip', name: 'a.zip' }], ''), 'archive.extract');
  assert.equal(pickAction('pentad.archive', [pdf()], ''), 'archive.create');
});

test('validates required, patterned and password options before running', () => {
  const extract = findAction('pentad.pdf', 'pdf.extract');
  assert.equal(validate(extract, [pdf()], { pages: '' }).ok, false);
  assert.equal(validate(extract, [pdf()], { pages: '1-3; rm' }).ok, false);
  assert.equal(validate(extract, [pdf()], { pages: '1-3, 5, 8-z' }).ok, true);
  assert.equal(validate(extract, [], { pages: '1' }).reason, 'Add files first');
  assert.equal(validate(findAction('pentad.pdf', 'pdf.lock'), [pdf()], { password: 'a\nb' }).ok, false);
  assert.equal(validate(findAction('pentad.media', 'media.gif'), [song], defaultOptions(findAction('pentad.media', 'media.gif'))).ok, false);
});

test('builds helper requests without empty options and keeps passwords verbatim', () => {
  const rotate = findAction('pentad.pdf', 'pdf.rotate');
  assert.deepEqual(requestFor(rotate, [pdf()], { angle: '180', pages: '  ' }),
    { operation: 'pdf.rotate', inputs: ['file:///tmp/a.pdf'], options: { angle: '180' }, timeoutMs: 300000 });
  assert.equal(requestFor(findAction('pentad.pdf', 'pdf.unlock'), [pdf()], { password: ' x ' }).options.password, ' x ');
  assert.equal(runLabel(findAction('pentad.images', 'image.convert'), 3), 'Convert 3 files');
  assert.equal(runLabel(findAction('pentad.pdf', 'pdf.merge'), 3), 'Merge');
});

test('merges local file references and rejects text or unsupported files', () => {
  assert.equal(mergeFiles([], [{ kind: 'text', value: 'hi', mimeType: 'text/plain' }], ['application/pdf']).ok, false);
  assert.equal(mergeFiles([], [video], ['application/pdf']).ok, false);
  const first = mergeFiles([], [pdf()], ['application/pdf']);
  assert.equal(first.ok, true);
  assert.ok(first.files[0].compatibleTypes.includes(LOCAL_FILE));
  assert.equal(mergeFiles(first.files, [pdf('b.pdf')], ['application/pdf']).reason, 'choose-replace-or-append');
  assert.equal(mergeFiles(first.files, [pdf(), pdf('b.pdf')], ['application/pdf'], 'append').files.length, 2);
  assert.equal(mergeFiles(first.files, [pdf('b.pdf')], ['application/pdf'], 'replace').files[0].name, 'b.pdf');
  assert.equal(mergeFiles([], [{ ...pdf(), compatibleTypes: ['text/plain', LOCAL_FILE] }], [LOCAL_FILE]).ok, true);
});

test('formats sizes, parents, languages and hand-off items', () => {
  assert.equal(formatBytes(512), '512 B');
  assert.equal(formatBytes(1536), '1.5 KB');
  assert.equal(formatBytes(50 * 1024 * 1024), '50 MB');
  assert.equal(formatBytes(-1), '');
  assert.equal(parentUri('file:///home/a/b.pdf'), 'file:///home/a');
  assert.deepEqual(languageChoices(['ukr', 'afr', 'eng']).map(item => item.id), ['eng', 'afr', 'ukr']);
  assert.deepEqual(outputItems({ outputs: [{ kind: 'folder', uri: 'file:///x' }, { kind: 'file', uri: 'file:///y.pdf', name: 'y.pdf', mimeType: 'application/pdf', sizeBytes: 3 }] }),
    [{ kind: 'file', uri: 'file:///y.pdf', name: 'y.pdf', mimeType: 'application/pdf', sizeBytes: 3, compatibleTypes: ['application/pdf', LOCAL_FILE] }]);
});
