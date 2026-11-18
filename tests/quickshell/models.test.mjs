import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import {
  modelsDefaults, parseModels, parseRole, providerDisclosure, providerKinds, resolveRole, validateEndpoint,
  applyLocalSetup, chooseLocalRoles, importEndpoint, inlineProvider, localOllama,
} from '../../quickshell/logic/models.mjs';

const local = { id: 'local', kind: 'ollama', name: 'Ollama', baseUrl: 'http://127.0.0.1:11434', credential: '', credentialEnv: '' };
const openai = { id: 'openai', kind: 'openai-compatible', name: 'OpenAI', baseUrl: 'https://api.openai.com/v1',
  credential: 'secret://pentad/providers/openai', credentialEnv: '' };
const sample = () => ({
  schemaVersion: 1,
  providers: [Object.assign({}, local), Object.assign({}, openai)],
  roles: { chat: 'local/qwen3.5:9b', fast: 'local/qwen3.5:0.8b', vision: 'local/qwen3.5:9b', embed: 'local/embeddinggemma-2:270m', translate: '' },
  roleOptions: { chat: { keepAlive: '' } },
  grants: { 'example.summarizer': { remote: false } },
  privacy: { localOnly: false },
  worker: { idleExitSeconds: 600, cacheMiB: 64 },
});

test('an empty document yields the defaults: no providers and every role empty', () => {
  const value = parseModels({});
  assert.deepEqual(value, modelsDefaults);
  assert.deepEqual(value.providers, []);
  assert.deepEqual(Object.keys(value.roles), ['chat', 'fast', 'vision', 'embed', 'translate']);
  for (const role of Object.keys(value.roles)) assert.deepEqual(resolveRole(value, role), { ok: false, reason: 'not-configured' });
  assert.deepEqual(value.worker, { idleExitSeconds: 600, cacheMiB: 64 });
  assert.equal(value.privacy.localOnly, false);
});

test('the reference copy in defaults/ matches the built-in defaults', async () => {
  const text = await readFile(new URL('../../quickshell/defaults/models.json', import.meta.url), 'utf8');
  assert.deepEqual(parseModels(JSON.parse(text)), modelsDefaults);
  assert.deepEqual(JSON.parse(text), JSON.parse(JSON.stringify(modelsDefaults)));
});

test('the spec example round-trips unchanged and parsing is idempotent', () => {
  const value = parseModels(sample());
  assert.deepEqual(value, sample());
  assert.deepEqual(parseModels(JSON.parse(JSON.stringify(value))), value);
});

test('parsing never mutates its input or the frozen defaults', () => {
  const input = sample();
  const copy = JSON.parse(JSON.stringify(input));
  const value = parseModels(input);
  assert.deepEqual(input, copy);
  value.roles.chat = 'changed/x';
  value.worker.cacheMiB = 1;
  assert.equal(modelsDefaults.roles.chat, '');
  assert.equal(modelsDefaults.worker.cacheMiB, 64);
  assert.ok(Object.isFrozen(modelsDefaults) && Object.isFrozen(modelsDefaults.roles));
});

test('sections merge with the defaults key by key', () => {
  const value = parseModels({ roles: { chat: 'local/a' }, worker: { cacheMiB: 8 }, privacy: {}, providers: [local] });
  assert.deepEqual(value.roles, { chat: 'local/a', fast: '', vision: '', embed: '', translate: '' });
  assert.deepEqual(value.worker, { idleExitSeconds: 600, cacheMiB: 8 });
  assert.deepEqual(value.privacy, { localOnly: false });
});

test('unknown top-level, provider, role and section keys are preserved', () => {
  const input = sample();
  input.future = { nested: [1, 2] };
  input.providers[0].contextWindow = 8192;
  input.roles.rerank = 'local/bge-reranker';
  input.roleOptions.rerank = { topK: 5 };
  input.grants['example.summarizer'].note = 'kept';
  input.privacy.redact = true;
  input.worker.threads = 2;
  const value = parseModels(input);
  assert.deepEqual(value.future, { nested: [1, 2] });
  assert.equal(value.providers[0].contextWindow, 8192);
  assert.equal(value.roles.rerank, 'local/bge-reranker');
  assert.deepEqual(value.roleOptions.rerank, { topK: 5 });
  assert.deepEqual(value.grants['example.summarizer'], { remote: false, note: 'kept' });
  assert.equal(value.privacy.redact, true);
  assert.equal(value.worker.threads, 2);
  assert.deepEqual(resolveRole(value, 'rerank').model, 'bge-reranker');
});

