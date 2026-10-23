import test from 'node:test';
import assert from 'node:assert/strict';
import { HelperClient, HELPER_REQUEST_LIMIT } from '../../quickshell/logic/spotlight-helper.mjs';

const settle = calls => { for (const [done, result] of calls) done(result); };
const recorder = () => { const replies = []; return { replies, done: result => replies.push(result) }; };
const line = (id, request) => `{"id":${id},"request":${JSON.stringify(request)}}\n`;

test('requests queue until the helper starts, then go out in order with their ids', () => {
  const client = new HelperClient();
  assert.deepEqual(client.request({ operation: 'history' }, () => {}), { lines: [], calls: [] });
  assert.deepEqual(client.request({ operation: 'emoji', languages: ['en'] }, () => {}), { lines: [], calls: [] });
  assert.equal(client.idle, false);
  assert.equal(client.waiting, false);
  assert.deepEqual(client.started(), [line(1, { operation: 'history' }), line(2, { operation: 'emoji', languages: ['en'] })]);
  assert.equal(client.waiting, true);
  assert.deepEqual(client.request({ operation: 'clipboard-list' }, () => {}).lines, [line(3, { operation: 'clipboard-list' })]);
  assert.deepEqual(client.started(), []);
});

test('each reply settles its own request once; unknown, repeated and late ids are dropped', () => {
  const client = new HelperClient();
  const first = recorder(), second = recorder();
  client.started();
  client.request({ operation: 'history' }, first.done);
  client.request({ operation: 'keyboard-layouts' }, second.done);
  const outcome = client.receive('{"id":2,"result":{"ok":true,"layouts":["us"]}}');
  assert.equal(outcome.broken, false);
  settle(outcome.calls);
  assert.deepEqual(second.replies, [{ ok: true, layouts: ['us'] }]);
  assert.ok(Array.isArray(second.replies[0].layouts));
  settle(client.receive('{"id":2,"result":{"ok":true,"layouts":["de"]}}').calls);
  settle(client.receive('{"id":99,"result":{"ok":true}}').calls);
  settle(client.receive('{"id":null,"result":{"ok":false,"reason":"io"}}').calls);
  assert.deepEqual(second.replies, [{ ok: true, layouts: ['us'] }]);
  assert.deepEqual(first.replies, []);
  settle(client.receive('{"id":1,"result":[1]}').calls);
  assert.deepEqual(first.replies, [{ ok: false, reason: 'io' }]);
  assert.equal(client.idle, true);
});

test('per-keystroke requests keep one in flight and only the newest waiting', () => {
  const client = new HelperClient();
  const se = recorder(), sea = recorder(), seas = recorder(), sunset = recorder(), history = recorder();
  client.started();
  assert.deepEqual(client.request({ operation: 'files', query: 'se' }, se.done, 'files').lines, [line(1, { operation: 'files', query: 'se' })]);
  assert.deepEqual(client.request({ operation: 'files', query: 'sea' }, sea.done, 'files'), { lines: [], calls: [] });
  const third = client.request({ operation: 'files', query: 'seas' }, seas.done, 'files');
  assert.deepEqual(third.lines, []);
  settle(third.calls);
  assert.deepEqual(sea.replies, [{ ok: false, reason: 'superseded' }]);
  // Other requests are not held behind the key.
  assert.deepEqual(client.request({ operation: 'history' }, history.done).lines, [line(4, { operation: 'history' })]);
  const reply = client.receive('{"id":1,"result":{"ok":true,"files":[]}}');
  settle(reply.calls);
  assert.deepEqual(se.replies, [{ ok: true, files: [] }]);
  assert.deepEqual(reply.lines, [line(3, { operation: 'files', query: 'seas' })]);
  client.request({ operation: 'files', query: 'sunset' }, sunset.done, 'files');
  settle(client.receive('{"id":3,"result":{"ok":true,"files":[1]}}').calls);
  assert.deepEqual(seas.replies, [{ ok: true, files: [1] }]);
  assert.equal(client.entries.get(5).sent, true);
  assert.deepEqual(sunset.replies, []);
});

