import test from 'node:test';
import assert from 'node:assert/strict';
import Ajv from 'ajv';
import { readFile } from 'node:fs/promises';
import { validateManifest, validateSettings, widgetSlots } from '../../quickshell/logic/plugin-manifest.mjs';

const valid = {
  id: 'pentad.clock', name: 'Clock', version: '1.0.0', apiVersion: 2, entry: 'View.qml', controller: 'Controller.qml',
  allowedSlots: ['system'], defaults: { duration: 1500 },
  settingsFields: [{ key: 'duration', labelKey: 'clock.duration', kind: 'integer', min: 1, max: 86400 }],
};

test('shared migration fixtures define Draft 7 schema and runtime contracts', async () => {
  const fixtures = JSON.parse(await readFile(new URL('../fixtures/migration/manifests.json', import.meta.url)));
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v2/manifest.schema.json', import.meta.url)));
  const validateSchema = new Ajv({ allErrors: true, schemaId: 'auto' }).compile(schema);
  assert.equal(validateSchema(fixtures.valid), true);
  assert.equal(validateManifest(fixtures.valid).ok, true);

  for (const { name, change } of fixtures.invalidSchema) {
    const manifest = { ...fixtures.valid, ...change };
    assert.equal(validateSchema(manifest), false, `schema rejects ${name}`);
    assert.equal(validateManifest(manifest).ok, false, `runtime rejects ${name}`);
  }

  for (const { name, change } of fixtures.runtimeOnly) {
    const manifest = { ...fixtures.valid, ...change };
    assert.equal(validateSchema(manifest), true, `schema cannot express ${name}`);
    assert.equal(validateManifest(manifest).ok, false, `runtime rejects ${name}`);
  }
});

test('tool metadata schema and runtime validator agree on v1 declarations', async () => {
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v2/manifest.schema.json', import.meta.url)));
  const validateSchema = new Ajv({ allErrors: true, schemaId: 'auto' }).compile(schema);
  const tool = { protocolVersion: 1, category: 'Text', keywords: ['json'], accepts: ['text/*'], produces: ['application/json'],
    execution: 'local', multiple: false, maxItems: 1, maxBytes: 65536 };
  assert.equal(validateSchema({ ...valid, tool }), true);
  assert.equal(validateManifest({ ...valid, tool }).ok, true);
  for (const change of [{ maxBytes: 0 }, { accepts: ['bad'] }, { unknown: true }]) {
    const manifest = { ...valid, tool: { ...tool, ...change } };
    assert.equal(validateSchema(manifest), false);
    assert.equal(validateManifest(manifest).ok, false);
  }
});

test('accepts v2 manifests and enforces requested slots', () => {
  assert.deepEqual(validateManifest(valid), { ok: true, manifest: valid });
  assert.equal(validateManifest(valid, { slot: 'system' }).ok, true);
  assert.match(validateManifest(valid, { slot: 'sidebar-left' }).errors.join(' '), /not allowed/);
});

test('validates optional typed tool metadata and keeps legacy widgets valid', () => {
  const tool = { protocolVersion: 1, category: 'Text', keywords: ['json'], accepts: ['text/plain', 'application/*'],
    produces: ['application/json'], execution: 'local', multiple: false, maxItems: 1, maxBytes: 65536 };
  assert.equal(validateManifest(valid).ok, true);
  assert.equal(validateManifest({ ...valid, tool }).ok, true);
  for (const change of [
    { protocolVersion: 2 }, { accepts: ['not-a-mime'] }, { execution: 'shell' },
    { multiple: 'yes' }, { maxItems: 101 }, { maxBytes: 10485761 }, { extra: true },
  ]) assert.equal(validateManifest({ ...valid, tool: { ...tool, ...change } }).ok, false);
});

