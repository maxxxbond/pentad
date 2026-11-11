import { pentadErrors, pentadSlotErrors, isReservedKey, validatePlacementSettings, zonesForSlots } from './pentads.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const semver = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;
const idPattern = /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/;
export const widgetSlots = Object.freeze(['navigation', 'telemetry', 'center', 'tools', 'system', 'sidebar-left', 'sidebar-right']);
const safePath = (value, requiredExtension = '.qml') => typeof value === 'string' && value.endsWith(requiredExtension) && !/[\\%?#\0]/.test(value) && !value.startsWith('/') && !value.split('/').some(part => !part || part === '.' || part === '..') && !/^[A-Za-z][A-Za-z0-9+.-]*:/.test(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const scalar = value => typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number' && Number.isFinite(value);
const mimePattern = /^[a-z0-9][a-z0-9!#$&^_.+-]*\/(?:[a-z0-9][a-z0-9!#$&^_.+-]*|\*)$/;

function validFieldValue(field, value) {
  switch (field.kind) {
    case 'text': return typeof value === 'string';
    case 'integer': return Number.isSafeInteger(value);
    case 'number': return typeof value === 'number' && Number.isFinite(value);
    case 'boolean': return typeof value === 'boolean';
    case 'select': return scalar(value) && Array.isArray(field.options) && field.options.some(option => object(option) && option.value === value);
    case 'color': return typeof value === 'string' && /^#[\da-f]{6}(?:[\da-f]{2})?$/i.test(value);
    default: return false;
  }
}

function outsideBounds(field, value) {
  return typeof value === 'number' && (typeof field.min === 'number' && value < field.min || typeof field.max === 'number' && value > field.max);
}

// Shared by runtime settings and the generated editor. Explicit falsy defaults still win.
export function settingDefault(manifest, field) {
  return object(manifest.defaults) && own(manifest.defaults, field.key)
    ? manifest.defaults[field.key] : field.default;
}

function toolErrors(tool) {
  const errors = [];
  if (!object(tool)) return ['manifest.tool must be an object'];
  for (const key of Object.keys(tool)) if (!['protocolVersion', 'category', 'keywords', 'accepts', 'produces', 'execution', 'multiple', 'maxItems', 'maxBytes'].includes(key)) errors.push(`manifest.tool.${key} is not supported`);
  if (tool.protocolVersion !== 1) errors.push('manifest.tool.protocolVersion must be 1');
  if (typeof tool.category !== 'string' || !tool.category.trim() || tool.category.length > 48) errors.push('manifest.tool.category must be a short non-empty string');
  if (!Array.isArray(tool.keywords) || tool.keywords.length > 24 || tool.keywords.some(value => typeof value !== 'string' || !value.trim() || value.length > 48)) errors.push('manifest.tool.keywords must contain short non-empty strings');
  for (const key of ['accepts', 'produces']) if (!Array.isArray(tool[key]) || tool[key].length > 16 || new Set(tool[key]).size !== tool[key].length || tool[key].some(value => typeof value !== 'string' || !mimePattern.test(value))) errors.push(`manifest.tool.${key} must contain unique MIME types`);
  if (!['local', 'network', 'ai'].includes(tool.execution)) errors.push('manifest.tool.execution is invalid');
  if (typeof tool.multiple !== 'boolean') errors.push('manifest.tool.multiple must be boolean');
  if (!Number.isInteger(tool.maxItems) || tool.maxItems < 1 || tool.maxItems > 100) errors.push('manifest.tool.maxItems must be between 1 and 100');
  if (!Number.isInteger(tool.maxBytes) || tool.maxBytes < 1 || tool.maxBytes > 10485760) errors.push('manifest.tool.maxBytes must be between 1 and 10485760');
  return errors;
}

function fieldErrors(field, path, errors) {
  if (!object(field)) { errors.push(`${path} must be an object`); return; }
  if (typeof field.key !== 'string' || !/^[A-Za-z][A-Za-z0-9_]*$/.test(field.key)) errors.push(`${path}.key is invalid`);
  if (!['text', 'integer', 'number', 'boolean', 'select', 'color'].includes(field.kind)) errors.push(`${path}.kind is invalid`);
  if (!(typeof field.label === 'string' || typeof field.labelKey === 'string')) errors.push(`${path} requires label or labelKey`);
  for (const key of ['label', 'labelKey', 'labelUk', 'labelEn', 'help', 'helpUk', 'helpEn', 'group', 'groupUk', 'groupEn'])
    if (own(field, key) && typeof field[key] !== 'string') errors.push(`${path}.${key} must be a string`);
  if (own(field, 'step') && (typeof field.step !== 'number' || !Number.isFinite(field.step) || field.step <= 0)) errors.push(`${path}.step must be positive and finite`);
  if (own(field, 'showWhen') && (!object(field.showWhen) || typeof field.showWhen.key !== 'string'
      || !/^[A-Za-z][A-Za-z0-9_]*$/.test(field.showWhen.key) || !own(field.showWhen, 'equals') || !scalar(field.showWhen.equals)))
    errors.push(`${path}.showWhen must contain a setting key and scalar equals value`);
  if (Array.isArray(field.options)) for (const [index, option] of field.options.entries()) {
    if (!object(option)) continue;
    for (const key of ['labelUk', 'labelEn'])
      if (own(option, key) && typeof option[key] !== 'string') errors.push(`${path}.options[${index}].${key} must be a string`);
  }
  if (own(field, 'default')) {
    if (!validFieldValue(field, field.default)) errors.push(`${path}.default has the wrong type or value`);
    if (outsideBounds(field, field.default)) errors.push(`${path}.default is outside its bounds`);
    if (typeof field.default === 'string' && /(?:password|secret|token|api[-_]?key)/i.test(field.key ?? '') && field.default !== '' && !/^secret:\/\/[A-Za-z0-9._/-]+$/.test(field.default)) errors.push(`${path}.default must be a secret reference`);
  }
  if (field.kind === 'select' && (!Array.isArray(field.options) || !field.options.length || field.options.some(option => !object(option) || !own(option, 'value') || !scalar(option.value) || typeof option.label !== 'string'))) errors.push(`${path}.options must contain scalar {value,label} options`);
  if (['integer', 'number'].includes(field.kind)) {
    if (own(field, 'min') && (typeof field.min !== 'number' || !Number.isFinite(field.min))) errors.push(`${path}.min must be finite`);
    if (own(field, 'max') && (typeof field.max !== 'number' || !Number.isFinite(field.max))) errors.push(`${path}.max must be finite`);
    if (typeof field.min === 'number' && typeof field.max === 'number' && field.min > field.max) errors.push(`${path}.min must not exceed max`);
  }
}

// requirePentads: set for new or updated widgets; legacy manifests without pentads stay valid otherwise.
export function validateManifest(manifest, { slot, requirePentads = false } = {}) {
  const errors = [];
  if (!object(manifest)) return { ok: false, errors: ['manifest must be an object'] };
  for (const key of ['id', 'name', 'version', 'apiVersion', 'entry']) if (!own(manifest, key)) errors.push(`manifest.${key} is required`);
  if (typeof manifest.id !== 'string' || !idPattern.test(manifest.id) || manifest.id.includes('..')) errors.push('manifest.id is invalid');
  if (typeof manifest.name !== 'string' || !manifest.name.trim()) errors.push('manifest.name must be a non-empty string');
  if (typeof manifest.version !== 'string' || !semver.test(manifest.version)) errors.push('manifest.version must be semantic versioning');
  if (manifest.apiVersion !== 1) errors.push('manifest.apiVersion must be 1');
  if (own(manifest, 'tool')) errors.push(...toolErrors(manifest.tool));
  for (const key of ['entry', 'controller']) if (own(manifest, key) && !safePath(manifest[key])) errors.push(`manifest.${key} must be a safe relative path`);
  if (!Array.isArray(manifest.allowedSlots) || !manifest.allowedSlots.length || manifest.allowedSlots.some(value => !widgetSlots.includes(value)) || new Set(manifest.allowedSlots).size !== manifest.allowedSlots.length) errors.push('manifest.allowedSlots must be a unique non-empty array of supported slots');
  if (requirePentads || own(manifest, 'pentads')) {
    const bad = pentadErrors(manifest.pentads);
    errors.push(...bad);
    if (!bad.length) errors.push(...pentadSlotErrors(manifest.pentads, manifest.allowedSlots));
  }
  if (slot !== undefined && Array.isArray(manifest.allowedSlots) && !manifest.allowedSlots.includes(slot)) errors.push(`slot ${slot} is not allowed`);
  if (manifest.defaults !== undefined && !object(manifest.defaults)) errors.push('manifest.defaults must be an object');
  if (manifest.settingsFields !== undefined && !Array.isArray(manifest.settingsFields)) errors.push('manifest.settingsFields must be an array');
  const fields = Array.isArray(manifest.settingsFields) ? manifest.settingsFields : [];
  const keys = new Set();
  for (const [index, field] of fields.entries()) {
    fieldErrors(field, `settingsFields[${index}]`, errors);
    if (object(field) && isReservedKey(field.key)) errors.push(`settingsFields[${index}].key ${field.key} is reserved (keys starting with _ belong to Placement and Frame)`);
    if (object(field) && typeof field.key === 'string') {
      if (keys.has(field.key)) errors.push(`duplicate settingsFields key: ${field.key}`);
      keys.add(field.key);
      if (object(manifest.defaults) && own(manifest.defaults, field.key)) {
        const explicit = Object.assign({}, field, { default: manifest.defaults[field.key] });
        fieldErrors(explicit, `defaults.${field.key}`, errors);
      }
    }
  }
  if (object(manifest.defaults)) for (const key of Object.keys(manifest.defaults)) if (!keys.has(key)) errors.push(`defaults.${key} has no settings field`);
  if (manifest.credentials !== undefined && !object(manifest.credentials)) errors.push('manifest.credentials must be an object');
  for (const [key, value] of Object.entries(object(manifest.credentials) ? manifest.credentials : {})) {
    if (typeof value !== 'string' || !/^secret:\/\/[A-Za-z0-9._/-]+$/.test(value)) errors.push(`credentials.${key} must be a secret reference`);
  }
  return errors.length ? { ok: false, errors } : { ok: true, manifest };
}

// Pentads implied by a legacy allowedSlots list (used to migrate manifests).
export const pentadsFromSlots = zonesForSlots;

export function validateSettings(manifest, settings) {
  const errors = [];
  if (!object(manifest) || (manifest.settingsFields !== undefined && !Array.isArray(manifest.settingsFields))) return { ok: false, errors: ['manifest.settingsFields must be an array'] };
  if (!object(settings)) return { ok: false, errors: ['settings must be an object'] };
  const fields = new Map((manifest.settingsFields ?? []).filter(object).map(field => [field.key, field]));
  const merged = Object.assign({}, object(manifest.defaults) ? manifest.defaults : {});
  for (const field of fields.values()) if (!own(merged, field.key) && own(field, 'default')) merged[field.key] = settingDefault(manifest, field);
  Object.assign(merged, settings);
  const placement = validatePlacementSettings(merged, { allowed: Array.isArray(manifest.pentads) ? manifest.pentads : undefined });
  if (!placement.ok) errors.push(...placement.errors);
  for (const [key, value] of Object.entries(merged)) {
    if (isReservedKey(key)) continue;
    const field = fields.get(key);
    if (!field) { errors.push(`settings.${key} has no declared field`); continue; }
    if (!validFieldValue(field, value)) errors.push(`settings.${key} has the wrong type or value`);
    if (outsideBounds(field, value)) errors.push(`settings.${key} is outside its bounds`);
    if (field.kind === 'text' && /(?:password|secret|token|api[-_]?key)/i.test(key) && value !== '' && !/^secret:\/\/[A-Za-z0-9._/-]+$/.test(value)) errors.push(`settings.${key} must be a secret reference`);
  }
  return errors.length ? { ok: false, errors } : { ok: true, settings: merged };
}
