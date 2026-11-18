import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import {
  modelsDefaults, parseModels, parseRole, providerDisclosure, providerKinds, resolveRole, validateEndpoint,
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
