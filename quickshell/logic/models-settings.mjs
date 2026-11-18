// The Models settings page: pure rules behind its cards. Editing the `models` document (providers,
// roles, grants, privacy, worker), choosing which models a role picker offers, and the numbers the
// hero strip and the installed-model cards show. Host-internal, not part of widget API v1.
// Nothing here opens a connection, touches the keyring or holds a key value.
//
// Written for the QML JavaScript engine too: no object spread, no structuredClone, no `??`, no
// optional chaining, no catch without a binding.

import { modelRoles, modelsDefaults, parseModels, parseRole, providerDisclosure, providerKinds, validateEndpoint, cloudModelName } from './models.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const providerIdPattern = /^[a-z0-9][a-z0-9-]{0,31}$/;
const envNamePattern = /^[A-Z_][A-Z0-9_]{0,127}$/;
const moduleIdPattern = /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/;
const MAX_NAME = 80;
const fail = (reason, message) => ({ ok: false, reason, message: message || reason });

// The kinds the "Add provider" sheet offers. OpenRouter is a preset of the OpenAI-compatible kind.
export const providerPresets = Object.freeze([
  Object.freeze({ id: 'ollama', kind: 'ollama', name: 'Ollama', baseUrl: 'http://127.0.0.1:11434', keySource: 'none' }),
  Object.freeze({ id: 'openai-compatible', kind: 'openai-compatible', name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', keySource: 'keyring' }),
  Object.freeze({ id: 'anthropic', kind: 'anthropic', name: 'Anthropic', baseUrl: 'https://api.anthropic.com', keySource: 'keyring' }),
  Object.freeze({ id: 'gemini', kind: 'gemini', name: 'Gemini', baseUrl: 'https://generativelanguage.googleapis.com/v1beta', keySource: 'keyring' }),
  Object.freeze({ id: 'openrouter', kind: 'openai-compatible', name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1', keySource: 'keyring' }),
]);

export function presetFor(id) {
  return providerPresets.find(preset => preset.id === id) || providerPresets[0];
}

// The keyring reference the page stores a provider's key under.
export function keyRef(providerId) {
  return `secret://pentad/providers/${providerId}`;
}

function parsed(value) {
  try {
    return { ok: true, value: parseModels(value) };
  } catch (error) {
    return fail('invalid', error.message);
  }
}

function source(document) {
  return object(document) ? document : modelsDefaults;
}

function providersOf(document) {
  const list = source(document).providers;
  return Array.isArray(list) ? list.filter(object) : [];
}

// A provider id from its name: "OpenRouter" -> "openrouter", "My Server 2" -> "my-server-2";
// a taken id gets "-2", "-3"… A loopback Ollama prefers "local".
export function suggestProviderId(document, name, kind, baseUrl) {
  const taken = id => providersOf(document).some(item => item.id === id);
  let base = String(name || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 24);
  const endpoint = validateEndpoint(baseUrl);
  if (kind === 'ollama' && endpoint.ok && providerDisclosure({ baseUrl: endpoint.url }, '').execution === 'local') base = 'local';
  if (!providerIdPattern.test(base)) base = kind === 'ollama' ? 'local' : 'provider';
  if (!taken(base)) return base;
  for (let n = 2; n < 100; n++) {
    const id = `${base.slice(0, 28)}-${n}`;
    if (!taken(id)) return id;
  }
  return '';
}

// Field errors of the provider sheet's draft { kind, name, baseUrl, keySource: 'none' | 'keyring' |
// 'env', credentialEnv }. -> { ok, errors: { name?, baseUrl?, credentialEnv? } } where each error is
// a code: 'required', 'too-long', 'invalid-url', 'insecure-endpoint', 'env-invalid'.
export function draftErrors(draft) {
  const errors = {};
  const input = object(draft) ? draft : {};
  const name = typeof input.name === 'string' ? input.name.trim() : '';
  if (!name) errors.name = 'required';
  else if (name.length > MAX_NAME || /[\x00-\x1f\x7f]/.test(name)) errors.name = 'too-long';
  const url = typeof input.baseUrl === 'string' ? input.baseUrl.trim() : '';
  if (!url) errors.baseUrl = 'required';
  else {
    const endpoint = validateEndpoint(url);
    if (!endpoint.ok) errors.baseUrl = endpoint.reason;
  }
  if (input.keySource === 'env') {
    const env = typeof input.credentialEnv === 'string' ? input.credentialEnv.trim() : '';
    if (!envNamePattern.test(env)) errors.credentialEnv = 'env-invalid';
  }
  if (providerKinds.indexOf(input.kind) < 0) errors.kind = 'required';
  return { ok: Object.keys(errors).length === 0, errors };
}

// The sheet's draft for an existing provider (editing) or a preset (adding).
export function draftFor(provider, presetId) {
  if (object(provider)) {
    return {
      kind: provider.kind,
      name: provider.name || provider.id,
      baseUrl: provider.baseUrl || '',
      keySource: provider.credential ? 'keyring' : provider.credentialEnv ? 'env' : 'none',
      credentialEnv: provider.credentialEnv || '',
    };
  }
  const preset = presetFor(presetId);
  return { kind: preset.kind, name: preset.name, baseUrl: preset.baseUrl, keySource: preset.keySource, credentialEnv: '' };
}

function providerFields(id, draft, previous) {
  const endpoint = validateEndpoint(draft.baseUrl);
  const keyring = draft.keySource === 'keyring';
  const env = draft.keySource === 'env';
  // A provider that already had a keyring key keeps its reference, so renaming never orphans it.
  const credential = keyring ? (object(previous) && previous.credential ? previous.credential : keyRef(id)) : '';
  return Object.assign({}, object(previous) ? previous : {}, {
    id,
    kind: draft.kind,
    name: draft.name.trim(),
    baseUrl: endpoint.url,
    credential,
    credentialEnv: env ? draft.credentialEnv.trim() : '',
  });
}

// `id` (optional) fixes the new provider's id, so a key stored under keyRef(id) before the save
// still matches after a reload and retry; a taken id is `id-taken`.
// -> { ok: true, value, providerId, credential } | { ok: false, reason, message, errors? }
export function addProvider(document, draft, id) {
  const checked = draftErrors(draft);
  if (!checked.ok) return { ok: false, reason: 'invalid-input', message: 'invalid-input', errors: checked.errors };
  const current = source(document);
  if (id !== undefined && (typeof id !== 'string' || !providerIdPattern.test(id))) return fail('invalid-input', 'The provider id is invalid');
  if (id !== undefined && providersOf(current).some(item => item.id === id)) return fail('id-taken', `Provider ${id} exists`);
  if (id === undefined) id = suggestProviderId(current, draft.name, draft.kind, draft.baseUrl);
  if (!id) return fail('invalid', 'No free provider id');
  const provider = providerFields(id, draft, null);
  const result = parsed(Object.assign({}, current, { providers: providersOf(current).concat([provider]) }));
  return result.ok ? { ok: true, value: result.value, providerId: id, credential: provider.credential } : result;
}

// -> { ok: true, value, providerId, credential, previousCredential } | failure
export function updateProvider(document, id, draft) {
  const checked = draftErrors(draft);
  if (!checked.ok) return { ok: false, reason: 'invalid-input', message: 'invalid-input', errors: checked.errors };
  const current = source(document);
  const list = providersOf(current);
  const index = list.findIndex(item => item.id === id);
  if (index < 0) return fail('unknown-provider', `No provider ${id}`);
  const provider = providerFields(id, draft, list[index]);
  const next = list.slice();
  next[index] = provider;
  const result = parsed(Object.assign({}, current, { providers: next }));
  return result.ok ? { ok: true, value: result.value, providerId: id, credential: provider.credential,
    previousCredential: list[index].credential || '' } : result;
}

// The roles bound to a provider, in Pentad's role order and then any others.
export function rolesUsing(document, providerId) {
  const roles = object(source(document).roles) ? source(document).roles : {};
  return Object.keys(roles).filter(role => {
    const binding = parseRole(roles[role]);
    return !!binding && binding.providerId === providerId;
  }).sort((a, b) => roleRank(a) - roleRank(b));
}

function roleRank(role) {
  const index = modelRoles.indexOf(role);
  return index < 0 ? modelRoles.length : index;
}

// Removes a provider and empties every role bound to it.
// -> { ok: true, value, clearedRoles, credential } | failure
export function removeProvider(document, providerId) {
  const current = source(document);
  const list = providersOf(current);
  const provider = list.find(item => item.id === providerId);
  if (!provider) return fail('unknown-provider', `No provider ${providerId}`);
  const cleared = rolesUsing(current, providerId);
  const roles = Object.assign({}, object(current.roles) ? current.roles : modelsDefaults.roles);
  for (const role of cleared) roles[role] = '';
  const result = parsed(Object.assign({}, current, { providers: list.filter(item => item.id !== providerId), roles }));
  return result.ok ? { ok: true, value: result.value, clearedRoles: cleared, credential: provider.credential || '' } : result;
}

// Binds a role to "<providerId>/<model>", or empties it when the model is empty.
export function setRole(document, role, providerId, model) {
  const current = source(document);
  if (typeof role !== 'string' || !/^[a-z][a-z0-9-]{0,31}$/.test(role)) return fail('invalid-input', 'The role name is invalid');
  const name = typeof model === 'string' ? model.trim() : '';
  let binding = '';
  if (name) {
    if (!providersOf(current).some(item => item.id === providerId)) return fail('unknown-provider', `No provider ${providerId}`);
    binding = `${providerId}/${name}`;
    if (!parseRole(binding)) return fail('invalid-input', 'The model name is invalid');
  }
  const roles = Object.assign({}, object(current.roles) ? current.roles : modelsDefaults.roles);
  if ((roles[role] || '') === binding) return { ok: true, value: current, changed: false };
  roles[role] = binding;
  const result = parsed(Object.assign({}, current, { roles }));
  return result.ok ? { ok: true, value: result.value, changed: true } : result;
}

// grants[moduleId].remote; other keys of that grant are kept.
export function setGrant(document, moduleId, remote) {
  const current = source(document);
  if (typeof moduleId !== 'string' || moduleId.length > 128 || !moduleIdPattern.test(moduleId)) return fail('invalid-input', 'Not a widget id');
  const grants = Object.assign({}, object(current.grants) ? current.grants : {});
  grants[moduleId] = Object.assign({}, object(grants[moduleId]) ? grants[moduleId] : {}, { remote: remote === true });
  const result = parsed(Object.assign({}, current, { grants }));
  return result.ok ? { ok: true, value: result.value } : result;
}

// worker.idleExitSeconds from whole minutes (1 to 1440).
export const idleMinutesRange = Object.freeze({ min: 1, max: 1440 });
export function idleMinutes(document) {
  const worker = object(source(document).worker) ? source(document).worker : modelsDefaults.worker;
  const seconds = Number.isFinite(worker.idleExitSeconds) ? worker.idleExitSeconds : modelsDefaults.worker.idleExitSeconds;
  return Math.max(idleMinutesRange.min, Math.min(idleMinutesRange.max, Math.round(seconds / 60)));
}
export function setIdleMinutes(document, minutes) {
  const current = source(document);
  const value = Math.round(Number(minutes));
  if (!Number.isFinite(value) || value < idleMinutesRange.min || value > idleMinutesRange.max) return fail('invalid-input', 'Minutes out of range');
  const worker = Object.assign({}, object(current.worker) ? current.worker : modelsDefaults.worker, { idleExitSeconds: value * 60 });
  const result = parsed(Object.assign({}, current, { worker }));
  return result.ok ? { ok: true, value: result.value } : result;
}

// --- Models a role picker offers -----------------------------------------------------------

// The capability chips worth showing, in this order; anything else a server reports is ignored.
export const chipCapabilities = Object.freeze(['vision', 'embedding', 'tools', 'thinking']);

export function modelChips(model) {
  const caps = object(model) && Array.isArray(model.capabilities) ? model.capabilities : [];
  return chipCapabilities.filter(cap => caps.indexOf(cap) >= 0);
}

// Whether a listed model fits a role. Capabilities are read when the server reports them:
// `embed` wants "embedding", `vision` wants "vision", every other role a completion model (an
// embedding-only model never answers a chat). A server that reports no capabilities at all
// (OpenAI-compatible and Anthropic lists) has every model offered to every role.
export function roleAccepts(role, model) {
  if (!object(model)) return false;
  const caps = Array.isArray(model.capabilities) ? model.capabilities : null;
  if (!caps) return true;
  if (role === 'embed') return caps.indexOf('embedding') >= 0;
  if (role === 'vision') return caps.indexOf('vision') >= 0;
  return caps.indexOf('completion') >= 0;
}

// Choices for one role from every provider's live list.
// lists: { [providerId]: { state: 'ready' | 'loading' | 'error', models: [...] } }.
// -> [{ value: "<providerId>/<model>", providerId, providerName, model, sizeBytes, chips, local, cloud }]
// Local providers first (document order), then remote ones; inside a provider the largest model first.
export function roleChoices(document, role, lists) {
  const all = [];
  const listed = object(lists) ? lists : {};
  const providers = providersOf(document);
  const ordered = providers.filter(item => providerDisclosure(item, '').execution === 'local')
    .concat(providers.filter(item => providerDisclosure(item, '').execution !== 'local'));
  for (const provider of ordered) {
    const entry = listed[provider.id];
    const models = object(entry) && Array.isArray(entry.models) ? entry.models : [];
    const choices = models.filter(model => object(model) && typeof model.name === 'string' && roleAccepts(role, model))
      .map(model => choiceFor(provider, model));
    choices.sort((a, b) => (b.sizeBytes || 0) - (a.sizeBytes || 0) || (a.model < b.model ? -1 : a.model > b.model ? 1 : 0));
    for (const choice of choices) all.push(choice);
  }
  return all;
}

function choiceFor(provider, model) {
  const disclosure = providerDisclosure(provider, model.name);
  const relayed = cloudModelName(model.name) && provider.kind === 'ollama';
  return {
    value: `${provider.id}/${model.name}`,
    providerId: provider.id,
    providerName: provider.name || provider.id,
    model: model.name,
    // A relayed cloud model reports the size of its stub, not of the model.
    sizeBytes: !relayed && typeof model.sizeBytes === 'number' && model.sizeBytes > 0 ? model.sizeBytes : 0,
    chips: modelChips(model),
    local: disclosure.execution === 'local',
    cloud: disclosure.execution !== 'local',
  };
}

// What a role picker shows for the current binding, also when the model is not in any list
// (a hand-typed name, a server that is down).
export function currentChoice(document, role, lists) {
  const roles = object(source(document).roles) ? source(document).roles : {};
  const binding = parseRole(roles[role]);
  if (!binding) return null;
  const provider = providersOf(document).find(item => item.id === binding.providerId);
  if (!provider) return { value: roles[role], providerId: binding.providerId, providerName: binding.providerId, model: binding.model,
    sizeBytes: 0, chips: [], local: false, cloud: true, missing: true };
  const entry = object(lists) ? lists[provider.id] : null;
  const models = object(entry) && Array.isArray(entry.models) ? entry.models : [];
  const found = models.find(model => object(model) && model.name === binding.model);
  return choiceFor(provider, found || { name: binding.model });
}

// --- Hero strip and installed models -----------------------------------------------------------

// The headline: 'empty' (no provider), 'unbound' (providers but no role bound), 'local' (every bound
// role runs on this machine) or 'mixed' (some role is remote; `cloud` names those providers).
export function heroSummary(document) {
  const current = source(document);
  const providers = providersOf(current);
  if (!providers.length) return { state: 'empty', cloud: [], local: [], boundRoles: 0 };
  const roles = object(current.roles) ? current.roles : {};
  const cloud = [];
  const local = [];
  let bound = 0;
  for (const role of Object.keys(roles)) {
    const binding = parseRole(roles[role]);
    if (!binding) continue;
    const provider = providers.find(item => item.id === binding.providerId);
    if (!provider) continue;
    bound += 1;
    const disclosure = providerDisclosure(provider, binding.model);
    const label = provider.name || provider.id;
    const list = disclosure.execution === 'local' ? local : cloud;
    const name = disclosure.execution !== 'local' && provider.kind === 'ollama' && cloudModelName(binding.model) ? `${label} cloud` : label;
    if (list.indexOf(name) < 0) list.push(name);
  }
  return { state: bound === 0 ? 'unbound' : cloud.length ? 'mixed' : 'local', cloud, local, boundRoles: bound };
}

// Providers whose endpoint is this machine and that speak Ollama: the ones with loaded models.
export function localOllamaProviders(document) {
  return providersOf(document).filter(item => item.kind === 'ollama' && providerDisclosure(item, '').execution === 'local');
}

// The cards of "Installed models": every model a local Ollama lists, with what is in memory now.
// loaded: { [providerId]: { models: [{ name, sizeBytes?, vramBytes?, expiresAt? }] } }
// vram: the `system.vram` value or null.
export function installedModels(document, lists, loaded, vram) {
  const cards = [];
  const total = object(vram) && vram.available === true && vram.totalBytes > 0 ? vram.totalBytes : 0;
  for (const provider of localOllamaProviders(document)) {
    const entry = object(lists) ? lists[provider.id] : null;
    const models = object(entry) && Array.isArray(entry.models) ? entry.models : [];
    const resident = object(loaded) && object(loaded[provider.id]) && Array.isArray(loaded[provider.id].models) ? loaded[provider.id].models : [];
    for (const model of models) {
      if (!object(model) || typeof model.name !== 'string') continue;
      const cloud = cloudModelName(model.name);
      const hot = resident.find(item => object(item) && item.name === model.name) || null;
      const size = !cloud && typeof model.sizeBytes === 'number' && model.sizeBytes > 0 ? model.sizeBytes : 0;
      cards.push({
        key: `${provider.id}/${model.name}`,
        providerId: provider.id,
        name: model.name,
        title: model.name.replace(/:latest$/, ''),
        sizeBytes: size,
        parameterSize: typeof model.parameterSize === 'string' ? model.parameterSize : '',
        chips: modelChips(model),
        cloud,
        loaded: !!hot,
        vramBytes: hot && typeof hot.vramBytes === 'number' ? hot.vramBytes : 0,
        expiresAt: hot && typeof hot.expiresAt === 'string' ? hot.expiresAt : '',
        tooBig: !cloud && total > 0 && size > total,
      });
    }
  }
  cards.sort((a, b) => (b.loaded ? 1 : 0) - (a.loaded ? 1 : 0) || (a.cloud ? 1 : 0) - (b.cloud ? 1 : 0) || b.sizeBytes - a.sizeBytes);
  return cards;
}

// The VRAM meter: the loaded models' share, the rest of the used memory, the free part.
// -> { available, totalBytes, usedBytes, models: [{ name, bytes, fraction }], otherBytes, otherFraction, freeBytes }
export function vramMeter(vram, loaded) {
  if (!object(vram) || vram.available !== true || !(vram.totalBytes > 0)) return { available: false };
  const total = vram.totalBytes;
  const used = Math.min(total, Math.max(0, vram.usedBytes || 0));
  const models = [];
  let resident = 0;
  const sources = object(loaded) ? Object.keys(loaded).map(key => loaded[key]) : [];
  for (const entry of sources) {
    const list = object(entry) && Array.isArray(entry.models) ? entry.models : [];
    for (const model of list) {
      const bytes = object(model) && typeof model.vramBytes === 'number' && model.vramBytes > 0 ? model.vramBytes : 0;
      if (!bytes) continue;
      resident += bytes;
      models.push({ name: model.name, bytes, fraction: Math.min(1, bytes / total) });
    }
  }
  const other = Math.max(0, used - resident);
  return {
    available: true,
    totalBytes: total,
    usedBytes: used,
    residentBytes: resident,
    models,
    otherBytes: other,
    otherFraction: Math.min(1, other / total),
    freeBytes: Math.max(0, total - Math.max(used, resident)),
  };
}

// --- Numbers in text -----------------------------------------------------------------------

// Decimal units, as Ollama reports sizes: 6600000000 -> { value: "6,6", unit: "ГБ" }.
// One decimal below 10, whole numbers above; Ukrainian uses a decimal comma.
export function formatBytes(bytes, uk) {
  const n = typeof bytes === 'number' && Number.isFinite(bytes) && bytes > 0 ? bytes : 0;
  const units = uk ? ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'] : ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = n;
  let index = 0;
  while (value >= 1000 && index < units.length - 1) {
    value /= 1000;
    index += 1;
  }
  let text = value >= 10 || index === 0 ? String(Math.round(value)) : (Math.round(value * 10) / 10).toFixed(1).replace(/\.0$/, '');
  if (text === '1000' && index < units.length - 1) {
    text = '1';
    index += 1;
  }
  return { value: uk ? text.replace('.', ',') : text, unit: units[index] };
}

export function bytesText(bytes, uk) {
  const parts = formatBytes(bytes, uk);
  return `${parts.value} ${parts.unit}`;
}

// Binary units, as the cache size is set (worker.cacheMiB): 12 * 2^20 -> "12 МіБ" / "12 MiB".
export function binaryText(bytes, uk) {
  let value = typeof bytes === 'number' && Number.isFinite(bytes) && bytes > 0 ? bytes : 0;
  const units = uk ? ['Б', 'КіБ', 'МіБ', 'ГіБ'] : ['B', 'KiB', 'MiB', 'GiB'];
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  const text = value >= 10 || index === 0 ? String(Math.round(value)) : (Math.round(value * 10) / 10).toFixed(1).replace(/\.0$/, '');
  return `${uk ? text.replace('.', ',') : text} ${units[index]}`;
}

// 4600 -> "4,6 с" / "4.6 s"; 320 -> "0,3 с".
export function secondsText(ms, uk) {
  const s = Math.max(0, Number(ms) || 0) / 1000;
  const text = s >= 10 ? String(Math.round(s)) : (Math.round(s * 10) / 10).toFixed(1);
  return uk ? `${text.replace('.', ',')} с` : `${text} s`;
}

// Whole minutes until an Ollama `expires_at`, or -1 when unknown or already past.
export function minutesUntil(expiresAt, nowMs) {
  if (typeof expiresAt !== 'string' || !expiresAt) return -1;
  const when = Date.parse(expiresAt);
  if (!Number.isFinite(when)) return -1;
  const left = when - (Number.isFinite(nowMs) ? nowMs : Date.now());
  // Ollama reports a far-future time for keepAlive -1.
  if (left > 365 * 24 * 3600 * 1000) return Infinity;
  return left > 0 ? Math.ceil(left / 60000) : -1;
}

// Ukrainian plural form: 1 модель, 2 моделі, 5 моделей, 21 модель, 11 моделей.
export function pluralUk(n, one, few, many) {
  const count = Math.abs(Math.round(Number(n) || 0));
  const tens = count % 100;
  const units = count % 10;
  if (tens >= 11 && tens <= 14) return many;
  if (units === 1) return one;
  if (units >= 2 && units <= 4) return few;
  return many;
}

// "127.0.0.1:11434", "openrouter.ai/api/v1": the endpoint without its scheme.
export function endpointCaption(baseUrl) {
  return typeof baseUrl === 'string' ? baseUrl.replace(/^https?:\/\//i, '') : '';
}

// --- Privacy and access ------------------------------------------------------------------------

// One row per external widget that declares capabilities, plus grants for widgets that are not
// installed (so a remote grant can still be withdrawn).
// catalog: services.plugins.catalog ({ [id]: { manifest, builtin } }).
// -> [{ moduleId, name, capabilities, remote, installed }]
export function grantRows(catalog, document) {
  const grants = object(source(document).grants) ? source(document).grants : {};
  const rows = [];
  const seen = {};
  const entries = object(catalog) ? catalog : {};
  for (const id of Object.keys(entries).sort()) {
    const entry = entries[id];
    if (!object(entry) || entry.builtin === true || !object(entry.manifest)) continue;
    const capabilities = Array.isArray(entry.manifest.capabilities) ? entry.manifest.capabilities.filter(cap => typeof cap === 'string') : [];
    if (!capabilities.length || !moduleIdPattern.test(id)) continue;
    seen[id] = true;
    rows.push({ moduleId: id, name: typeof entry.manifest.name === 'string' && entry.manifest.name ? entry.manifest.name : id,
      capabilities, remote: object(grants[id]) && grants[id].remote === true, installed: true });
  }
  for (const id of Object.keys(grants).sort()) {
    if (seen[id] || !object(grants[id]) || grants[id].remote !== true) continue;
    rows.push({ moduleId: id, name: id, capabilities: [], remote: true, installed: false });
  }
  return rows;
}

// Group hues of the page: a surface tint and ink per kind, tuned like the cheatsheet's palette
// (logic/keybind-hues.mjs), so they are not theme tokens and widgets never depend on them.
export const HUES = Object.freeze({
  dark: Object.freeze({ local: '#8FD3AE', cloud: '#F2C078', vision: '#CDB4F7', embed: '#97BFFA' }),
  light: Object.freeze({ local: '#1E7148', cloud: '#835500', vision: '#6544A8', embed: '#2459AE' }),
});

export function hue(appearance, name) {
  const palette = appearance === 'light' ? HUES.light : HUES.dark;
  return palette[name] || palette.local;
}

// The hue of a role's square: local roles green, remote amber, unbound none.
export function roleHue(document, role) {
  const current = source(document);
  const binding = parseRole(object(current.roles) ? current.roles[role] : '');
  if (!binding) return '';
  const provider = providersOf(current).find(item => item.id === binding.providerId);
  if (!provider) return 'cloud';
  return providerDisclosure(provider, binding.model).execution === 'local' ? 'local' : 'cloud';
}
