import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { widgetSteps, buildPlacement, registryFromCatalog } from '../../quickshell/logic/settings-widget-flow.mjs';
import { createFlow, setDraft, canContinue, next } from '../../quickshell/logic/settings-flow.mjs';
import { defaultWidgets, parseDocument, slots } from '../../quickshell/logic/config.mjs';

const registry = [
  { id: 'pentad.weather', name: 'Weather', allowedSlots: ['sidebar-left', 'center'],
    defaults: { units: 'celsius' },
    settingsFields: [{ key: 'units', kind: 'select', label: 'Units', options: [{ value: 'celsius', label: 'C' }, { value: 'fahrenheit', label: 'F' }] },
      { key: 'refresh', kind: 'integer', label: 'Refresh', min: 1, max: 60, default: 10 }] },
  { id: 'pentad.tools', name: 'Tools', allowedSlots: ['tools'], defaults: {}, settingsFields: [] },
];
const draftFor = (patch = {}) => ({ moduleId: 'pentad.weather', slot: 'sidebar-left', settings: { units: 'celsius' }, existing: [], ...patch });
const stepById = (id) => widgetSteps(registry).find((step) => step.id === id);

test('steps are Widget, Placement, Settings, Review with existing icons', () => {
  const steps = widgetSteps(registry);
  assert.deepEqual(steps.map((step) => step.id), ['widget', 'placement', 'settings', 'review']);
  const root = fileURLToPath(new URL('../../quickshell/assets/icons/', import.meta.url));
  for (const step of steps) {
    assert.ok(step.labelUk && step.labelEn);
    assert.ok(existsSync(root + step.icon), step.icon);
    assert.equal(typeof step.validate, 'function');
  }
});

test('widget step requires a registered widget', () => {
  assert.ok(stepById('widget').validate(draftFor({ moduleId: '' })).length > 0);
  assert.ok(stepById('widget').validate(draftFor({ moduleId: 'nope' })).length > 0);
  assert.deepEqual(stepById('widget').validate(draftFor()), []);
});

test('slot outside allowedSlots fails Placement', () => {
  assert.ok(stepById('placement').validate(draftFor({ slot: 'tools' })).length > 0);
  assert.ok(stepById('placement').validate(draftFor({ slot: 'bogus' })).length > 0);
  assert.deepEqual(stepById('placement').validate(draftFor({ slot: 'center' })), []);
});

test('invalid widget settings fail Settings step', () => {
  assert.ok(stepById('settings').validate(draftFor({ settings: { units: 'kelvin' } })).length > 0);
  assert.ok(stepById('settings').validate(draftFor({ settings: { refresh: 500 } })).length > 0);
  assert.ok(stepById('settings').validate(draftFor({ settings: { unknown: 1 } })).length > 0);
  assert.deepEqual(stepById('settings').validate(draftFor({ settings: { refresh: 5 } })), []);
});

test('review fails when any earlier step fails', () => {
  assert.deepEqual(stepById('review').validate(draftFor()), []);
  assert.ok(stepById('review').validate(draftFor({ slot: 'tools' })).length > 0);
});

test('buildPlacement yields unique instance ids', () => {
  assert.equal(buildPlacement(draftFor({ existing: ['weather-main'] })).instanceId, 'weather-1');
  assert.equal(buildPlacement(draftFor({ existing: ['weather-main', 'weather-1', 'weather-2'] })).instanceId, 'weather-3');
  const placement = buildPlacement(draftFor({ existing: [] }));
  assert.deepEqual(Object.keys(placement).sort(), ['enabled', 'instanceId', 'moduleId', 'settings', 'slot']);
  assert.equal(placement.enabled, true);
});

test('buildPlacement does not alias draft settings', () => {
  const draft = draftFor();
  const placement = buildPlacement(draft);
  placement.settings.units = 'x';
  assert.equal(draft.settings.units, 'celsius');
});

test('final placement validates in the layout document', () => {
  const placement = buildPlacement(draftFor({ existing: defaultWidgets.map((w) => w.instanceId) }));
  const text = JSON.stringify({ schemaVersion: 1, widgets: [...defaultWidgets, placement] });
  const parsed = parseDocument('layout', text);
  assert.equal(parsed.ok, true, parsed.message);
  assert.ok(slots.includes(placement.slot));
  assert.ok(parsed.value.widgets.some((w) => w.instanceId === placement.instanceId));
});

test('works through the flow state machine', () => {
  let flow = createFlow(widgetSteps(registry), { moduleId: '', slot: '', settings: {}, existing: [] });
  assert.equal(canContinue(flow), false);
  flow = next(setDraft(flow, { moduleId: 'pentad.tools' }));
  assert.equal(flow.index, 1);
  assert.equal(canContinue(flow), false);
  flow = next(setDraft(flow, { slot: 'tools' }));
  assert.equal(flow.index, 2);
});

test('registryFromCatalog maps Plugins.catalog entries', () => {
  const catalog = { 'pentad.tools': { manifest: { id: 'pentad.tools', name: 'Tools', allowedSlots: ['tools'] }, builtin: true } };
  assert.deepEqual(registryFromCatalog(catalog), [{ id: 'pentad.tools', name: 'Tools', allowedSlots: ['tools'], settingsFields: [], defaults: {} }]);
  assert.deepEqual(registryFromCatalog(null), []);
});
