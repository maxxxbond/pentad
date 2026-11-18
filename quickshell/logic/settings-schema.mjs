import { isShortcut } from './settings-shortcut.mjs';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
export const groups = Object.freeze(['personalization', 'devices', 'shell', 'behavior', 'system']);
export const controls = Object.freeze(['toggle', 'segmented', 'dropdown', 'slider', 'stepper', 'text', 'color', 'options', 'cards', 'shortcut', 'list', 'pentads', 'framePreview', 'button', 'link', 'value', 'font', 'chips', 'catalog', 'wallpapers', 'swatches', 'panel',
  'modelsHero', 'modelProviders', 'modelRoles', 'installedModels', 'modelGrants', 'modelWorker']);
// The Models page's editors (features/settings/SettingsModel*.qml): each edits a part of the
// `models` document through services.modelSettings and lives only on that document.
export const modelControls = Object.freeze(['modelsHero', 'modelProviders', 'modelRoles', 'installedModels', 'modelGrants', 'modelWorker']);
// Editors that take the whole row with no label (SettingsField `bare`) ...
export const fullBleedControls = Object.freeze(['catalog', 'wallpapers', 'panel'].concat(modelControls));
// ... and those that also bring their own cards, so a section made only of them draws none.
export const framelessControls = Object.freeze(['catalog', 'wallpapers', 'panel', 'modelsHero', 'modelProviders', 'modelRoles', 'installedModels']);
// Live device panels a `panel` item can embed; they talk to services, not to a config document.
export const panels = Object.freeze(['wifi', 'sound', 'mixer', 'power', 'brightness',
  'bluetooth', 'bluetooth-devices', 'bluetooth-nearby', 'datetime', 'default-apps', 'about', 'idle',
  'network-overview', 'network-known-wifi', 'network-wired', 'network-tethering', 'network-hotspot', 'network-vpn']);
// Editors that manage a whole document fragment and never appear as plain manifest fields.
const editorControls = ['list', 'catalog', 'chips', 'wallpapers'].concat(modelControls);
const documents = ['theme', 'layout', 'interface', 'spotlight', 'notifications', 'session', 'wallpaper', 'models'];
const actionControls = ['button', 'link', 'value', 'panel'];
const nonEmpty = value => typeof value === 'string' && value.trim() !== '';

function itemErrors(item, path, keys, errors) {
  if (!object(item)) { errors.push(`${path} must be an object`); return; }
  if (!nonEmpty(item.key)) errors.push(`${path}.key is invalid`);
  else if (keys.has(item.key)) errors.push(`${path} duplicate item key: ${item.key}`);
  else keys.add(item.key);
  if (!controls.includes(item.control)) errors.push(`${path}.control is invalid`);
  if (!nonEmpty(item.labelUk) || !nonEmpty(item.labelEn)) errors.push(`${path} requires labelUk and labelEn`);
  if (!actionControls.includes(item.control)) {
    if (!documents.includes(item.document)) errors.push(`${path}.document is invalid`);
    if (!nonEmpty(item.path)) errors.push(`${path}.path is required`);
  }
  if (item.control === 'toggle' && item.kind !== 'boolean') errors.push(`${path} toggle requires kind boolean`);
  if (['segmented', 'dropdown'].includes(item.control) && (!Array.isArray(item.options) || !item.options.length)) errors.push(`${path} ${item.control} requires options`);
  if (Array.isArray(item.options) && item.options.some(option => !object(option) || !own(option, 'value') || !nonEmpty(option.labelUk) || !nonEmpty(option.labelEn))) errors.push(`${path}.options must contain {value,labelUk,labelEn}`);
  if (item.control === 'slider') {
    if (!(typeof item.min === 'number' && typeof item.max === 'number' && item.min < item.max)) errors.push(`${path} slider requires min < max`);
    if (!(typeof item.step === 'number' && item.step > 0)) errors.push(`${path} slider requires step > 0`);
  }
  if (item.control === 'cards') {
    if (!Array.isArray(item.options) || !item.options.length) errors.push(`${path} cards requires options`);
    if (item.kind !== 'select') errors.push(`${path} cards requires kind select`);
  }
  if (item.control === 'color' && item.kind !== 'color') errors.push(`${path} color requires kind color`);
  if (item.control === 'shortcut') {
    if (item.kind !== 'text') errors.push(`${path} shortcut requires kind text`);
    if (item.default !== undefined && !isShortcut(item.default)) errors.push(`${path} shortcut default is not a valid shortcut`);
  }
  if (item.control === 'list' && item.kind !== 'select') errors.push(`${path} list requires kind select`);
  if (item.control === 'catalog' && item.kind !== 'select') errors.push(`${path} catalog requires kind select`);
  if (item.control === 'font' && item.kind !== 'text') errors.push(`${path} font requires kind text`);
  if (item.control === 'wallpapers' && item.kind !== 'text') errors.push(`${path} wallpapers requires kind text`);
  if (item.control === 'swatches' && item.kind !== 'color') errors.push(`${path} swatches requires kind color`);
  if (item.control === 'chips') {
    if (item.kind !== 'select') errors.push(`${path} chips requires kind select`);
    if (!Array.isArray(item.choices) || !item.choices.length
      || item.choices.some(choice => !object(choice) || !own(choice, 'value') || !nonEmpty(choice.labelUk) || !nonEmpty(choice.labelEn)))
      errors.push(`${path} chips requires choices {value,labelUk,labelEn}`);
    if (item.sentinel !== undefined && !nonEmpty(item.sentinel)) errors.push(`${path}.sentinel must be a non-empty string`);
    if (Boolean(item.sentinelUk) !== Boolean(item.sentinelEn)) errors.push(`${path} sentinel labels come in pairs`);
  }
  if (item.unit !== undefined && (!nonEmpty(item.unit) || !['slider', 'stepper'].includes(item.control))) errors.push(`${path}.unit requires a non-empty string on a slider or stepper`);
  if (item.prefix !== undefined && (!nonEmpty(item.prefix) || item.control !== 'text')) errors.push(`${path}.prefix requires a non-empty string on a text control`);
  if (item.art !== undefined && !nonEmpty(item.art)) errors.push(`${path}.art must be a non-empty string`);
  if (Array.isArray(item.options) && item.options.some(option => object(option) && option.art !== undefined && !nonEmpty(option.art))) errors.push(`${path}.options art must be a non-empty string`);
  if (['button', 'link'].includes(item.control) && !nonEmpty(item.action)) errors.push(`${path} ${item.control} requires action`);
  if (item.control === 'panel' && !panels.includes(item.panel)) errors.push(`${path} panel requires one of ${panels.join(', ')}`);
  if (modelControls.includes(item.control) && item.document !== 'models') errors.push(`${path} ${item.control} requires document models`);
}

