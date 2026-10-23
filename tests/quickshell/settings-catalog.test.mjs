import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import test from 'node:test';
import { defaults } from '../../quickshell/logic/config.mjs';
import { readValue, commitCheck } from '../../quickshell/logic/settings-bindings.mjs';
import { validateCatalog, manifestFor, groups } from '../../quickshell/logic/settings-schema.mjs';
import { pages, groupCaptions } from '../../quickshell/logic/settings-catalog.mjs';

const iconRoot = new URL('../../quickshell/assets/icons/', import.meta.url);
const documents = () => structuredClone({ theme: defaults.theme, layout: defaults.layout, interface: defaults.interface,
  spotlight: defaults.spotlight, notifications: defaults.notifications, wallpaper: defaults.wallpaper });
const items = pages.flatMap(page => page.sections.flatMap(section => section.items.map(item => [page, item])));
const dataBearing = items.filter(([, item]) => !['button', 'link', 'value', 'panel'].includes(item.control));

test('catalog has the fifteen pages and validates', () => {
  assert.deepEqual(pages.map(page => page.id), ['appearance', 'wallpaper', 'language', 'network', 'sound', 'power', 'bar',
    'control-center', 'widgets', 'spotlight', 'notifications', 'screenshots', 'session', 'shortcuts', 'system']);
  for (const [page, item] of items.filter(([, item]) => item.control === 'panel'))
    assert.equal(page.group, 'devices', `${page.id}.${item.key} panels live on device pages`);
  const result = validateCatalog(pages);
  assert.equal(result.ok, true, JSON.stringify(result.errors));
});

test('data-bearing items read a defined default', () => {
  const docs = documents();
  for (const [page, item] of dataBearing) assert.notEqual(readValue(docs, item), undefined, `${page.id}.${item.key}`);
});

test('every option value passes commitCheck', () => {
  for (const [page, item] of items.filter(([, item]) => item.options)) {
    for (const option of item.options) {
      const result = commitCheck(documents(), item, option.value);
      assert.equal(result.ok, true, `${page.id}.${item.key}=${option.value}: ${result.message}`);
    }
  }
});

test('labels are bilingual, short, and help comes in pairs', () => {
  const check = (node, where) => {
    assert.ok(node.labelUk?.trim() && node.labelEn?.trim(), `${where} label`);
    assert.ok(node.labelUk.length <= 32 && node.labelEn.length <= 32, `${where} label too long`);
    assert.equal(Boolean(node.helpUk), Boolean(node.helpEn), `${where} help pair`);
  };
  for (const page of pages) {
    check(page, page.id);
    for (const tab of page.tabs ?? []) check(tab, `${page.id}/${tab.id}`);
    for (const section of page.sections) {
      check(section, `${page.id}/${section.id}`);
      for (const item of section.items) {
        check(item, `${page.id}.${item.key}`);
        for (const option of item.options ?? []) check(option, `${page.id}.${item.key}.${option.value}`);
      }
    }
  }
});

test('group captions exist for all four groups', () => {
  for (const group of groups) {
    assert.ok(groupCaptions[group]?.uk && groupCaptions[group]?.en, group);
    assert.ok(pages.some(page => page.group === group), group);
  }
});

test('icons exist and the emoji languages key is listed once', () => {
  for (const page of pages) assert.ok(existsSync(new URL(page.icon, iconRoot)), page.icon);
  for (const [, item] of items) if (item.icon) assert.ok(existsSync(new URL(item.icon, iconRoot)), item.icon);
  assert.equal(items.filter(([, item]) => item.document === 'spotlight' && item.path === 'emoji.languages').length, 1);
  assert.deepEqual(pages.find(page => page.id === 'spotlight').sections.flatMap(s => s.items).map(item => item.key),
    ['calculator', 'webSearch', 'webEngine', 'emojiLanguages']);
});

test('catalog defaults match the config defaults they describe', () => {
  const docs = documents();
  const at = (document, path) => path.split('.').reduce((value, key) => value == null ? undefined : value[key], docs[document]);
  for (const [page, item] of dataBearing) {
    if (item.default === undefined || !docs[item.document]) continue;
    // The wallpaper swatches share theme.accent but suggest the shipped accent as their reset value.
    if (item.key === 'wallpaperAccent') continue;
    assert.deepEqual(item.default, at(item.document, item.path), `${page.id}.${item.key}`);
  }
});

test('manifestFor works for every page', () => {
  for (const page of pages) assert.ok(Array.isArray(manifestFor(page).settingsFields));
});