test('providers get a name, empty credentials and a normalised endpoint when omitted', () => {
  const value = parseModels({ providers: [{ id: 'lm', kind: 'openai-compatible', baseUrl: ' HTTP://LocalHost:1234/v1/ ' }] });
  assert.deepEqual(value.providers, [{ id: 'lm', kind: 'openai-compatible', name: 'lm', baseUrl: 'http://localhost:1234/v1', credential: '', credentialEnv: '' }]);
  assert.deepEqual(parseModels({ grants: { 'example.widget': {} } }).grants, { 'example.widget': { remote: false } });
});

test('invalid documents are rejected with a message that names the problem', () => {
  const provider = change => Object.assign({}, local, change);
  const cases = [
    [null, /must be an object/],
    [[], /must be an object/],
    [{ schemaVersion: 2 }, /schemaVersion/],
    [{ providers: {} }, /providers must be an array/],
    [{ providers: ['local'] }, /providers\[0\] must be an object/],
    [{ providers: [provider({ kind: 'mistral' })] }, /provider "local" has an unknown kind/],
    [{ providers: [provider({ kind: undefined })] }, /unknown kind/],
    [{ providers: [provider({ id: 'Local' })] }, /providers\[0\]\.id/],
    [{ providers: [provider({ id: '' })] }, /providers\[0\]\.id/],
    [{ providers: [provider({ id: 'has/slash' })] }, /providers\[0\]\.id/],
    [{ providers: [provider({ id: '-lead' })] }, /providers\[0\]\.id/],
    [{ providers: [provider({ id: 'a'.repeat(33) })] }, /providers\[0\]\.id/],
    [{ providers: [provider({ id: 7 })] }, /providers\[0\]\.id/],
    [{ providers: [local, provider({ name: 'Second' })] }, /duplicate provider id "local"/],
    [{ providers: [provider({ name: '' })] }, /invalid name/],
    [{ providers: [provider({ baseUrl: 'http://api.example.com/v1' })] }, /must use https/],
    [{ providers: [provider({ baseUrl: '' })] }, /not a valid http\(s\) URL/],
    [{ providers: [provider({ baseUrl: undefined })] }, /not a valid http\(s\) URL/],
    [{ providers: [provider({ credential: 'sk-plain-text-key' })] }, /credential must be empty or a secret:\/\/pentad/],
    [{ providers: [provider({ credential: 'secret://other/providers/x' })] }, /credential/],
    [{ providers: [provider({ credentialEnv: 'NOT A NAME' })] }, /credentialEnv/],
    [{ providers: [provider({ apiKey: 'sk-plain-text-key' })] }, /key "apiKey" is not allowed/],
    [{ providers: [provider({ token: '' })] }, /key "token" is not allowed/],
    [{ providers: Array.from({ length: 33 }, (_, index) => provider({ id: `p${index}` })) }, /more than 32 providers/],
    [{ roles: [] }, /roles must be an object/],
    [{ roles: { chat: 5 } }, /role "chat" must be a string/],
    [{ roles: { chat: 'no-slash' } }, /role "chat" must be empty or/],
    [{ roles: { chat: 'local/' } }, /role "chat"/],
    [{ roles: { 'Bad Role': '' } }, /role name "Bad Role"/],
    [{ roleOptions: { chat: 'x' } }, /roleOptions\.chat must be an object/],
    [{ roleOptions: { chat: { keepAlive: 5 } } }, /keepAlive/],
    [{ grants: { 'example.widget': true } }, /grants\.example\.widget must be an object/],
    [{ grants: { 'example.widget': { remote: 'yes' } } }, /remote must be true or false/],
    [{ grants: { 'Not An Id': { remote: true } } }, /not a widget id/],
    [{ privacy: { localOnly: 'no' } }, /privacy\.localOnly/],
    [{ privacy: null }, /privacy must be an object/],
    [{ worker: { idleExitSeconds: 0 } }, /idleExitSeconds/],
    [{ worker: { idleExitSeconds: 1.5 } }, /idleExitSeconds/],
    [{ worker: { cacheMiB: 0 } }, /cacheMiB/],
    [{ worker: { cacheMiB: '64' } }, /cacheMiB/],
  ];
  for (const [input, pattern] of cases) assert.throws(() => parseModels(input), pattern, JSON.stringify(input));
});

