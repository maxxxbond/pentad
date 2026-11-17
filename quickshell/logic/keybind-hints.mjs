// The submap hint: the binds of the Hyprland submap (key mode) that is active right now, for the
// strip that lists them near the bottom of the screen. Qt-free. It reads the groups that
// keybinds.mjs parseBinds() builds and never changes them.
//
// Written for the QML JavaScript engine too: no object spread, no structuredClone, no `??`, no
// optional chaining.

// The most rows the strip lists; the rest are counted as "+N".
export const MAX_ROWS = 12;
export const MAX_COLUMNS = 3;
// Submap names are clipped like keybinds.mjs clips them, so a long name still finds its group.
const MAX_NAME = 40;
const LUA_TEXT = ['Функція Lua без опису', 'Lua function without a description'];

function translator(text) {
    return typeof text === 'function' ? text : function(uk, en) { return text === 'uk' ? uk : en; };
}

// The submap name from Hyprland's `submap>>NAME` event, as plain text: control characters become
// spaces, bidirectional overrides are dropped, white space collapses, and it is clipped to 40
// characters. '' means no submap is active: Hyprland reports a reset with an empty name, and
// 'reset' is the dispatcher's own word for leaving a submap, so no submap can carry it.
export function submapName(value) {
    if (typeof value !== 'string' && typeof value !== 'number') return '';
    const text = String(value).replace(/[‎‏‪-‮⁦-⁩]+/g, '')
        .replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim();
    if (text === '' || text === 'reset') return '';
    return text.length > MAX_NAME ? text.slice(0, MAX_NAME - 1).trim() + '…' : text;
}

function isBind(bind) {
    return !!bind && typeof bind === 'object' && Array.isArray(bind.keys);
}

// What the strip shows for submap `name`: { title, rows, overflow, total }. `rows` are the
// submap's binds in config order as { keys, description, described }, at most `options.limit`
// (12 by default); `overflow` counts the rest and `total` all of them. The submap is matched
// case-insensitively against the `kind: 'submap'` groups. A bind without a description reads as
// its dispatcher, the way parseBinds wrote it, with `described` false. Lua binds without a
// description have nothing to read, so they are left out unless the submap has nothing else.
// `options.text` is the shell's translation function, or 'uk' / 'en'.
export function submapHint(groups, name, options) {
    const tr = translator(options ? options.text : null);
    const shown = submapName(name);
    const requested = options && Number.isInteger(options.limit) && options.limit > 0 ? options.limit : MAX_ROWS;
    const limit = Math.min(requested, 100);
    const result = { title: shown ? tr('Режим клавіш: ' + shown, 'Submap: ' + shown) : '', rows: [], overflow: 0, total: 0 };
    if (!shown) return result;
    const wanted = shown.toLowerCase();
    const group = (Array.isArray(groups) ? groups : []).find(function(item) {
        return !!item && item.kind === 'submap' && submapName(item.name).toLowerCase() === wanted;
    });
    const binds = group && Array.isArray(group.binds) ? group.binds.filter(isBind) : [];
    const readable = binds.filter(function(bind) { return !(bind.lua && !bind.described); });
    const rows = (readable.length ? readable : binds).map(function(bind) {
        const unreadable = !!bind.lua && !bind.described;
        return {
            keys: bind.keys.filter(function(key) { return typeof key === 'string'; }),
            description: unreadable ? tr(LUA_TEXT[0], LUA_TEXT[1]) : typeof bind.description === 'string' ? bind.description : '',
            described: !!bind.described && !unreadable,
        };
    });
    result.total = rows.length;
    result.rows = rows.slice(0, limit);
    result.overflow = rows.length - result.rows.length;
    return result;
}

// The columns the rows flow into: one up to 4 rows, two up to 8, three above; never more than
// `fit`, the number of columns the width allows (at least one).
export function columnCount(rowCount, fit) {
    const count = Math.max(0, Math.floor(Number(rowCount)) || 0);
    const wanted = count <= 4 ? 1 : count <= 8 ? 2 : MAX_COLUMNS;
    return Math.max(1, Math.min(wanted, Math.floor(Number(fit)) || 1));
}

// Rows split into `count` columns top to bottom, then left to right, so they read in config
// order; every column but the last is full. No rows, no columns.
export function splitColumns(rows, count) {
    const list = Array.isArray(rows) ? rows : [];
    const total = Math.max(1, Math.min(MAX_COLUMNS, Math.floor(Number(count)) || 1));
    const height = Math.max(1, Math.ceil(list.length / total));
    const columns = [];
    for (let index = 0; index < list.length; index += height) columns.push(list.slice(index, index + height));
    return columns;
}
