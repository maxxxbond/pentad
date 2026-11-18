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
    { language: 'uk', firstDayOfWeek: 'auto', levelOverlay: true, notificationTimeout: 7, notificationPopups: 3, stashWindow: 'overlay',
      barMenus: 'speed', notificationStyle: 'toast', superKeyLogo: 'pentad' });
  assert.equal(parseDocument('interface', '{"firstDayOfWeek":"sunday","levelOverlay":false}').ok, true);
  assert.equal(parseDocument('interface', '{"firstDayOfWeek":"friday"}').ok, false);
  assert.equal(parseDocument('interface', '{"levelOverlay":1}').ok, false);
  assert.equal(parseDocument('interface', '{"notificationTimeout":1}').ok, false);
  assert.equal(parseDocument('interface', '{"notificationPopups":6}').ok, false);

  // Bar menus: an interface document written before the setting existed keeps every value and gets
  // the default; the saved choice survives a round trip; anything else is rejected.
  const older = { language: 'en', firstDayOfWeek: 'monday', levelOverlay: false, notificationTimeout: 12, notificationPopups: 2 };
  assert.deepEqual(parseDocument('interface', JSON.stringify(older)).value, Object.assign({}, older, { stashWindow: 'overlay', barMenus: 'speed', notificationStyle: 'toast', superKeyLogo: 'pentad' }));
  const memory = parseDocument('interface', JSON.stringify(Object.assign({}, older, { barMenus: 'memory' })));
  assert.equal(memory.ok, true);
  assert.deepEqual(memory.value, Object.assign({}, older, { stashWindow: 'overlay', barMenus: 'memory', notificationStyle: 'toast', superKeyLogo: 'pentad' }));
  assert.equal(parseDocument('interface', JSON.stringify(memory.value)).value.barMenus, 'memory');
  assert.equal(parseDocument('interface', '{"barMenus":"fast"}').ok, false);
  assert.equal(parseDocument('interface', '{"barMenus":true}').ok, false);

  assert.deepEqual(parseDocument('spotlight', '{"emoji":{"languages":["uk"]}}').value,
    { emoji: { languages: ['uk'] }, calculator: true, webSearch: true, webEngine: 'duckduckgo', clipboardEnter: 'paste', pasteShortcut: 'auto' });
  assert.equal(parseDocument('spotlight', '{"webSearch":false,"webEngine":"brave"}').value.webEngine, 'brave');
  assert.equal(parseDocument('spotlight', '{"webEngine":"altavista"}').ok, false);
  assert.equal(parseDocument('spotlight', '{"calculator":"no"}').ok, false);
});
test('interface.stashWindow defaults to overlay, keeps window and rejects anything else', () => {
  assert.equal(defaults.interface.stashWindow, 'overlay');
  assert.equal(parseDocument('interface', '{}').value.stashWindow, 'overlay');
  const window = parseDocument('interface', JSON.stringify({ ...defaults.interface, stashWindow: 'window' }));
  assert.equal(window.ok, true);
  assert.equal(window.value.stashWindow, 'window');
  assert.equal(parseDocument('interface', JSON.stringify(window.value)).value.stashWindow, 'window');
  const floating = parseDocument('interface', '{"stashWindow":"floating"}');
  assert.equal(floating.ok, false);
  assert.equal(floating.reason, 'invalid');
  assert.equal(parseDocument('interface', '{"stashWindow":null}').ok, false);

  const old = { language: 'en', firstDayOfWeek: 'sunday', levelOverlay: false, notificationTimeout: 12, notificationPopups: 5 };
  const parsed = parseDocument('interface', JSON.stringify(old));
  assert.equal(parsed.ok, true);
  assert.deepEqual(parsed.value, { ...old, stashWindow: 'overlay', barMenus: 'speed', notificationStyle: 'toast', superKeyLogo: 'pentad' });
});
test('interface.notificationStyle defaults to toast, keeps every style and rejects anything else', () => {
  assert.equal(defaults.interface.notificationStyle, 'toast');
  assert.equal(parseDocument('interface', '{}').value.notificationStyle, 'toast');
  for (const style of ['toast', 'bold', 'line', 'source']) {
    const parsed = parseDocument('interface', JSON.stringify({ ...defaults.interface, notificationStyle: style }));
    assert.equal(parsed.ok, true, style);
    assert.equal(parseDocument('interface', JSON.stringify(parsed.value)).value.notificationStyle, style);
  }
  assert.equal(parseDocument('interface', '{"notificationStyle":"glass"}').ok, false);
  assert.equal(parseDocument('interface', '{"notificationStyle":null}').ok, false);
});
test('interface.superKeyLogo defaults to the Pentad logo, keeps every symbol and rejects anything else', () => {
  assert.equal(defaults.interface.superKeyLogo, 'pentad');
  assert.equal(parseDocument('interface', '{}').value.superKeyLogo, 'pentad');
  for (const logo of ['pentad', 'tux', 'text']) {
    const parsed = parseDocument('interface', JSON.stringify({ ...defaults.interface, superKeyLogo: logo }));
    assert.equal(parsed.ok, true, logo);
    assert.equal(parsed.value.superKeyLogo, logo);
    assert.equal(parseDocument('interface', JSON.stringify(parsed.value)).value.superKeyLogo, logo);
  }
  for (const garbage of ['"arch"', '"Tux"', '""', 'null', 'true', '1', '["tux"]', '{"logo":"tux"}']) {
    const parsed = parseDocument('interface', `{"superKeyLogo":${garbage}}`);
    assert.equal(parsed.ok, false, garbage);
    assert.equal(parsed.reason, 'invalid', garbage);
  }

  // A document written before the setting existed needs no migration: every value stays and the
  // key takes its default.
  const old = { language: 'uk', firstDayOfWeek: 'saturday', levelOverlay: false, notificationTimeout: 20, notificationPopups: 1,
    stashWindow: 'window', barMenus: 'memory', notificationStyle: 'line' };
  const parsed = parseDocument('interface', JSON.stringify(old));
  assert.equal(parsed.ok, true);
  assert.deepEqual(parsed.value, { ...old, superKeyLogo: 'pentad' });
  // A choice survives next to keys this version does not know.
  const newer = parseDocument('interface', JSON.stringify({ ...old, superKeyLogo: 'tux', futureKey: 3 }));
  assert.deepEqual(newer.value, { ...old, superKeyLogo: 'tux', futureKey: 3 });
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
test('chat placements gain a model source: own endpoint stays custom, the rest use the registry', () => {
  const legacyDefault = { provider: 'api', baseUrl: '', model: '', credentialRef: 'pentad-chat-api', apiKeyEnv: '' };
  const working = { provider: 'api', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o', credentialRef: 'pentad-chat-api', apiKeyEnv: 'OPENAI_API_KEY', _margin: 4 };
  const ollama = { provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', model: '' };
  const placement = (instanceId, settings) => ({ instanceId, moduleId: 'pentad.chat', slot: 'sidebar-left', enabled: true, settings });
  const input = { ...defaults.layout, widgets: [
    placement('chat-main', legacyDefault), placement('chat-work', working), placement('chat-local', ollama),
    placement('chat-empty', {}), placement('chat-chosen', { ...working, modelSource: 'registry' }),
    { instanceId: 'weather-main', moduleId: 'pentad.weather', slot: 'sidebar-left', enabled: true, settings: { city: 'Kyiv' } },
  ] };
  const result = parseDocument('layout', JSON.stringify(input));
  assert.equal(result.ok, true, result.message);
  const settingsOf = id => result.value.widgets.find(item => item.instanceId === id).settings;
  // Lossless: every legacy key survives, only modelSource is added.
  assert.deepEqual(settingsOf('chat-main'), { ...legacyDefault, modelSource: 'registry' });
  assert.deepEqual(settingsOf('chat-work'), { ...working, modelSource: 'custom' });
  assert.deepEqual(settingsOf('chat-local'), { ...ollama, modelSource: 'custom' });
  assert.deepEqual(settingsOf('chat-empty'), { modelSource: 'registry' });
  assert.deepEqual(settingsOf('chat-chosen'), { ...working, modelSource: 'registry' }, 'a stored choice wins');
  assert.deepEqual(settingsOf('weather-main'), { city: 'Kyiv' }, 'other widgets gain nothing');
  // Idempotent: parsing the result again changes nothing.
  assert.deepEqual(parseDocument('layout', JSON.stringify(result.value)).value, result.value);
  // A fresh install (no widgets key) uses the registry.
  const fresh = parseDocument('layout', JSON.stringify({ schemaVersion: 1, barHeight: 40 }));
  assert.equal(fresh.value.widgets.find(item => item.instanceId === 'chat-main').settings.modelSource, 'registry');
  assert.equal(defaults.layout.widgets.find(item => item.instanceId === 'chat-main').settings.modelRole, 'chat');
});
test('the default chat placement validates against the chat manifest', async () => {
  const manifest = JSON.parse(await readFile(new URL('../../quickshell/widgets/chat/manifest.json', import.meta.url), 'utf8'));
  const { validateSettings } = await import('../../quickshell/logic/plugin-manifest.mjs');
  const placement = defaults.layout.widgets.find(item => item.instanceId === 'chat-main');
  assert.equal(validateSettings(manifest, placement.settings).ok, true);
  assert.deepEqual(placement.settings, manifest.defaults);
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
  assert.equal(fresh.find(widget => widget.instanceId === 'mixer-main').enabled, false);
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

test('the models document parses through the shared document path and merges nested sections', () => {
  assert.deepEqual(defaults.models.providers, []);
  assert.deepEqual(defaults.models.roles, { chat: '', fast: '', vision: '', embed: '', translate: '' });
  const empty = parseDocument('models', '{}');
  assert.equal(empty.ok, true, empty.message);
  assert.deepEqual(empty.value, defaults.models);
  const saved = parseDocument('models', JSON.stringify({
    providers: [{ id: 'local', kind: 'ollama', name: 'Ollama', baseUrl: 'http://127.0.0.1:11434' }],
    roles: { chat: 'local/qwen3.5:9b' }, worker: { cacheMiB: 16 }, future: true,
  }));
  assert.equal(saved.ok, true, saved.message);
  assert.equal(saved.value.roles.chat, 'local/qwen3.5:9b');
  assert.equal(saved.value.roles.embed, '');
  assert.deepEqual(saved.value.worker, { idleExitSeconds: 600, cacheMiB: 16 });
  assert.equal(saved.value.future, true);
  assert.deepEqual(parseDocument('models', JSON.stringify(saved.value)).value, saved.value);
});

test('an invalid models document is rejected loudly, not replaced with defaults', () => {
  const remoteHttp = parseDocument('models', JSON.stringify({ providers: [{ id: 'far', kind: 'ollama', baseUrl: 'http://example.com:11434' }] }));
  assert.equal(remoteHttp.ok, false);
  assert.equal(remoteHttp.reason, 'invalid');
  assert.match(remoteHttp.message, /provider "far" baseUrl must use https/);
  assert.equal(parseDocument('models', JSON.stringify({ providers: [{ id: 'x', kind: 'nope', baseUrl: 'https://example.com' }] })).reason, 'invalid');
  assert.equal(parseDocument('models', '[]').reason, 'invalid');
  assert.equal(parseDocument('models', '{broken').reason, 'invalid');
});
