// The keyboard map of the keybind cheatsheet: an ANSI 75 % layout and the binds of one modifier
// layer placed on its keys, so the view can show at a glance which keys are bound and which are
// free. Qt-free.
//
// Written for the QML JavaScript engine too: no object spread, no structuredClone, no `??`, no
// optional chaining.

import { keyLabel, labelFor } from './keybinds.mjs';

// Modifier names in the order the cheatsheet writes them (keybinds.mjs keyLabels).
const MODIFIERS = ['Super', 'Ctrl', 'Alt', 'Shift', 'Caps', 'Mod2', 'Mod3', 'Mod5'];
const MODIFIER_LOOKUP = { control: 'Ctrl' };
MODIFIERS.forEach(function(name) { MODIFIER_LOOKUP[name.toLowerCase()] = name; });

const MAX_LABEL = 64;
const MAX_TEXT = 160;

function key(id, label, w, extra) {
    return Object.assign({ id: id, label: label, w: w }, extra || {});
}
function gap(w) {
    return { id: '', label: '', w: w };
}
function letters(text) {
    return text.split('').map(function(letter) { return key(letter.toLowerCase(), letter, 1); });
}
function fKeys(from, to) {
    const keys = [];
    for (let number = from; number <= to; number++) keys.push(key('f' + number, 'F' + number, 1));
    return keys;
}

// Rows of { id, label, w } with `w` in key units (1 = a letter key). Spacers have the id ''.
// Modifier keys carry `mod`; the right-hand copies of a modifier carry `of`, the id their binds
// are filed under. `short` is a conventional shorter legend for narrow keys.
export const LAYOUT = [
    [key('esc', 'Esc', 1), gap(0.25)].concat(fKeys(1, 4), [gap(0.25)], fKeys(5, 8), [gap(0.25)], fKeys(9, 12),
        [gap(0.25), key('print', 'Print', 1, { short: 'PrtSc' }), key('delete', 'Delete', 1, { short: 'Del' })]),
    [key('grave', '`', 1)].concat(letters('1234567890'), [key('minus', '-', 1), key('equal', '=', 1),
        key('backspace', 'Backspace', 2, { short: 'Bksp' }), key('home', 'Home', 1)]),
    [key('tab', 'Tab', 1.5)].concat(letters('QWERTYUIOP'), [key('bracketleft', '[', 1), key('bracketright', ']', 1),
        key('backslash', '\\', 1.5), key('pgup', 'PgUp', 1)]),
    [key('caps', 'Caps', 1.75, { mod: 'Caps' })].concat(letters('ASDFGHJKL'), [key('semicolon', ';', 1),
        key('apostrophe', '\'', 1), key('enter', 'Enter', 2.25), key('pgdn', 'PgDn', 1)]),
    [key('shift', 'Shift', 2.25, { mod: 'Shift' })].concat(letters('ZXCVBNM'), [key('comma', ',', 1),
        key('period', '.', 1), key('slash', '/', 1), key('shift-r', 'Shift', 1.75, { mod: 'Shift', of: 'shift' }),
        key('up', '↑', 1), key('end', 'End', 1)]),
    [key('ctrl', 'Ctrl', 1.25, { mod: 'Ctrl' }), key('super', 'Super', 1.25, { mod: 'Super' }),
        key('alt', 'Alt', 1.25, { mod: 'Alt' }), key('space', 'Space', 6.25),
        key('alt-r', 'Alt', 1.5, { mod: 'Alt', of: 'alt' }), key('ctrl-r', 'Ctrl', 1.5, { mod: 'Ctrl', of: 'ctrl' }),
        key('left', '←', 1), key('down', '↓', 1), key('right', '→', 1)],
];

function rowWidth(row) {
    let width = 0;
    for (const entry of row) width += entry.w;
    return width;
}

export const UNITS = rowWidth(LAYOUT[0]);

// The board's measures in pixels for one key unit (the side of a 1 × 1 key): keys stand `gap`
// apart, the function row a further `functionGap` (about a quarter key) above the rest, and the
// case keeps `pad` around them; both grow with the unit on the 4 px grid.
export const MAX_UNIT = 72;
const MIN_UNIT = 12;
function measures(unit) {
    const gap = 4;
    const functionGap = Math.max(4, Math.round(unit / 16) * 4);
    const pad = unit >= 56 ? 16 : unit >= 40 ? 12 : 8;
    const pitch = unit + gap;
    const boardWidth = UNITS * pitch - gap;
    const boardHeight = LAYOUT.length * pitch - gap + functionGap;
    return {
        unit: unit, gap: gap, pitch: pitch, functionGap: functionGap, pad: pad,
        boardWidth: boardWidth, boardHeight: boardHeight, width: boardWidth + 2 * pad, height: boardHeight + 2 * pad,
    };
}

