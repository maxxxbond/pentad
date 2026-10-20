import assert from 'node:assert/strict';
import test from 'node:test';
import { enabledWidgetCount, isResettable, modifiedItems } from '../../quickshell/logic/settings-state.mjs';

const page = { sections: [{ items: [
  { key: 'a', document: 'layout', path: 'barHeight', control: 'slider', default: 40 },
  { key: 'b', document: 'layout', path: 'showSeconds', control: 'toggle', default: false },
  { key: 'c', document: 'layout', path: 'barHeight', control: 'button', default: 1 },
  { key: 'd', document: 'layout', path: 'trayIcons', control: 'segmented' },
] }] };

test('isResettable needs a document, a default and a non-action control', () => {
  assert.equal(isResettable(page.sections[0].items[0]), true);
  assert.equal(isResettable(page.sections[0].items[2]), false);
  assert.equal(isResettable(page.sections[0].items[3]), false);
  assert.equal(isResettable(null), false);
});

test('modifiedItems lists only resettable items that differ from the default', () => {
  assert.deepEqual(modifiedItems({ layout: { barHeight: 40, showSeconds: false } }, page), []);
  const items = modifiedItems({ layout: { barHeight: 48, showSeconds: true } }, page);
  assert.deepEqual(items.map(item => item.key), ['a', 'b']);
  assert.deepEqual(modifiedItems({}, null), []);
});

test('enabledWidgetCount counts placements that are not disabled', () => {
  assert.equal(enabledWidgetCount({ layout: { widgets: [{ enabled: true }, { enabled: false }, {}] } }), 2);
  assert.equal(enabledWidgetCount({}), 0);
});
