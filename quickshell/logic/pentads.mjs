// Pentads: Pentad splits the layout into five sections. Every widget declares at least one
// section it can live in (manifest.pentads) and the framework adds Placement and Frame settings.
// This module is pure: no QML, no config access.

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);

// kind 'menu' = side panel (sizes Icon/Row/Tile), kind 'bar' = bar section (sizes Icon/Label/Full).
export const zones = Object.freeze([
  Object.freeze({ id: 'left-menu', kind: 'menu', labelUk: 'Ліве меню', labelEn: 'Left menu' }),
  Object.freeze({ id: 'left', kind: 'bar', labelUk: 'Ліва секція', labelEn: 'Left' }),
  Object.freeze({ id: 'center', kind: 'bar', labelUk: 'Центр', labelEn: 'Center' }),
  Object.freeze({ id: 'right', kind: 'bar', labelUk: 'Права секція', labelEn: 'Right' }),
  Object.freeze({ id: 'right-menu', kind: 'menu', labelUk: 'Праве меню', labelEn: 'Right menu' }),
]);
export const zoneIds = Object.freeze(zones.map(zone => zone.id));

// The ONLY place that maps the five sections to the existing widgetSlots: menus = sidebars,
// center = center, and the bar slots split as left = navigation + telemetry, right = tools + system.
// Changing a line here is enough: manifests, the consistency check, the page builder and config
// validation all read this table.
export const zoneSlots = Object.freeze({
  'left-menu': Object.freeze(['sidebar-left']),
  'left': Object.freeze(['navigation', 'telemetry']),
  'center': Object.freeze(['center']),
  'right': Object.freeze(['tools', 'system']),
  'right-menu': Object.freeze(['sidebar-right']),
});

export const frameLimits = Object.freeze({
  margin: Object.freeze({ min: 0, max: 16, step: 4, default: 0 }),
  padding: Object.freeze({ min: 0, max: 12, step: 4, default: 0 }),
  position: Object.freeze({ min: 1, max: 9, step: 1, default: 1 }),
});
export const backgrounds = Object.freeze(['none', 'subtle', 'solid']);
export const sizesByKind = Object.freeze({ menu: Object.freeze(['icon', 'row', 'tile']), bar: Object.freeze(['icon', 'label', 'full']) });
export const defaultSizeByKind = Object.freeze({ menu: 'row', bar: 'icon' });
export const defaultBackground = 'none';

export const isZone = id => zoneIds.includes(id);
export const zoneOf = id => zones.find(zone => zone.id === id) ?? null;
export const sizesFor = id => sizesByKind[zoneOf(id)?.kind ?? 'bar'];
export const defaultSize = id => defaultSizeByKind[zoneOf(id)?.kind ?? 'bar'];

// Union of slots owned by the given sections, in table order.
export function slotsFor(selected) {
  const result = [];
  for (const id of zoneIds) if (Array.isArray(selected) && selected.includes(id)) for (const slot of zoneSlots[id]) if (!result.includes(slot)) result.push(slot);
  return result;
}

// Sections (canonical order) that own at least one of the given slots.
export function zonesForSlots(slotList) {
  return zoneIds.filter(id => Array.isArray(slotList) && zoneSlots[id].some(slot => slotList.includes(slot)));
}

// Keeps known, allowed, unique ids in canonical order. Falls back to one section, never empty when any is allowed.
export function normalizeZones(value, allowed = zoneIds, fallback) {
  const list = Array.isArray(value) ? value : [];
  const permitted = zoneIds.filter(id => allowed.includes(id));
  const kept = permitted.filter(id => list.includes(id));
  if (kept.length) return kept;
  return fallback !== undefined && permitted.includes(fallback) ? [fallback] : permitted.slice(0, 1);
}

// A section can be switched off only while at least one other stays on.
export function canClear(selected, id) {
  return !(Array.isArray(selected) && selected.includes(id) && selected.length <= 1);
}

// Toggles one section. Refuses unknown/unsupported sections and clearing the last one.
export function toggleZone(selected, id, allowed = zoneIds) {
  const current = normalizeZones(selected, allowed);
  if (!isZone(id) || !allowed.includes(id)) return { ok: false, zones: current, error: 'unsupported' };
  if (current.includes(id)) {
    if (!canClear(current, id)) return { ok: false, zones: current, error: 'last' };
    return { ok: true, zones: current.filter(zone => zone !== id) };
  }
  return { ok: true, zones: normalizeZones([...current, id], allowed) };
}

export function pentadErrors(pentads) {
  if (!Array.isArray(pentads) || !pentads.length || new Set(pentads).size !== pentads.length || pentads.some(id => !isZone(id)))
    return [`manifest.pentads must be a unique non-empty array of: ${zoneIds.join(', ')}`];
  return [];
}

