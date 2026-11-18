import test from 'node:test';
import assert from 'node:assert/strict';
import { WorkerClient, encodeRequest, decodeLine, backoffMs, utf8Length, WORKER_BACKOFF_MS, WORKER_REQUEST_LIMIT, WORKER_RECOVERY_MS } from '../../quickshell/logic/worker-protocol.mjs';

const hello = (ops, protocol) => JSON.stringify({ type: 'hello', protocol: protocol === undefined ? 1 : protocol, worker: '1', ops: ops || ['file.run', 'image.ocr', 'llm.chat'] });
const make = () => {
  const out = { lines: [], time: 1000 };
  out.client = new WorkerClient({ write: line => out.lines.push(line), now: () => out.time });
  return out;
};
const rec = () => {
  const r = { results: [], progress: [], partial: [] };
  r.options = { onResult: v => r.results.push(v), onProgress: v => r.progress.push(v), onPartial: v => r.partial.push(v) };
  return r;
};
const ready = (ops) => { const h = make(); h.client.started(); h.client.receive(hello(ops)); return h; };

test('encoding: request, limit and defaults', () => {
  assert.deepEqual(JSON.parse(encodeRequest(7, 'image.ocr', { a: 1 }, 5)), { type: 'request', id: 7, op: 'image.ocr', payload: { a: 1 }, timeoutMs: 5 });
  assert.equal(encodeRequest(1, 'x', { big: 'a'.repeat(WORKER_REQUEST_LIMIT) }, 1), null);
  assert.ok(encodeRequest(1, 'x', {}, 1).endsWith('\n'));
  assert.deepEqual(decodeLine('{"type":"hello"}').message, { type: 'hello' });
  assert.equal(decodeLine('nope').error, true);
  assert.equal(decodeLine('[1]').error, true);
  assert.equal(decodeLine('  ').empty, true);
});

test('requests queue until a valid hello, then go out in order', () => {
  const h = make();
  const a = h.client.request('image.ocr', { n: 1 }, {});
  const b = h.client.request('llm.chat', { n: 2 }, { timeoutMs: 5000 });
  assert.deepEqual([a, b], [1, 2]);
  assert.equal(h.client.needsStart, true);
  assert.equal(h.client.busyCount, 2);
  assert.deepEqual(h.client.started(), { restart: false, delayMs: 0, state: 'starting' });
  assert.deepEqual(h.lines, []);
  assert.equal(h.client.needsStart, false);
  h.client.receive(hello());
  assert.equal(h.client.state, 'ready');
  const sent = h.lines.map(l => JSON.parse(l));
  assert.deepEqual(sent.map(s => s.id), [1, 2]);
  assert.equal(sent[0].timeoutMs, 120000);
  assert.equal(sent[1].timeoutMs, 5000);
  h.client.request('file.run', {}, {});
  assert.equal(h.lines.length, 3);
});

test('llm ops default to a 600 s timeout', () => {
  const h = ready();
  h.client.request('llm.chat', {}, {});
  assert.equal(JSON.parse(h.lines[0]).timeoutMs, 600000);
});

test('protocol other than 1 makes the worker unavailable and fails the queue', () => {
  const h = make();
  const r = rec();
  h.client.request('image.ocr', {}, r.options);
  h.client.started();
  assert.deepEqual(h.client.receive(hello(null, 2)), { kill: true });
  assert.equal(h.client.state, 'unavailable');
  assert.equal(r.results[0].reason, 'unavailable');
  assert.equal(h.client.accepts('image.ocr'), false);
  const again = rec();
  h.client.request('image.ocr', {}, again.options);
  assert.equal(again.results[0].reason, 'unavailable');
  assert.deepEqual(h.client.stopped(2000), { restart: false, delayMs: 0, state: 'unavailable' });
  h.client.reset();
  assert.equal(h.client.state, 'idle');
});

test('hello timeout kills and marks unavailable', () => {
  const h = make();
  const r = rec();
  h.client.request('image.ocr', {}, r.options);
  h.client.started();
  const out = h.client.helloTimedOut();
  assert.equal(out.kill, true);
  assert.equal(out.restart, false);
  assert.equal(out.state, 'unavailable');
  assert.equal(r.results.length, 1);
  assert.equal(h.client.helloTimedOut().kill, undefined);
});

