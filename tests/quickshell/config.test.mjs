import assert from 'node:assert/strict';
import test from 'node:test';
import { defaults, parseDocument, slots } from '../../quickshell/logic/config.mjs';
import { widgetSlots, validateManifest } from '../../quickshell/logic/plugin-manifest.mjs';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('config module uses syntax accepted by Qt', (t) => {
  const args = [fileURLToPath(new URL('../../quickshell/logic/config.mjs', import.meta.url))];
  const options = { encoding: 'utf8', timeout: 10000 };
  let result = spawnSync('qmllint', args, options);
  if (result.error?.code === 'ENOENT') result = spawnSync('/usr/lib/qt6/bin/qmllint', args, options);
  if (result.error?.code === 'ENOENT') return t.skip('qmllint is unavailable');
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
});

test('Spotlight retains emoji preferences and rejects unsupported languages', () => {
  assert.deepEqual(parseDocument('spotlight', '{}').value, defaults.spotlight);
  assert.deepEqual(parseDocument('spotlight', '{"emoji":{"languages":["uk_UA","de","uk"]}}').value.emoji.languages, ['uk', 'de']);
  assert.equal(parseDocument('spotlight', '{"emoji":{"languages":["unsupported"]}}').ok, false);
  assert.equal(parseDocument('spotlight', '{"emoji":{"languages":[]}}').ok, false);
});