// The largest board, case included, that fits `width` and, when `height` is above 0, `height`:
// { unit, gap, pitch, functionGap, pad, boardWidth, boardHeight, width, height }. The unit is at
// most MAX_UNIT, so a wide card centres a board of readable keys instead of stretching them, and
// at least 12 px however small the room.
export function boardMetrics(width, height) {
    const room = Number(width) > 0 ? Number(width) : 0;
    const tall = Number(height) > 0 ? Number(height) : Infinity;
    for (let unit = MAX_UNIT; unit > MIN_UNIT; unit--) {
        const sized = measures(unit);
        if (sized.width <= room && sized.height <= tall) return sized;
    }
    return measures(MIN_UNIT);
}

// Every key without the spacers, with its row and its left edge in key units:
// [{ id, label, w, x, row, mod?, of?, short? }], in reading order.
export const KEYS = [];
LAYOUT.forEach(function(row, rowIndex) {
    let x = 0;
    for (const entry of row) {
        if (entry.id) KEYS.push(Object.assign({}, entry, { x: x, row: rowIndex }));
        x += entry.w;
    }
});

const BY_ID = {};
const BY_LABEL = {};
for (const entry of KEYS) {
    BY_ID[entry.id] = entry;
    // The first key with a legend wins, so 'Alt' is the left Alt.
    const lower = entry.label.toLowerCase();
    if (!Object.prototype.hasOwnProperty.call(BY_LABEL, lower)) BY_LABEL[lower] = entry.id;
}
// Names other sheets write for the same keys.
const ALIASES = { control: 'ctrl', escape: 'esc', return: 'enter', del: 'delete', pageup: 'pgup', pagedown: 'pgdn',
    'caps lock': 'caps', capslock: 'caps', prtsc: 'print', bksp: 'backspace' };

function text(value, limit) {
    if (typeof value !== 'string' && typeof value !== 'number') return '';
    const result = String(value).trim();
    return result.length > limit ? result.slice(0, limit) : result;
}

function lookup(label) {
    const lower = label.toLowerCase();
    if (Object.prototype.hasOwnProperty.call(BY_LABEL, lower)) return BY_LABEL[lower];
    if (Object.prototype.hasOwnProperty.call(ALIASES, lower)) return ALIASES[lower];
    return '';
}

// The layout key id for a keycap label ('Q', 'q', '/', 'Enter', 'Super'), or '' when the label
// is not one physical key on this layout: mouse buttons, scroll, media keys, 'Key 123',
// composites such as 'h / j / k / l', or anything unknown. Raw Hyprland names ('slash',
// 'code:49', 'Page_Up') resolve through keybinds.mjs keyLabel.
export function keyId(label) {
    const raw = text(label, MAX_LABEL);
    if (!raw) return '';
    return lookup(raw) || lookup(keyLabel(raw));
}

// The id a key's binds are filed under: the right Alt, Ctrl and Shift share the left key's binds.
export function bindId(id) {
    const entry = Object.prototype.hasOwnProperty.call(BY_ID, String(id)) ? BY_ID[String(id)] : null;
    return entry ? entry.of || entry.id : '';
}

export function keyById(id) {
    return Object.prototype.hasOwnProperty.call(BY_ID, String(id)) ? BY_ID[String(id)] : null;
}

function modifierName(value) {
    const lower = text(value, MAX_LABEL).toLowerCase();
    return Object.prototype.hasOwnProperty.call(MODIFIER_LOOKUP, lower) ? MODIFIER_LOOKUP[lower] : '';
}

// Modifier names in display order, each once; unknown names and non-strings drop out.
export function normalizeMods(mods) {
    const found = {};
    for (const value of Array.isArray(mods) ? mods : []) {
        const name = modifierName(value);
        if (name) found[name] = true;
    }
    return MODIFIERS.filter(function(name) { return !!found[name]; });
}

// Order-insensitive equality of two modifier lists; anything but an array reads as no modifiers.
export function sameMods(a, b) {
    const left = normalizeMods(a);
    const right = normalizeMods(b);
    return left.length === right.length && left.every(function(name, index) { return name === right[index]; });
}

// A bind's keycap labels split into its modifier layer and its key: { mods, key }, or null when
// it has no keys. The leading labels that name a modifier are the layer; one label after them is
// the key. A bind of modifiers only (['Super'], or ['Super', 'Alt'] for Super + Alt_L) presses
// its last modifier as the key. A sequence or several keys after the modifiers gives key ''.
export function splitBind(keys) {
    const labels = (Array.isArray(keys) ? keys : []).map(function(label) { return text(label, MAX_LABEL); });
    if (!labels.length) return null;
    let index = 0;
    while (index < labels.length && modifierName(labels[index])) index++;
    const leading = labels.slice(0, index).map(modifierName);
    const rest = labels.slice(index);
    let pressed = rest.length === 1 ? rest[0] : '';
    if (!rest.length) pressed = leading.pop();
    const pressedMod = modifierName(pressed);
    return {
        mods: normalizeMods(leading).filter(function(name) { return name !== pressedMod; }),
        key: pressed,
    };
}

