import { slots } from './config.mjs';
import { validateSettings } from './plugin-manifest.mjs';

const find = (registry, id) => (Array.isArray(registry) ? registry : []).find((entry) => entry.id === id);

export function registryFromCatalog(catalog) {
  if (!catalog || typeof catalog !== 'object') return [];
  return Object.values(catalog).filter((entry) => entry && entry.manifest).map(({ manifest }) => ({
    id: manifest.id,
    name: manifest.name,
    allowedSlots: manifest.allowedSlots,
    settingsFields: manifest.settingsFields ?? [],
    defaults: manifest.defaults ?? {},
  }));
}

function widgetErrors(registry, draft) {
  return find(registry, draft.moduleId) ? [] : ['Choose a widget'];
}
function placementErrors(registry, draft) {
  const widget = find(registry, draft.moduleId);
  if (!widget) return ['Choose a widget'];
  if (!slots.includes(draft.slot)) return ['Choose a slot'];
  if (!widget.allowedSlots.includes(draft.slot)) return [`Slot ${draft.slot} is not allowed for this widget`];
  return [];
}
function settingsErrors(registry, draft) {
  const widget = find(registry, draft.moduleId);
  if (!widget) return ['Choose a widget'];
  const result = validateSettings({ settingsFields: widget.settingsFields, defaults: widget.defaults }, draft.settings ?? {});
  return result.ok ? [] : result.errors;
}

export function widgetSteps(registry) {
  return [
    { id: 'widget', icon: 'material/extension-symbolic.svg', labelUk: 'Віджет', labelEn: 'Widget',
      validate: (draft) => widgetErrors(registry, draft) },
    { id: 'placement', icon: 'tabler/device-desktop-symbolic.svg', labelUk: 'Розміщення', labelEn: 'Placement',
      validate: (draft) => placementErrors(registry, draft) },
    { id: 'settings', icon: 'material/colorize-symbolic.svg', labelUk: 'Параметри', labelEn: 'Settings',
      validate: (draft) => settingsErrors(registry, draft) },
    { id: 'review', icon: 'material/radio-button-checked-symbolic.svg', labelUk: 'Перевірка', labelEn: 'Review',
      validate: (draft) => [widgetErrors, placementErrors, settingsErrors].flatMap((check) => check(registry, draft)) },
  ];
}

export function buildPlacement(draft) {
  const taken = new Set(draft.existing ?? []);
  const suffix = String(draft.moduleId).split('.').pop();
  let n = 1;
  while (taken.has(`${suffix}-${n}`)) n++;
  return { instanceId: `${suffix}-${n}`, moduleId: draft.moduleId, slot: draft.slot, enabled: true,
    settings: Object.assign({}, draft.settings ?? {}) };
}
