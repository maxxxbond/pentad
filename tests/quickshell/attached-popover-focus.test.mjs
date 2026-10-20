import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../quickshell/components/AttachedPopover.qml', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
function fixture(grabFocus) {
  const calls = [], deferred = [];
  const previous = { Window: { window: {} }, forceActiveFocus() { calls.push('restore'); } };
  const p = vm.createContext({
    grabFocus, focusBeforeOpen: null, focusRequestedForOpen: false, wasOpened: false, focusGeneration: 0,
    closeReason: '', pointerIntent: { trace() {} },
    anchorItem: { Window: { window: { activeFocusItem: previous } } },
    contentHost: { forceActiveFocus() { calls.push('content'); } },
    manager: { childSurface: null, registerChild() { calls.push('register'); }, unregisterChild() { calls.push('unregister'); } },
    Qt: { PopupFocusReason: 4, callLater(callback) { deferred.push(callback); } },
    closed() { calls.push('closed'); },
  });
  let visible = false;
  p.popup = {};
  Object.defineProperty(p.popup, 'visible', { get() { return visible; }, set(value) { visible = value; if (!value) p.finishClose(); } });
  Object.defineProperty(p, 'opened', { get() { return visible; } });
  p.root = p;
  vm.runInContext(methods, p, { timeout: 1000 });
  return { p, calls, flush() { while (deferred.length) deferred.shift()(); } };
}

test('passive hover popup neither takes focus nor restores focus to the bar', () => {
  const { p, calls, flush } = fixture(false);
  for (let i = 0; i < 3; i++) { p.open(); flush(); p.close(); flush(); }
  assert.equal(calls.includes('content'), false);
  assert.equal(calls.includes('restore'), false);
  assert.equal(calls.filter(call => call === 'register').length, 3);
  assert.equal(calls.filter(call => call === 'closed').length, 3);
});

test('interactive menus retain keyboard focus and return it once on close', () => {
  const { p, calls, flush } = fixture(true);
  p.open(); flush(); p.close(); flush(); p.close(); flush();
  assert.equal(calls.filter(call => call === 'content').length, 1);
  assert.equal(calls.filter(call => call === 'restore').length, 1);
});

test('closing before the open callback prevents a hidden popup taking focus', () => {
  const { p, calls, flush } = fixture(true);
  p.open(); p.close(); flush();
  assert.equal(calls.includes('content'), false);
});

test('rapid reopen cancels the previous close focus restoration', () => {
  const { p, calls, flush } = fixture(true);
  p.open(); flush(); p.close(); p.open(); flush();
  assert.equal(calls.filter(call => call === 'content').length, 2);
  assert.equal(calls.includes('restore'), false);
});
