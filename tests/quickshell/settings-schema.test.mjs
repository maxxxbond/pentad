import assert from 'node:assert/strict';
import test from 'node:test';
import { validateSettings } from '../../quickshell/logic/plugin-manifest.mjs';
import { controls, framelessControls, fullBleedControls, groups, manifestFor, modelControls, validateCatalog } from '../../quickshell/logic/settings-schema.mjs';

const item = (key, extra = {}) => ({ key, kind: 'boolean', control: 'toggle', document: 'layout', path: `bar.${key}`, labelUk: key, labelEn: key, default: false, ...extra });
const page = (id, items, extra = {}) => ({ id, group: 'shell', icon: 'tune', labelUk: id, labelEn: id, keywords: [], sections: [{ id: 's', labelUk: 's', labelEn: 's', items }], ...extra });
const valid = () => [
  page('bar', [
    item('showSeconds'),
    item('density', { kind: 'select', control: 'segmented', default: 'compact', options: [{ value: 'compact', labelUk: 'К', labelEn: 'Compact' }, { value: 'wide', labelUk: 'Ш', labelEn: 'Wide' }] }),
    item('barHeight', { kind: 'integer', control: 'slider', default: 40, min: 32, max: 64, step: 2 }),
    item('secondsFormat', { kind: 'text', control: 'text', default: 'ss', visibleWhen: { key: 'showSeconds', equals: true } }),
    item('openShots', { kind: 'text', control: 'button', action: 'screenshots.open' }),
  ]),
  page('system', [item('x')], { group: 'system' }),
];
const errorsOf = pages => { const r = validateCatalog(pages); assert.equal(r.ok, false); return r.errors.join('\n'); };
const withItem = (extra) => { const p = valid(); p[0].sections[0].items.push(item('extra', extra)); return p; };

test('exports', () => {
  assert.deepEqual([...groups], ['personalization', 'devices', 'shell', 'behavior', 'system']);
  assert.equal(controls.length, 28);
  assert.deepEqual([...modelControls], ['modelsHero', 'modelProviders', 'modelRoles', 'installedModels', 'modelGrants', 'modelWorker']);
  for (const name of modelControls) assert.ok(controls.includes(name) && fullBleedControls.includes(name), name);
  assert.deepEqual(framelessControls.filter(name => modelControls.includes(name)), ['modelsHero', 'modelProviders', 'modelRoles', 'installedModels']);
});
test('valid catalog passes', () => assert.deepEqual(validateCatalog(valid()), { ok: true }));
test('a device panel needs a known panel and no document', () => {
  const panel = { kind: 'text', control: 'panel', document: undefined, path: undefined };
  assert.deepEqual(validateCatalog(withItem(Object.assign({}, panel, { panel: 'wifi' }))), { ok: true });
  assert.match(errorsOf(withItem(Object.assign({}, panel, { panel: 'printer' }))), /panel requires one of/);
  assert.equal(manifestFor(withItem(Object.assign({}, panel, { panel: 'sound' }))[0]).settingsFields.some(field => field.key === 'extra'), false);
});
test('duplicate page id fails', () => { const p = valid(); p[1].id = 'bar'; assert.match(errorsOf(p), /duplicate page id: bar/); });
test('duplicate item key within a page fails', () => { const p = valid(); p[0].sections[0].items.push(item('showSeconds')); assert.match(errorsOf(p), /duplicate item key: showSeconds/); });
test('unknown control fails', () => assert.match(errorsOf(withItem({ control: 'knob' })), /control is invalid/));
test("control 'toggle' requires kind 'boolean'", () => assert.match(errorsOf(withItem({ kind: 'text' })), /toggle requires kind boolean/));
test("'segmented' and 'dropdown' require options", () => {
  for (const control of ['segmented', 'dropdown']) assert.match(errorsOf(withItem({ kind: 'select', control, options: undefined })), /requires options/);
});
test("'slider' requires min < max and step > 0", () => {
  assert.match(errorsOf(withItem({ kind: 'integer', control: 'slider', min: 5, max: 5, step: 1 })), /min < max/);
  assert.match(errorsOf(withItem({ kind: 'integer', control: 'slider', min: 1, max: 5, step: 0 })), /step > 0/);
});
test('visibleWhen must reference an existing key on the same page', () => {
  assert.match(errorsOf(withItem({ visibleWhen: { key: 'nope', equals: true } })), /visibleWhen/);
});
test('manifestFor skips button/link/value items and output validates via validateSettings', () => {
  const manifest = manifestFor(valid()[0]);
  assert.deepEqual(manifest.settingsFields.map(f => f.key), ['showSeconds', 'density', 'barHeight', 'secondsFormat']);
  assert.equal(manifest.settingsFields[0].label, 'showSeconds');
  assert.equal(manifest.defaults.barHeight, 40);
  assert.equal(validateSettings(manifest, {}).ok, true);
  assert.equal(validateSettings(manifest, { barHeight: 99 }).ok, false);
  assert.equal(validateSettings(manifest, { density: 'huge' }).ok, false);
});

