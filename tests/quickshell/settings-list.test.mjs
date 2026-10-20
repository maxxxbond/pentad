import { test } from 'node:test';
import assert from 'node:assert/strict';
import { moveItem } from '../../quickshell/logic/settings-list.mjs';

test('moveItem moves an id forward and backward', () => {
  assert.deepEqual(moveItem(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
  assert.deepEqual(moveItem(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
  assert.deepEqual(moveItem(['a', 'b', 'c'], 1, 2), ['a', 'c', 'b']);
});

test('moveItem clamps the target index to the list bounds', () => {
  assert.deepEqual(moveItem(['a', 'b', 'c'], 0, 99), ['b', 'c', 'a']);
  assert.deepEqual(moveItem(['a', 'b', 'c'], 2, -5), ['c', 'a', 'b']);
});

test('moveItem is a no-op on the same index', () => {
  assert.deepEqual(moveItem(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c']);
});

test('moveItem returns a new array and leaves the input untouched', () => {
  const ids = ['a', 'b', 'c'];
  const out = moveItem(ids, 0, 2);
  assert.notEqual(out, ids);
  assert.deepEqual(ids, ['a', 'b', 'c']);
  const same = moveItem(ids, 1, 1);
  assert.notEqual(same, ids);
  assert.deepEqual(ids, ['a', 'b', 'c']);
});

test('moveItem on an empty list returns an empty list', () => {
  assert.deepEqual(moveItem([], 0, 0), []);
});
