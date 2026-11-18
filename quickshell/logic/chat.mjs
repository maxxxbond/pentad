import { inlineProvider, validateEndpoint } from './models.mjs';

const MAX_MESSAGE_BYTES = 16 * 1024;
const MAX_RESPONSE_BYTES = 1024 * 1024;
const utf8Length = value => {
  const text = String(value);
  let bytes = 0;
  for (let index = 0; index < text.length; index++) {
    const code = text.charCodeAt(index);
    if (code < 0x80) bytes++;
    else if (code < 0x800) bytes += 2;
    else if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length
        && text.charCodeAt(index + 1) >= 0xdc00 && text.charCodeAt(index + 1) <= 0xdfff) { bytes += 4; index++; }
    else bytes += 3;
  }
  return bytes;
};
const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const trimmed = value => typeof value === 'string' ? value.trim() : '';
const english = (uk, en) => en;
const envNamePattern = /^[A-Z_][A-Z0-9_]{0,127}$/;
const secretRefPattern = /^secret:\/\/pentad\/[a-z0-9._-]+(?:\/[a-z0-9._-]+)*$/;

// Where a placement takes its model from. Placements saved before model sources existed keep their
// own endpoint ("custom") when they name a base URL or a model; everything else uses the registry.
// The layout parser stores the answer, so this runs once per placement.
export function chatModelSource(settings) {
  if (!isObject(settings)) return 'registry';
  if (settings.modelSource === 'custom' || settings.modelSource === 'registry') return settings.modelSource;
  return trimmed(settings.baseUrl) || trimmed(settings.model) ? 'custom' : 'registry';
}

// The model a placement asks for: a registry role, or (custom) its own endpoint. null when the
// custom endpoint cannot be used at all; `setup` when it still lacks a base URL or a model.
export function chatProfile(settings) {
  if (!isObject(settings)) return null;
  const role = settings.modelRole === 'fast' ? 'fast' : 'chat';
  if (chatModelSource(settings) === 'registry') return { source: 'registry', role, setup: false };
  const provider = settings.provider === 'ollama' ? 'ollama' : settings.provider === 'api' ? 'api' : null;
  const baseUrl = trimmed(settings.baseUrl);
  const model = trimmed(settings.model);
  const apiKeyEnv = trimmed(settings.apiKeyEnv);
  const credentialRef = trimmed(settings.credentialRef);
  if (!provider || baseUrl.length > 2048 || model.length > 200 || apiKeyEnv.length > 128
      || credentialRef.length > 160 || (apiKeyEnv && !envNamePattern.test(apiKeyEnv))) return null;
  if (!baseUrl || !model) return { source: 'custom', role, provider, baseUrl, model, apiKeyEnv, credentialRef, setup: true };
  const endpoint = validateEndpoint(baseUrl);
  if (!endpoint.ok) return null;
  return { source: 'custom', role, provider, baseUrl: endpoint.url, model, apiKeyEnv, credentialRef, setup: false };
}

// The inline provider a custom profile hands to services.capabilities (host-internal option).
// The legacy `api` provider is OpenAI-compatible; a `secret://` credentialRef becomes the
// credential, anything else in it is ignored; apiKeyEnv becomes credentialEnv.
export function customProvider(profile) {
  if (!isObject(profile) || profile.source !== 'custom' || profile.setup) return null;
  const checked = inlineProvider({
    id: 'custom',
    kind: profile.provider === 'ollama' ? 'ollama' : 'openai-compatible',
    name: profile.provider === 'ollama' ? 'Ollama' : (/^https?:\/\/([^/:]+|\[[^\]]+\])/i.exec(profile.baseUrl) || ['', ''])[1].toLowerCase().replace(/^\[|\]$/g, ''),
    baseUrl: profile.baseUrl,
    credential: secretRefPattern.test(profile.credentialRef) ? profile.credentialRef : '',
    credentialEnv: profile.apiKeyEnv,
  });
  return checked.ok ? checked.provider : null;
}

// A custom OpenAI-compatible endpoint needs a key reference before anything is sent.
function missingCredential(profile, text) {
  if (profile.source !== 'custom' || profile.provider !== 'api' || profile.apiKeyEnv || secretRefPattern.test(profile.credentialRef)) return '';
  return profile.credentialRef
    ? text(`Посилання на ключ ${profile.credentialRef} не читається. Вкажіть змінну середовища з ключем API у налаштуваннях віджета.`,
      `Saved credential reference ${profile.credentialRef} cannot be read. Set an API key environment variable in widget settings.`)
    : text('Ключ API не налаштовано. Вкажіть змінну середовища з ключем у налаштуваннях віджета.',
      'API credential is not configured. Set an API key environment variable in widget settings.');
}