const opts = [{ value: 'a', labelUk: 'А', labelEn: 'A', art: 'dark' }, { value: 'b', labelUk: 'Б', labelEn: 'B' }];
test('new controls validate and project to manifest kinds', () => {
  const p = valid();
  p[0].sections[0].collapsible = true;
  p[0].sections[0].items.push(
    item('look', { kind: 'select', control: 'cards', default: 'a', options: opts }),
    item('tint', { kind: 'color', control: 'color', default: '#869677' }),
    item('hotkey', { kind: 'text', control: 'shortcut', default: 'Super+Space' }),
    item('order', { kind: 'select', control: 'list', default: undefined }),
    item('gap', { kind: 'integer', control: 'slider', default: 4, min: 0, max: 8, step: 1, unit: 'px' }),
    item('slug', { kind: 'text', control: 'text', default: '', prefix: '@' }),
  );
  assert.deepEqual(validateCatalog(p), { ok: true });
  const manifest = manifestFor(p[0]);
  const byKey = Object.fromEntries(manifest.settingsFields.map(f => [f.key, f]));
  assert.equal(byKey.look.kind, 'select');
  assert.equal(byKey.look.options.length, 2);
  assert.equal(byKey.tint.kind, 'color');
  assert.equal(byKey.hotkey.kind, 'text');
  assert.equal(byKey.order, undefined);
  assert.equal(validateSettings(manifest, { look: 'zzz' }).ok, false);
  assert.equal(validateSettings(manifest, { tint: 'red' }).ok, false);
  assert.equal(validateSettings(manifest, { look: 'b', tint: '#112233', hotkey: 'Alt+Tab' }).ok, true);
});
test('new control constraints are enforced', () => {
  assert.match(errorsOf(withItem({ kind: 'select', control: 'cards', options: undefined })), /cards requires options/);
  assert.match(errorsOf(withItem({ kind: 'text', control: 'cards', options: opts })), /cards requires kind select/);
  assert.match(errorsOf(withItem({ kind: 'text', control: 'color' })), /color requires kind color/);
  assert.match(errorsOf(withItem({ kind: 'text', control: 'shortcut', default: 'A' })), /valid shortcut/);
  assert.match(errorsOf(withItem({ kind: 'boolean', control: 'shortcut' })), /shortcut requires kind text/);
  assert.match(errorsOf(withItem({ kind: 'text', control: 'list' })), /list requires kind select/);
  assert.match(errorsOf(withItem({ unit: 'px' })), /unit requires/);
  assert.match(errorsOf(withItem({ prefix: '@' })), /prefix requires/);
  assert.match(errorsOf(withItem({ kind: 'select', control: 'cards', options: [{ value: 'a', labelUk: 'А', labelEn: 'A', art: '' }] })), /art must be/);
  const p = valid(); p[0].sections[0].collapsible = 'yes';
  assert.match(errorsOf(p), /collapsible must be a boolean/);
});
