import assert from 'node:assert/strict';
import test from 'node:test';
import { isSentinel, selectedChoices, toggleChoice } from '../../quickshell/logic/settings-chips.mjs';
import { parseDocument } from '../../quickshell/logic/config.mjs';
import { pages } from '../../quickshell/logic/settings-catalog.mjs';

test('the sentinel, non-lists and empty lists all count as "auto"', () => {
  assert.equal(isSentinel('auto'), true);
  assert.equal(isSentinel(undefined), true);
  assert.equal(isSentinel([]), true);
  assert.equal(isSentinel(['uk']), false);
  assert.deepEqual(selectedChoices('auto'), []);
  assert.deepEqual(selectedChoices(['uk', 3, 'en']), ['uk', 'en']);
});

test('toggling adds in click order, removes, and falls back to the sentinel', () => {
  assert.deepEqual(toggleChoice('auto', 'uk'), ['uk']);
  assert.deepEqual(toggleChoice(['uk'], 'en'), ['uk', 'en']);
  assert.deepEqual(toggleChoice(['uk', 'en'], 'uk'), ['en']);
  assert.equal(toggleChoice(['en'], 'en'), 'auto');
  assert.equal(toggleChoice(['en'], 'en', 'none'), 'none');
});

test('every emoji language chip produces a value the spotlight document accepts', () => {
  const item = pages.find(page => page.id === 'spotlight').sections.flatMap(section => section.items)
    .find(entry => entry.key === 'emojiLanguages');
  assert.equal(item.control, 'chips');
  assert.ok(item.choices.length >= 20);
  for (const choice of item.choices) {
    const value = toggleChoice('auto', choice.value);
    const parsed = parseDocument('spotlight', JSON.stringify({ emoji: { languages: value } }));
    assert.equal(parsed.ok, true, `${choice.value}: ${parsed.message}`);
    assert.deepEqual(parsed.value.emoji.languages, value);
    assert.ok(choice.labelUk.trim() && choice.labelEn.trim(), choice.value);
  }
});