test('progress, partial and result reach the right callbacks, result exactly once', () => {
  const h = ready();
  const r = rec();
  const id = h.client.request('llm.chat', {}, r.options);
  h.client.receive(JSON.stringify({ type: 'progress', id, data: { pct: 5 } }));
  h.client.receive(JSON.stringify({ type: 'partial', id, chunk: { text: 'hi' } }));
  h.client.receive(JSON.stringify({ type: 'result', id, result: { ok: true, value: { text: 'hi' }, cached: false } }));
  h.client.receive(JSON.stringify({ type: 'result', id, result: { ok: true, value: {} } }));
  h.client.receive(JSON.stringify({ type: 'partial', id, chunk: { text: 'late' } }));
  assert.deepEqual(r.progress, [{ pct: 5 }]);
  assert.deepEqual(r.partial, [{ text: 'hi' }]);
  assert.deepEqual(r.results, [{ ok: true, value: { text: 'hi' }, cached: false }]);
  assert.equal(h.client.busyCount, 0);
});

test('malformed lines and unknown ids are ignored; malformed result is invalid-response', () => {
  const h = ready();
  const r = rec();
  const id = h.client.request('image.ocr', {}, r.options);
  h.client.receive('garbage');
  h.client.receive('');
  h.client.receive(JSON.stringify({ type: 'result', id: 99, result: { ok: true } }));
  h.client.receive(JSON.stringify({ type: 'wat', id }));
  assert.equal(r.results.length, 0);
  h.client.receive(JSON.stringify({ type: 'result', id, result: 'nope' }));
  assert.equal(r.results[0].reason, 'invalid-response');
});

test('a throwing callback does not break the loop', () => {
  const h = ready();
  const id = h.client.request('image.ocr', {}, { onResult: () => { throw new Error('boom'); } });
  h.client.receive(JSON.stringify({ type: 'result', id, result: { ok: true, value: {} } }));
  assert.equal(h.client.busyCount, 0);
});

test('cancel: queued settles at once, sent writes a cancel line, unknown ignored', () => {
  const h = make();
  const q = rec();
  const queued = h.client.request('image.ocr', {}, q.options);
  assert.equal(h.client.cancel(queued), true);
  assert.equal(q.results[0].reason, 'cancelled');
  assert.equal(h.client.busyCount, 0);
  h.client.started();
  h.client.receive(hello());
  const s = rec();
  const id = h.client.request('llm.chat', {}, s.options);
  assert.equal(h.client.cancel(id), true);
  assert.deepEqual(JSON.parse(h.lines[h.lines.length - 1]), { type: 'cancel', id });
  assert.equal(s.results.length, 0);
  h.client.receive(JSON.stringify({ type: 'result', id, result: { ok: false, reason: 'cancelled' } }));
  assert.equal(s.results[0].reason, 'cancelled');
  assert.equal(h.client.cancel(id), false);
  assert.equal(h.client.cancel(12345), false);
});

test('unsupported ops: rejected when ready, and at hello for queued ones', () => {
  const h = make();
  const r = rec();
  h.client.request('image.ocr', {}, r.options);
  h.client.started();
  h.client.receive(hello(['file.run']));
  assert.equal(r.results[0].reason, 'unsupported');
  const r2 = rec();
  h.client.request('pdf.text', {}, r2.options);
  assert.equal(r2.results[0].reason, 'unsupported');
  assert.equal(h.client.accepts('file.run'), true);
  assert.equal(h.client.accepts('pdf.text'), false);
});

test('accepts is optimistic before hello and false for bad input', () => {
  const h = make();
  assert.equal(h.client.accepts('image.ocr'), true);
  assert.equal(h.client.accepts('nope.op'), false);
  assert.equal(h.client.accepts(), false);
});