export function validateCatalog(pages) {
  const errors = [];
  if (!Array.isArray(pages)) return { ok: false, errors: ['pages must be an array'] };
  const ids = new Set();
  for (const [pi, page] of pages.entries()) {
    const path = `pages[${pi}]`;
    if (!object(page)) { errors.push(`${path} must be an object`); continue; }
    if (!nonEmpty(page.id)) errors.push(`${path}.id is invalid`);
    else if (ids.has(page.id)) errors.push(`${path} duplicate page id: ${page.id}`);
    else ids.add(page.id);
    if (!groups.includes(page.group)) errors.push(`${path}.group is invalid`);
    if (!nonEmpty(page.labelUk) || !nonEmpty(page.labelEn)) errors.push(`${path} requires labelUk and labelEn`);
    if (!Array.isArray(page.keywords)) errors.push(`${path}.keywords must be an array`);
    const tabs = new Set((Array.isArray(page.tabs) ? page.tabs : []).filter(object).map(tab => tab.id));
    if (!Array.isArray(page.sections)) { errors.push(`${path}.sections must be an array`); continue; }
    const keys = new Set();
    const all = [];
    for (const [si, section] of page.sections.entries()) {
      const sp = `${path}.sections[${si}]`;
      if (!object(section)) { errors.push(`${sp} must be an object`); continue; }
      if (!nonEmpty(section.id)) errors.push(`${sp}.id is invalid`);
      if (section.collapsible !== undefined && typeof section.collapsible !== 'boolean') errors.push(`${sp}.collapsible must be a boolean`);
      if (section.untitled !== undefined && typeof section.untitled !== 'boolean') errors.push(`${sp}.untitled must be a boolean`);
      if (section.tab !== undefined && !tabs.has(section.tab)) errors.push(`${sp}.tab references an unknown tab`);
      if (!Array.isArray(section.items)) { errors.push(`${sp}.items must be an array`); continue; }
      for (const [ii, item] of section.items.entries()) { itemErrors(item, `${sp}.items[${ii}]`, keys, errors); if (object(item)) all.push([`${sp}.items[${ii}]`, item]); }
    }
    for (const [ip, item] of all) {
      if (item.visibleWhen !== undefined && (!object(item.visibleWhen) || !keys.has(item.visibleWhen.key))) errors.push(`${ip}.visibleWhen must reference an existing key on the same page`);
    }
  }
  return errors.length ? { ok: false, errors } : { ok: true };
}

export function manifestFor(page) {
  const defaults = {};
  const settingsFields = [];
  for (const section of page.sections) for (const item of section.items) {
    if (actionControls.includes(item.control) || editorControls.includes(item.control)) continue;
    const field = { key: item.key, kind: item.kind, label: item.labelEn };
    if (own(item, 'default')) { field.default = item.default; defaults[item.key] = item.default; }
    if (item.options) field.options = item.options.map(option => ({ value: option.value, label: option.labelEn }));
    if (typeof item.min === 'number') field.min = item.min;
    if (typeof item.max === 'number') field.max = item.max;
    settingsFields.push(field);
  }
  return { defaults, settingsFields };
}
