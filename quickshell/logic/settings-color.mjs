import { isHexColor } from './theme.mjs';

// Same #RRGGBB rule as resolveTheme. Returns the upper-cased color or '' when invalid.
export function normalizeColor(text) {
  const value = typeof text === 'string' ? text.trim() : '';
  return isHexColor(value) ? value.toUpperCase() : '';
}

export function sameColor(a, b) {
  return typeof a === 'string' && typeof b === 'string' && a.toLowerCase() === b.toLowerCase();
}

export const defaultSwatches = Object.freeze(['#869677', '#7C9AB5', '#B58C6A', '#A57FB0', '#C27C7C', '#6FA8A0', '#C2B26A']);