test('a crafted __proto__ key cannot change the shape of the result', () => {
  for (const text of ['{"roles":{"__proto__":"local/x"}}', '{"roleOptions":{"__proto__":{"keepAlive":""}}}', '{"grants":{"__proto__":{"remote":true}}}'])
    assert.throws(() => parseModels(JSON.parse(text)), /Invalid models document/, text);
  const value = parseModels(JSON.parse('{"privacy":{"__proto__":{"localOnly":true}},"worker":{"__proto__":{"cacheMiB":1}}}'));
  assert.equal(value.privacy.localOnly, false);
  assert.equal(value.worker.cacheMiB, 64);
  assert.equal({}.localOnly, undefined);
});

test('endpoints: https anywhere, plain http only to this machine', () => {
  const accepted = {
    'https://api.openai.com/v1': 'https://api.openai.com/v1',
    'https://openrouter.ai/api/v1/': 'https://openrouter.ai/api/v1',
    'https://example.com:8443': 'https://example.com:8443',
    'http://localhost:11434': 'http://localhost:11434',
    'http://127.0.0.1:11434': 'http://127.0.0.1:11434',
    'http://127.8.9.10/v1': 'http://127.8.9.10/v1',
    'http://[::1]:11434/': 'http://[::1]:11434',
    'https://[::1]': 'https://[::1]',
    'https://192.168.1.20/v1': 'https://192.168.1.20/v1',
    '  HTTPS://API.Example.COM/V1  ': 'https://api.example.com/V1',
  };
  for (const [url, normalised] of Object.entries(accepted)) assert.deepEqual(validateEndpoint(url), { ok: true, url: normalised }, url);
  const insecure = ['http://api.openai.com/v1', 'http://192.168.1.20:11434', 'http://10.0.0.5', 'http://0.0.0.0:11434',
    'http://127.example.com', 'http://127.0.0.1.example.com', 'http://localhost.example.com', 'http://[::2]:11434', 'http://[fe80::1]'];
  for (const url of insecure) assert.deepEqual(validateEndpoint(url), { ok: false, reason: 'insecure-endpoint' }, url);
  const invalid = ['', '   ', 'localhost:11434', 'ftp://example.com', 'file:///etc/passwd', 'https://', 'https://user:pass@example.com',
    'https://example.com/v1?key=1', 'https://example.com/v1#frag', 'https://example.com:0', 'https://example.com:70000',
    'https://exa mple.com', 'https://example.com/a b', 'javascript:alert(1)', `https://example.com/${'a'.repeat(2048)}`, null, undefined, 42, {}];
  for (const url of invalid) assert.deepEqual(validateEndpoint(url), { ok: false, reason: 'invalid-url' }, String(url));
});

test('roles split at the first slash so model names keep their own slashes and colons', () => {
  assert.deepEqual(parseRole('local/qwen3.5:9b'), { providerId: 'local', model: 'qwen3.5:9b' });
  assert.deepEqual(parseRole('openrouter/anthropic/claude-sonnet'), { providerId: 'openrouter', model: 'anthropic/claude-sonnet' });
  assert.deepEqual(parseRole('local/hf.co/unsloth/Qwen-GGUF:Q4_K_M'), { providerId: 'local', model: 'hf.co/unsloth/Qwen-GGUF:Q4_K_M' });
  assert.deepEqual(parseRole('  local/model  '), { providerId: 'local', model: 'model' });
  for (const value of ['', 'local', '/model', 'local/', 'local/   ', 'Local/model', 'bad id/model', `local/${'m'.repeat(201)}`, 'local/a\nb', null, undefined, 7, {}])
    assert.equal(parseRole(value), null, String(value));
});

test('resolving a role returns the provider, model and role options', () => {
  const models = parseModels(sample());
  const chat = resolveRole(models, 'chat');
  assert.deepEqual(chat, { ok: true, provider: models.providers[0], model: 'qwen3.5:9b', roleOptions: { keepAlive: '' } });
  assert.deepEqual(resolveRole(models, 'embed'), { ok: true, provider: models.providers[0], model: 'embeddinggemma-2:270m', roleOptions: {} });
  assert.deepEqual(resolveRole(models, 'translate'), { ok: false, reason: 'not-configured' });
  assert.deepEqual(resolveRole(models, 'nonexistent'), { ok: false, reason: 'not-configured' });
  for (const role of ['constructor', 'toString', '__proto__', '', null, undefined])
    assert.deepEqual(resolveRole(models, role), { ok: false, reason: 'not-configured' }, String(role));
  for (const broken of [null, undefined, {}, { roles: null }, 'text'])
    assert.deepEqual(resolveRole(broken, 'chat'), { ok: false, reason: 'not-configured' });
});

