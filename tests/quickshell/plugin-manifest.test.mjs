import test from 'node:test';
import assert from 'node:assert/strict';
import Ajv from 'ajv';
import { readFile } from 'node:fs/promises';
import { validateManifest, validateSettings, widgetSlots } from '../../quickshell/logic/plugin-manifest.mjs';

const valid = {
  id: 'pentad.clock', name: 'Clock', version: '1.0.0', apiVersion: 1, entry: 'View.qml', controller: 'Controller.qml',
  allowedSlots: ['system'], defaults: { duration: 1500 },
  settingsFields: [{ key: 'duration', labelKey: 'clock.duration', kind: 'integer', min: 1, max: 86400 }],
};

test('shared migration fixtures define Draft 7 schema and runtime contracts', async () => {
  const fixtures = JSON.parse(await readFile(new URL('../fixtures/migration/manifests.json', import.meta.url)));
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v1/manifest.schema.json', import.meta.url)));
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
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v1/manifest.schema.json', import.meta.url)));
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

test('accepts v1 manifests and enforces requested slots', () => {
  assert.deepEqual(validateManifest(valid), { ok: true, manifest: valid });
  assert.equal(validateManifest(valid, { slot: 'system' }).ok, true);
  assert.match(validateManifest(valid, { slot: 'sidebar-left' }).errors.join(' '), /not allowed/);
});

test('version 1 is the only supported public widget contract', async () => {
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v1/manifest.schema.json', import.meta.url)));
  const validateSchema = new Ajv({ allErrors: true }).compile(schema);
  assert.equal(schema.$id, 'https://pentad.dev/widget-api/v1/manifest.schema.json');
  assert.equal(validateSchema(valid), true);
  for (const apiVersion of [0, 2, 3, '1', null]) {
    assert.equal(validateSchema({ ...valid, apiVersion }), false);
    assert.match(validateManifest({ ...valid, apiVersion }).errors.join(' '), /apiVersion must be 1/);
  }
  const services = await readFile(new URL('../../quickshell/services/Services.qml', import.meta.url), 'utf8');
  assert.match(services, /readonly property string apiVersion: "1"/);
});

test('settings editor metadata is shared by schema and runtime validation', async () => {
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v1/manifest.schema.json', import.meta.url)));
  const validateSchema = new Ajv({ allErrors: true }).compile(schema);
  const field = { key: 'duration', label: 'Duration', labelUk: 'Тривалість', labelEn: 'Duration', kind: 'number',
    help: 'Seconds', helpUk: 'Секунди', helpEn: 'Seconds', group: 'timer', groupUk: 'Таймер', groupEn: 'Timer',
    step: 0.5, showWhen: { key: 'enabled', equals: true } };
  for (const change of [{}, { showWhen: { key: 'mode', equals: 'timer' } }, { showWhen: { key: 'count', equals: 0 } }]) {
    const manifest = { ...valid, settingsFields: [{ ...field, ...change }] };
    assert.equal(validateSchema(manifest), true, JSON.stringify(validateSchema.errors));
    assert.equal(validateManifest(manifest).ok, true);
  }
  for (const change of [{ labelUk: 1 }, { labelEn: null }, { help: false }, { groupUk: [] }, { step: 0 }, { step: -1 },
    { showWhen: null }, { showWhen: {} }, { showWhen: { key: 'bad.key', equals: true } }, { showWhen: { key: 'enabled', equals: {} } }]) {
    const manifest = { ...valid, settingsFields: [{ ...field, ...change }] };
    assert.equal(validateSchema(manifest), false, JSON.stringify(change));
    assert.equal(validateManifest(manifest).ok, false, JSON.stringify(change));
  }
  const select = { ...valid, defaults: {}, settingsFields: [{ key: 'mode', kind: 'select', label: 'Mode',
    options: [{ value: 'on', label: 'On', labelUk: 'Увімкнено', labelEn: 'On' }] }] };
  assert.equal(validateSchema(select), true);
  assert.equal(validateManifest(select).ok, true);
  select.settingsFields[0].options[0].labelUk = 5;
  assert.equal(validateSchema(select), false);
  assert.equal(validateManifest(select).ok, false);
});

test('new-widget template resolves to a valid v1 manifest in every supported slot', async () => {
  const { zonesForSlots } = await import('../../quickshell/logic/pentads.mjs');
  const template = await readFile(new URL('../../.claude/skills/new-widget/templates/manifest.json', import.meta.url), 'utf8');
  for (const slot of widgetSlots) {
    const manifest = JSON.parse(template.replaceAll('__NAME__', 'example').replaceAll('__TITLE_EN__', 'Example')
      .replaceAll('__SLOT__', slot).replaceAll('__ZONE__', zonesForSlots([slot])[0]));
    assert.equal(manifest.apiVersion, 1);
    assert.equal(validateManifest(manifest, { slot, requirePentads: true }).ok, true, slot);
  }
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
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v1/manifest.schema.json', import.meta.url)));
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

test('environment-variable names are not secrets, key values still are', async () => {
  const chat = JSON.parse(await readFile(new URL('../../quickshell/widgets/chat/manifest.json', import.meta.url)));
  const placement = { ...chat.defaults, baseUrl: 'https://api.openai.com/v1', model: 'gpt' };
  assert.equal(validateSettings(chat, { ...placement, apiKeyEnv: 'OPENAI_API_KEY' }).ok, true);
  assert.equal(validateSettings(chat, { ...placement, apiKeyEnv: '' }).ok, true);
  // Not an environment-variable name: a pasted key does not slip through the Env suffix.
  // Real token shapes that happen to be identifiers: only upper-case variable names pass.
  for (const apiKeyEnv of ['sk-proj-abc123', 'Bearer abc', '1KEY', 'KEY=value', '$OPENAI_API_KEY',
    'gsk_' + 'a1B2'.repeat(12), 'ghp_' + 'Ab3d'.repeat(9), 'github_pat_11ABCDEFG0123456789_abcdef', 'hf_' + 'aBcD'.repeat(8), 'aB3d'.repeat(8)])
    assert.match(validateSettings(chat, { ...placement, apiKeyEnv }).errors.join(' '), /apiKeyEnv must be a secret reference/, apiKeyEnv);

  const field = key => ({ key, kind: 'text', label: key });
  const manifest = { ...valid, defaults: {}, settingsFields: ['apiKey', 'apiKeyEnv', 'tokenEnv', 'password', 'apiKeyEnvironment'].map(field) };
  assert.equal(validateSettings(manifest, { apiKeyEnv: 'OPENAI_API_KEY', tokenEnv: 'GH_TOKEN', apiKey: 'secret://pentad/providers/openai' }).ok, true);
  for (const settings of [{ apiKey: 'sk-proj-abc123' }, { apiKey: 'OPENAI_API_KEY' }, { password: 'HUNTER2' }, { apiKeyEnvironment: 'OPENAI_API_KEY' }, { tokenEnv: 'ghp-abc.def' }])
    assert.match(validateSettings(manifest, settings).errors.join(' '), /must be a secret reference/, JSON.stringify(settings));

  // Manifest defaults follow the same rule as placement settings.
  const withDefault = (key, value) => validateManifest({ ...valid, defaults: {}, settingsFields: [{ ...field(key), default: value }] });
  assert.equal(withDefault('apiKeyEnv', 'OPENAI_API_KEY').ok, true);
  assert.equal(validateManifest({ ...valid, defaults: { apiKeyEnv: 'OPENAI_API_KEY' }, settingsFields: [field('apiKeyEnv')] }).ok, true);
  assert.match(withDefault('apiKey', 'sk-proj-abc123').errors.join(' '), /default must be a secret reference/);
  assert.match(withDefault('apiKeyEnv', 'sk-proj-abc123').errors.join(' '), /default must be a secret reference/);
  assert.match(validateManifest({ ...valid, defaults: { apiKey: 'OPENAI_API_KEY' }, settingsFields: [field('apiKey')] }).errors.join(' '), /secret reference/);
});

test('capabilities are validated by schema and runtime together', async () => {
  const schema = JSON.parse(await readFile(new URL('../../packages/widget-api/v1/manifest.schema.json', import.meta.url)));
  const validateSchema = new Ajv({ allErrors: true }).compile(schema);
  const { capabilityPattern, knownCapabilities, maxCapabilities } = await import('../../quickshell/logic/capabilities.mjs');
  assert.equal(schema.properties.capabilities.items.pattern, capabilityPattern.source);
  assert.equal(schema.properties.capabilities.maxItems, maxCapabilities);
  const tool = { protocolVersion: 1, category: 'AI', keywords: ['chat'], accepts: ['text/plain'], produces: ['text/plain'],
    execution: 'ai', multiple: false, maxItems: 1, maxBytes: 16384 };
  // Unknown but well-formed names are not a manifest error (the call reports `unsupported`).
  for (const manifest of [{ ...valid, capabilities: [] }, { ...valid, capabilities: Object.keys(knownCapabilities) },
    { ...valid, capabilities: ['vendor.future-thing.v2'] }, { ...valid, tool, capabilities: Object.keys(knownCapabilities) },
    { ...valid, tool: { ...tool, execution: 'network' }, capabilities: ['text.translate', 'image.ocr'] },
    { ...valid, tool: { ...tool, execution: 'local' }, capabilities: ['image.ocr', 'pdf.text'] }]) {
    assert.equal(validateSchema(manifest), true, JSON.stringify(validateSchema.errors));
    assert.deepEqual(validateManifest(manifest), { ok: true, manifest });
  }
  for (const capabilities of [null, 'llm.chat', { 'llm.chat': true }, ['llm'], ['llm.Chat'], ['llm chat.x'], [1], ['a.b', 'a.b'],
    Array.from({ length: 17 }, (_, index) => `a.b${index}`)]) {
    assert.equal(validateSchema({ ...valid, capabilities }), false, JSON.stringify(capabilities));
    assert.match(validateManifest({ ...valid, capabilities }).errors.join(' '), /manifest\.capabilities/, JSON.stringify(capabilities));
  }
  for (const [execution, capability] of [['local', 'llm.chat'], ['network', 'llm.chat'], ['network', 'text.embed'], ['local', 'text.translate']]) {
    const manifest = { ...valid, tool: { ...tool, execution }, capabilities: [capability] };
    assert.equal(validateSchema(manifest), true);
    assert.match(validateManifest(manifest).errors.join(' '), /manifest\.tool\.execution must be/, `${capability} with ${execution}`);
  }
  const contracts = await readFile(new URL('../../packages/widget-api/v1/contracts.d.ts', import.meta.url), 'utf8');
  for (const value of ["'cancelled'", "'busy'", 'capabilities?: string[]', 'interface Disclosure', 'interface Availability', 'interface CapabilitiesService',
    'readonly capabilities: CapabilitiesService', ...Object.keys(knownCapabilities).map(name => `'${name}'`)]) assert.ok(contracts.includes(value), `contract contains ${value}`);
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

test('field defaults and supplied settings share type and bounds checks', () => {
  const cases = [
    [{ kind: 'text' }, ['', 'text'], [false, 2]],
    [{ kind: 'integer', min: 0, max: 5 }, [0, 5], [-1, 6, 1.5, Number.MAX_SAFE_INTEGER + 1]],
    [{ kind: 'number', min: 0, max: 5 }, [0, 1.5, 5], [-1, 6, NaN, Infinity]],
    [{ kind: 'boolean' }, [false, true], [0, 'true']],
    [{ kind: 'select', options: [{ value: false, label: 'Off' }, { value: 'on', label: 'On' }] }, [false, 'on'], [true, 'off', {}]],
    [{ kind: 'color' }, ['#112233', '#112233ff'], ['red', '#123', 0]],
  ];
  for (const [definition, accepted, rejected] of cases) {
    const field = { key: 'value', label: 'Value', ...definition };
    for (const [values, expected] of [[accepted, true], [rejected, false]]) {
      for (const value of values) {
        const manifest = { ...valid, defaults: {}, settingsFields: [field] };
        assert.equal(validateSettings(manifest, { value }).ok, expected, `${field.kind}: setting ${String(value)}`);
        assert.equal(validateManifest({ ...manifest, settingsFields: [{ ...field, default: value }] }).ok, expected, `${field.kind}: field default ${String(value)}`);
        assert.equal(validateManifest({ ...manifest, defaults: { value } }).ok, expected, `${field.kind}: manifest default ${String(value)}`);
      }
    }
  }
});

test('documented greeting widget and placement satisfy the runtime contract', async () => {
  const guide = await readFile(new URL('../../docs/development/widgets.md', import.meta.url), 'utf8');
  const examples = [...guide.matchAll(/```json\n([\s\S]*?)\n```/g)].map(match => JSON.parse(match[1]));
  const manifest = examples.find(example => example.id === 'example.greeting');
  const placement = examples.find(example => example.moduleId === 'example.greeting');
  assert.ok(manifest);
  assert.ok(placement);
  assert.equal(validateManifest(manifest, { slot: placement.slot, requirePentads: true }).ok, true);
  assert.deepEqual(validateSettings(manifest, placement.settings), { ok: true, settings: { message: '' } });
});

test('external widget fixture conforms to the v1 runtime contract', async () => {
  const manifest = JSON.parse(await readFile(new URL('../../quickshell/tests/fixtures/external-widget/manifest.json', import.meta.url)));
  assert.equal(validateManifest(manifest, { slot: 'sidebar-left' }).ok, true);
  assert.equal(validateSettings(manifest, manifest.defaults).ok, true);
  const view = await readFile(new URL('../../quickshell/tests/fixtures/external-widget/View.qml', import.meta.url), 'utf8');
  for (const prop of ['instanceId', 'context', 'settings', 'services', 'controller']) assert.match(view, new RegExp(`required property var ${prop}|required property string ${prop}`));
  const contracts = await readFile(new URL('../../packages/widget-api/v1/contracts.d.ts', import.meta.url), 'utf8');
  for (const value of ['outputId', 'compact', 'preview', 'navigation', 'telemetry', 'center', 'tools', 'system', 'sidebar-left', 'positionMicros', 'lengthMicros', 'trackId', 'sourceId', 'commandFinished']) assert.ok(contracts.includes(value), `contract contains ${value}`);
  for (const invented of [/\| 'bar-left'/, /readonly property var theme/, /now: Date/]) assert.equal(invented.test(contracts), false, `contract excludes ${invented}`);
});
