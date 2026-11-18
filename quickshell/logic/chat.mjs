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

// Worker and helper messages are English diagnostics. They follow the localized sentence only in
// the English interface; other languages get the sentence and, when there is one, the HTTP status.
function withDetail(t, uk, en, message) {
  if (!message) return t(uk, en);
  const status = /\bHTTP (\d{3})\b/.exec(message);
  return t(status ? `${uk.replace(/\.$/, '')} (HTTP ${status[1]}).` : uk, `${en.replace(/\.$/, '')}: ${message}`);
}

// User-facing text for a failed capability result ({ ok: false, reason, message }) or an
// availability answer ({ available: false, reason }, where the registry reasons come bare).
// Every `Result` reason has its own sentence in both languages.
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
  if (reason === 'unavailable' && (message === 'crash-loop' || message === 'worker unavailable' || message === 'unavailable'))
    return t('Робочий процес моделей не запускається. Спробуйте ще раз за пів хвилини.', 'The model worker does not start. Try again in half a minute.');
  const fixed = {
    'safe-mode': t('У безпечному режимі чат вимкнено.', 'Chat is off in safe mode.'),
    preview: t('У попередньому перегляді чат не працює.', 'Chat does not run in preview.'),
    timeout: t('Модель не відповіла вчасно.', 'The model did not answer in time.'),
    cancelled: t('Запит скасовано.', 'Chat request cancelled.'),
    'service-stopped': t('Робочий процес моделей зупинився. Спробуйте ще раз.', 'The model worker stopped. Try again.'),
    'service-missing': t('Служба моделей недоступна.', 'The model service is not available.'),
  };
  if (Object.prototype.hasOwnProperty.call(fixed, reason)) return fixed[reason];
  const detailed = {
    busy: ['Постачальник зайнятий. Спробуйте трохи згодом.', 'The provider is busy. Try again shortly.'],
    unavailable: ['Модель недоступна.', 'The model is unavailable.'],
    denied: ['Запит відхилено. Перевірте ключ постачальника й дозволи.', 'The request was refused. Check the provider key and permissions.'],
    'invalid-input': ['Запит до моделі містить недійсні дані.', 'The request to the model is not valid.'],
    'invalid-response': ['Постачальник надіслав відповідь, яку не вдалося прочитати.', 'The provider sent an answer that could not be read.'],
    unsupported: ['Постачальник або модель не підтримує такий запит.', 'The provider or model does not support this request.'],
    io: ['Запит до моделі не вдався.', 'Chat request failed.'],
  };
  const pair = Object.prototype.hasOwnProperty.call(detailed, reason) ? detailed[reason] : detailed.io;
  return withDetail(t, pair[0], pair[1], message);
}

// Why an answer stopped before its natural end (`finishReason` other than `stop`).
export function finishReasonMessage(reason, text) {
  const t = typeof text === 'function' ? text : english;
  if (reason === 'length')
    return t('Відповідь обірвано: досягнуто межі довжини.', 'The answer was cut off: it reached the length limit.');
  if (reason === 'content-filter')
    return t('Відповідь зупинив фільтр вмісту постачальника.', 'The provider\'s content filter stopped the answer.');
  return t('Відповідь обірвано.', `The answer ended early (${String(reason).slice(0, 40)}).`);
}

// May a config document be written now? Only when its last read succeeded (a missing file reads
// as ready). After a failed parse the store still holds defaults under the broken file's revision,
// so a write would replace what the user edited by hand.
export function documentWritable(name, states) {
  const state = isObject(states) ? states[name] : null;
  if (isObject(state) && state.kind === 'ready') return { ok: true };
  const kind = isObject(state) ? state.kind : '';
  return { ok: false, document: name,
    reason: kind === 'invalid' ? 'document-invalid' : kind === 'error' ? 'document-unreadable' : 'document-loading' };
}

// Text for a document that cannot be written or trusted, '' for any other failure.
export function documentFailureMessage(result, text) {
  const t = typeof text === 'function' ? text : english;
  if (!isObject(result) || typeof result.reason !== 'string' || result.reason.indexOf('document-') !== 0) return '';
  const layout = result.document === 'layout';
  const file = layout ? 'layout.json' : 'models.json';
  const uk = layout ? 'Файл розкладки' : 'Файл моделей';
  const en = layout ? 'The layout file' : 'The models file';
  if (result.reason === 'document-invalid')
    return t(`${uk} містить помилку — виправте ${file}.`, `${en} has an error — fix ${file}.`);
  if (result.reason === 'document-unreadable')
    return t(`${uk} не вдалося прочитати — перевірте ${file}.`, `${en} could not be read — check ${file}.`);
  return t(`${uk} ще завантажується. Спробуйте за мить.`, `${en} is still loading. Try again in a moment.`);
}

// Text for a failed quick setup (`setup`) or "Move to Models" (`move`) click.
export function chatActionFailureMessage(action, result, text) {
  const t = typeof text === 'function' ? text : english;
  const failed = isObject(result) ? result : {};
  const message = typeof failed.message === 'string' ? failed.message.trim() : '';
  const broken = documentFailureMessage(failed, t);
  if (broken) return broken;
  if (failed.reason === 'safe-mode' || failed.reason === 'preview') return chatFailureMessage(failed, t);
  if (action === 'setup') {
    if (failed.reason === 'unreachable')
      return t('Не вдалося зв’язатися з Ollama на 127.0.0.1:11434. Чи вона запущена?', 'Could not reach Ollama at 127.0.0.1:11434. Is it running?');
    if (failed.reason === 'no-models')
      return t('В Ollama немає локальної моделі, яка вміє спілкуватися.', 'Ollama has no local model that can chat.');
    return withDetail(t, 'Не вдалося зберегти Моделі.', 'Could not save Models.', message);
  }
  if (failed.reason === 'role-taken') {
    const current = typeof failed.current === 'string' ? failed.current : '';
    return t(`Роль уже зайнята: ${current}. Нічого не змінено.`, `That role is already bound to ${current}. Nothing was changed.`);
  }
  return withDetail(t, 'Не вдалося перенести в Моделі.', 'Could not move to Models.', message);
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
                  error: stopped ? finishReasonMessage(delta.reason, t) : '' });
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
