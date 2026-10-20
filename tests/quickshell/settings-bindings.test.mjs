import assert from 'node:assert/strict';
import test from 'node:test';
import { defaults } from '../../quickshell/logic/config.mjs';
import { readValue, writeValue, commitCheck } from '../../quickshell/logic/settings-bindings.mjs';

const deepFreeze = (value) => {
  if (value && typeof value === 'object') { Object.values(value).forEach(deepFreeze); Object.freeze(value); }
  return value;
};
const docs = () => deepFreeze(structuredClone({ theme: defaults.theme, layout: defaults.layout, spotlight: defaults.spotlight }));
const item = (document, path, extra = {}) => ({ key: path, kind: 'text', control: 'text', document, path, labelUk: 'x', labelEn: 'x', ...extra });

test('reads nested path emoji.languages', () => {
  const documents = deepFreeze({ spotlight: { emoji: { languages: ['uk', 'de'] } } });
  assert.deepEqual(readValue(documents, item('spotlight', 'emoji.languages')), ['uk', 'de']);
});

test('falls back to item default, then undefined', () => {
  assert.equal(readValue({}, item('session', 'a.b', { default: 7 })), 7);
  assert.equal(readValue({ session: { a: {} } }, item('session', 'a.b', { default: 7 })), 7);
  assert.equal(readValue({}, item('session', 'a.b')), undefined);
  assert.equal(readValue({ session: { a: { b: false } } }, item('session', 'a.b', { default: true })), false);
});

test('writeValue does not mutate frozen input and sets value', () => {
  const documents = docs();
  const result = writeValue(documents, item('layout', 'barHeight'), 32);
  assert.equal(result.name, 'layout');
  assert.equal(result.document.barHeight, 32);
  assert.equal(documents.layout.barHeight, 40);
  assert.notEqual(result.document.widgets, documents.layout.widgets);
});

test('writeValue creates missing parents', () => {
  const result = writeValue({}, item('session', 'a.b.c'), 1);
  assert.deepEqual(result.document, { a: { b: { c: 1 } } });
});

test('commitCheck rejects invalid values', () => {
  const bar = commitCheck(docs(), item('layout', 'barHeight', { kind: 'integer' }), 50);
  assert.equal(bar.ok, false);
  assert.ok(bar.message);
  assert.equal(commitCheck(docs(), item('theme', 'accent', { kind: 'color' }), 'red').ok, false);
});

test('commitCheck accepts valid values', () => {
  const result = commitCheck(docs(), item('layout', 'trayIcons'), 'color');
  assert.equal(result.ok, true);
  assert.equal(result.name, 'layout');
  assert.equal(result.document.trayIcons, 'color');
});
