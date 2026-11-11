import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import {
  zones, zoneIds, zoneSlots, slotsFor, zonesForSlots, normalizeZones, canClear, toggleZone, pentadSlotErrors,
  validatePlacementSettings, resolvePlacement, innerRadius, sizesFor, defaultSize,
} from '../../quickshell/logic/pentads.mjs';
import { validateManifest, validateSettings, widgetSlots } from '../../quickshell/logic/plugin-manifest.mjs';
import { widgetSettingsPage } from '../../quickshell/logic/widget-settings.mjs';
import { validateCatalog } from '../../quickshell/logic/settings-schema.mjs';
import { parseDocument, defaults } from '../../quickshell/logic/config.mjs';

const base = { id: 'pentad.demo', name: 'Demo', version: '1.0.0', apiVersion: 1, entry: 'View.qml', allowedSlots: ['system'], pentads: ['right'] };

test('five sections in canonical order with a complete slot mapping', () => {
  assert.deepEqual(zoneIds, ['left-menu', 'left', 'center', 'right', 'right-menu']);
  assert.deepEqual(Object.keys(zoneSlots), zoneIds);
  const mapped = zoneIds.flatMap(id => zoneSlots[id]);
  assert.equal(new Set(mapped).size, mapped.length, 'a slot belongs to one section');
  assert.deepEqual([...mapped].sort(), [...widgetSlots].sort(), 'every widget slot is reachable');
  assert.deepEqual(zones.filter(z => z.kind === 'menu').map(z => z.id), ['left-menu', 'right-menu']);
});

test('slotsFor and zonesForSlots round trip through the table', () => {
  assert.deepEqual(slotsFor(['right', 'left-menu']), ['sidebar-left', 'tools', 'system']);
  assert.deepEqual(slotsFor([]), []);
  assert.deepEqual(zonesForSlots(['system', 'sidebar-right', 'sidebar-left']), ['left-menu', 'right', 'right-menu']);
  assert.deepEqual(zonesForSlots(undefined), []);
});

test('normalizeZones keeps known allowed sections in order and never returns empty', () => {
  assert.deepEqual(normalizeZones(['right', 'left', 'bogus', 'left'], ['left', 'right']), ['left', 'right']);
  assert.deepEqual(normalizeZones([], ['center', 'left']), ['left']);
  assert.deepEqual(normalizeZones(undefined, ['center', 'left'], 'center'), ['center']);
  assert.deepEqual(normalizeZones(['right'], ['center']), ['center']);
});

test('the last active section cannot be cleared', () => {
  assert.equal(canClear(['center'], 'center'), false);
  assert.equal(canClear(['center', 'left'], 'center'), true);
  assert.equal(canClear(['center'], 'left'), true);
  assert.deepEqual(toggleZone(['center'], 'center', ['center', 'left']), { ok: false, zones: ['center'], error: 'last' });
  assert.deepEqual(toggleZone(['center'], 'left', ['center', 'left']), { ok: true, zones: ['left', 'center'] });
  assert.deepEqual(toggleZone(['left', 'center'], 'left', ['center', 'left']), { ok: true, zones: ['center'] });
  assert.equal(toggleZone(['center'], 'right', ['center', 'left']).error, 'unsupported');
  assert.equal(toggleZone(['center'], 'nope').error, 'unsupported');
});

