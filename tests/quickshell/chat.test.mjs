import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { chatProfile, createChatService } from '../../quickshell/logic/chat.mjs';
import { validateManifest } from '../../quickshell/logic/plugin-manifest.mjs';

const ollamaSettings = { provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', model: 'fixture' };
const flush = async () => { await Promise.resolve(); await Promise.resolve(); await new Promise(resolve => setImmediate(resolve)); };

test('chat profiles permit HTTPS and loopback HTTP but reject unsafe endpoints and malformed env refs', () => {
  assert.equal(chatProfile({ provider: 'api', baseUrl: 'http://example.org', model: 'm' }), null);
  assert.equal(chatProfile({ provider: 'ollama', baseUrl: 'http://127.0.0.1:11434/', model: 'm' }).baseUrl,
    'http://127.0.0.1:11434');
  assert.equal(chatProfile({ provider: 'api', baseUrl: 'https://api.example/v1', model: 'm', apiKeyEnv: 'INVALID-NAME' }), null);
  assert.equal(chatProfile({ provider: 'api', baseUrl: 'https://api.example/v1', model: 'm', apiKeyEnv: 'PENTAD_API_KEY' }).setup, false);
});

test('chat manifest is a sidebar widget and stores only credential references or environment names', async () => {
  const manifest = JSON.parse(await readFile(new URL('../../quickshell/widgets/chat/manifest.json', import.meta.url), 'utf8'));
  assert.equal(validateManifest(manifest, { slot: 'sidebar-left' }).ok, true);
  assert.deepEqual(manifest.defaults, { provider: 'api', baseUrl: '', model: '', credentialRef: 'pentad-chat-api', apiKeyEnv: '' });
  assert.equal(Object.hasOwn(manifest.defaults, 'apiKey'), false);
});

test('Ollama session streams fake deltas, isolates state, and sends no API key', async () => {
  const requests = [];
  const service = createChatService({
    apiKeyFor: async () => 'never-called',
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
  assert.equal(requests[0].cancellation.isCancelled(), false);
  first.release(); other.release(); service.dispose();
});

test('API credential is requested by environment name and never enters persisted session state', async () => {
  let requestedName = '';
  let observedKey = '';
  const service = createChatService({
    apiKeyFor: async name => { requestedName = name; return 'test-only-secret'; },
    changed: () => {},
    stream: async (_profile, _messages, key, _cancel, onDelta) => {
      observedKey = key;
      onDelta({ type: 'text', text: 'ok' });
      onDelta({ type: 'done', reason: 'stop' });
    },
  });
  const session = service.acquire('api-main', { provider: 'api', baseUrl: 'https://api.example/v1', model: 'model', apiKeyEnv: 'PENTAD_API_KEY' });
  await session.send('hello');
  assert.equal(requestedName, 'PENTAD_API_KEY');
  assert.equal(observedKey, 'test-only-secret');
  assert.equal(JSON.stringify(session.read()).includes('test-only-secret'), false);
  session.release(); service.dispose();
});

test('stop invalidates a late stream delta and releases the active generation', async () => {
  let emit;
  let cancel;
  const service = createChatService({
    apiKeyFor: async () => '', changed: () => {},
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