test('a role bound to a removed provider is reported, never rerouted', () => {
  const input = sample();
  input.roles.chat = 'gone/some-model';
  const models = parseModels(input);
  assert.deepEqual(resolveRole(models, 'chat'), { ok: false, reason: 'unknown-provider' });
  assert.equal(resolveRole(models, 'fast').ok, true);
});

test('disclosure is local only for an endpoint on this machine', () => {
  assert.deepEqual(providerDisclosure(local, 'qwen3.5:9b'), { execution: 'local', provider: 'Ollama', host: '127.0.0.1', model: 'qwen3.5:9b' });
  assert.deepEqual(providerDisclosure(openai, 'gpt-x'), { execution: 'remote', provider: 'OpenAI', host: 'api.openai.com', model: 'gpt-x' });
  const at = baseUrl => providerDisclosure({ id: 'p', kind: 'ollama', name: 'P', baseUrl }, 'm');
  assert.deepEqual([at('http://localhost:11434').execution, at('http://localhost:11434').host], ['local', 'localhost']);
  assert.deepEqual([at('http://[::1]:11434').execution, at('http://[::1]:11434').host], ['local', '::1']);
  assert.equal(at('https://127.0.0.1:8443').execution, 'local');
  // A LAN machine, a look-alike host name and an unreadable endpoint all count as remote.
  assert.deepEqual([at('https://192.168.1.20').execution, at('https://192.168.1.20').host], ['remote', '192.168.1.20']);
  assert.equal(at('https://127.example.com').execution, 'remote');
  assert.equal(at('https://localhost.example.com').execution, 'remote');
  assert.deepEqual(at('not a url'), { execution: 'remote', provider: 'P', host: '', model: 'm' });
  assert.deepEqual(providerDisclosure(null, null), { execution: 'remote', provider: '', host: '', model: '' });
  assert.equal(providerDisclosure({ id: 'p', baseUrl: 'http://127.0.0.1:1' }, 'm').provider, 'p');
});

test('every provider kind from the spec is accepted', () => {
  assert.deepEqual(Array.from(providerKinds), ['ollama', 'openai-compatible', 'anthropic', 'gemini']);
  for (const kind of providerKinds)
    assert.equal(parseModels({ providers: [{ id: 'p', kind, baseUrl: 'https://example.com' }] }).providers[0].kind, kind);
});

test('review fixes: env names, loopback octets, cloud relays and nested secrets', () => {
  // Only conventional upper-case variable names: real token shapes such as gsk_/hf_ are refused.
  assert.equal(parseModels({ providers: [{ ...local, credentialEnv: 'OLLAMA_KEY' }] }).providers[0].credentialEnv, 'OLLAMA_KEY');
  for (const credentialEnv of ['gsk_' + 'a1B2'.repeat(12), 'hf_' + 'aBcD'.repeat(8), 'lower_case'])
    assert.throws(() => parseModels({ providers: [{ ...local, credentialEnv }] }), /credentialEnv/, credentialEnv);

  // 127.0.0.0/8 needs real octets; anything else is a DNS name and needs https.
  assert.equal(validateEndpoint('http://127.255.255.254:8080').ok, true);
  for (const url of ['http://127.300.0.1', 'http://127.0.0.256:11434', 'http://127.999.999.999'])
    assert.deepEqual(validateEndpoint(url), { ok: false, reason: 'insecure-endpoint' }, url);

  // Ollama cloud models leave the machine even though the endpoint is loopback.
  for (const model of ['gpt-oss:120b-cloud', 'qwen3-coder:480b-cloud', 'deepseek-v3.1:cloud'])
    assert.equal(providerDisclosure(local, model).execution, 'remote', model);
  assert.equal(providerDisclosure(local, 'qwen3.5:9b').execution, 'local');
  assert.equal(providerDisclosure({ ...local, kind: 'openai-compatible' }, 'my-cloud').execution, 'local');

  // Secret-looking keys anywhere in the document are refused; ordinary words are not.
  for (const doc of [
    { apiKey: 'x' },
    { roleOptions: { chat: { apiKey: 'x' } } },
    { providers: [{ ...local, headers: { Authorization: 'Bearer x' } }] },
    { providers: [{ ...local, extra: [{ client_secret: 'x' }] }] },
  ]) assert.throws(() => parseModels(doc), /not allowed/, JSON.stringify(doc));
  const kept = parseModels({ providers: [{ ...local, maxTokens: 4096, contextTokens: 8192 }], roleOptions: { chat: { maxTokens: 512 } } });
  assert.equal(kept.providers[0].maxTokens, 4096);
  assert.equal(kept.roleOptions.chat.maxTokens, 512);
});

