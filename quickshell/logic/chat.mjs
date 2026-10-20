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

export function chatProfile(settings) {
  if (!isObject(settings)) return null;
  const provider = settings.provider === 'ollama' ? 'ollama' : settings.provider === 'api' ? 'api' : null;
  const baseUrl = typeof settings.baseUrl === 'string' ? settings.baseUrl.trim() : '';
  const model = typeof settings.model === 'string' ? settings.model.trim() : '';
  const apiKeyEnv = typeof settings.apiKeyEnv === 'string' ? settings.apiKeyEnv.trim() : '';
  const credentialRef = typeof settings.credentialRef === 'string' ? settings.credentialRef.trim() : '';
  if (!provider || baseUrl.length > 2048 || model.length > 200 || apiKeyEnv.length > 128
      || credentialRef.length > 160 || (apiKeyEnv && !/^[A-Za-z_][A-Za-z0-9_]*$/.test(apiKeyEnv))) return null;
  if (!baseUrl || !model) return { provider, baseUrl, model, apiKeyEnv, credentialRef, setup: true };
  const match = /^(https?):\/\/(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(?::([0-9]{1,5}))?(\/[^?#]*)?$/.exec(baseUrl);
  if (!match) return null;
  const protocol = `${match[1]}:`;
  const hostHeader = match[2];
  const host = hostHeader.toLowerCase().replace(/^\[|\]$/g, '');
  const port = match[3] ? Number(match[3]) : 0;
  if (port > 65535 || port === 0 && match[3]) return null;
  const loopback = host === 'localhost' || host === '::1' || host === '127.0.0.1' || /^127\./.test(host);
  if (protocol !== 'https:' && !(protocol === 'http:' && loopback)) return null;
  const path = (match[4] || '').replace(/\/+$/, '');
  return { provider, baseUrl: `${protocol}//${hostHeader}${match[3] ? `:${port}` : ''}${path}`,
    model, apiKeyEnv, credentialRef, setup: false };
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

export function createChatService({ stream, apiKeyFor, changed, preview = false, safeMode = false }) {
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
          const text = String(input).trim();
          if (preview || safeMode) { update(entry, { status: 'error', error: 'Chat requests are disabled in preview and safe mode.' }); return false; }
          if (!entry.profile || entry.profile.setup) { update(entry, { status: 'setup', error: 'Choose a provider, endpoint, and model in widget settings.' }); return false; }
          if (!text) return false;
          if (utf8Length(text) > MAX_MESSAGE_BYTES) { update(entry, { status: 'error', error: 'Message exceeds 16 KiB.' }); return false; }
          if (entry.cancel) return false;
          if (entry.state.messages.some(message => ['partial', 'failed'].includes(message.status))) {
            update(entry, { status: 'error', error: 'Retry or clear the incomplete response before sending.' }); return false;
          }
          const user = { id: `chat-${++serial}`, role: 'user', content: text, status: 'complete' };
          const assistant = { id: `chat-${++serial}`, role: 'assistant', content: '', status: 'partial' };
          const messages = [...entry.state.messages, user, assistant];
          if (messages.length > 100) { update(entry, { status: 'error', error: 'Conversation reached its 100 message limit. Clear it to continue.' }); return false; }
          entry.activeAssistant = assistant.id;
          const generation = ++entry.generation;
          const cancel = createCancellation();
          entry.cancel = cancel;
          update(entry, { messages, draft: '', status: 'sending', error: '' });
          const keyPromise = entry.profile.provider === 'api' ? apiKeyFor(entry.profile.apiKeyEnv) : Promise.resolve('');
          let responseBytes = 0;
          const fail = error => {
            if (generation === entry.generation && !cancel.isCancelled()) {
              const message = error instanceof Error ? error.message : 'Chat request failed.';
              update(entry, { messages: entry.state.messages.map(item => item.id === assistant.id
                ? Object.assign({}, item, { status: item.content ? 'partial' : 'failed' }) : item), status: 'error', error: message });
              entry.activeAssistant = null;
            }
          };
          const consumeStream = key => Promise.resolve().then(() => stream(entry.profile, messages.slice(0, -1), key, cancel, delta => {
              if (generation !== entry.generation || cancel.isCancelled()) return;
              if (delta.type === 'text') {
                responseBytes += utf8Length(delta.text);
                if (responseBytes > MAX_RESPONSE_BYTES) throw new Error('Response exceeded 1 MiB.');
                const next = entry.state.messages.map(message => message.id === assistant.id
                  ? Object.assign({}, message, { content: message.content + delta.text }) : message);
                entry.state = Object.assign({}, entry.state, { messages: next, status: 'streaming' });
                publish(entry);
              } else if (delta.type === 'done') {
                const next = entry.state.messages.map(message => message.id === assistant.id
                  ? Object.assign({}, message, { status: delta.reason && delta.reason !== 'stop' ? 'partial' : 'complete' }) : message);
                entry.state = Object.assign({}, entry.state, { messages: next,
                  status: delta.reason && delta.reason !== 'stop' ? 'error' : 'idle',
                  error: delta.reason && delta.reason !== 'stop' ? `Response ended (${delta.reason}).` : '' });
                publish(entry);
                entry.activeAssistant = null;
              }
            })).then(() => {
            if (generation === entry.generation && !cancel.isCancelled() && entry.state.status !== 'error'
                && entry.activeAssistant === assistant.id) throw new Error('Provider stream ended before its completion marker.');
          }).then(() => {}, fail).then(() => {
            if (generation === entry.generation) entry.cancel = null;
            return entry.state.status === 'idle';
          });
          return Promise.resolve(keyPromise).then(key => {
            if (generation !== entry.generation || cancel.isCancelled()) return false;
            if (entry.profile.provider === 'api' && !key) {
              entry.cancel = null;
              update(entry, { messages: entry.state.messages.map(item => item.id === assistant.id
                ? Object.assign({}, item, { status: 'failed' }) : item), status: 'error', error: entry.profile.credentialRef
                ? `Saved credential reference ${entry.profile.credentialRef} cannot be read yet. Configure an environment variable in widget settings.`
                : entry.profile.apiKeyEnv
                  ? `Credential unavailable. Set ${entry.profile.apiKeyEnv} in the shell environment.`
                  : 'API credential is unavailable. Configure an environment variable in widget settings.' });
              return false;
            }
            return consumeStream(key);
          }, error => {
            fail(error);
            if (generation === entry.generation) entry.cancel = null;
            return false;
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