// User-facing text for a failed capability result ({ ok: false, reason, message }) or an
// availability answer ({ available: false, reason }, where the registry reasons come bare).
export function chatFailureMessage(result, text) {
  const t = typeof text === 'function' ? text : english;
  const reason = isObject(result) && typeof result.reason === 'string' ? result.reason : 'io';
  const message = isObject(result) && typeof result.message === 'string' ? result.message.trim() : '';
  if (reason === 'not-configured' || reason === 'unavailable' && message === 'not-configured')
    return t('Модель для чату ще не вибрано.', 'No chat model is set up yet.');
  if (reason === 'unknown-provider' || reason === 'unavailable' && message === 'unknown-provider')
    return t('Роль чату вказує на постачальника, якого вже немає в Моделях.', 'The chat role names a provider that is no longer in Models.');
  if (reason === 'denied' && /local only/.test(message))
    return t('Віддалені моделі вимкнено (лише локальні).', 'Remote models are turned off (local only).');
  const known = {
    'safe-mode': t('У безпечному режимі чат вимкнено.', 'Chat is off in safe mode.'),
    preview: t('У попередньому перегляді чат не працює.', 'Chat does not run in preview.'),
    timeout: t('Модель не відповіла вчасно.', 'The model did not answer in time.'),
    busy: t('Постачальник зайнятий. Спробуйте трохи згодом.', 'The provider is busy. Try again shortly.'),
    cancelled: t('Запит скасовано.', 'Chat request cancelled.'),
    'service-stopped': t('Робочий процес моделей зупинився. Спробуйте ще раз.', 'The model worker stopped. Try again.'),
    'service-missing': t('Служба моделей недоступна.', 'The model service is not available.'),
  };
  if (Object.prototype.hasOwnProperty.call(known, reason)) return known[reason];
  if (reason === 'unavailable')
    return message ? t(`Модель недоступна: ${message}`, `The model is unavailable: ${message}`) : t('Модель недоступна.', 'The model is unavailable.');
  return message || t('Запит до моделі не вдався.', 'Chat request failed.');
}

// "Move to Models", second step: the placement switches to the registry. Its own endpoint keys
// stay, so switching back to "custom" restores it.
export function layoutWithModelSource(layout, instanceId, source) {
  if (!isObject(layout) || !Array.isArray(layout.widgets)) return { ok: false, reason: 'invalid', message: 'Invalid layout' };
  const index = layout.widgets.findIndex(item => isObject(item) && item.instanceId === instanceId && item.moduleId === 'pentad.chat');
  if (index < 0) return { ok: false, reason: 'missing', message: 'The chat placement is not in the layout' };
  const placement = layout.widgets[index];
  if (isObject(placement.settings) && placement.settings.modelSource === source) return { ok: true, value: layout, changed: false };
  const widgets = layout.widgets.slice();
  widgets[index] = Object.assign({}, placement, { settings: Object.assign({}, placement.settings, { modelSource: source }) });
  return { ok: true, value: Object.assign({}, layout, { widgets }), changed: true };
}

function createCancellation() {
  let cancelled = false;
  const listeners = new Set();
  return {
    isCancelled: () => cancelled,
    subscribe(listener) {
      if (cancelled) listener(); else listeners.add(listener);
      return () => listeners.delete(listener);
    },
    cancel() {
      if (cancelled) return;
      cancelled = true;
      for (const listener of [...listeners]) listener();
      listeners.clear();
    },
  };
}

