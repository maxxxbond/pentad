import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import test from 'node:test';
import { defaults } from '../../quickshell/logic/config.mjs';
import { readValue, commitCheck } from '../../quickshell/logic/settings-bindings.mjs';
import { validateCatalog, manifestFor, groups } from '../../quickshell/logic/settings-schema.mjs';
import { pages, groupCaptions } from '../../quickshell/logic/settings-catalog.mjs';
import { search } from '../../quickshell/logic/settings-search.mjs';

const iconRoot = new URL('../../quickshell/assets/icons/', import.meta.url);
const documents = () => structuredClone({ theme: defaults.theme, layout: defaults.layout, interface: defaults.interface,
  spotlight: defaults.spotlight, notifications: defaults.notifications, wallpaper: defaults.wallpaper, models: defaults.models });
const items = pages.flatMap(page => page.sections.flatMap(section => section.items.map(item => [page, item])));
const dataBearing = items.filter(([, item]) => !['button', 'link', 'value', 'panel'].includes(item.control));

test('catalog has the twenty pages and validates', () => {
  assert.deepEqual(pages.map(page => page.id), ['appearance', 'wallpaper', 'language', 'network', 'bluetooth', 'sound', 'power', 'bar',
    'control-center', 'widgets', 'spotlight', 'notifications', 'screenshots', 'session', 'models', 'datetime', 'default-apps', 'shortcuts', 'system', 'about']);
  for (const [page, item] of items.filter(([, item]) => item.control === 'panel'))
    assert.ok(['devices', 'system'].includes(page.group), `${page.id}.${item.key} panels live on device or system pages`);
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
  // A row starts with its label on the leading line of the grid: only pages carry an icon.
  for (const [, item] of items) assert.equal(item.icon, undefined, item.key);
  assert.equal(items.filter(([, item]) => item.document === 'spotlight' && item.path === 'emoji.languages').length, 1);
  assert.deepEqual(pages.find(page => page.id === 'spotlight').sections.flatMap(s => s.items).map(item => item.key),
    ['calculator', 'webSearch', 'webEngine', 'clipboardEnter', 'pasteShortcut', 'emojiLanguages']);
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

test('the Super key symbol is one row on the Shortcuts page, found by search in both languages', () => {
  const found = items.filter(([, item]) => item.document === 'interface' && item.path === 'superKeyLogo');
  assert.equal(found.length, 1);
  const [page, item] = found[0];
  assert.equal(page.id, 'shortcuts');
  assert.equal(item.default, 'pentad');
  assert.deepEqual(item.options.map(option => option.value), ['pentad', 'tux', 'text']);
  assert.equal(readValue(documents(), item), 'pentad');
  const rejected = commitCheck(documents(), item, 'arch');
  assert.equal(rejected.ok, false);
  for (const query of ['super key', 'tux', 'penguin', 'logo', 'символ', 'пінгвін', 'логотип'])
    assert.ok(search(pages, query, 'en').some(hit => hit.pageId === 'shortcuts' && hit.key === 'superKeyLogo'), query);
});

test('manifestFor works for every page', () => {
  for (const page of pages) assert.ok(Array.isArray(manifestFor(page).settingsFields));
});

test('the Models page edits only the models document and its editors stay out of the manifest projection', () => {
  const page = pages.find(entry => entry.id === 'models');
  assert.equal(page.group, 'behavior');
  assert.ok(existsSync(new URL(page.icon, iconRoot)));
  const controls = page.sections.flatMap(section => section.items.map(item => item.control));
  assert.deepEqual(controls, ['modelsHero', 'modelProviders', 'modelRoles', 'installedModels', 'toggle', 'modelGrants', 'modelWorker']);
  for (const section of page.sections) for (const item of section.items) assert.equal(item.document, 'models', item.key);
  assert.deepEqual(manifestFor(page).settingsFields.map(field => field.key), ['localOnly']);
  const localOnly = page.sections.flatMap(section => section.items).find(item => item.key === 'localOnly');
  assert.equal(localOnly.path, 'privacy.localOnly');
  assert.equal(readValue(documents(), localOnly), false);
  const checked = commitCheck(documents(), localOnly, true);
  assert.equal(checked.ok, true);
  assert.equal(checked.name, 'models');
  assert.equal(checked.document.privacy.localOnly, true);
  assert.deepEqual(page.sections.filter(section => section.untitled).map(section => section.id), ['overview', 'providers']);
  for (const query of ['ollama', 'моделі', 'vram', 'ключ']) assert.ok(search(pages, query, 'en').some(hit => hit.pageId === 'models'), query);
});

test('model editors are refused outside the models document', () => {
  const page = { id: 'x', group: 'behavior', labelUk: 'Ікс', labelEn: 'X', keywords: [], sections: [{ id: 's', labelUk: 'С', labelEn: 'S', untitled: 'yes',
    items: [{ key: 'k', kind: 'select', control: 'modelRoles', document: 'layout', path: 'widgets', labelUk: 'Р', labelEn: 'R' }] }] };
  const result = validateCatalog([page]);
  assert.equal(result.ok, false);
  assert.ok(result.errors.some(error => /requires document models/.test(error)));
  assert.ok(result.errors.some(error => /untitled must be a boolean/.test(error)));
});