test('placement settings validate structurally and ignore ordinary keys', () => {
  assert.deepEqual(validatePlacementSettings({ city: 'x' }), { ok: true, value: {} });
  const good = { _zones: ['right', 'left'], _margin: 12, _padding: 0, _bg: 'solid', _order_left: 9, _size_left: 'full', _size_right: 'label' };
  assert.deepEqual(validatePlacementSettings(good), { ok: true, value: { _zones: ['left', 'right'], _margin: 12, _padding: 0, _bg: 'solid', _order_left: 9, _size_left: 'full', _size_right: 'label' } });
  for (const bad of [{ _zones: [] }, { _zones: ['left', 'left'] }, { _zones: ['nope'] }, { _zones: 'left' }, { _margin: 6 }, { _margin: 20 }, { _padding: 16 }, { _bg: 'glass' },
    { _order_left: 0 }, { _order_left: 10 }, { _order_left: 1.5 }, { _size_left: 'tile' }, { _order_nope: 1 }, { _unknown: 1 }, { _size_center: 'row' }])
    assert.equal(validatePlacementSettings(bad).ok, false, JSON.stringify(bad));
  assert.equal(validatePlacementSettings({ _size_left: 'tile' }).ok, false, 'bar sections have no tile size');
  assert.equal(validatePlacementSettings({ '_size_right-menu': 'tile' }).ok, true);
  assert.equal(validatePlacementSettings({ _zones: ['left'] }, { allowed: ['center'] }).ok, false);
  assert.equal(validatePlacementSettings(null).ok, false);
});

test('resolvePlacement fills defaults, falls back to the legacy slot and ignores bad values', () => {
  const manifest = { pentads: ['right', 'left-menu'], allowedSlots: ['system', 'sidebar-left'] };
  const r = resolvePlacement(manifest, {}, 'sidebar-left');
  assert.deepEqual(r.zones, ['left-menu']);
  assert.equal(r.margin, 0); assert.equal(r.padding, 0); assert.equal(r.bg, 'none');
  assert.equal(r.size['left-menu'], 'row'); assert.equal(r.size.right, 'icon'); assert.equal(r.order.right, 1);
  assert.deepEqual(resolvePlacement(manifest, {}).zones, ['left-menu'], 'first allowed without a legacy slot');
  assert.deepEqual(resolvePlacement(manifest, { _zones: ['center'], _margin: 7 }, 'system').zones, ['right']);
  assert.equal(resolvePlacement(manifest, { _margin: 7 }).margin, 0);
  assert.deepEqual(resolvePlacement(manifest, { _zones: ['right', 'left-menu'], _size_right: 'full' }).size.right, 'full');
  assert.deepEqual(resolvePlacement({ allowedSlots: ['center'] }).zones, ['center'], 'derives sections for legacy manifests');
});

test('concentric radius law: inner radius is outer minus padding', () => {
  assert.equal(innerRadius(8, 14), 6);
  assert.equal(innerRadius(0, 14), 14);
  assert.equal(innerRadius(12, 14), 2);
  assert.equal(innerRadius(16, 14), 0);
  assert.deepEqual([sizesFor('left-menu'), sizesFor('center')], [['icon', 'row', 'tile'], ['icon', 'label', 'full']]);
  assert.deepEqual([defaultSize('right-menu'), defaultSize('left')], ['row', 'icon']);
});

test('manifest pentads: required for new widgets, optional for legacy, checked when present', () => {
  const { pentads, ...legacy } = base;
  assert.equal(validateManifest(legacy).ok, true);
  assert.match(validateManifest(legacy, { requirePentads: true }).errors.join(' '), /pentads/);
  assert.equal(validateManifest(base, { requirePentads: true }).ok, true);
  for (const bad of [[], ['nope'], ['right', 'right'], 'right', null])
    assert.match(validateManifest({ ...base, pentads: bad }).errors.join(' '), /pentads must be a unique non-empty array/, JSON.stringify(bad));
});

test('manifest pentads must agree with allowedSlots through the mapping table', () => {
  assert.match(validateManifest({ ...base, pentads: ['center'] }).errors.join(' '), /center has no matching slot/);
  assert.match(validateManifest({ ...base, allowedSlots: ['system', 'sidebar-left'] }).errors.join(' '), /sidebar-left is not covered/);
  assert.equal(validateManifest({ ...base, allowedSlots: ['system', 'tools'] }).ok, true);
  assert.deepEqual(pentadSlotErrors(['left', 'right'], ['telemetry', 'system']), []);
});