// stream(profile, messages, key, cancellation, onDelta) runs one request. Keys never reach this
// module: the worker resolves them, so `key` is always ''. profile carries instanceId for routing.
export function createChatService({ stream, changed, preview = false, safeMode = false, text = english }) {
  const t = typeof text === 'function' ? text : english;
  const sessions = new Map();
  let serial = 0;
  const publish = entry => {
    changed(entry.instanceId, entry.state);
    entry.subscribers.forEach(listener => { try { listener(entry.state); } catch (error) {  } });
  };
  const update = (entry, values) => { entry.state = Object.assign({}, entry.state, values); publish(entry); };
  const stop = entry => {
    if (!entry.cancel) return;
    entry.cancel.cancel();
    entry.cancel = null;
    entry.generation++;
    const messages = entry.state.messages.map(message => message.id === entry.activeAssistant
      ? Object.assign({}, message, { status: message.content ? 'partial' : 'failed' }) : message);
    entry.activeAssistant = null;
    update(entry, { messages, status: 'stopped', error: '' });
  };
  return {
    acquire(instanceId, settings) {
      const profile = chatProfile(settings);
      const fingerprint = JSON.stringify(profile);
      let entry = sessions.get(instanceId);
      if (!entry || entry.fingerprint !== fingerprint) {
        if (entry) stop(entry);
        entry = { instanceId, fingerprint, profile, refs: 0, generation: 0, cancel: null,
          activeAssistant: null, subscribers: new Set(), state: { messages: [], draft: '', status: profile?.setup ? 'setup' : 'idle', error: '' } };
        sessions.set(instanceId, entry);
      }
      entry.refs++;
      let released = false;
      return {
        profile: () => entry.profile,
        read: () => entry.state,
        subscribe(listener) {
          if (released) return () => {};
          entry.subscribers.add(listener);
          listener(entry.state);
          let active = true;
          return () => {
            if (!active) return;
            active = false;
            entry.subscribers.delete(listener);
            if (entry.subscribers.size === 0) stop(entry);
          };
        },
        setDraft(draft) { entry.state = Object.assign({}, entry.state, { draft: String(draft).slice(0, 4096) }); publish(entry); },
        send: function(input) {
          const value = String(input).trim();
          if (preview || safeMode) { update(entry, { status: 'error', error: t('У попередньому перегляді та безпечному режимі чат вимкнено.', 'Chat requests are disabled in preview and safe mode.') }); return false; }
          if (!entry.profile || entry.profile.setup) { update(entry, { status: 'setup', error: t('Вкажіть постачальника, адресу й модель у налаштуваннях віджета.', 'Choose a provider, endpoint, and model in widget settings.') }); return false; }
          if (!value) return false;
          if (utf8Length(value) > MAX_MESSAGE_BYTES) { update(entry, { status: 'error', error: t('Повідомлення більше за 16 КіБ.', 'Message exceeds 16 KiB.') }); return false; }
          if (entry.cancel) return false;
          if (entry.state.messages.some(message => ['partial', 'failed'].includes(message.status))) {
            update(entry, { status: 'error', error: t('Повторіть або очистьте незавершену відповідь, перш ніж надсилати.', 'Retry or clear the incomplete response before sending.') }); return false;
          }
          const missing = missingCredential(entry.profile, t);
          if (missing) { update(entry, { status: 'error', error: missing }); return false; }
          const user = { id: `chat-${++serial}`, role: 'user', content: value, status: 'complete' };
          const assistant = { id: `chat-${++serial}`, role: 'assistant', content: '', status: 'partial' };
          const messages = [...entry.state.messages, user, assistant];
          if (messages.length > 100) { update(entry, { status: 'error', error: t('Розмова досягла межі в 100 повідомлень. Очистьте її, щоб продовжити.', 'Conversation reached its 100 message limit. Clear it to continue.') }); return false; }
          entry.activeAssistant = assistant.id;
          const generation = ++entry.generation;
          const cancel = createCancellation();
          entry.cancel = cancel;
          update(entry, { messages, draft: '', status: 'sending', error: '' });
          const request = Object.assign({ instanceId }, entry.profile);
          let responseBytes = 0;
          const fail = error => {
            if (generation === entry.generation && !cancel.isCancelled()) {
              const message = error instanceof Error ? error.message : t('Запит до моделі не вдався.', 'Chat request failed.');
              update(entry, { messages: entry.state.messages.map(item => item.id === assistant.id
                ? Object.assign({}, item, { status: item.content ? 'partial' : 'failed' }) : item), status: 'error', error: message });
              entry.activeAssistant = null;
            }
          };
          return Promise.resolve().then(() => stream(request, messages.slice(0, -1), '', cancel, delta => {
              if (generation !== entry.generation || cancel.isCancelled()) return;
              if (delta.type === 'text') {
                responseBytes += utf8Length(delta.text);
                if (responseBytes > MAX_RESPONSE_BYTES) throw new Error(t('Відповідь більша за 1 МіБ.', 'Response exceeded 1 MiB.'));
                const next = entry.state.messages.map(message => message.id === assistant.id
                  ? Object.assign({}, message, { content: message.content + delta.text }) : message);
                entry.state = Object.assign({}, entry.state, { messages: next, status: 'streaming' });
                publish(entry);
              } else if (delta.type === 'done') {
                const stopped = delta.reason && delta.reason !== 'stop';
                const next = entry.state.messages.map(message => message.id === assistant.id
                  ? Object.assign({}, message, { status: stopped ? 'partial' : 'complete' }) : message);
                entry.state = Object.assign({}, entry.state, { messages: next,
                  status: stopped ? 'error' : 'idle',
                  error: stopped ? t(`Відповідь обірвано (${delta.reason}).`, `Response ended (${delta.reason}).`) : '' });
                publish(entry);
                entry.activeAssistant = null;
              }
            })).then(() => {
            if (generation === entry.generation && !cancel.isCancelled() && entry.state.status !== 'error'
                && entry.activeAssistant === assistant.id) throw new Error(t('Відповідь закінчилася без позначки завершення.', 'Provider stream ended before its completion marker.'));
          }).then(() => {}, fail).then(() => {
            if (generation === entry.generation) entry.cancel = null;
            return entry.state.status === 'idle';
          });
        },
        stop: () => stop(entry),
        clear() { stop(entry); update(entry, { messages: [], draft: '', status: entry.profile?.setup ? 'setup' : 'idle', error: '' }); },
        release() { if (released) return; released = true; entry.refs = Math.max(0, entry.refs - 1); },
      };
    },
    dispose() { for (const entry of sessions.values()) stop(entry); sessions.clear(); },
    diagnostics() { return { sessions: sessions.size, active: [...sessions.values()].filter(entry => !!entry.cancel).length }; },
  };
}