test('invalid requests settle immediately', () => {
  const h = make();
  const a = rec(); const b = rec(); const c = rec();
  h.client.request('', {}, a.options);
  h.client.request('image.ocr', [1], b.options);
  h.client.request('image.ocr', { big: 'a'.repeat(WORKER_REQUEST_LIMIT) }, c.options);
  assert.equal(a.results[0].reason, 'invalid-input');
  assert.equal(b.results[0].reason, 'invalid-input');
  assert.equal(c.results[0].reason, 'invalid-input');
  assert.equal(h.client.busyCount, 0);
});

test('crash fails in-flight with service-stopped and never replays', () => {
  const h = ready();
  const r = rec();
  h.client.request('image.ocr', {}, r.options);
  const written = h.lines.length;
  const out = h.client.stopped(5000);
  assert.deepEqual(out, { restart: false, delayMs: 1000, state: 'idle' });
  assert.equal(r.results.length, 1);
  assert.equal(r.results[0].reason, 'service-stopped');
  h.client.started();
  h.client.receive(hello());
  assert.equal(h.lines.length, written);
});

test('queued request survives a crash and is sent after the restart', () => {
  const h = make();
  const r = rec();
  h.client.request('image.ocr', {}, r.options);
  h.client.started();
  const out = h.client.stopped(2000);
  assert.deepEqual(out, { restart: true, delayMs: 1000, state: 'starting' });
  assert.equal(r.results.length, 0);
  h.client.started();
  h.client.receive(hello());
  assert.equal(h.lines.length, 1);
});

test('backoff grows 1,2,4,8 s and crash-loop comes on the 5th crash within 120 s', () => {
  assert.deepEqual(WORKER_BACKOFF_MS, [1000, 2000, 4000, 8000, 16000, 30000]);
  assert.equal(backoffMs(1), 1000);
  assert.equal(backoffMs(6), 30000);
  assert.equal(backoffMs(40), 30000);
  const h = make();
  h.client.request('image.ocr', {}, {});
  h.client.started();
  const delays = [];
  for (let i = 0; i < 4; i++) {
    const out = h.client.stopped(1000 + i * 10000);
    delays.push(out.delayMs);
    assert.equal(out.restart, true);
    h.client.started();
  }
  assert.deepEqual(delays, [1000, 2000, 4000, 8000]);
  const r = rec();
  h.client.request('image.ocr', {}, r.options);
  const last = h.client.stopped(41000);
  assert.deepEqual(last, { restart: false, delayMs: 0, state: 'crash-loop' });
  assert.equal(h.client.busyCount, 0);
  const after = rec();
  h.client.request('image.ocr', {}, after.options);
  assert.equal(after.results[0].reason, 'unavailable');
  assert.equal(h.client.accepts('image.ocr'), false);
  h.client.reset();
  assert.equal(h.client.state, 'idle');
});

test('crashes older than 120 s fall out of the window', () => {
  const h = make();
  for (let i = 0; i < 4; i++) { h.client.request('image.ocr', {}, {}); h.client.started(); h.client.stopped(i * 10000); }
  h.client.request('image.ocr', {}, {});
  h.client.started();
  const out = h.client.stopped(200000);
  assert.equal(out.state, 'starting');
  assert.equal(out.delayMs, 1000);
});

test('retire is not a crash: in-flight fail, no restart, no count', () => {
  const h = ready();
  const r = rec();
  h.client.request('llm.chat', {}, r.options);
  h.client.retire();
  assert.equal(JSON.parse(h.lines[h.lines.length - 1]).type, 'shutdown');
  const out = h.client.stopped(3000);
  assert.deepEqual(out, { restart: false, delayMs: 0, state: 'idle' });
  assert.equal(r.results[0].reason, 'service-stopped');
  for (let i = 0; i < 10; i++) { h.client.started(); h.client.receive(hello()); h.client.retire(); h.client.stopped(3000 + i); }
  assert.equal(h.client.state, 'idle');
});

test('a request made while retiring waits for a restart', () => {
  const h = ready();
  h.client.retire();
  const before = h.lines.length;
  const r = rec();
  h.client.request('image.ocr', {}, r.options);
  assert.equal(h.lines.length, before);
  const out = h.client.stopped(4000);
  assert.deepEqual(out, { restart: true, delayMs: 0, state: 'idle' });
  assert.equal(r.results.length, 0);
});

