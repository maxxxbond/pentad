import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initialState, canCommit, reduceCommit, reduceFinished } from '../../quickshell/logic/settings-controller.mjs';

test('initial state is idle', () => {
  assert.deepEqual(initialState(), { pendingId: '', pendingKey: '', error: '' });
  assert.equal(canCommit(initialState()), true);
});

test('commit records pending request and clears the old error', () => {
  const start = { ...initialState(), error: 'old' };
  const { state, accepted } = reduceCommit(start, 'accent', 'file-1');
  assert.equal(accepted, true);
  assert.deepEqual(state, { pendingId: 'file-1', pendingKey: 'accent', error: '' });
  assert.equal(canCommit(state), false);
});

test('second commit while pending is refused and keeps the first', () => {
  const first = reduceCommit(initialState(), 'accent', 'file-1').state;
  const second = reduceCommit(first, 'fontFamily', 'file-2');
  assert.equal(second.accepted, false);
  assert.deepEqual(second.state, first);
});

test('commit without a request id is refused', () => {
  const result = reduceCommit(initialState(), 'accent', '');
  assert.equal(result.accepted, false);
  assert.deepEqual(result.state, initialState());
});

test('foreign request ids are ignored', () => {
  const pending = reduceCommit(initialState(), 'accent', 'file-1').state;
  assert.deepEqual(reduceFinished(pending, 'other', { ok: false, message: 'x' }), pending);
});

test('failure sets error and clears pending', () => {
  const pending = reduceCommit(initialState(), 'accent', 'file-1').state;
  assert.deepEqual(reduceFinished(pending, 'file-1', { ok: false, reason: 'conflict' }),
    { pendingId: '', pendingKey: '', error: 'conflict' });
  assert.equal(reduceFinished(pending, 'file-1', { ok: false, reason: 'io', message: 'disk' }).error, 'disk');
});

test('failure without reason or message still reports an error', () => {
  const pending = reduceCommit(initialState(), 'accent', 'file-1').state;
  assert.notEqual(reduceFinished(pending, 'file-1', { ok: false }).error, '');
  assert.notEqual(reduceFinished(pending, 'file-1', undefined).error, '');
});

test('success clears pending and error', () => {
  const pending = { pendingId: 'file-1', pendingKey: 'accent', error: 'stale' };
  assert.deepEqual(reduceFinished(pending, 'file-1', { ok: true }), initialState());
});

test('finish with nothing pending is a no-op', () => {
  const idle = initialState();
  assert.deepEqual(reduceFinished(idle, '', { ok: true }), idle);
});
