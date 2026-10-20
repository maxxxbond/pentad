import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as flow from '../../quickshell/logic/settings-flow.mjs';

const ok = () => [];
const needName = (draft) => (draft.name ? [] : ['name required']);
const steps = [
  { id: 'a', icon: 'a', labelUk: 'А', labelEn: 'A', validate: ok },
  { id: 'b', icon: 'b', labelUk: 'Б', labelEn: 'B', validate: needName },
  { id: 'c', icon: 'c', labelUk: 'В', labelEn: 'C', validate: ok },
];

test('exports exactly the flow API', () => {
  assert.deepEqual(
    Object.keys(flow).sort(),
    ['back', 'canContinue', 'createFlow', 'isLast', 'next', 'progress', 'setDraft'],
  );
});

test('next blocked by invalid step keeps index and fills errors', () => {
  let f = flow.createFlow(steps, {});
  f = flow.next(f);
  assert.equal(f.index, 1);
  f = flow.next(f);
  assert.equal(f.index, 1);
  assert.deepEqual(f.errors, ['name required']);
  assert.equal(flow.canContinue(f), false);
  f = flow.next(flow.setDraft(f, { name: 'x' }));
  assert.equal(f.index, 2);
  assert.deepEqual(f.errors, []);
});

test('back at 0 stays 0 and back moves down otherwise', () => {
  let f = flow.createFlow(steps, { name: 'x' });
  assert.equal(flow.back(f).index, 0);
  f = flow.next(f);
  assert.equal(flow.back(f).index, 0);
});

test('progress is 1-based for display', () => {
  const seven = Array.from({ length: 7 }, (_, i) => ({ id: `s${i}`, icon: 'i', labelUk: 'у', labelEn: 'e', validate: ok }));
  const f = flow.createFlow(seven, {});
  assert.deepEqual(flow.progress(f), { index: 1, total: 7, ratio: 1 / 7 });
});

test('setDraft does not mutate previous flow or draft', () => {
  const draft = { name: '' };
  const f1 = flow.createFlow(steps, draft);
  const f2 = flow.setDraft(f1, { name: 'y' });
  assert.deepEqual(f1.draft, { name: '' });
  assert.deepEqual(draft, { name: '' });
  assert.deepEqual(f2.draft, { name: 'y' });
  assert.notEqual(f1, f2);
});

test('isLast is true only on the final step', () => {
  let f = flow.createFlow(steps, { name: 'x' });
  assert.equal(flow.isLast(f), false);
  f = flow.next(f);
  f = flow.next(f);
  assert.equal(flow.isLast(f), true);
  assert.equal(flow.next(f).index, 2);
});

test('createFlow does not mutate inputs', () => {
  const draft = { name: 'z' };
  const list = steps.slice();
  const f = flow.createFlow(list, draft);
  assert.equal(f.index, 0);
  assert.deepEqual(f.errors, []);
  assert.deepEqual(list, steps);
  assert.deepEqual(draft, { name: 'z' });
});
