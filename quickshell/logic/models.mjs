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
const envNamePattern = /^[A-Za-z_][A-Za-z0-9_]{0,127}$/;
const secretRefPattern = /^secret:\/\/pentad\/[a-z0-9._-]+(?:\/[a-z0-9._-]+)*$/;
// A key value written into the document would reach QML views and backups; only references are accepted.
const inlineSecretKey = /(?:password|secret|token|api[-_]?key)/i;
const printable = value => !/[\x00-\x1f\x7f]/.test(value);

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
  const loopback = host === 'localhost' || host === '::1' || /^127(?:\.[0-9]{1,3}){3}$/.test(host);
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

// Where a call to this provider runs, shown to the user before any data leaves.
// Local only when the endpoint is this machine; anything unreadable counts as remote.
export function providerDisclosure(provider, model) {
  const source = object(provider) ? provider : {};
  const parts = endpointParts(source.baseUrl);
  const name = typeof source.name === 'string' && source.name ? source.name : typeof source.id === 'string' ? source.id : '';
  return {
    execution: parts && parts.loopback ? 'local' : 'remote',
    provider: name,
    host: parts ? parts.host : '',
    model: typeof model === 'string' ? model : '',
  };
}
