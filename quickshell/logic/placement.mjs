// Applies widget placement: which enabled widgets a slot shows, in what order, with what frame.
// Pure (no QML, no config access). A widget with no stored `_zones` keeps its legacy single
// `slot` and renders exactly as before; frame defaults are neutral (0 / 0 / none).
import { resolvePlacement, zoneSlots, zonesForSlots } from './pentads.mjs';

const manifestOf = (catalog, moduleId) => {
  const entry = catalog && catalog[moduleId];
  return entry && entry.manifest ? entry.manifest : null;
};

// Slots a placement occupies, one per active section. A section maps to the first of its slots
// that the widget's manifest allows; sections without such a slot are skipped.
export function occupiedSlots(manifest, placement) {
  const stored = placement.settings && Array.isArray(placement.settings._zones);
  if (!manifest || !stored) {
    const zone = zonesForSlots([placement.slot])[0];
    return [{ zone, slot: placement.slot }];
  }
  const allowedSlots = Array.isArray(manifest.allowedSlots) ? manifest.allowedSlots : [];
  const resolved = resolvePlacement(manifest, placement.settings, placement.slot);
  const result = [];
  for (const zone of resolved.zones) {
    const slot = zoneSlots[zone].find(candidate => allowedSlots.includes(candidate));
    if (slot !== undefined) result.push({ zone, slot });
  }
  return result;
}

// Enabled placements shown in `slot`, ordered by their Position in that section (stable for ties).
// Each entry is the original placement plus `slot` (the occupied slot), `zone`, `order`, `size`
// and `frame` { margin, padding, background }.
export function placementsForSlot(widgets, catalog, slot) {
  if (!Array.isArray(widgets)) return [];
  const entries = [];
  widgets.forEach((placement, index) => {
    if (!placement || placement.enabled !== true) return;
    const manifest = manifestOf(catalog, placement.moduleId);
    const found = occupiedSlots(manifest, placement).find(item => item.slot === slot);
    if (!found) return;
    const resolved = manifest ? resolvePlacement(manifest, placement.settings, placement.slot) : null;
    entries.push({
      index,
      value: Object.assign({}, placement, {
        slot,
        zone: found.zone,
        order: resolved && found.zone ? resolved.order[found.zone] : 1,
        size: resolved && found.zone ? resolved.size[found.zone] : undefined,
        frame: resolved
          ? { margin: resolved.margin, padding: resolved.padding, background: resolved.bg }
          : { margin: 0, padding: 0, background: 'none' },
      }),
    });
  });
  entries.sort((a, b) => a.value.order - b.value.order || a.index - b.index);
  return entries.map(entry => entry.value);
}
