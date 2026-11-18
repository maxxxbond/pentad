import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import {
  chatFailureMessage, chatModelSource, chatProfile, createChatService, customProvider, layoutWithModelSource,
} from '../../quickshell/logic/chat.mjs';
import { validateManifest, validateSettings } from '../../quickshell/logic/plugin-manifest.mjs';

const ollamaSettings = { provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', model: 'fixture' };
const flush = async () => { await Promise.resolve(); await Promise.resolve(); await new Promise(resolve => setImmediate(resolve)); };
const uk = (ukText, en) => ukText;

test('custom chat profiles permit HTTPS and loopback HTTP but reject unsafe endpoints and malformed env refs', () => {
  assert.equal(chatProfile({ provider: 'api', baseUrl: 'http://example.org', model: 'm' }), null);
  assert.equal(chatProfile({ provider: 'ollama', baseUrl: 'http://127.0.0.1:11434/', model: 'm' }).baseUrl,
    'http://127.0.0.1:11434');
  assert.equal(chatProfile({ provider: 'api', baseUrl: 'https://api.example/v1', model: 'm', apiKeyEnv: 'INVALID-NAME' }), null);
  assert.equal(chatProfile({ provider: 'api', baseUrl: 'https://api.example/v1', model: 'm', apiKeyEnv: 'lower_case' }), null);
  assert.equal(chatProfile({ provider: 'api', baseUrl: 'https://api.example/v1', model: 'm', apiKeyEnv: 'PENTAD_API_KEY' }).setup, false);
  assert.equal(chatProfile({ modelSource: 'custom', provider: 'api', baseUrl: '', model: '' }).setup, true);
});

test('the model source: stored values win, legacy placements with an endpoint stay custom', () => {
  assert.equal(chatModelSource({}), 'registry');
  assert.equal(chatModelSource(null), 'registry');
  assert.equal(chatModelSource({ provider: 'api', baseUrl: '', model: '', credentialRef: 'pentad-chat-api', apiKeyEnv: '' }), 'registry');
  assert.equal(chatModelSource({ baseUrl: '  ', model: '' }), 'registry');
  assert.equal(chatModelSource({ baseUrl: 'https://api.openai.com/v1', model: '' }), 'custom');
  assert.equal(chatModelSource({ baseUrl: '', model: 'gpt-4o' }), 'custom');
  assert.equal(chatModelSource({ modelSource: 'registry', baseUrl: 'https://api.openai.com/v1', model: 'gpt' }), 'registry');
  assert.equal(chatModelSource({ modelSource: 'custom' }), 'custom');
  assert.deepEqual(chatProfile({ modelSource: 'registry', modelRole: 'fast', baseUrl: 'http://example.org' }),
    { source: 'registry', role: 'fast', setup: false });
  assert.deepEqual(chatProfile({}), { source: 'registry', role: 'chat', setup: false });
});

test('a custom profile becomes an inline provider: api is OpenAI-compatible, only secret:// refs are credentials', () => {
  assert.deepEqual(customProvider(chatProfile({ provider: 'api', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o',
    apiKeyEnv: 'OPENAI_API_KEY', credentialRef: 'pentad-chat-api' })), {
    id: 'custom', kind: 'openai-compatible', name: 'api.openai.com', baseUrl: 'https://api.openai.com/v1', credential: '', credentialEnv: 'OPENAI_API_KEY',
  });
  assert.deepEqual(customProvider(chatProfile({ provider: 'ollama', baseUrl: 'http://localhost:11434', model: 'qwen3.5:9b',
    credentialRef: 'secret://pentad/providers/openai' })), {
    id: 'custom', kind: 'ollama', name: 'Ollama', baseUrl: 'http://localhost:11434', credential: 'secret://pentad/providers/openai', credentialEnv: '',
  });
  assert.equal(customProvider(chatProfile({})), null);
  assert.equal(customProvider(chatProfile({ modelSource: 'custom', provider: 'api', baseUrl: '', model: '' })), null);
});

test('chat manifest 1.1.0 declares llm.chat, model source fields and uk/en labels; legacy fields show only for custom', async () => {
  const manifest = JSON.parse(await readFile(new URL('../../quickshell/widgets/chat/manifest.json', import.meta.url), 'utf8'));
  assert.equal(validateManifest(manifest, { slot: 'sidebar-left' }).ok, true);
  assert.equal(manifest.version, '1.1.0');
  assert.deepEqual(manifest.capabilities, ['llm.chat']);
  assert.deepEqual(manifest.defaults, { modelSource: 'registry', modelRole: 'chat', provider: 'api', baseUrl: '', model: '', credentialRef: 'pentad-chat-api', apiKeyEnv: '' });
  assert.equal(Object.hasOwn(manifest.defaults, 'apiKey'), false);
  for (const field of manifest.settingsFields) {
    assert.ok(field.labelUk && field.labelEn && field.label, field.key);
    for (const option of field.options || []) assert.ok(option.labelUk && option.labelEn, `${field.key}.${option.value}`);
  }
  const shown = Object.fromEntries(manifest.settingsFields.map(field => [field.key, field.showWhen || null]));
  for (const key of ['provider', 'baseUrl', 'model', 'credentialRef', 'apiKeyEnv'])
    assert.deepEqual(shown[key], { key: 'modelSource', equals: 'custom' }, key);
  assert.deepEqual(shown.modelRole, { key: 'modelSource', equals: 'registry' });
  // Every legacy placement still validates, migrated or not.
  assert.equal(validateSettings(manifest, { provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', model: 'm', modelSource: 'custom' }).ok, true);
  assert.equal(validateSettings(manifest, { provider: 'api', baseUrl: '', model: '', credentialRef: 'pentad-chat-api', apiKeyEnv: '' }).ok, true);
  assert.equal(validateSettings(manifest, { modelSource: 'elsewhere' }).ok, false);
});

test('a custom Ollama session streams fake deltas, isolates state, and never sees a key', async () => {
  const requests = [];
  const service = createChatService({
    changed: () => {},
    stream: async (profile, messages, key, cancellation, onDelta) => {
      requests.push({ profile, messages, key, cancellation });
      onDelta({ type: 'text', text: 'Привіт' });
      onDelta({ type: 'done', reason: 'stop' });
    },
  });
  const first = service.acquire('main', ollamaSettings);
  const other = service.acquire('main', { ...ollamaSettings, model: 'other' });
  await first.send('hello');
  assert.equal(first.read().status, 'idle');
  assert.equal(first.read().messages[1].content, 'Привіт');
  assert.equal(other.read().messages.length, 0);
  assert.equal(requests[0].key, '');
  assert.equal(requests[0].profile.instanceId, 'main');
  assert.equal(requests[0].profile.source, 'custom');
  assert.equal(requests[0].cancellation.isCancelled(), false);
  first.release(); other.release(); service.dispose();
});

test('a registry session asks for its role and carries the instance id', async () => {
  let seen = null;
  const service = createChatService({
    changed: () => {},
    stream: async (profile, _messages, _key, _cancel, onDelta) => { seen = profile; onDelta({ type: 'done', reason: 'stop' }); },
  });
  const session = service.acquire('chat-main', { modelSource: 'registry', modelRole: 'fast' });
  assert.equal(session.read().status, 'idle');
  await session.send('hi');
  assert.deepEqual(seen, { instanceId: 'chat-main', source: 'registry', role: 'fast', setup: false });
  session.release(); service.dispose();
});

test('a custom API endpoint needs a key reference before anything is sent, and keys never enter state', async () => {
  let streamed = 0;
  let profileSeen = null;
  const service = createChatService({
    changed: () => {}, text: uk,
    stream: async (profile, _messages, key, _cancel, onDelta) => {
      streamed++; profileSeen = profile;
      assert.equal(key, '');
      onDelta({ type: 'text', text: 'ok' });
      onDelta({ type: 'done', reason: 'stop' });
    },
  });
  const base = { provider: 'api', baseUrl: 'https://api.example/v1', model: 'model' };
  const missing = service.acquire('api-missing', { ...base, credentialRef: 'pentad-chat-api' });
  assert.equal(await missing.send('hello'), false);
  assert.equal(streamed, 0);
  assert.match(missing.read().error, /pentad-chat-api/);
  assert.match(missing.read().error, /змінну середовища/);
  const session = service.acquire('api-main', { ...base, apiKeyEnv: 'PENTAD_API_KEY' });
  await session.send('hello');
  assert.equal(streamed, 1);
  assert.equal(profileSeen.apiKeyEnv, 'PENTAD_API_KEY');
  assert.equal(customProvider(profileSeen).credentialEnv, 'PENTAD_API_KEY');
  assert.equal(JSON.stringify(session.read()).includes('PENTAD_API_KEY'), false);
  missing.release(); session.release(); service.dispose();
});

test('stop invalidates a late stream delta and releases the active generation', async () => {
  let emit;
  let cancel;
  const service = createChatService({
    changed: () => {},
    stream: (_profile, _messages, _key, token, onDelta) => {
      emit = onDelta; cancel = token;
      return new Promise(resolve => token.subscribe(resolve));
    },
  });
  const session = service.acquire('cancel-main', ollamaSettings);
  const pending = session.send('wait');
  await flush();
  session.stop();
  emit({ type: 'text', text: 'late' });
  assert.equal(cancel.isCancelled(), true);
  assert.equal(session.read().messages[1].content, '');
  await pending;
  session.release(); service.dispose();
});

test('a failed stream shows its message and keeps a partial answer', async () => {
  const service = createChatService({
    changed: () => {},
    stream: async (_profile, _messages, _key, _cancel, onDelta) => {
      onDelta({ type: 'text', text: 'half' });
      throw new Error(chatFailureMessage({ ok: false, reason: 'timeout' }));
    },
  });
  const session = service.acquire('fail-main', {});
  assert.equal(await session.send('hi'), false);
  assert.equal(session.read().status, 'error');
  assert.equal(session.read().error, 'The model did not answer in time.');
  assert.equal(session.read().messages[1].status, 'partial');
  session.release(); service.dispose();
});

test('capability failures read as short uk/en messages', () => {
  assert.equal(chatFailureMessage({ reason: 'unavailable', message: 'not-configured' }), 'No chat model is set up yet.');
  assert.equal(chatFailureMessage({ reason: 'not-configured' }, uk), 'Модель для чату ще не вибрано.');
  assert.equal(chatFailureMessage({ reason: 'unknown-provider' }), 'The chat role names a provider that is no longer in Models.');
  assert.equal(chatFailureMessage({ reason: 'denied', message: 'remote models are disabled (local only)' }), 'Remote models are turned off (local only).');
  assert.equal(chatFailureMessage({ reason: 'safe-mode', message: 'llm.chat is disabled in safe mode' }, uk), 'У безпечному режимі чат вимкнено.');
  assert.equal(chatFailureMessage({ reason: 'unavailable', message: 'The credential environment variable is not set' }),
    'The model is unavailable: The credential environment variable is not set');
  assert.equal(chatFailureMessage({ reason: 'io', message: 'HTTP 500' }), 'HTTP 500');
  assert.equal(chatFailureMessage({ reason: 'io' }), 'Chat request failed.');
  assert.equal(chatFailureMessage(null), 'Chat request failed.');
});

test('moving a placement to the registry flips only its modelSource and keeps its endpoint', () => {
  const layout = { schemaVersion: 1, widgets: [
    { instanceId: 'w', moduleId: 'pentad.weather', slot: 'sidebar-left', enabled: true, settings: { city: 'Kyiv' } },
    { instanceId: 'chat-main', moduleId: 'pentad.chat', slot: 'sidebar-left', enabled: true,
      settings: { modelSource: 'custom', provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', model: 'm', _margin: 4 } },
  ] };
  const moved = layoutWithModelSource(layout, 'chat-main', 'registry');
  assert.equal(moved.ok, true);
  assert.equal(moved.changed, true);
  assert.deepEqual(moved.value.widgets[1].settings,
    { modelSource: 'registry', provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', model: 'm', _margin: 4 });
  assert.equal(moved.value.widgets[0], layout.widgets[0]);
  assert.equal(layout.widgets[1].settings.modelSource, 'custom', 'the input is not mutated');
  assert.equal(layoutWithModelSource(moved.value, 'chat-main', 'registry').changed, false);
  assert.equal(layoutWithModelSource(layout, 'w', 'registry').reason, 'missing');
  assert.equal(layoutWithModelSource(null, 'chat-main', 'registry').ok, false);
});
