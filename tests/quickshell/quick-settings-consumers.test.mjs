import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const text = readFileSync(new URL('../../quickshell/services/QuickSettings.qml', import.meta.url), 'utf8');
function method(pattern) {
  const start = text.search(pattern);
  assert.ok(start >= 0, 'QML method exists');
  let depth = 0;
  let end = text.indexOf('{', start);
  for (; end < text.length; end++) {
    if (text[end] === '{') depth++;
    if (text[end] === '}' && --depth === 0) return text.slice(start, end + 1);
  }
  throw new Error('unterminated method');
}

function harness(flags = {}) {
  const ctx = { consumers: [], preview: false, safeMode: false, refreshes: 0, ...flags };
  ctx.refresh = () => { ctx.refreshes++; };
  vm.createContext(ctx);
  vm.runInContext([method(/function acquire\(/), method(/function release\(/)].join('\n'), ctx, { timeout: 1000 });
  return ctx;
}

test('the first consumer refreshes once and repeated acquires are ignored', () => {
  const ctx = harness();
  const panel = {};
  const other = {};
  ctx.acquire(panel);
  ctx.acquire(panel);
  ctx.acquire(other);
  assert.equal(ctx.refreshes, 1);
  assert.equal(ctx.consumers.length, 2);
  ctx.release(panel);
  ctx.release(panel);
  assert.equal(ctx.consumers.length, 1);
  ctx.release(other);
  assert.equal(ctx.consumers.length, 0);
  ctx.acquire(other);
  assert.equal(ctx.refreshes, 2);
});

test('preview and safe mode count consumers without reading the system', () => {
  for (const flags of [{ preview: true }, { safeMode: true }]) {
    const ctx = harness(flags);
    ctx.acquire({});
    assert.equal(ctx.consumers.length, 1);
    assert.equal(ctx.refreshes, 0);
  }
  const ctx = harness();
  ctx.acquire(null);
  assert.equal(ctx.consumers.length, 0);
});
