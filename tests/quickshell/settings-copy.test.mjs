import test from 'node:test';
import assert from 'node:assert/strict';
import { pages, groupCaptions } from '../../quickshell/logic/settings-catalog.mjs';

const MAX_LABEL = 32;

const SAME_IN_BOTH = new Set([
  'Spotlight',
  'English',
  // Product names are not translated.
  'Bluetooth',
  'Wi-Fi',
  'DeepL',
  'trans',
  'Google Lens',
  'Yandex',
  'Bing',
  'TinEye',
  'Baidu',
  'Sogou',
  'SauceNAO',
  'IQDB',
  'ascii2d',
  'DuckDuckGo',
  'Google',
  'Brave Search',
  'Startpage',
  'Ecosia',
  // Zoom factors.
  '×2',
  '×3',
  '×4',
  '×6',
  '×8',
  // Language and color-format codes.
  'HEX',
  'RGB',
  'HSL',
  'HSV',
  'CMYK',
  'UK',
  'EN-US',
  'EN-GB',
  'DE',
  'PL',
  'FR',
  'ES',
  'IT',
  'PT-PT',
  'CS',
  'JA',
  'ZH',
]);

function collect() {
  const out = [];
  const add = (where, uk, en, kind) => out.push({ where, uk, en, kind });
  for (const [group, caption] of Object.entries(groupCaptions)) add(`group ${group}`, caption.uk, caption.en, 'label');
  for (const page of pages) {
    add(`page ${page.id}`, page.labelUk, page.labelEn, 'label');
    for (const tab of page.tabs || []) add(`tab ${page.id}/${tab.id}`, tab.labelUk, tab.labelEn, 'label');
    for (const section of page.sections) {
      const s = `section ${page.id}/${section.id}`;
      add(s, section.labelUk, section.labelEn, 'label');
      if ('helpUk' in section || 'helpEn' in section) add(`${s} help`, section.helpUk, section.helpEn, 'help');
      for (const item of section.items) {
        const i = `item ${page.id}/${item.key}`;
        add(i, item.labelUk, item.labelEn, 'label');
        if ('helpUk' in item || 'helpEn' in item) add(`${i} help`, item.helpUk, item.helpEn, 'help');
        for (const option of item.options || []) add(`${i} option ${option.value}`, option.labelUk, option.labelEn, 'label');
        for (const choice of item.choices || []) add(`${i} choice ${choice.value}`, choice.labelUk, choice.labelEn, 'label');
        if ('sentinelUk' in item || 'sentinelEn' in item) add(`${i} sentinel`, item.sentinelUk, item.sentinelEn, 'label');
      }
    }
  }
  return out;
}

const entries = collect();

test('the collector sees groups, pages, sections, items and options', () => {
  assert.ok(entries.length > 60, `only ${entries.length} pairs collected`);
  assert.ok(entries.some((e) => e.where.startsWith('group ')));
  assert.ok(entries.some((e) => e.where.includes(' option ')));
  assert.ok(entries.some((e) => e.kind === 'help'));
});

test('every Uk/En pair is a non-empty string', () => {
  const bad = entries.filter((e) => [e.uk, e.en].some((s) => typeof s !== 'string' || s.trim() === ''));
  assert.deepEqual(bad.map((e) => e.where), []);
});

test('help texts come in pairs', () => {
  const bad = entries.filter((e) => e.kind === 'help' && !!e.uk !== !!e.en);
  assert.deepEqual(bad.map((e) => e.where), []);
});

test('Ukrainian differs from English unless allow-listed', () => {
  const bad = entries.filter((e) => e.uk === e.en && !SAME_IN_BOTH.has(e.en));
  assert.deepEqual(bad.map((e) => `${e.where}: ${e.en}`), []);
});

test('the allow-list has no stale entries', () => {
  const used = new Set(entries.filter((e) => e.uk === e.en).map((e) => e.en));
  assert.deepEqual([...SAME_IN_BOTH].filter((s) => !used.has(s)), []);
});

test(`no label exceeds ${MAX_LABEL} characters in either language`, () => {
  const bad = entries.filter((e) => e.kind === 'label' && (e.uk.length > MAX_LABEL || e.en.length > MAX_LABEL));
  assert.deepEqual(bad.map((e) => `${e.where}: ${e.uk} / ${e.en}`), []);
});

test('Ukrainian copy contains Cyrillic unless allow-listed', () => {
  const bad = entries.filter((e) => !/[Ѐ-ӿ]/.test(e.uk) && !SAME_IN_BOTH.has(e.uk));
  assert.deepEqual(bad.map((e) => `${e.where}: ${e.uk}`), []);
});