test('migration preserves unknown placements and settings while normalizing legacy zones', () => {
  const result = parseDocument('layout', JSON.stringify({ ...defaults.layout, widgets: [
    { instanceId: 'author-instance', moduleId: 'author.unknown', slot: 'left', enabled: true, settings: { custom: 7 } },
  ] }));
  assert.equal(result.ok, true);
  assert.deepEqual(result.value.widgets[0], { instanceId: 'author-instance', moduleId: 'author.unknown', slot: 'telemetry', enabled: true, settings: { custom: 7 } });
  assert.equal(parseDocument('layout', JSON.stringify({ ...result.value, widgets: [result.value.widgets[0], result.value.widgets[0]] })).ok, false);
});
test('invalid reload produces an error, never a substituted successful config', () => {
  assert.equal(parseDocument('theme', '{broken').ok, false);
  assert.equal(parseDocument('theme', JSON.stringify({ ...defaults.theme, accent: 'red' })).ok, false);
  assert.equal(parseDocument('layout', '{"schemaVersion":2}').ok, false);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, clockLayout: 'diagonal' })).ok, false);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, clockLayout: 'emphasis' })).ok, true);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, clockSize: 30 })).ok, false);
  assert.equal(parseDocument('layout', '{"schemaVersion":1,"barHeight":40}').value.widgets[3].instanceId, 'clock-main');
});
test('clock, battery, workspace, interface and Spotlight options are validated and default for old documents', () => {
  const layout = parseDocument('layout', '{"schemaVersion":1,"barHeight":40}').value;
  assert.deepEqual([layout.clockFormat, layout.clockDate, layout.showBatteryPercent, layout.workspaceCount], ['24h', 'day-month', false, 5]);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, clockFormat: '12h', clockDate: 'month-day' })).ok, true);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, clockFormat: '36h' })).ok, false);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, clockDate: 'long' })).ok, false);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, showBatteryPercent: 'yes' })).ok, false);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, workspaceCount: 9 })).ok, false);
  assert.equal(parseDocument('layout', JSON.stringify({ ...defaults.layout, workspaceCount: 1 })).ok, true);

  assert.deepEqual(parseDocument('interface', '{"language":"uk"}').value,
    { language: 'uk', firstDayOfWeek: 'auto', levelOverlay: true, notificationTimeout: 7, notificationPopups: 3, barMenus: 'speed' });
  assert.equal(parseDocument('interface', '{"firstDayOfWeek":"sunday","levelOverlay":false}').ok, true);
  assert.equal(parseDocument('interface', '{"firstDayOfWeek":"friday"}').ok, false);
  assert.equal(parseDocument('interface', '{"levelOverlay":1}').ok, false);
  assert.equal(parseDocument('interface', '{"notificationTimeout":1}').ok, false);
  assert.equal(parseDocument('interface', '{"notificationPopups":6}').ok, false);

  // Bar menus: an interface document written before the setting existed keeps every value and gets
  // the default; the saved choice survives a round trip; anything else is rejected.
  const older = { language: 'en', firstDayOfWeek: 'monday', levelOverlay: false, notificationTimeout: 12, notificationPopups: 2 };
  assert.deepEqual(parseDocument('interface', JSON.stringify(older)).value, Object.assign({}, older, { barMenus: 'speed' }));
  const memory = parseDocument('interface', JSON.stringify(Object.assign({}, older, { barMenus: 'memory' })));
  assert.equal(memory.ok, true);
  assert.deepEqual(memory.value, Object.assign({}, older, { barMenus: 'memory' }));
  assert.equal(parseDocument('interface', JSON.stringify(memory.value)).value.barMenus, 'memory');
  assert.equal(parseDocument('interface', '{"barMenus":"fast"}').ok, false);
  assert.equal(parseDocument('interface', '{"barMenus":true}').ok, false);

  assert.deepEqual(parseDocument('spotlight', '{"emoji":{"languages":["uk"]}}').value,
    { emoji: { languages: ['uk'] }, calculator: true, webSearch: true, webEngine: 'duckduckgo' });
  assert.equal(parseDocument('spotlight', '{"webSearch":false,"webEngine":"brave"}').value.webEngine, 'brave');
  assert.equal(parseDocument('spotlight', '{"webEngine":"altavista"}').ok, false);
  assert.equal(parseDocument('spotlight', '{"calculator":"no"}').ok, false);
});
test('legacy weather location settings migrate to widget fields without changing placement identity', () => {
  const result = parseDocument('layout', JSON.stringify({ ...defaults.layout, widgets: [
    { instanceId: 'weather-main', moduleId: 'pentad.weather', slot: 'sidebar-left', enabled: true,
      settings: { location: { name: 'Kyiv', country: 'Ukraine', region: 'Kyiv City', latitude: 50.45,
        longitude: 30.52, timezone: 'Europe/Kyiv' }, units: 'fahrenheit' } },
  ] }));
  assert.equal(result.ok, true);
  assert.deepEqual(result.value.widgets[0], { instanceId: 'weather-main', moduleId: 'pentad.weather',
    slot: 'sidebar-left', enabled: true, settings: { city: 'Kyiv', country: 'Ukraine', region: 'Kyiv City',
      latitude: 50.45, longitude: 30.52, timezone: 'Europe/Kyiv', units: 'fahrenheit' } });
});
test('organizer state is strict and preserves its bounded document shape', () => {
  const value = { schemaVersion: 1, tab: 'tasks', collapsed: true,
    tasks: [{ id: 'one', text: 'Task', done: false, createdAt: 10 }] };
  assert.deepEqual(parseDocument('organizer', JSON.stringify(value)), { ok: true, value });
  assert.equal(parseDocument('organizer', JSON.stringify({ ...value, tasks: [
    value.tasks[0], value.tasks[0],
  ] })).ok, false);
});

test('Tailscale is a VPN profile: the default menu has no launcher and saved launcher placements are dropped', () => {
  assert.equal(defaults.layout.controlCenter.items.some(item => item.definitionId === 'tailscale'), false);
  const layout = structuredClone(defaults.layout);
  layout.controlCenter.items.push({ instanceId: 'tailscale', definitionId: 'tailscale', template: 'compact',
    columnSpan: 3, rowSpan: 1, visible: true });
  const original = defaults.layout.controlCenter.items;
  const result = parseDocument('layout', JSON.stringify(layout));
  assert.equal(result.ok, true);
  assert.deepEqual(result.value.controlCenter.items, original);
  assert.equal(parseDocument('layout', JSON.stringify(result.value)).value.controlCenter.items.length, original.length);
  layout.controlCenter.items.push({ instanceId: 'x', definitionId: 'record', template: 'icon',
    columnSpan: 1, rowSpan: 1, visible: true });
  assert.equal(parseDocument('layout', JSON.stringify(layout)).ok, false);
});

test('full custom menus stay valid without exceeding placement capacity', () => {
  const layout = structuredClone(defaults.layout);
  layout.controlCenter.items = Array.from({ length: 64 }, (_, i) => ({
    instanceId: 'wifi-' + i, definitionId: 'network', template: 'icon', columnSpan: 1, rowSpan: 1, visible: true,
  }));
  const result = parseDocument('layout', JSON.stringify(layout));
  assert.equal(result.ok, true);
  assert.deepEqual(result.value.controlCenter.items, layout.controlCenter.items);
});

