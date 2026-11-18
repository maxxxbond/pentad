// The `models` document: model providers (local and remote), one default model per role,
// per-widget grants, privacy and worker settings. Pure rules; nothing here opens a connection.

export const providerKinds = Object.freeze(['ollama', 'openai-compatible', 'anthropic', 'gemini']);
// The roles Pentad itself routes to. The set is open: other role keys in a document are kept.
export const modelRoles = Object.freeze(['chat', 'fast', 'vision', 'embed', 'translate']);

export const modelsDefaults = Object.freeze({
  schemaVersion: 1,
  providers: Object.freeze([]),
  roles: Object.freeze({ chat: '', fast: '', vision: '', embed: '', translate: '' }),
  roleOptions: Object.freeze({}),
  grants: Object.freeze({}),
  privacy: Object.freeze({ localOnly: false }),
  worker: Object.freeze({ idleExitSeconds: 600, cacheMiB: 64 }),
});

const MAX_PROVIDERS = 32;
const MAX_ROLES = 32;
const MAX_GRANTS = 256;
const MAX_URL = 2048;
const MAX_MODEL = 200;
const MAX_NAME = 80;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const providerIdPattern = /^[a-z0-9][a-z0-9-]{0,31}$/;
const roleKeyPattern = /^[a-z][a-z0-9-]{0,31}$/;
const moduleIdPattern = /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/;
const envNamePattern = /^[A-Z_][A-Z0-9_]{0,127}$/;
const secretRefPattern = /^secret:\/\/pentad\/[a-z0-9._-]+(?:\/[a-z0-9._-]+)*$/;
// A key value written into the document would reach QML views and backups; only references are accepted.
// Whole words only, so "maxTokens" or "contextTokens" stay allowed while "apiKey", "api_key",
// "authToken" and "clientSecret" are refused.
function secretLikeKey(key) {
  const words = String(key).replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  for (let i = 0; i < words.length; i++) {
    const word = words[i];
    if (word === 'password' || word === 'passwd' || word === 'secret' || word === 'token' || word === 'apikey' || word === 'bearer' || word === 'authorization') return true;
    if (word === 'api' && words[i + 1] === 'key') return true;
  }
  return false;
}
// Walks the whole document, including unknown and nested keys that are otherwise kept verbatim.
function inlineSecretPath(value, path, depth) {
  if (depth > 16 || value === null || typeof value !== 'object') return '';
  const keys = Array.isArray(value) ? value.map((_, index) => String(index)) : Object.keys(value);
  for (const key of keys) {
    const here = `${path}.${key}`;
    if (!Array.isArray(value) && secretLikeKey(key)) return here;
    const nested = inlineSecretPath(value[key], here, depth + 1);
    if (nested) return nested;
  }
  return '';
}
const inlineSecretKey = { test: secretLikeKey };
const printable = value => !/[\x00-\x1f\x7f]/.test(value);

// 127.0.0.0/8 as a real dotted quad: "127.300.0.1" is a DNS name and may resolve anywhere.
function loopbackQuad(host) {
  const match = /^127\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/.exec(host);
  if (!match) return false;
  for (let i = 1; i <= 3; i++) if (Number(match[i]) > 255) return false;
  return true;
}