test('lastActivityMs follows the injected clock', () => {
  const h = make();
  h.time = 5000;
  h.client.request('image.ocr', {}, {});
  assert.equal(h.client.lastActivityMs, 5000);
  h.client.started();
  h.time = 6000;
  h.client.receive(hello());
  assert.equal(h.client.lastActivityMs, 6000);
});

test('the request limit counts UTF-8 bytes, not UTF-16 code units', () => {
  assert.equal(utf8Length('abc'), 3);
  assert.equal(utf8Length('Привіт'), 12);
  assert.equal(utf8Length('😀'), 4);
  // 600k Cyrillic characters are ~1.2 MB on the wire: refused on the client with a clear reason.
  const text = 'ж'.repeat(600000);
  assert.equal(encodeRequest(1, 'llm.chat', { text }, 1000), null);
  const w = make(); const r = rec();
  w.client.request('llm.chat', { text }, r.options);
  assert.equal(r.results[0].reason, 'invalid-input');
});

test('a retire during start keeps queued requests for the next process', () => {
  const w = make(); const r = rec();
  w.client.request('file.run', {}, r.options);
  w.client.started();
  w.client.retire();
  w.client.receive(hello());
  assert.equal(w.lines.filter(line => line.indexOf('"type":"request"') >= 0).length, 0);
  const decision = w.client.stopped(w.time);
  assert.equal(r.results.length, 0);
  assert.equal(decision.restart, true);
});

test('recover: one fresh start per 30 s window after unavailable or crash-loop', () => {
  const h = make();
  assert.equal(h.client.recover(), false, 'a healthy client has nothing to recover');
  h.client.started();
  h.client.helloTimedOut();
  assert.equal(h.client.state, 'unavailable');
  h.time += WORKER_RECOVERY_MS - 1;
  assert.equal(h.client.recover(), false, 'too early');
  const early = rec();
  h.client.request('image.ocr', {}, early.options);
  assert.equal(early.results[0].reason, 'unavailable');
  h.time += 1;
  assert.equal(h.client.recover(), true);
  assert.equal(h.client.state, 'idle');
  const retried = rec();
  h.client.request('image.ocr', {}, retried.options);
  assert.equal(h.client.needsStart, true);
  // The retry fails as well: the wait starts again from this failure.
  h.client.started();
  h.client.helloTimedOut();
  assert.equal(retried.results[0].reason, 'unavailable');
  assert.equal(h.client.recover(), false, 'one retry per window');
  h.time += WORKER_RECOVERY_MS;
  assert.equal(h.client.recover(), true);

  const loop = make();
  for (let crash = 0; crash < 5; crash++) {
    loop.client.started();
    loop.client.receive(hello());
    loop.client.stopped(loop.time);
  }
  assert.equal(loop.client.state, 'crash-loop');
  assert.equal(loop.client.recover(loop.time + WORKER_RECOVERY_MS - 1), false);
  assert.equal(loop.client.recover(loop.time + WORKER_RECOVERY_MS), true);
  assert.equal(loop.client.state, 'idle');
  assert.equal(loop.client.accepts('file.run'), true);
});

test('a sent request does not keep its line, so a stored key leaves memory once written', () => {
  const h = ready(['secret.store', 'system.vram', 'llm.loaded', 'worker.clear-cache']);
  const r = rec();
  const id = h.client.request('secret.store', { ref: 'secret://pentad/providers/x', value: 'sk-fixture-value' }, r.options);
  assert.equal(h.lines.length, 1);
  assert.match(h.lines[0], /sk-fixture-value/);
  assert.equal(h.client.entries.get(id).line, '');
  assert.ok(!JSON.stringify([...h.client.entries.values()]).includes('sk-fixture-value'));
  h.client.receive(JSON.stringify({ type: 'result', id, result: { ok: true, value: { status: 'stored' } } }));
  assert.deepEqual(r.results, [{ ok: true, value: { status: 'stored' } }]);
});

test('the Models page ops are known before hello', () => {
  const h = make();
  for (const op of ['llm.loaded', 'system.vram', 'worker.clear-cache']) assert.equal(h.client.accepts(op), true, op);
});