function eachBind(groups, visit) {
    for (const group of Array.isArray(groups) ? groups : []) {
        if (!group || typeof group !== 'object' || !Array.isArray(group.binds)) continue;
        for (const bind of group.binds) {
            if (!bind || typeof bind !== 'object' || text(bind.submap, MAX_LABEL)) continue;
            const split = splitBind(bind.keys);
            if (split) visit(group, bind, split);
        }
    }
}

// The binds of one modifier layer placed on the layout: { keys: { [id]: [{ description, group,
// groupId, described, lua, label }] }, bound, unplaced }. A bind belongs to the layer when its
// modifiers equal `mods` exactly and it is outside a submap. `bound` counts the placed binds,
// `unplaced` the binds of the layer with no key on the layout (mouse, media, sequences).
// `translate(uk, en)` (the shell's text function) names the dispatcher groups as keybinds.mjs
// labelFor does; without it they read in English.
export function layer(groups, mods, translate) {
    const wanted = normalizeMods(mods);
    const keys = {};
    let bound = 0;
    let unplaced = 0;
    eachBind(groups, function(group, bind, split) {
        if (!sameMods(split.mods, wanted)) return;
        const id = split.key ? keyId(split.key) : '';
        if (!id) {
            unplaced++;
            return;
        }
        if (!keys[id]) keys[id] = [];
        keys[id].push({
            description: text(bind.description, MAX_TEXT),
            group: text(labelFor(group, translate), MAX_TEXT),
            groupId: text(group.id, MAX_TEXT),
            described: bind.described === true,
            lua: bind.lua === true,
            label: split.key,
        });
        bound++;
    });
    return { keys: keys, bound: bound, unplaced: unplaced };
}

// The modifier sets that have at least one bind outside a submap: [{ mods, count }], the most
// used first, then the one with fewer modifiers, then the one the config uses first.
export function layers(groups) {
    const found = [];
    const byName = {};
    eachBind(groups, function(group, bind, split) {
        const name = split.mods.join('+');
        if (!byName[name]) {
            byName[name] = { mods: split.mods, count: 0, order: found.length };
            found.push(byName[name]);
        }
        byName[name].count++;
    });
    found.sort(function(a, b) {
        return b.count - a.count || a.mods.length - b.mods.length || a.order - b.order;
    });
    return found.map(function(entry) { return { mods: entry.mods, count: entry.count }; });
}

// Whether the map has something to show for these groups: at least one bind outside a submap
// lands on a key of the layout, and at least half of them do. References of typed commands or
// key sequences (Git, most of Neovim) do not, so the cheatsheet offers only its list for them.
export function usable(groups) {
    let placed = 0;
    let total = 0;
    eachBind(groups, function(group, bind, split) {
        total++;
        if (split.key && keyId(split.key)) placed++;
    });
    return placed > 0 && placed * 2 >= total;
}

// The key the arrow `direction` ('left', 'right', 'up', 'down') moves to from `id`: left and
// right along the row, up and down to the key whose centre is nearest (the left one on a tie).
// The edges hold; an unknown id gives ''.
export function neighbor(id, direction) {
    const from = keyById(id);
    if (!from) return '';
    if (direction === 'left' || direction === 'right') {
        const row = KEYS.filter(function(entry) { return entry.row === from.row; });
        const index = row.indexOf(from) + (direction === 'left' ? -1 : 1);
        return index >= 0 && index < row.length ? row[index].id : from.id;
    }
    const target = from.row + (direction === 'up' ? -1 : direction === 'down' ? 1 : 0);
    if (target === from.row || target < 0 || target >= LAYOUT.length) return from.id;
    const centre = from.x + from.w / 2;
    let best = null;
    let bestDistance = Infinity;
    for (const entry of KEYS) {
        if (entry.row !== target) continue;
        const distance = Math.abs(entry.x + entry.w / 2 - centre);
        if (distance < bestDistance - 1e-9) {
            best = entry;
            bestDistance = distance;
        }
    }
    return best ? best.id : from.id;
}

// The first key in reading order that has binds in `keys` (a layer's `keys`), else the first key.
export function firstKey(keys) {
    const map = keys && typeof keys === 'object' ? keys : {};
    for (const entry of KEYS) {
        const list = map[bindId(entry.id)];
        if (Array.isArray(list) && list.length) return entry.id;
    }
    return KEYS[0].id;
}

// At most `max` lines for a key's binds: all of them when they fit, otherwise `max - 1` and a
// count of the rest for a last "+N" line. { binds, more }. `max` is at least 2.
export function detailLines(binds, max) {
    const list = Array.isArray(binds) ? binds : [];
    const limit = Math.max(2, Math.floor(Number(max)) || 2);
    if (list.length <= limit) return { binds: list.slice(), more: 0 };
    return { binds: list.slice(0, limit - 1), more: list.length - (limit - 1) };
}

// "Super + Shift + Q": the layer's modifiers in display order, then the key.
export function comboLabel(mods, label) {
    const name = text(label, MAX_LABEL);
    return normalizeMods(mods).concat(name ? [name] : []).join(' + ');
}