// Scheme, host, port and path of an endpoint, or null when the text is not a plain http(s) URL.
// Credentials in the URL, a query and a fragment are refused: keys travel in headers only.
function endpointParts(url) {
  if (typeof url !== 'string') return null;
  const text = url.trim();
  if (!text || text.length > MAX_URL) return null;
  const match = /^([Hh][Tt][Tt][Pp][Ss]?):\/\/(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(?::([0-9]{1,5}))?(\/[^?#\s]*)?$/.exec(text);
  if (!match) return null;
  const port = match[3] ? Number(match[3]) : 0;
  if (match[3] && (port === 0 || port > 65535)) return null;
  const host = match[2].toLowerCase().replace(/^\[|\]$/g, '');
  // A full dotted quad only: "127.example.com" is a public name, not loopback.
  const loopback = host === 'localhost' || host === '::1' || loopbackQuad(host);
  const path = (match[4] || '').replace(/\/+$/, '');
  return {
    protocol: match[1].toLowerCase(),
    host,
    loopback,
    url: `${match[1].toLowerCase()}://${match[2].toLowerCase()}${match[3] ? `:${port}` : ''}${path}`,
  };
}

// https anywhere; plain http only to this machine (localhost, 127.x.x.x, ::1).
export function validateEndpoint(url) {
  const parts = endpointParts(url);
  if (!parts) return { ok: false, reason: 'invalid-url' };
  if (parts.protocol !== 'https' && !parts.loopback) return { ok: false, reason: 'insecure-endpoint' };
  return { ok: true, url: parts.url };
}

// "<providerId>/<model>", split at the first slash: model names may contain slashes and colons.
export function parseRole(value) {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  const slash = text.indexOf('/');
  if (slash <= 0) return null;
  const providerId = text.slice(0, slash);
  const model = text.slice(slash + 1).trim();
  if (!providerIdPattern.test(providerId) || !model || model.length > MAX_MODEL || !printable(model)) return null;
  return { providerId, model };
}

function parseProvider(input, index, ids) {
  const where = `providers[${index}]`;
  if (!object(input)) throw new Error(`Invalid models document: ${where} must be an object`);
  if (typeof input.id !== 'string' || !providerIdPattern.test(input.id))
    throw new Error(`Invalid models document: ${where}.id must match ${providerIdPattern.source}`);
  if (ids.has(input.id)) throw new Error(`Invalid models document: duplicate provider id "${input.id}"`);
  ids.add(input.id);
  if (!providerKinds.includes(input.kind))
    throw new Error(`Invalid models document: provider "${input.id}" has an unknown kind (expected ${providerKinds.join(', ')})`);
  for (const key of Object.keys(input)) {
    if (inlineSecretKey.test(key))
      throw new Error(`Invalid models document: provider "${input.id}" key "${key}" is not allowed; store the key in the keyring and reference it in "credential"`);
  }
  const name = input.name === undefined ? input.id : input.name;
  if (typeof name !== 'string' || !name.trim() || name.length > MAX_NAME || !printable(name))
    throw new Error(`Invalid models document: provider "${input.id}" has an invalid name`);
  const endpoint = validateEndpoint(input.baseUrl);
  if (!endpoint.ok) {
    throw new Error(endpoint.reason === 'insecure-endpoint'
      ? `Invalid models document: provider "${input.id}" baseUrl must use https (http is allowed only to this machine)`
      : `Invalid models document: provider "${input.id}" baseUrl is not a valid http(s) URL`);
  }
  const credential = input.credential === undefined ? '' : input.credential;
  if (typeof credential !== 'string' || (credential !== '' && !secretRefPattern.test(credential)))
    throw new Error(`Invalid models document: provider "${input.id}" credential must be empty or a secret://pentad/… reference`);
  const credentialEnv = input.credentialEnv === undefined ? '' : input.credentialEnv;
  if (typeof credentialEnv !== 'string' || (credentialEnv !== '' && !envNamePattern.test(credentialEnv)))
    throw new Error(`Invalid models document: provider "${input.id}" credentialEnv must be empty or an environment variable name`);
  return Object.assign({}, input, { id: input.id, kind: input.kind, name: name.trim(), baseUrl: endpoint.url, credential, credentialEnv });
}

// A section that must be an object when present; a missing one falls back to the defaults.
function section(input, key) {
  if (!own(input, key)) return {};
  if (!object(input[key])) throw new Error(`Invalid models document: ${key} must be an object`);
  return input[key];
}

// Normalises a models document. Unknown top-level, provider, role and section keys are kept;
// `roles`, `roleOptions`, `grants`, `privacy` and `worker` merge with the defaults key by key.
export function parseModels(input) {
  if (!object(input)) throw new Error('Invalid models document: it must be an object');
  const schemaVersion = own(input, 'schemaVersion') ? input.schemaVersion : 1;
  if (schemaVersion !== 1) throw new Error('Invalid models document: unsupported schemaVersion');
  const secretPath = inlineSecretPath(own(input, 'providers') ? Object.assign({}, input, { providers: [] }) : input, 'models', 0);
  if (secretPath)
    throw new Error(`Invalid models document: key "${secretPath}" is not allowed; store keys in the keyring and reference them in a provider's "credential"`);
  if (Array.isArray(input.providers)) {
    for (let index = 0; index < input.providers.length; index++) {
      const provider = input.providers[index];
      if (!object(provider)) continue;
      for (const key of Object.keys(provider)) {
        if (secretLikeKey(key)) continue; // reported below with the provider's name
        const nested = inlineSecretPath(provider[key], `models.providers.${index}.${key}`, 1);
        if (nested)
          throw new Error(`Invalid models document: key "${nested}" is not allowed; store keys in the keyring and reference them in a provider's "credential"`);
      }
    }
  }

  const providerList = own(input, 'providers') ? input.providers : [];
  if (!Array.isArray(providerList)) throw new Error('Invalid models document: providers must be an array');
  if (providerList.length > MAX_PROVIDERS) throw new Error(`Invalid models document: more than ${MAX_PROVIDERS} providers`);
  const ids = new Set();
  const providers = providerList.map((provider, index) => parseProvider(provider, index, ids));

  const roles = Object.assign({}, modelsDefaults.roles);
  const roleInput = section(input, 'roles');
  for (const key of Object.keys(roleInput)) {
    if (!roleKeyPattern.test(key)) throw new Error(`Invalid models document: role name "${key}" is invalid`);
    const value = roleInput[key];
    if (typeof value !== 'string') throw new Error(`Invalid models document: role "${key}" must be a string`);
    const text = value.trim();
    if (text !== '' && !parseRole(text))
      throw new Error(`Invalid models document: role "${key}" must be empty or "<providerId>/<model>"`);
    roles[key] = text;
  }
  if (Object.keys(roles).length > MAX_ROLES) throw new Error(`Invalid models document: more than ${MAX_ROLES} roles`);

  const roleOptions = {};
  const optionInput = section(input, 'roleOptions');
  for (const key of Object.keys(optionInput)) {
    if (!roleKeyPattern.test(key)) throw new Error(`Invalid models document: roleOptions name "${key}" is invalid`);
    const options = optionInput[key];
    if (!object(options)) throw new Error(`Invalid models document: roleOptions.${key} must be an object`);
    // Ollama duration text ("5m", "-1") or empty to leave model residency to the provider.
    if (own(options, 'keepAlive') && (typeof options.keepAlive !== 'string' || !/^[0-9a-z.-]{0,16}$/.test(options.keepAlive)))
      throw new Error(`Invalid models document: roleOptions.${key}.keepAlive is invalid`);
    roleOptions[key] = Object.assign({}, options);
  }

  const grants = {};
  const grantInput = section(input, 'grants');
  const grantKeys = Object.keys(grantInput);
  if (grantKeys.length > MAX_GRANTS) throw new Error(`Invalid models document: more than ${MAX_GRANTS} grants`);
  for (const key of grantKeys) {
    if (key.length > 128 || !moduleIdPattern.test(key)) throw new Error(`Invalid models document: grant "${key}" is not a widget id`);
    const grant = grantInput[key];
    if (!object(grant)) throw new Error(`Invalid models document: grants.${key} must be an object`);
    if (own(grant, 'remote') && typeof grant.remote !== 'boolean')
      throw new Error(`Invalid models document: grants.${key}.remote must be true or false`);
    grants[key] = Object.assign({}, grant, { remote: grant.remote === true });
  }

  const privacy = Object.assign({}, modelsDefaults.privacy, section(input, 'privacy'));
  if (typeof privacy.localOnly !== 'boolean') throw new Error('Invalid models document: privacy.localOnly must be true or false');

  const worker = Object.assign({}, modelsDefaults.worker, section(input, 'worker'));
  if (!Number.isInteger(worker.idleExitSeconds) || worker.idleExitSeconds < 10 || worker.idleExitSeconds > 86400)
    throw new Error('Invalid models document: worker.idleExitSeconds must be a whole number from 10 to 86400');
  if (!Number.isInteger(worker.cacheMiB) || worker.cacheMiB < 1 || worker.cacheMiB > 1024)
    throw new Error('Invalid models document: worker.cacheMiB must be a whole number from 1 to 1024');

  return Object.assign({}, input, { schemaVersion: 1, providers, roles, roleOptions, grants, privacy, worker });
}

// The provider and model bound to a role. A role that is empty, missing or malformed is
// `not-configured`; one that names a provider the document no longer has is `unknown-provider`.
export function resolveRole(models, role) {
  const roles = object(models) && object(models.roles) ? models.roles : {};
  const binding = typeof role === 'string' && own(roles, role) ? parseRole(roles[role]) : null;
  if (!binding) return { ok: false, reason: 'not-configured' };
  const providers = Array.isArray(models.providers) ? models.providers : [];
  const provider = providers.find(item => object(item) && item.id === binding.providerId);
  if (!provider) return { ok: false, reason: 'unknown-provider' };
  const options = object(models.roleOptions) && own(models.roleOptions, role) && object(models.roleOptions[role])
    ? models.roleOptions[role] : {};
  return { ok: true, provider, model: binding.model, roleOptions: Object.assign({}, options) };
}

// Ollama serves "*-cloud" / "*:cloud" models through the local daemon but forwards the prompt to
// ollama.com, so they are remote even though the endpoint is loopback.
function relayedModel(provider, model) {
  return provider.kind === 'ollama' && typeof model === 'string' && /(?:^|[:-])cloud$/i.test(model.trim());
}

// Where a call to this provider runs, shown to the user before any data leaves.
// Local only when the endpoint is this machine; anything unreadable counts as remote.
export function providerDisclosure(provider, model) {
  const source = object(provider) ? provider : {};
  const parts = endpointParts(source.baseUrl);
  const name = typeof source.name === 'string' && source.name ? source.name : typeof source.id === 'string' ? source.id : '';
  return {
    execution: parts && parts.loopback && !relayedModel(source, model) ? 'local' : 'remote',
    provider: name,
    host: parts ? parts.host : '',
    model: typeof model === 'string' ? model : '',
  };
}

// --- Host-internal helpers (not part of widget API v1) ---------------------------------------

const defaultProviderNames = { ollama: 'Ollama', 'openai-compatible': 'OpenAI-compatible', anthropic: 'Anthropic', gemini: 'Gemini' };
const invalid = (reason, message) => ({ ok: false, reason, message });

// A provider named inline by a built-in caller (a chat placement's own endpoint, the quick setup's
// local Ollama), checked with the rules of a document provider. Only the fields the worker needs
// are kept. -> { ok: true, provider } | { ok: false, reason, message }
export function inlineProvider(input) {
  if (!object(input)) return invalid('invalid-input', 'provider must be an object');
  const id = input.id === undefined || input.id === '' ? 'custom' : input.id;
  if (typeof id !== 'string' || !providerIdPattern.test(id)) return invalid('invalid-input', 'provider.id is invalid');
  if (!providerKinds.includes(input.kind)) return invalid('invalid-input', `provider.kind must be one of ${providerKinds.join(', ')}`);
  const endpoint = validateEndpoint(input.baseUrl);
  if (!endpoint.ok) {
    return endpoint.reason === 'insecure-endpoint'
      ? invalid('denied', 'The endpoint must use https (plain http is allowed only to this machine)')
      : invalid('invalid-input', 'The endpoint is not a valid http(s) URL');
  }
  const credential = input.credential === undefined ? '' : input.credential;
  if (typeof credential !== 'string' || (credential !== '' && !secretRefPattern.test(credential)))
    return invalid('invalid-input', 'provider.credential must be empty or a secret://pentad/… reference');
  const credentialEnv = input.credentialEnv === undefined ? '' : input.credentialEnv;
  if (typeof credentialEnv !== 'string' || (credentialEnv !== '' && !envNamePattern.test(credentialEnv)))
    return invalid('invalid-input', 'provider.credentialEnv must be an upper-case environment variable name');
  const name = typeof input.name === 'string' && input.name.trim() ? input.name.trim() : defaultProviderNames[input.kind];
  if (name.length > MAX_NAME || !printable(name)) return invalid('invalid-input', 'provider.name is invalid');
  return { ok: true, provider: { id, kind: input.kind, name, baseUrl: endpoint.url, credential, credentialEnv } };
}

// A model name a provider may serve: printable and bounded, as in a role binding.
export function validModelName(model) {
  return typeof model === 'string' && model.trim() !== '' && model.trim().length <= MAX_MODEL && printable(model);
}

// "*-cloud" / "*:cloud" names that a local Ollama relays to ollama.com.
export function cloudModelName(name) {
  return typeof name === 'string' && /(?:^|[:-])cloud$/i.test(name.trim());
}

// What the quick setup binds, from an `llm.models` answer [{ name, sizeBytes?, capabilities? }].
// Capabilities are read, never assumed; cloud relays and models of unknown size are skipped.
// chat: the largest completion model up to 10 GB; fast: the smallest completion model;
// vision: the chat model when it reports "vision"; embed: the first "embedding" model.
export const quickSetupChatLimitBytes = 10 * 1000 * 1000 * 1000;
export function chooseLocalRoles(list) {
  const models = (Array.isArray(list) ? list : []).filter(item => object(item) && validModelName(item.name) && !cloudModelName(item.name));
  const has = (item, capability) => Array.isArray(item.capabilities) && item.capabilities.indexOf(capability) >= 0;
  const sized = item => typeof item.sizeBytes === 'number' && Number.isFinite(item.sizeBytes) && item.sizeBytes > 0;
  const bySize = (a, b) => a.sizeBytes - b.sizeBytes || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  const completion = models.filter(item => has(item, 'completion') && sized(item)).sort(bySize);
  const fitting = completion.filter(item => item.sizeBytes <= quickSetupChatLimitBytes);
  const chat = fitting.length ? fitting[fitting.length - 1] : null;
  const smallest = completion.length ? completion[0] : null;
  const embed = models.find(item => has(item, 'embedding')) || null;
  return {
    chat: chat ? chat.name : '',
    fast: smallest ? smallest.name : '',
    vision: chat && has(chat, 'vision') ? chat.name : '',
    embed: embed ? embed.name : '',
  };
}

const sameProvider = (a, b) => object(a) && a.kind === b.kind && a.baseUrl === b.baseUrl
  && (a.credential || '') === b.credential && (a.credentialEnv || '') === b.credentialEnv;

// A free provider id: the preferred one, else "<preferred>-2", "-3"…
function freeProviderId(providers, preferred) {
  const taken = id => providers.some(item => object(item) && item.id === id);
  const base = providerIdPattern.test(preferred) ? preferred : 'custom';
  if (!taken(base)) return base;
  for (let n = 2; n < 100; n++) {
    const id = `${base.slice(0, 28)}-${n}`;
    if (!taken(id)) return id;
  }
  return '';
}

// The provider already in the document with the same endpoint and key reference, or a new entry.
function providerEntry(document, provider, preferredId) {
  const providers = Array.isArray(document.providers) ? document.providers : [];
  const existing = providers.find(item => sameProvider(item, provider));
  if (existing) return { id: existing.id, providers };
  const id = freeProviderId(providers, preferredId);
  if (!id) return null;
  const entry = { id, kind: provider.kind, name: provider.name, baseUrl: provider.baseUrl, credential: provider.credential, credentialEnv: provider.credentialEnv };
  return { id, providers: providers.concat([entry]) };
}

function parsedDocument(value) {
  try { return { ok: true, value: parseModels(value) }; } catch (error) { return invalid('invalid', error.message); }
}

export const localOllama = Object.freeze({ id: 'local', kind: 'ollama', name: 'Ollama', baseUrl: 'http://127.0.0.1:11434', credential: '', credentialEnv: '' });

// Quick setup: bind the local Ollama's models to the empty roles chat, fast, vision and embed.
// A role that is already set is never overwritten.
// -> { ok: true, value, providerId, assigned: { role: binding } } | { ok: false, reason, message }
export function applyLocalSetup(document, list) {
  const source = object(document) ? document : modelsDefaults;
  const chosen = chooseLocalRoles(list);
  if (!chosen.chat && !chosen.fast && !chosen.embed) return invalid('no-models', 'Ollama has no local model that fits a role');
  const entry = providerEntry(source, localOllama, localOllama.id);
  if (!entry) return invalid('invalid', 'No free provider id');
  const roles = Object.assign({}, object(source.roles) ? source.roles : modelsDefaults.roles);
  const assigned = {};
  for (const role of ['chat', 'fast', 'vision', 'embed']) {
    const current = typeof roles[role] === 'string' ? roles[role].trim() : '';
    if (current || !chosen[role]) continue;
    roles[role] = `${entry.id}/${chosen[role]}`;
    assigned[role] = roles[role];
  }
  if (!Object.keys(assigned).length) return invalid('no-change', 'Every role this setup fills is already set');
  const parsed = parsedDocument(Object.assign({}, source, { providers: entry.providers, roles }));
  return parsed.ok ? { ok: true, value: parsed.value, providerId: entry.id, assigned } : parsed;
}

// A short provider id from an endpoint: loopback -> "local", "api.openai.com" -> "openai".
function providerIdFor(provider) {
  const disclosure = providerDisclosure(provider, '');
  if (disclosure.execution === 'local') return 'local';
  const labels = disclosure.host.split('.').filter(label => label && label !== 'api' && label !== 'www');
  const label = (labels.length > 1 ? labels[labels.length - 2] : labels[0] || '').replace(/[^a-z0-9-]/g, '').replace(/^-+/, '').slice(0, 24);
  return label && providerIdPattern.test(label) ? label : 'custom';
}

// "Move to Models": add a placement's own endpoint to the registry and bind it to `role` when that
// role is empty. A role bound to anything else is left alone and reported as `role-taken`.
// -> { ok: true, value, providerId, binding, changed } | { ok: false, reason, message, current? }
export function importEndpoint(document, input, model, role) {
  const source = object(document) ? document : modelsDefaults;
  const checked = inlineProvider(input);
  if (!checked.ok) return checked;
  if (!validModelName(model)) return invalid('invalid-input', 'The model name is invalid');
  if (typeof role !== 'string' || !roleKeyPattern.test(role)) return invalid('invalid-input', 'The role name is invalid');
  const host = providerDisclosure(checked.provider, '').host;
  const provider = Object.assign({}, checked.provider, { name: checked.provider.kind === 'ollama' ? 'Ollama' : host || checked.provider.name });
  const providers = Array.isArray(source.providers) ? source.providers : [];
  const existing = providers.find(item => sameProvider(item, provider));
  const current = object(source.roles) && typeof source.roles[role] === 'string' ? source.roles[role].trim() : '';
  const bound = parseRole(current);
  if (current && !(existing && bound && bound.providerId === existing.id && bound.model === model.trim()))
    return { ok: false, reason: 'role-taken', message: `The ${role} role is already bound to ${current}`, current };
  const entry = providerEntry(source, provider, providerIdFor(provider));
  if (!entry) return invalid('invalid', 'No free provider id');
  const binding = `${entry.id}/${model.trim()}`;
  if (current === binding) return { ok: true, value: source, providerId: entry.id, binding, changed: false };
  const roles = Object.assign({}, object(source.roles) ? source.roles : modelsDefaults.roles);
  roles[role] = binding;
  const parsed = parsedDocument(Object.assign({}, source, { providers: entry.providers, roles }));
  return parsed.ok ? { ok: true, value: parsed.value, providerId: entry.id, binding, changed: true } : parsed;
}