test('rejects unsupported API, malformed identity/version, duplicate fields and unsafe paths', async () => {
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v2/manifest.schema.json', import.meta.url)));
  const versionPattern = new RegExp(schema.properties.version.pattern);
  const pathPattern = new RegExp(schema.definitions.entryPath.pattern);
  assert.equal(versionPattern.test(valid.version), true);
  assert.equal(pathPattern.test(valid.entry), true);
  for (const [change, pattern] of [
    [{ apiVersion: 3 }, /apiVersion/], [{ id: '../clock' }, /id/], [{ version: '1.0' }, /semantic/], [{ version: '1.0.0-' }, /semantic/],
    [{ entry: '/tmp/View.qml' }, /relative path/], [{ entry: '../View.qml' }, /relative path/],
    ...['folder\\View.qml', 'folder/%2e%2e/View.qml', 'View.qml?x', 'View.qml#x', 'View.js', 'folder//View.qml', 'folder/./View.qml', 'folder/../View.qml'].map(entry => [{ entry }, /relative path/]),
    [{ settingsFields: [...valid.settingsFields, valid.settingsFields[0]] }, /duplicate/],
    [{ defaults: { duration: 'many' } }, /wrong type/],
    [{ allowedSlots: ['unknown-slot'] }, /supported slots/], [{ allowedSlots: undefined }, /supported slots/],
  ]) {
    assert.match(validateManifest({ ...valid, ...change }).errors.join(' '), pattern);
    if (change.version) assert.equal(versionPattern.test(change.version), false);
    if (change.entry) assert.equal(pathPattern.test(change.entry), false, `schema rejects ${change.entry}`);
  }
  assert.deepEqual(schema.required, ['id', 'name', 'version', 'apiVersion', 'entry', 'allowedSlots']);
  assert.deepEqual(schema.properties.allowedSlots.items.enum, widgetSlots);
  assert.equal(schema.properties.defaults.additionalProperties.oneOf.some(type => type.type === 'object' || type.type === 'array'), false);
});

test('validates settings types, select options, numeric limits and secret references', () => {
  const manifest = { settingsFields: [
    { key: 'count', kind: 'integer', min: 1, max: 5 },
    { key: 'mode', kind: 'select', options: [{ value: 'a', label: 'A' }] },
    { key: 'apiToken', kind: 'text' },
  ] };
  assert.equal(validateSettings(manifest, { count: 3, mode: 'a', apiToken: 'secret://plugins.x.token' }).ok, true);
  for (const settings of [{ count: 0 }, { count: 1.5 }, { mode: 'b' }, { apiToken: 'plaintext' }, { extra: true }]) assert.equal(validateSettings(manifest, settings).ok, false);
});

test('settings default, then apply supplied values, and validate retained defaults', () => {
  const manifest = { defaults: { count: 6, label: 'manifest default' }, settingsFields: [
    { key: 'count', kind: 'integer', label: 'Count', default: 2, min: 1, max: 5 },
    { key: 'label', kind: 'text', label: 'Label', default: 'field default' },
  ] };
  assert.equal(validateSettings(manifest, {}).ok, false);
  assert.deepEqual(validateSettings({ settingsFields: [{ key: 'label', kind: 'text', label: 'Label', default: 'field' }] }, {}).settings, { label: 'field' });
  const validManifest = { ...manifest, defaults: { count: 3, label: 'manifest default' } };
  assert.deepEqual(validateSettings(validManifest, { count: 4 }).settings, { count: 4, label: 'manifest default' });
  assert.deepEqual(validateSettings({}, {}), { ok: true, settings: {} });
});

test('external widget fixture conforms to the v2 runtime contract', async () => {
  const manifest = JSON.parse(await readFile(new URL('../../quickshell/tests/fixtures/external-widget/manifest.json', import.meta.url)));
  assert.equal(validateManifest(manifest, { slot: 'sidebar-left' }).ok, true);
  assert.equal(validateSettings(manifest, manifest.defaults).ok, true);
  const view = await readFile(new URL('../../quickshell/tests/fixtures/external-widget/View.qml', import.meta.url), 'utf8');
  for (const prop of ['instanceId', 'context', 'settings', 'services', 'controller']) assert.match(view, new RegExp(`required property var ${prop}|required property string ${prop}`));
  const contracts = await readFile(new URL('../../packages/widget-api/v2/contracts.d.ts', import.meta.url), 'utf8');
  for (const value of ['outputId', 'compact', 'preview', 'navigation', 'telemetry', 'center', 'tools', 'system', 'sidebar-left', 'positionMicros', 'lengthMicros', 'trackId', 'sourceId', 'commandFinished']) assert.ok(contracts.includes(value), `contract contains ${value}`);
  for (const invented of [/\| 'bar-left'/, /readonly property var theme/, /now: Date/]) assert.equal(invented.test(contracts), false, `contract excludes ${invented}`);
});
