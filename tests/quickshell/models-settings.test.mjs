import assert from 'node:assert/strict';
import test from 'node:test';
import { parseModels } from '../../quickshell/logic/models.mjs';
import {
  addProvider, binaryText, bytesText, currentChoice, draftErrors, draftFor, endpointCaption, formatBytes, grantRows, heroSummary, hue,
  idleMinutes, installedModels, keyRef, minutesUntil, modelChips, pluralUk, presetFor, providerPresets, removeProvider, roleAccepts,
  roleChoices, roleHue, rolesUsing, secondsText, setGrant, setIdleMinutes, setRole, suggestProviderId, updateProvider, vramMeter,
} from '../../quickshell/logic/models-settings.mjs';

// The model shapes `llm.models` reports for a real local Ollama (2026-11-18).
const ollamaModels = [
  { name: 'qwen3.8:latest', sizeBytes: 17700000000, parameterSize: '27B', capabilities: ['completion', 'tools'] },
  { name: 'gpt-oss:120b-cloud', sizeBytes: 384, capabilities: ['completion', 'tools', 'thinking'] },
  { name: 'embeddinggemma-2:270m', sizeBytes: 300000000, capabilities: ['embedding'] },
  { name: 'qwen3.5:9b', sizeBytes: 6600000000, capabilities: ['completion', 'vision', 'tools', 'thinking'] },
  { name: 'qwen3.5:0.8b', sizeBytes: 1300000000, capabilities: ['completion', 'vision', 'tools', 'thinking'] },
];
const local = { id: 'local', kind: 'ollama', name: 'Ollama', baseUrl: 'http://127.0.0.1:11434', credential: '', credentialEnv: '' };
const router = { id: 'openrouter', kind: 'openai-compatible', name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1',
  credential: 'secret://pentad/providers/openrouter', credentialEnv: '' };
const doc = (extra) => parseModels(Object.assign({ providers: [local, router] }, extra || {}));
const lists = { local: { state: 'ready', models: ollamaModels }, openrouter: { state: 'ready', models: [{ name: 'openai/gpt-5-mini' }] } };