test('reserved keys starting with _ are rejected in manifests and not declarable in settings', () => {
  const field = { key: '_zones', kind: 'text', label: 'x' };
  assert.match(validateManifest({ ...base, settingsFields: [field] }).errors.join(' '), /reserved/);
  const manifest = { ...base, defaults: { a: 'x' }, settingsFields: [{ key: 'a', kind: 'text', label: 'A' }] };
  assert.equal(validateSettings(manifest, { a: 'y', _margin: 4, _zones: ['right'] }).ok, true);
  assert.equal(validateSettings(manifest, { _margin: 5 }).ok, false);
  const { pentads: _omit, ...noPentads } = manifest;
  assert.equal(validateSettings(noPentads, { _zones: ['center'] }).ok, true, 'structural only without manifest.pentads');
  assert.equal(validateSettings(manifest, { _zones: [] }).ok, false);
  assert.equal(validateSettings({ ...manifest, pentads: ['right'] }, { _zones: ['center'] }).ok, false, 'zones limited to the manifest');
  assert.equal(validateSettings(manifest, { nope: 1 }).ok, false);
});

test('every builtin widget manifest declares pentads consistent with allowedSlots', async () => {
  const dirs = await readdir(new URL('../../quickshell/widgets/', import.meta.url));
  let count = 0;
  for (const dir of dirs) {
    let text;
    try { text = await readFile(new URL(`../../quickshell/widgets/${dir}/manifest.json`, import.meta.url), 'utf8'); } catch { continue; }
    const manifest = JSON.parse(text);
    const result = validateManifest(manifest, { requirePentads: true });
    assert.equal(result.ok, true, `${dir}: ${result.errors}`);
    assert.deepEqual(manifest.pentads, zonesForSlots(manifest.allowedSlots), `${dir} pentads match the mapping`);
    count++;
  }
  assert.ok(count >= 12);
});

test('config accepts valid placement settings and rejects invalid ones', () => {
  const doc = widgets => JSON.stringify({ ...defaults.layout, widgets });
  const placement = settings => ({ instanceId: 'a', moduleId: 'pentad.clock', slot: 'system', enabled: true, settings });
  const ok = parseDocument('layout', doc([placement({ defaultDurationSeconds: 60, _zones: ['right'], _margin: 4, _bg: 'none' })]));
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.value.widgets[0].settings._zones, ['right']);
  assert.equal(parseDocument('layout', doc([placement({})])).ok, true, 'legacy placements still load');
  for (const bad of [{ _zones: [] }, { _margin: 3 }, { _bg: 'x' }, { _other: 1 }]) {
    const result = parseDocument('layout', doc([placement(bad)]));
    assert.equal(result.ok, false, JSON.stringify(bad));
    assert.match(result.message, /placement settings/);
  }
  assert.equal(parseDocument('layout', JSON.stringify(defaults.layout)).ok, true);
});

const manifestWithFields = {
  ...base, allowedSlots: ['system', 'sidebar-left', 'center'], pentads: ['left-menu', 'center', 'right'],
  defaults: { greeting: 'hi', big: true, mode: 'a', n: 3, tint: '#112233' },
  settingsFields: [
    { key: 'greeting', kind: 'text', label: 'Greeting', labelUk: 'Привітання' },
    { key: 'big', kind: 'boolean', label: 'Big' },
    { key: 'mode', kind: 'select', label: 'Mode', options: [{ value: 'a', label: 'A' }, { value: 'b', label: 'B' }], showWhen: { key: 'big', equals: true } },
    { key: 'n', kind: 'integer', label: 'Count', min: 1, max: 9 },
    { key: 'tint', kind: 'color', label: 'Tint', group: 'Style' },
  ],
};

