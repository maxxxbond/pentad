import { placementsForSlot } from './placement.mjs';

// With a plugin catalog, placement (sections, position, frame) is applied; without one the legacy slot filter is used.
export function sidebarPlacements(widgets, catalog) {
  if (!Array.isArray(widgets)) return [];
  if (catalog) return placementsForSlot(widgets, catalog, 'sidebar-left');
  return widgets.filter(placement => placement
    && placement.enabled === true
    && placement.slot === 'sidebar-left');
}