// The shapes the worker's llm.models returns for the maintainer's Ollama (2026-11-18).
const GB = 1000 * 1000 * 1000;
const ollamaModels = () => [
  { name: 'qwen3.8:latest', sizeBytes: 17.7 * GB, capabilities: ['completion', 'tools'] },
  { name: 'gpt-oss:120b-cloud', sizeBytes: 384, capabilities: ['completion', 'tools', 'thinking'] },
  { name: 'embeddinggemma-2:270m', sizeBytes: 0.3 * GB, capabilities: ['embedding'] },
  { name: 'qwen3.5:9b', sizeBytes: 6.6 * GB, capabilities: ['completion', 'vision', 'tools', 'thinking'] },
  { name: 'qwen3.5:0.8b', sizeBytes: 1.3 * GB, capabilities: ['completion', 'vision', 'tools', 'thinking'] },
];

test('quick setup picks chat ≤ 10 GB, the smallest fast model, vision from chat and the first embedder', () => {
  assert.deepEqual(chooseLocalRoles(ollamaModels()), {
    chat: 'qwen3.5:9b', fast: 'qwen3.5:0.8b', vision: 'qwen3.5:9b', embed: 'embeddinggemma-2:270m',
  });
  // Cloud relays are never bound, even when they are the only "small" entry.
  assert.deepEqual(chooseLocalRoles([{ name: 'gpt-oss:120b-cloud', sizeBytes: 384, capabilities: ['completion'] }]),
    { chat: '', fast: '', vision: '', embed: '' });
  // Only models over the limit: no chat role, but the smallest still serves as fast.
  assert.deepEqual(chooseLocalRoles([{ name: 'big', sizeBytes: 17.7 * GB, capabilities: ['completion'] }]),
    { chat: '', fast: 'big', vision: '', embed: '' });
  // A chat model without "vision" leaves vision empty; unknown capabilities or size are skipped.
  assert.deepEqual(chooseLocalRoles([
    { name: 'text-only', sizeBytes: 4 * GB, capabilities: ['completion'] },
    { name: 'unknown-caps', sizeBytes: 5 * GB },
    { name: 'unknown-size', capabilities: ['completion', 'vision'] },
  ]), { chat: 'text-only', fast: 'text-only', vision: '', embed: '' });
  assert.deepEqual(chooseLocalRoles(null), { chat: '', fast: '', vision: '', embed: '' });
});

test('quick setup adds the local provider and fills only empty roles', () => {
  const fresh = applyLocalSetup(parseModels({}), ollamaModels());
  assert.equal(fresh.ok, true, fresh.message);
  assert.deepEqual(fresh.value.providers, [Object.assign({}, localOllama)]);
  assert.deepEqual(fresh.value.roles, { chat: 'local/qwen3.5:9b', fast: 'local/qwen3.5:0.8b', vision: 'local/qwen3.5:9b',
    embed: 'local/embeddinggemma-2:270m', translate: '' });
  assert.deepEqual(Object.keys(fresh.assigned).sort(), ['chat', 'embed', 'fast', 'vision']);
  assert.equal(fresh.providerId, 'local');

  // Existing roles and unknown keys survive; a provider "local" of another kind is not reused.
  const other = { id: 'local', kind: 'openai-compatible', name: 'llama.cpp', baseUrl: 'http://127.0.0.1:8080/v1', credential: '', credentialEnv: '' };
  const kept = applyLocalSetup(parseModels({ providers: [other], roles: { fast: 'local/tiny', custom: 'local/x' }, future: 1 }), ollamaModels());
  assert.equal(kept.ok, true, kept.message);
  assert.equal(kept.providerId, 'local-2');
  assert.deepEqual(kept.value.providers.map(item => item.id), ['local', 'local-2']);
  assert.equal(kept.value.roles.fast, 'local/tiny');
  assert.equal(kept.value.roles.custom, 'local/x');
  assert.equal(kept.value.roles.chat, 'local-2/qwen3.5:9b');
  assert.equal(kept.value.future, 1);
  assert.equal(Object.hasOwn(kept.assigned, 'fast'), false);

  // The same Ollama already listed under another id is reused, not duplicated.
  const listed = applyLocalSetup(parseModels({ providers: [{ ...localOllama, id: 'home', name: 'Home' }] }), ollamaModels());
  assert.deepEqual(listed.value.providers.map(item => item.id), ['home']);
  assert.equal(listed.value.roles.chat, 'home/qwen3.5:9b');

  assert.equal(applyLocalSetup(parseModels({}), []).reason, 'no-models');
  assert.equal(applyLocalSetup(fresh.value, ollamaModels()).reason, 'no-change');
});