test('keyed requests queued before the start go out as one', () => {
  const client = new HelperClient();
  const old = recorder();
  client.request({ operation: 'files', query: 'se' }, old.done, 'files');
  settle(client.request({ operation: 'files', query: 'sea' }, () => {}, 'files').calls);
  assert.deepEqual(old.replies, [{ ok: false, reason: 'superseded' }]);
  assert.deepEqual(client.started(), [line(2, { operation: 'files', query: 'sea' })]);
});

test('a reply line that is not a JSON object marks the helper broken', () => {
  const client = new HelperClient();
  client.started();
  assert.equal(client.receive('Traceback (most recent call last):').broken, true);
  assert.equal(client.receive('[1]').broken, true);
  assert.equal(client.receive('null').broken, true);
});

test('a timeout fails what the helper holds and keeps later requests for the next process', () => {
  const client = new HelperClient();
  const held = recorder(), later = recorder();
  client.started();
  client.request({ operation: 'clipboard-list' }, held.done);
  settle(client.timeout());
  assert.deepEqual(held.replies, [{ ok: false, reason: 'timeout' }]);
  assert.deepEqual(client.request({ operation: 'history' }, later.done), { lines: [], calls: [] });
  // The killed process may still print the old reply; it is stale now.
  settle(client.receive('{"id":1,"result":{"ok":true,"text":""}}').calls);
  assert.equal(held.replies.length, 1);
  const stop = client.stopped(true);
  assert.deepEqual(stop.calls, []);
  assert.equal(stop.restart, true);
  assert.deepEqual(client.started(), [line(2, { operation: 'history' })]);
  settle(client.receive('{"id":2,"result":{"ok":true}}').calls);
  assert.deepEqual(later.replies, [{ ok: true }]);
});

test('a crash fails held requests and releases keyed ones for the next process', () => {
  const client = new HelperClient();
  const held = recorder(), waiting = recorder();
  client.started();
  client.request({ operation: 'files', query: 'se' }, held.done, 'files');
  client.request({ operation: 'files', query: 'sea' }, waiting.done, 'files');
  const stop = client.stopped(true);
  settle(stop.calls);
  assert.deepEqual(held.replies, [{ ok: false, reason: 'io' }]);
  assert.equal(stop.restart, true);
  assert.deepEqual(client.started(), [line(2, { operation: 'files', query: 'sea' })]);
});

test('a crash with nothing queued does not restart; a failed start fails everything', () => {
  const client = new HelperClient();
  const held = recorder(), queued = recorder();
  client.started();
  client.request({ operation: 'history' }, held.done);
  let stop = client.stopped(true);
  settle(stop.calls);
  assert.equal(stop.restart, false);
  assert.deepEqual(held.replies, [{ ok: false, reason: 'io' }]);
  client.request({ operation: 'history' }, queued.done);
  stop = client.stopped(false);
  settle(stop.calls);
  assert.equal(stop.restart, false);
  assert.deepEqual(queued.replies, [{ ok: false, reason: 'unavailable' }]);
  assert.equal(client.idle, true);
});

test('retiring an idle helper queues new requests for a restart', () => {
  const client = new HelperClient();
  client.started();
  client.retire();
  assert.deepEqual(client.request({ operation: 'history' }, () => {}).lines, []);
  assert.equal(client.stopped(true).restart, true);
});

test('invalid and oversized requests are refused before they reach the helper', () => {
  const client = new HelperClient();
  client.started();
  assert.deepEqual(client.request(null, () => {}), { error: 'invalid' });
  assert.deepEqual(client.request(['history'], () => {}), { error: 'invalid' });
  assert.deepEqual(client.request({ operation: 'history' }), { error: 'invalid' });
  const cyclic = { operation: 'copy-text' };
  cyclic.self = cyclic;
  assert.deepEqual(client.request(cyclic, () => {}), { error: 'invalid' });
  assert.deepEqual(client.request({ operation: 'copy-text', text: 'x'.repeat(HELPER_REQUEST_LIMIT) }, () => {}), { error: 'io' });
  assert.equal(client.idle, true);
  assert.match(client.request({ operation: 'copy-text', text: 'x'.repeat(1000) }, () => {}).lines[0], /^\{"id":\d+,"request":/);
});