test('widget settings page: General and Placement tabs, Frame group and per-section items', () => {
  const page = widgetSettingsPage(manifestWithFields, { pathPrefix: 'widgets.2.settings', settings: { _zones: ['center', 'left-menu'] } });
  assert.deepEqual(page.tabs.map(t => t.id), ['general', 'placement']);
  const byId = Object.fromEntries(page.sections.map(s => [s.id, s]));
  assert.deepEqual(Object.keys(byId), ['group-settings', 'group-Style', 'frame', 'placement', 'zone-left-menu', 'zone-center']);
  assert.equal(byId.frame.tab, 'general');
  assert.deepEqual(byId.frame.items.map(i => i.key), ['_framePreview', '_margin', '_padding', '_bg']);
  const items = Object.fromEntries(page.sections.flatMap(s => s.items).map(i => [i.key, i]));
  assert.equal(items.greeting.labelUk, 'Привітання'); assert.equal(items.greeting.labelEn, 'Greeting');
  assert.equal(items.greeting.path, 'widgets.2.settings.greeting'); assert.equal(items.greeting.document, 'layout');
  assert.equal(items.big.control, 'toggle'); assert.equal(items.mode.control, 'segmented');
  assert.deepEqual(items.mode.visibleWhen, { key: 'big', equals: true });
  assert.equal(items.n.control, 'stepper'); assert.equal(items.tint.control, 'color'); assert.equal(items.tint.default, '#112233');
  assert.deepEqual([items._margin.min, items._margin.max, items._margin.step, items._margin.default], [0, 16, 4, 0]);
  assert.deepEqual([items._padding.min, items._padding.max, items._padding.step], [0, 12, 4]);
  assert.deepEqual(items._bg.options.map(o => o.value), ['none', 'subtle', 'solid']);
  assert.equal(items._zones.control, 'pentads'); assert.deepEqual(items._zones.allowed, ['left-menu', 'center', 'right']);
  assert.deepEqual(items._zones.default, ['left-menu']);
  assert.deepEqual(items['_size_left-menu'].options.map(o => o.value), ['icon', 'row', 'tile']);
  assert.deepEqual(items['_size_center'].options.map(o => o.value), ['icon', 'label', 'full']);
  assert.equal(items['_size_center'].default, 'icon'); assert.equal(items['_size_left-menu'].default, 'row');
  assert.deepEqual([items['_order_center'].min, items['_order_center'].max], [1, 9]);
  assert.equal(items['_order_right'], undefined, 'inactive sections have no Position/Size');
});

test('widget settings page: no manifest fields still yields Frame and Placement; defaults to the legacy slot', () => {
  const page = widgetSettingsPage({ ...base, settingsFields: undefined }, { slot: 'system' });
  assert.deepEqual(page.sections.map(s => s.id), ['frame', 'placement', 'zone-right']);
  const wide = widgetSettingsPage(manifestWithFields, { slot: 'sidebar-left' });
  assert.deepEqual(wide.sections.filter(s => s.id.startsWith('zone-')).map(s => s.id), ['zone-left-menu']);
});

test('widget editor and runtime agree on manifest defaults, including falsy values', () => {
  const manifest = {
    ...base,
    defaults: { greeting: '', enabled: false, count: 0 },
    settingsFields: [
      { key: 'greeting', kind: 'text', label: 'Greeting', default: 'field' },
      { key: 'enabled', kind: 'boolean', label: 'Enabled', default: true },
      { key: 'count', kind: 'integer', label: 'Count', default: 5 },
      { key: 'fieldOnly', kind: 'text', label: 'Field only', default: 'fallback' },
    ],
  };
  const runtime = validateSettings(manifest, {});
  assert.equal(runtime.ok, true);
  const items = widgetSettingsPage(manifest).sections.flatMap(section => section.items);
  for (const field of manifest.settingsFields) {
    assert.equal(items.find(item => item.key === field.key).default, runtime.settings[field.key], field.key);
  }
  assert.equal(validateSettings(manifest, { greeting: 'saved' }).settings.greeting, 'saved');
});

test('widget settings page: copy is Uk/En paired, keys unique, only new controls are unknown to the schema', () => {
  const page = widgetSettingsPage(manifestWithFields, { settings: { _zones: ['left-menu', 'center', 'right'] } });
  const keys = page.sections.flatMap(s => s.items.map(i => i.key));
  assert.equal(new Set(keys).size, keys.length);
  for (const item of page.sections.flatMap(s => s.items)) {
    assert.ok(item.labelUk && item.labelEn, item.key);
    for (const option of item.options ?? []) assert.ok(option.labelUk && option.labelEn, `${item.key}.${option.value}`);
  }
  const result = validateCatalog([page]);
  assert.deepEqual(result.errors ?? [], []);
});