test('inline providers follow the document rules and keep only worker fields', () => {
  assert.deepEqual(inlineProvider({ kind: 'ollama', baseUrl: 'http://127.0.0.1:11434/', extra: 1 }),
    { ok: true, provider: { id: 'custom', kind: 'ollama', name: 'Ollama', baseUrl: 'http://127.0.0.1:11434', credential: '', credentialEnv: '' } });
  assert.equal(inlineProvider({ kind: 'openai-compatible', baseUrl: 'http://example.org/v1' }).reason, 'denied');
  assert.equal(inlineProvider({ kind: 'nope', baseUrl: 'https://example.org' }).reason, 'invalid-input');
  assert.equal(inlineProvider({ kind: 'ollama', baseUrl: 'not a url' }).reason, 'invalid-input');
  assert.equal(inlineProvider({ kind: 'ollama', baseUrl: 'http://localhost:11434', credential: 'pentad-chat-api' }).reason, 'invalid-input');
  assert.equal(inlineProvider({ kind: 'ollama', baseUrl: 'http://localhost:11434', credentialEnv: 'lower_case' }).reason, 'invalid-input');
  assert.equal(inlineProvider({ kind: 'ollama', baseUrl: 'http://localhost:11434', id: 'Bad Id' }).reason, 'invalid-input');
  assert.equal(inlineProvider(null).ok, false);
});

test('Move to Models imports an endpoint, binds an empty role and never takes a bound one', () => {
  const endpoint = { id: 'custom', kind: 'openai-compatible', name: 'api.openai.com', baseUrl: 'https://api.openai.com/v1', credential: '', credentialEnv: 'OPENAI_API_KEY' };
  const first = importEndpoint(parseModels({}), endpoint, 'gpt-4o', 'chat');
  assert.equal(first.ok, true, first.message);
  assert.equal(first.changed, true);
  assert.equal(first.binding, 'openai/gpt-4o');
  assert.deepEqual(first.value.providers, [{ id: 'openai', kind: 'openai-compatible', name: 'api.openai.com',
    baseUrl: 'https://api.openai.com/v1', credential: '', credentialEnv: 'OPENAI_API_KEY' }]);
  assert.equal(first.value.roles.chat, 'openai/gpt-4o');
  // Again: nothing to change.
  const again = importEndpoint(first.value, endpoint, 'gpt-4o', 'chat');
  assert.equal(again.ok, true);
  assert.equal(again.changed, false);
  // A bound role is reported, never overwritten.
  const taken = importEndpoint(first.value, endpoint, 'gpt-4o-mini', 'chat');
  assert.deepEqual([taken.ok, taken.reason, taken.current], [false, 'role-taken', 'openai/gpt-4o']);
  // The same endpoint with another key reference is another provider; a loopback endpoint is "local".
  const fast = importEndpoint(first.value, Object.assign({}, endpoint, { credentialEnv: 'WORK_KEY' }), 'gpt-4o-mini', 'fast');
  assert.equal(fast.binding, 'openai-2/gpt-4o-mini');
  const local = importEndpoint(parseModels({}), { kind: 'ollama', baseUrl: 'http://127.0.0.1:11434' }, 'qwen3.5:9b', 'chat');
  assert.equal(local.binding, 'local/qwen3.5:9b');
  assert.equal(local.value.providers[0].name, 'Ollama');
  assert.equal(importEndpoint(parseModels({}), endpoint, '', 'chat').reason, 'invalid-input');
  assert.equal(importEndpoint(parseModels({}), Object.assign({}, endpoint, { baseUrl: 'http://example.org' }), 'm', 'chat').reason, 'denied');
});