test('presets cover every kind and OpenRouter is an OpenAI-compatible preset', () => {
  assert.deepEqual(providerPresets.map(preset => preset.id), ['ollama', 'openai-compatible', 'anthropic', 'gemini', 'openrouter']);
  assert.deepEqual(presetFor('openrouter'), { id: 'openrouter', kind: 'openai-compatible', name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1', keySource: 'keyring' });
  assert.equal(presetFor('nope').id, 'ollama');
  assert.equal(keyRef('openrouter'), 'secret://pentad/providers/openrouter');
});

test('draft errors name the field and reuse the endpoint rule', () => {
  assert.deepEqual(draftErrors(draftFor(null, 'openrouter')), { ok: true, errors: {} });
  assert.deepEqual(draftErrors({ kind: 'ollama', name: ' ', baseUrl: 'http://example.com', keySource: 'none' }).errors,
    { name: 'required', baseUrl: 'insecure-endpoint' });
  assert.equal(draftErrors({ kind: 'ollama', name: 'x', baseUrl: 'not a url', keySource: 'none' }).errors.baseUrl, 'invalid-url');
  assert.equal(draftErrors({ kind: 'ollama', name: 'x', baseUrl: '', keySource: 'none' }).errors.baseUrl, 'required');
  assert.equal(draftErrors({ kind: 'gemini', name: 'x', baseUrl: 'https://a.b', keySource: 'env', credentialEnv: 'lower' }).errors.credentialEnv, 'env-invalid');
  assert.equal(draftErrors({ kind: 'gemini', name: 'x', baseUrl: 'https://a.b', keySource: 'env', credentialEnv: 'GEMINI_API_KEY' }).ok, true);
  assert.equal(draftErrors({ kind: 'mystery', name: 'x', baseUrl: 'https://a.b', keySource: 'none' }).errors.kind, 'required');
  assert.deepEqual(draftFor(router), { kind: 'openai-compatible', name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1',
    keySource: 'keyring', credentialEnv: '' });
});

test('adding a provider picks a free id and a keyring reference, never a key', () => {
  const empty = parseModels({});
  const added = addProvider(empty, draftFor(null, 'openrouter'));
  assert.equal(added.ok, true);
  assert.equal(added.providerId, 'openrouter');
  assert.equal(added.credential, 'secret://pentad/providers/openrouter');
  assert.deepEqual(added.value.providers, [router]);
  const second = addProvider(added.value, draftFor(null, 'openrouter'));
  assert.equal(second.providerId, 'openrouter-2');
  assert.equal(second.credential, 'secret://pentad/providers/openrouter-2');
  const ollama = addProvider(empty, draftFor(null, 'ollama'));
  assert.equal(ollama.providerId, 'local');
  assert.equal(ollama.value.providers[0].credential, '');
  const env = addProvider(empty, { kind: 'anthropic', name: 'Claude', baseUrl: 'https://api.anthropic.com', keySource: 'env', credentialEnv: 'ANTHROPIC_API_KEY' });
  assert.deepEqual(env.value.providers[0], { id: 'claude', kind: 'anthropic', name: 'Claude', baseUrl: 'https://api.anthropic.com',
    credential: '', credentialEnv: 'ANTHROPIC_API_KEY' });
  const bad = addProvider(empty, { kind: 'ollama', name: 'x', baseUrl: 'http://10.0.0.2:11434', keySource: 'none' });
  assert.equal(bad.ok, false);
  assert.deepEqual(bad.errors, { baseUrl: 'insecure-endpoint' });
  assert.equal(suggestProviderId(empty, '!!!', 'gemini', 'https://x.y'), 'provider');
  const fixed = addProvider(empty, draftFor(null, 'gemini'), 'my-gemini');
  assert.equal(fixed.providerId, 'my-gemini');
  assert.equal(fixed.credential, 'secret://pentad/providers/my-gemini');
  assert.equal(addProvider(fixed.value, draftFor(null, 'gemini'), 'my-gemini').reason, 'id-taken');
  assert.equal(addProvider(empty, draftFor(null, 'gemini'), 'Bad Id').reason, 'invalid-input');
});

test('editing keeps the id, the keyring reference and unknown keys', () => {
  const start = parseModels({ providers: [Object.assign({ future: 1 }, router)] });
  const renamed = updateProvider(start, 'openrouter', Object.assign(draftFor(router), { name: 'Router' }));
  assert.equal(renamed.ok, true);
  assert.deepEqual(renamed.value.providers[0], Object.assign({ future: 1 }, router, { name: 'Router' }));
  const toEnv = updateProvider(start, 'openrouter', Object.assign(draftFor(router), { keySource: 'env', credentialEnv: 'OPENROUTER_KEY' }));
  assert.equal(toEnv.value.providers[0].credential, '');
  assert.equal(toEnv.previousCredential, 'secret://pentad/providers/openrouter');
  assert.equal(updateProvider(start, 'missing', draftFor(router)).reason, 'unknown-provider');
});

test('removing a provider empties the roles bound to it and reports its key reference', () => {
  const start = doc({ roles: { chat: 'openrouter/openai/gpt-5-mini', fast: 'local/qwen3.5:0.8b', translate: 'openrouter/x', custom: 'openrouter/y' } });
  assert.deepEqual(rolesUsing(start, 'openrouter'), ['chat', 'translate', 'custom']);
  const removed = removeProvider(start, 'openrouter');
  assert.equal(removed.ok, true);
  assert.deepEqual(removed.clearedRoles, ['chat', 'translate', 'custom']);
  assert.equal(removed.credential, 'secret://pentad/providers/openrouter');
  assert.deepEqual(removed.value.providers, [local]);
  assert.deepEqual(removed.value.roles, { chat: '', fast: 'local/qwen3.5:0.8b', vision: '', embed: '', translate: '', custom: '' });
  assert.equal(removeProvider(start, 'nope').reason, 'unknown-provider');
});

test('roles, grants and the idle time are set through the document rules', () => {
  const start = doc();
  const bound = setRole(start, 'chat', 'local', 'qwen3.5:9b');
  assert.equal(bound.value.roles.chat, 'local/qwen3.5:9b');
  assert.equal(setRole(bound.value, 'chat', 'local', 'qwen3.5:9b').changed, false);
  assert.equal(setRole(bound.value, 'chat', '', '').value.roles.chat, '');
  assert.equal(setRole(start, 'chat', 'ghost', 'm').reason, 'unknown-provider');
  assert.equal(setRole(start, 'Bad Role', 'local', 'm').reason, 'invalid-input');
  const granted = setGrant(parseModels({ grants: { 'example.summarizer': { remote: false, note: 'x' } } }), 'example.summarizer', true);
  assert.deepEqual(granted.value.grants, { 'example.summarizer': { remote: true, note: 'x' } });
  assert.equal(setGrant(start, 'Not An Id', true).ok, false);
  assert.equal(idleMinutes(start), 10);
  assert.equal(setIdleMinutes(start, 3).value.worker.idleExitSeconds, 180);
  assert.equal(setIdleMinutes(start, 0).ok, false);
  assert.equal(idleMinutes(parseModels({ worker: { idleExitSeconds: 10 } })), 1);
});

test('role pickers offer what fits the role, local first, largest first', () => {
  const start = doc();
  const chat = roleChoices(start, 'chat', lists);
  assert.deepEqual(chat.map(choice => choice.value), ['local/qwen3.8:latest', 'local/qwen3.5:9b', 'local/qwen3.5:0.8b',
    'local/gpt-oss:120b-cloud', 'openrouter/openai/gpt-5-mini']);
  const cloud = chat.find(choice => choice.model === 'gpt-oss:120b-cloud');
  assert.equal(cloud.cloud, true);
  assert.equal(cloud.sizeBytes, 0);
  assert.deepEqual(chat[1].chips, ['vision', 'tools', 'thinking']);
  assert.equal(chat[1].local, true);
  assert.deepEqual(roleChoices(start, 'embed', lists).map(choice => choice.value), ['local/embeddinggemma-2:270m', 'openrouter/openai/gpt-5-mini']);
  assert.deepEqual(roleChoices(start, 'vision', lists).filter(choice => choice.local).map(choice => choice.model), ['qwen3.5:9b', 'qwen3.5:0.8b']);
  assert.equal(roleAccepts('chat', { name: 'e', capabilities: ['embedding'] }), false);
  assert.equal(roleAccepts('embed', { name: 'x' }), true);
  assert.deepEqual(modelChips({ capabilities: ['thinking', 'completion', 'vision', 'future'] }), ['vision', 'thinking']);
  assert.deepEqual(roleChoices(start, 'chat', {}), []);
});

test('the current choice survives a model no list reports', () => {
  const start = doc({ roles: { chat: 'local/hand-typed:1b', fast: 'gone/x' } });
  const chat = currentChoice(start, 'chat', lists);
  assert.equal(chat.model, 'hand-typed:1b');
  assert.equal(chat.local, true);
  assert.equal(currentChoice(start, 'fast', lists).missing, true);
  assert.equal(currentChoice(start, 'vision', lists), null);
  assert.deepEqual(currentChoice(doc({ roles: { chat: 'local/qwen3.5:9b' } }), 'chat', lists).chips, ['vision', 'tools', 'thinking']);
});

test('the hero headline: empty, unbound, all local, or naming the cloud providers', () => {
  assert.equal(heroSummary(parseModels({})).state, 'empty');
  assert.equal(heroSummary(doc()).state, 'unbound');
  const allLocal = heroSummary(doc({ roles: { chat: 'local/qwen3.5:9b', embed: 'local/embeddinggemma-2:270m' } }));
  assert.deepEqual(allLocal, { state: 'local', cloud: [], local: ['Ollama'], boundRoles: 2 });
  const mixed = heroSummary(doc({ roles: { chat: 'openrouter/openai/gpt-5-mini', fast: 'local/gpt-oss:120b-cloud', embed: 'local/embeddinggemma-2:270m' } }));
  assert.equal(mixed.state, 'mixed');
  assert.deepEqual(mixed.cloud, ['OpenRouter', 'Ollama cloud']);
  assert.equal(roleHue(doc({ roles: { chat: 'openrouter/x', fast: 'local/qwen3.5:0.8b' } }), 'chat'), 'cloud');
  assert.equal(roleHue(doc({ roles: { fast: 'local/qwen3.5:0.8b' } }), 'fast'), 'local');
  assert.equal(roleHue(doc(), 'fast'), '');
});

test('installed models and the VRAM meter from llm.loaded and system.vram', () => {
  const loaded = { local: { models: [{ name: 'qwen3.5:9b', sizeBytes: 6600000000, vramBytes: 6600000000, expiresAt: '2026-11-18T19:04:05Z' }] } };
  const vram = { available: true, totalBytes: 17000000000, usedBytes: 7400000000 };
  const cards = installedModels(doc(), lists, loaded, vram);
  assert.deepEqual(cards.map(card => card.name), ['qwen3.5:9b', 'qwen3.8:latest', 'qwen3.5:0.8b', 'embeddinggemma-2:270m', 'gpt-oss:120b-cloud']);
  assert.equal(cards[0].loaded, true);
  assert.equal(cards[0].vramBytes, 6600000000);
  assert.equal(cards[1].title, 'qwen3.8');
  assert.equal(cards[1].tooBig, true);
  assert.equal(cards[4].cloud, true);
  assert.equal(cards[4].sizeBytes, 0);
  assert.deepEqual(installedModels(parseModels({ providers: [router] }), lists, {}, vram), []);
  const meter = vramMeter(vram, loaded);
  assert.equal(meter.available, true);
  assert.deepEqual(meter.models, [{ name: 'qwen3.5:9b', bytes: 6600000000, fraction: 6600000000 / 17000000000 }]);
  assert.equal(meter.otherBytes, 800000000);
  assert.equal(meter.freeBytes, 9600000000);
  assert.deepEqual(vramMeter({ available: false }, loaded), { available: false });
  assert.deepEqual(vramMeter(null, null), { available: false });
});

test('numbers read naturally in both languages', () => {
  assert.deepEqual(formatBytes(6600000000, true), { value: '6,6', unit: 'ГБ' });
  assert.deepEqual(formatBytes(6600000000, false), { value: '6.6', unit: 'GB' });
  assert.equal(bytesText(300000000, true), '300 МБ');
  assert.equal(bytesText(17700000000, false), '18 GB');
  assert.equal(bytesText(1000000000, false), '1 GB');
  assert.equal(bytesText(999999999, false), '1 GB');
  assert.equal(bytesText(12 * 1024 * 1024, true), '13 МБ');
  assert.equal(bytesText(0, false), '0 B');
  assert.equal(secondsText(4600, true), '4,6 с');
  assert.equal(binaryText(64 * 1024 * 1024, true), '64 МіБ');
  assert.equal(binaryText(1536 * 1024, false), '1.5 MiB');
  assert.equal(binaryText(0, false), '0 B');
  assert.equal(secondsText(320, false), '0.3 s');
  assert.equal(minutesUntil('2026-11-18T19:04:05Z', Date.parse('2026-11-18T19:00:30Z')), 4);
  assert.equal(minutesUntil('2026-11-18T19:04:05Z', Date.parse('2026-11-18T19:10:00Z')), -1);
  assert.equal(minutesUntil('2318-01-01T00:00:00Z', Date.parse('2026-11-18T19:10:00Z')), Infinity);
  assert.equal(minutesUntil('garbage', 0), -1);
  assert.equal(endpointCaption('https://openrouter.ai/api/v1'), 'openrouter.ai/api/v1');
  assert.deepEqual([0, 1, 2, 4, 5, 11, 12, 21, 22, 25, 111].map(n => pluralUk(n, 'модель', 'моделі', 'моделей')),
    ['моделей', 'модель', 'моделі', 'моделі', 'моделей', 'моделей', 'моделей', 'модель', 'моделі', 'моделей', 'моделей']);
  assert.equal(hue('light', 'cloud'), '#835500');
  assert.equal(hue('dark', 'nope'), '#8FD3AE');
});

test('grant rows list external widgets that declare capabilities, and orphaned remote grants', () => {
  const catalog = {
    'pentad.chat': { builtin: true, manifest: { id: 'pentad.chat', name: 'Chat', capabilities: ['llm.chat'] } },
    'example.summarizer': { builtin: false, manifest: { id: 'example.summarizer', name: 'Summarizer', capabilities: ['llm.chat'] } },
    'example.clock': { builtin: false, manifest: { id: 'example.clock', name: 'Clock' } },
    'example.receipts': { builtin: false, manifest: { id: 'example.receipts', name: 'Receipt reader', capabilities: ['image.ocr', 'llm.chat'] } },
  };
  const rows = grantRows(catalog, parseModels({ grants: { 'example.receipts': { remote: true }, 'example.gone': { remote: true }, 'example.off': { remote: false } } }));
  assert.deepEqual(rows, [
    { moduleId: 'example.receipts', name: 'Receipt reader', capabilities: ['image.ocr', 'llm.chat'], remote: true, installed: true },
    { moduleId: 'example.summarizer', name: 'Summarizer', capabilities: ['llm.chat'], remote: false, installed: true },
    { moduleId: 'example.gone', name: 'example.gone', capabilities: [], remote: true, installed: false },
  ]);
  assert.deepEqual(grantRows(null, parseModels({})), []);
});
