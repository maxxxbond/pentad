// Pure helpers for the shortcut recorder: Qt key event data -> "Super+Space".
const order = ['Super', 'Ctrl', 'Alt', 'Shift'];
const functionKey = /^(?:F\d{1,2}|Print)$/;
const modifierKeys = new Set([0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01001103, 0x01000053, 0x01000054]);
const named = new Map([
  [0x20, 'Space'], [0x01000000, 'Escape'], [0x01000001, 'Tab'], [0x01000003, 'Backspace'], [0x01000004, 'Return'],
  [0x01000005, 'Enter'], [0x01000006, 'Insert'], [0x01000007, 'Delete'], [0x01000009, 'Print'],
  [0x01000010, 'Home'], [0x01000011, 'End'], [0x01000012, 'Left'], [0x01000013, 'Up'], [0x01000014, 'Right'],
  [0x01000015, 'Down'], [0x01000016, 'PageUp'], [0x01000017, 'PageDown'],
]);
const modifierBits = { Super: 0x10000000, Ctrl: 0x04000000, Alt: 0x08000000, Shift: 0x02000000 };

export const modifierNames = Object.freeze(order.slice());

export function isModifierKey(qtKey) {
  return modifierKeys.has(qtKey);
}

export function keyName(qtKey) {
  if (named.has(qtKey)) return named.get(qtKey);
  if (qtKey >= 0x01000030 && qtKey <= 0x01000047) return `F${qtKey - 0x0100002f}`;
  if (qtKey >= 0x21 && qtKey <= 0x7e) return String.fromCharCode(qtKey);
  return '';
}

export function modifiersFromQt(mask) {
  const out = {};
  for (const name of order) out[name.toLowerCase()] = Boolean((Number(mask) || 0) & modifierBits[name]);
  return out;
}

// Normalizes event data { key, super, ctrl, alt, shift } into "Super+Ctrl+Alt+Shift+Key".
export function normalizeShortcut(data) {
  if (!data || typeof data !== 'object') return '';
  const key = typeof data.key === 'string' ? data.key.trim() : '';
  if (!key) return '';
  const parts = order.filter(name => data[name.toLowerCase()] === true);
  parts.push(key.length === 1 ? key.toUpperCase() : key);
  return parts.join('+');
}

export function fromQtEvent(qtKey, modifierMask) {
  return normalizeShortcut(Object.assign({ key: keyName(qtKey) }, modifiersFromQt(modifierMask)));
}

export function parseShortcut(text) {
  if (typeof text !== 'string' || !text.trim()) return null;
  const parts = text.split('+').map(part => part.trim());
  if (parts.some(part => !part)) return null;
  const key = parts[parts.length - 1];
  const mods = parts.slice(0, -1);
  if (mods.some(mod => !order.includes(mod)) || new Set(mods).size !== mods.length) return null;
  return { mods, key };
}

// Returns '' when valid, otherwise a reason: 'empty' | 'invalid' | 'modifier-required'.
export function shortcutError(text) {
  const parsed = parseShortcut(text);
  if (!parsed) return text === '' || text === undefined || text === null ? 'empty' : 'invalid';
  if (order.includes(parsed.key)) return 'invalid';
  if (!parsed.mods.length && !functionKey.test(parsed.key)) return 'modifier-required';
  return '';
}

export function isShortcut(text) {
  return shortcutError(text) === '';
}

// Display parts for keycaps; accepts both "Super+Space" and "Super + Space".
export function shortcutParts(text) {
  return typeof text === 'string' && text.trim() ? text.split('+').map(part => part.trim()).filter(Boolean) : [];
}