// Manifest pentads must agree with allowedSlots through the mapping table.
export function pentadSlotErrors(pentads, allowedSlots) {
  const errors = [];
  if (!Array.isArray(pentads) || !Array.isArray(allowedSlots)) return errors;
  for (const id of pentads) if (isZone(id) && !zoneSlots[id].some(slot => allowedSlots.includes(slot))) errors.push(`manifest.pentads ${id} has no matching slot in allowedSlots`);
  const covered = slotsFor(pentads);
  for (const slot of allowedSlots) if (!covered.includes(slot)) errors.push(`manifest.allowedSlots ${slot} is not covered by manifest.pentads`);
  return errors;
}

export const isReservedKey = key => typeof key === 'string' && key.startsWith('_');
export const reservedKeys = Object.freeze(['_zones', '_margin', '_padding', '_bg', ...zoneIds.map(id => `_order_${id}`), ...zoneIds.map(id => `_size_${id}`)]);

// Placement and frame values of a widget instance are stored in placement.settings of the layout
// document, under reserved keys that start with an underscore. This validates only those keys.
// allowed limits _zones (default: every section).
export function validatePlacementSettings(settings, { allowed = zoneIds } = {}) {
  const errors = [];
  if (!object(settings)) return { ok: false, errors: ['settings must be an object'] };
  const value = {};
  for (const key of Object.keys(settings)) {
    if (!isReservedKey(key)) continue;
    if (!reservedKeys.includes(key)) { errors.push(`settings.${key} is not a reserved placement key`); continue; }
    const v = settings[key];
    if (key === '_zones') {
      if (!Array.isArray(v) || !v.length || new Set(v).size !== v.length || v.some(id => !isZone(id))) errors.push('settings._zones must be a unique non-empty array of sections');
      else if (v.some(id => !allowed.includes(id))) errors.push('settings._zones contains a section the widget does not support');
      else value[key] = zoneIds.filter(id => v.includes(id));
    } else if (key === '_margin' || key === '_padding') {
      const lim = frameLimits[key === '_margin' ? 'margin' : 'padding'];
      if (!Number.isInteger(v) || v < lim.min || v > lim.max || (v - lim.min) % lim.step !== 0) errors.push(`settings.${key} must be ${lim.min}..${lim.max} in steps of ${lim.step}`);
      else value[key] = v;
    } else if (key === '_bg') {
      if (!backgrounds.includes(v)) errors.push(`settings._bg must be one of: ${backgrounds.join(', ')}`);
      else value[key] = v;
    } else if (key.startsWith('_order_')) {
      const lim = frameLimits.position;
      if (!Number.isInteger(v) || v < lim.min || v > lim.max) errors.push(`settings.${key} must be ${lim.min}..${lim.max}`);
      else value[key] = v;
    } else {
      const id = key.slice('_size_'.length);
      if (!sizesFor(id).includes(v)) errors.push(`settings.${key} must be one of: ${sizesFor(id).join(', ')}`);
      else value[key] = v;
    }
  }
  return errors.length ? { ok: false, errors } : { ok: true, value };
}

// Full resolved placement of a widget instance (defaults filled in) for UI and consumers.
// fallbackSlot: the legacy placement.slot, used when _zones was never stored.
export function resolvePlacement(manifest, settings = {}, fallbackSlot) {
  const allowed = Array.isArray(manifest?.pentads) && manifest.pentads.length ? manifest.pentads : zonesForSlots(manifest?.allowedSlots);
  const stored = object(settings) ? settings : {};
  const legacy = fallbackSlot !== undefined ? zonesForSlots([fallbackSlot]).find(id => allowed.includes(id)) : undefined;
  const valid = (key, v) => validatePlacementSettings({ [key]: v }, { allowed }).ok;
  const pick = (key, fallback) => (own(stored, key) && valid(key, stored[key]) ? stored[key] : fallback);
  const result = {
    allowed,
    zones: normalizeZones(valid('_zones', stored._zones) ? stored._zones : undefined, allowed, legacy),
    margin: pick('_margin', frameLimits.margin.default),
    padding: pick('_padding', frameLimits.padding.default),
    bg: pick('_bg', defaultBackground),
    order: {}, size: {},
  };
  for (const id of allowed) {
    result.order[id] = pick(`_order_${id}`, frameLimits.position.default);
    result.size[id] = pick(`_size_${id}`, defaultSize(id));
  }
  return result;
}

// Concentric radius law: inner radius = outer radius - padding, never negative.
export const innerRadius = (padding, outer) => Math.max(0, outer - padding);