test('old layout gains menu defaults in memory and preserves widget identity', () => {
  const result = parseDocument('layout', '{"schemaVersion":1,"barHeight":40}');
  assert.equal(result.ok, true);
  assert.equal(result.value.controlCenter.version, 1);
  assert.equal(result.value.controlCenter.items.find(item => item.definitionId === 'bluetooth').template, 'row');
  assert.equal(result.value.audioPresentation, 'range-horizontal');
  assert.equal(result.value.clockLayout, 'stacked');
  assert.equal(result.value.clockSize, 18);
  assert.equal(result.value.widgets[3].instanceId, 'clock-main');
});

test('appearance changes are validated without changing device state or widget settings', () => {
  const layout = structuredClone(defaults.layout);
  const bluetooth = layout.controlCenter.items.find(item => item.definitionId === 'bluetooth');
  bluetooth.template = 'icon';
  bluetooth.columnSpan = 1;
  bluetooth.rowSpan = 1;
  layout.audioPresentation = 'range-vertical';
  const result = parseDocument('layout', JSON.stringify(layout));
  assert.equal(result.ok, true, result.message);
  assert.equal(result.value.controlCenter.items.find(item => item.instanceId === bluetooth.instanceId).template, 'icon');
  assert.deepEqual(result.value.widgets, defaults.layout.widgets);
  layout.controlCenter.items[0].template = 'range-vertical';
  assert.equal(parseDocument('layout', JSON.stringify(layout)).ok, false);
  assert.equal(defaults.layout.controlCenter.items[0].template, 'row');
});

test('runtime menu rejects unsupported controls and invalid audio templates before saving', () => {
  const layout = structuredClone(defaults.layout);
  layout.controlCenter.items[0].definitionId = 'record';
  assert.equal(parseDocument('layout', JSON.stringify(layout)).ok, false);
  layout.controlCenter = defaults.layout.controlCenter;
  layout.audioPresentation = 'arbitrary-qml';
  assert.equal(parseDocument('layout', JSON.stringify(layout)).ok, false);
});

test('mixer slot agrees across config, manifest and API schema', async () => {
  assert.deepEqual(slots, widgetSlots);
  const manifest = JSON.parse(await readFile(new URL('../../quickshell/widgets/audio-mixer/manifest.json', import.meta.url)));
  for (const slot of ['sidebar-right', 'sidebar-left', 'tools', 'system']) {
    assert.equal(validateManifest(manifest, {slot}).ok, true);
  }
  assert.equal(validateManifest(manifest, {slot: 'center'}).ok, false);
  const fresh = parseDocument('layout', '{}').value.widgets;
  assert.equal(fresh.find(widget => widget.instanceId === 'mixer-main').enabled, true);
  assert.equal(fresh.find(widget => widget.instanceId === 'mixer-bar').enabled, false);
});

test('saved layouts gain disabled mixer choices once without replacing custom placements', () => {
  const custom = {instanceId: 'my-mixer', moduleId: 'pentad.audio-mixer', slot: 'sidebar-right', enabled: true, settings: {}};
  const occupied = {instanceId: 'mixer-bar', moduleId: 'author.custom', slot: 'tools', enabled: false, settings: {value: 7}};
  const saved = parseDocument('layout', JSON.stringify({widgets: [custom, occupied]}));
  assert.equal(saved.ok, true, saved.message);
  assert.deepEqual(saved.value.widgets, [custom, occupied]);
  const old = parseDocument('layout', JSON.stringify({widgets: []}));
  assert.equal(old.ok, true, old.message);
  assert.deepEqual(old.value.widgets.map(widget => [widget.instanceId, widget.enabled]), [['mixer-main', false], ['mixer-bar', false]]);
  assert.deepEqual(parseDocument('layout', JSON.stringify(old.value)).value, old.value);
  const toggled = structuredClone(old.value);
  toggled.widgets[0].enabled = true;
  assert.deepEqual(parseDocument('layout', JSON.stringify(toggled)).value, toggled);
});
