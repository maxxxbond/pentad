// Key bindings from `hyprctl binds -j`, grouped for the keybind cheatsheet. Qt-free.
//
// Written for the QML JavaScript engine too: no object spread, no structuredClone, no `??`.

// `hyprctl binds -j` prints about 90 KB for 200 binds; anything past 1 MiB is not a bind list.
export const MAX_INPUT_LENGTH = 1024 * 1024;
export const MAX_BINDS = 2000;
const MAX_DESCRIPTION = 160;
const MAX_DISPATCHER = 48;
const MAX_ARG = 120;
const MAX_KEY = 32;
const MAX_GROUP = 40;
const MAX_TOKENS = 8;

// Hyprland's modifier bits, in the order the cheatsheet names them.
const MODIFIERS = [
    [64, 'Super'], [4, 'Ctrl'], [8, 'Alt'], [1, 'Shift'], [2, 'Caps'], [16, 'Mod2'], [32, 'Mod3'], [128, 'Mod5'],
];

// The modifier keycap names in display order, as keyLabels writes them.
export const MODIFIER_NAMES = MODIFIERS.map(function(entry) { return entry[1]; });

// Keysym names, looked up in lower case: Hyprland matches them case-insensitively and configs
// write both `Page_Up` and `Page_up`.
const KEY_NAMES = {
    slash: '/', backslash: '\\', comma: ',', period: '.', minus: '-', equal: '=', plus: '+',
    semicolon: ';', apostrophe: '\'', grave: '`', bracketleft: '[', bracketright: ']',
    return: 'Enter', enter: 'Enter', kp_enter: 'Enter', space: 'Space', escape: 'Esc', tab: 'Tab',
    backspace: 'Backspace', delete: 'Delete', insert: 'Insert', home: 'Home', end: 'End',
    page_up: 'PgUp', prior: 'PgUp', page_down: 'PgDn', next: 'PgDn',
    left: '←', right: '→', up: '↑', down: '↓', print: 'Print', pause: 'Pause',
    super_l: 'Super', super_r: 'Super', alt_l: 'Alt', alt_r: 'Alt', control_l: 'Ctrl', control_r: 'Ctrl',
    shift_l: 'Shift', shift_r: 'Shift', caps_lock: 'Caps',
    mouse_down: 'Scroll ↓', mouse_up: 'Scroll ↑', mouse_left: 'Scroll ←', mouse_right: 'Scroll →',
    'mouse:272': 'LMB', 'mouse:273': 'RMB', 'mouse:274': 'MMB',
    xf86audioraisevolume: 'Vol +', xf86audiolowervolume: 'Vol −', xf86audiomute: 'Mute', xf86audiomicmute: 'Mic mute',
    xf86audioplay: 'Play', xf86audiopause: 'Pause', xf86audionext: 'Next', xf86audioprev: 'Prev',
    xf86audiostop: 'Stop', xf86monbrightnessup: 'Bright +', xf86monbrightnessdown: 'Bright −',
};

// `code:NN` binds name a physical key by its X keycode (evdev + 8); these are the US legends of
// the main block, so `ALT + code:49` reads as Alt + ` on any layout.
const KEY_CODES = { 9: 'Esc', 20: '-', 21: '=', 22: 'Backspace', 23: 'Tab', 34: '[', 35: ']', 36: 'Enter',
    47: ';', 48: '\'', 49: '`', 51: '\\', 59: ',', 60: '.', 61: '/', 65: 'Space' };
'1234567890'.split('').forEach(function(digit, index) { KEY_CODES[10 + index] = digit; });
'QWERTYUIOP'.split('').forEach(function(letter, index) { KEY_CODES[24 + index] = letter; });
'ASDFGHJKL'.split('').forEach(function(letter, index) { KEY_CODES[38 + index] = letter; });
'ZXCVBNM'.split('').forEach(function(letter, index) { KEY_CODES[52 + index] = letter; });

// Groups for binds whose description names none, picked by dispatcher.
const BUILTIN_ORDER = ['workspaces', 'windows', 'launch', 'other'];
const BUILTIN_LABELS = {
    workspaces: ['Робочі простори', 'Workspaces'],
    windows: ['Вікна', 'Windows'],
    launch: ['Запуск', 'Launch'],
    other: ['Інше', 'Other'],
};
const WINDOW_DISPATCHERS = ['movefocus', 'movewindow', 'killactive', 'forcekillactive', 'closewindow', 'fullscreen',
    'fullscreenstate', 'togglefloating', 'setfloating', 'settiled', 'pin', 'swapwindow', 'resizeactive', 'resizewindow',
    'centerwindow', 'pseudo', 'togglesplit', 'focuswindow', 'cyclenext', 'swapnext'];

function clip(value, limit) {
    const text = String(value).replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim();
    return text.length > limit ? text.slice(0, limit - 1).trim() + '…' : text;
}

function stringField(value, limit) {
    return typeof value === 'string' || typeof value === 'number' ? clip(value, limit) : '';
}

// One key name as the cheatsheet shows it on a keycap; '' when the bind has no key (a bare
// modifier bind, or a keycode Hyprland did not report).
export function keyLabel(key, keycode) {
    const raw = typeof key === 'string' ? clip(key, MAX_KEY) : '';
    let match = /^code:(\d{1,4})$/i.exec(raw);
    const code = match ? Number(match[1]) : !raw && Number.isInteger(keycode) && keycode > 0 && keycode < 10000 ? keycode : 0;
    if (code) return KEY_CODES[code] || 'Key ' + code;
    if (!raw) return '';
    const lower = raw.toLowerCase();
    if (Object.prototype.hasOwnProperty.call(KEY_NAMES, lower)) return KEY_NAMES[lower];
    // Linux button codes start at 272 (BTN_LEFT), so 275 and 276 are the usual Mouse 4 and 5.
    match = /^mouse:(\d{1,4})$/.exec(lower);
    if (match) return 'Mouse ' + (Number(match[1]) >= 272 ? Number(match[1]) - 271 : match[1]);
    if (lower.indexOf('xf86monbrightness') === 0 && raw.length > 17) return 'Bright ' + raw.slice(17);
    if (lower.indexOf('xf86audio') === 0 && raw.length > 9) return raw.slice(9);
    return raw.charAt(0).toUpperCase() + raw.slice(1);
}

// Modifier names in a fixed order, then the key. A key that repeats a modifier (SUPER + SUPER_L)
// shows once.
export function keyLabels(modmask, key, keycode) {
    const mask = Number.isInteger(modmask) && modmask > 0 ? modmask & 255 : 0;
    const labels = [];
    for (const [bit, name] of MODIFIERS) if (mask & bit) labels.push(name);
    const label = keyLabel(key, keycode);
    if (label && labels.indexOf(label) < 0) labels.push(label);
    return labels;
}

// A keycap label list split into its modifiers and its key: { mods, key }. `mods` are the leading
// labels that name a modifier, in display order; `key` is the rest joined with a space ('' for a
// bare-modifier bind such as ['Super']). Anything but an array of labels reads as empty.
export function splitKeys(keys) {
    const labels = Array.isArray(keys) ? keys.filter(function(label) { return typeof label === 'string'; }) : [];
    const found = [];
    let index = 0;
    while (index < labels.length && MODIFIER_NAMES.indexOf(labels[index]) >= 0) {
        if (found.indexOf(labels[index]) < 0) found.push(labels[index]);
        index++;
    }
    const mods = MODIFIER_NAMES.filter(function(name) { return found.indexOf(name) >= 0; });
    return { mods: mods, key: labels.slice(index).join(' ') };
}

// "Group: text" → { group: 'Group', text: 'text' }. The colon must be followed by a space, so a
// URL or "12:30" in a description is not taken for a group.
export function splitDescription(description) {
    const text = clip(description || '', MAX_DESCRIPTION);
    const match = /^([^:]{1,40}?)\s*:\s+(\S.*)$/.exec(text);
    return match ? { group: clip(match[1], MAX_GROUP), text: match[2] } : { group: '', text: text };
}

export function dispatcherGroup(dispatcher) {
    const name = String(dispatcher || '').toLowerCase();
    if (name === 'workspace' || name.indexOf('movetoworkspace') === 0) return 'workspaces';
    if (WINDOW_DISPATCHERS.indexOf(name) >= 0) return 'windows';
    if (name === 'exec' || name === 'execr') return 'launch';
    return 'other';
}

function builtinGroup(id) {
    const pair = BUILTIN_LABELS[id];
    return { id: id, kind: 'builtin', label: pair[1], name: '', search: (pair[0] + ' ' + pair[1]).toLowerCase(), binds: [] };
}

// Parses `hyprctl binds -j` output (the JSON text or the parsed array) into groups:
// { groups: [{ id, kind, label, name, search, binds: [{ keys, description, described, lua,
// dispatcher, arg, submap, mods, key, duplicate, search }] }], total, truncated, error }. `error` is '' on success,
// otherwise 'too-large', 'invalid-json' or 'not-a-list'. Binds keep the config's order;
// groups named in descriptions come first, then the dispatcher groups, then one group per submap.
// `mods` and `key` are splitKeys(keys); `duplicate` is true when another bind fires on the same
// trigger (submap, exact modifier mask, key and press or release) under a different text.
// Hyprland reports a bind that runs Lua as '__lua' (0.55), as 'HL.Dispatcher(name)' for the hl.dsp.*
// objects and as 'function: 0x…' for a callback (0.56); the arg is a line or function number either way.
function isLuaDispatcher(dispatcher) {
    return dispatcher === '__lua' || dispatcher.startsWith('HL.Dispatcher(') || dispatcher.startsWith('function: ');
}

// What fires a bind, as Hyprland tells binds apart: the submap, the exact modifier mask, the key
// (or keycode) and press or release. Labels are not enough: `Super_L` and `SUPER + SUPER_L` both
// read "Super", and a press and a release bind on one key are a common, deliberate pair.
function triggerOf(entry, submap) {
    const mask = Number.isInteger(entry.modmask) && entry.modmask > 0 ? entry.modmask & 255 : 0;
    const raw = typeof entry.key === 'string' ? clip(entry.key, MAX_KEY).toLowerCase() : '';
    const code = Number.isInteger(entry.keycode) && entry.keycode > 0 && entry.keycode < 10000 ? 'code:' + entry.keycode : '';
    return submap.toLowerCase() + '\u0001' + mask + '\u0001' + (raw || code) + '\u0001' + (entry.release === true ? 'release' : 'press');
}

// Flags the rows whose trigger, or one of the triggers merged into them, fires more than one
// action (`actions`: trigger -> the distinct dispatcher, argument and text it runs). Two binds on
// one trigger with the same description share a row, and that row is flagged. Rows without keys
// take no part.
function markDuplicates(rows, actions) {
    for (const row of rows) {
        row.bind.duplicate = row.bind.keys.length > 0
            && row.triggers.some(function(trigger) { return !!actions[trigger] && actions[trigger].length > 1; });
    }
}

export function parseBinds(json) {
    let list = json;
    if (typeof json === 'string') {
        if (json.length > MAX_INPUT_LENGTH) return { groups: [], total: 0, truncated: false, error: 'too-large' };
        try { list = JSON.parse(json); }
        catch (error) { return { groups: [], total: 0, truncated: false, error: 'invalid-json' }; }
    }
    if (!Array.isArray(list)) return { groups: [], total: 0, truncated: false, error: 'not-a-list' };
    const truncated = list.length > MAX_BINDS;
    const described = [];
    const builtin = {};
    const submaps = [];
    // identity -> { bind, triggers }: a row and every trigger that leads to it.
    const seen = {};
    const rows = [];
    const actions = {};
    let total = 0;
    for (const entry of list.slice(0, MAX_BINDS)) {
        if (!entry || typeof entry !== 'object' || Array.isArray(entry)) continue;
        const dispatcher = stringField(entry.dispatcher, MAX_DISPATCHER);
        const arg = stringField(entry.arg, MAX_ARG);
        const submap = stringField(entry.submap, MAX_GROUP);
        const lua = isLuaDispatcher(dispatcher);
        const split = splitDescription(typeof entry.description === 'string' ? entry.description : '');
        const hasDescription = split.text !== '';
        const keys = keyLabels(entry.modmask, entry.key, entry.keycode);
        // A Lua bind's arg is a function reference, so its description is the only readable text.
        const text = hasDescription ? split.text : lua ? '' : clip(dispatcher + ' ' + arg, MAX_DESCRIPTION);
        if (!keys.length && !text) continue;
        const identity = submap + '\u0001' + keys.join('+') + '\u0001' + text;
        const trigger = triggerOf(entry, submap);
        if (keys.length) {
            const action = dispatcher + '\u0001' + arg + '\u0001' + text;
            if (!actions[trigger]) actions[trigger] = [];
            if (actions[trigger].indexOf(action) < 0) actions[trigger].push(action);
        }
        if (seen[identity]) {
            if (seen[identity].triggers.indexOf(trigger) < 0) seen[identity].triggers.push(trigger);
            continue;
        }
        let group;
        if (submap) {
            const id = 'submap:' + submap.toLowerCase();
            group = submaps.find(function(item) { return item.id === id; });
            if (!group) {
                group = { id: id, kind: 'submap', label: 'Submap: ' + submap, name: submap,
                    search: ('submap режим клавіш ' + submap).toLowerCase(), binds: [] };
                submaps.push(group);
            }
        } else if (split.group) {
            const id = 'group:' + split.group.toLowerCase();
            group = described.find(function(item) { return item.id === id; });
            if (!group) {
                group = { id: id, kind: 'described', label: split.group, name: split.group, search: split.group.toLowerCase(), binds: [] };
                described.push(group);
            }
        } else {
            const id = dispatcherGroup(dispatcher);
            group = builtin[id] || (builtin[id] = builtinGroup(id));
        }
        const parts = splitKeys(keys);
        const bind = {
            keys: keys,
            description: text,
            described: hasDescription,
            lua: lua,
            dispatcher: dispatcher,
            arg: arg,
            submap: submap,
            mods: parts.mods,
            key: parts.key,
            duplicate: false,
            search: [text, keys.join(' '), keys.join('+'), stringField(entry.key, MAX_KEY), dispatcher, lua ? '' : arg]
                .join(' ').toLowerCase(),
        };
        group.binds.push(bind);
        seen[identity] = { bind: bind, triggers: [trigger] };
        rows.push(seen[identity]);
        total++;
    }
    markDuplicates(rows, actions);
    const ordered = BUILTIN_ORDER.filter(function(id) { return !!builtin[id]; }).map(function(id) { return builtin[id]; });
    return { groups: described.concat(ordered, submaps), total: total, truncated: truncated, error: '' };
}

// A Lua bind without a description has nothing to read; the cheatsheet shows it only on request.
export function isHidden(bind) {
    return !!bind && bind.lua && !bind.described;
}

function bindParts(bind) {
    return Array.isArray(bind.mods) && typeof bind.key === 'string' ? { mods: bind.mods, key: bind.key } : splitKeys(bind.keys);
}

// Groups narrowed to the binds that match every word of `query` in their description, key
// names, dispatcher or arguments, or in the group's name in either language. Empty groups drop out.
// Options: `showAll` also lists hidden Lua binds; `mods` (modifier names) keeps the binds that use
// every one of them; `key` keeps the binds whose key equals it, ignoring case; `duplicates` keeps
// only the binds flagged as duplicates.
export function filterBinds(groups, query, options) {
    const showAll = !!(options && options.showAll);
    const wanted = options && Array.isArray(options.mods) ? options.mods : [];
    const key = options && typeof options.key === 'string' ? options.key.toLowerCase() : '';
    const duplicates = !!(options && options.duplicates);
    const tokens = String(query || '').toLowerCase().split(/\s+/).filter(function(token) { return token !== ''; })
        .slice(0, MAX_TOKENS);
    const result = [];
    for (const group of Array.isArray(groups) ? groups : []) {
        const binds = group.binds.filter(function(bind) {
            if (!showAll && !(duplicates && bind.duplicate) && isHidden(bind)) return false;
            if (duplicates && bind.duplicate !== true) return false;
            if (wanted.length || key) {
                const parts = bindParts(bind);
                if (!wanted.every(function(name) { return parts.mods.indexOf(name) >= 0; })) return false;
                if (key && parts.key.toLowerCase() !== key) return false;
            }
            return tokens.every(function(token) {
                return bind.search.indexOf(token) >= 0 || group.search.indexOf(token) >= 0;
            });
        });
        if (binds.length) result.push(Object.assign({}, group, { binds: binds }));
    }
    return result;
}

export function countBinds(groups) {
    let count = 0;
    for (const group of Array.isArray(groups) ? groups : []) count += group.binds.length;
    return count;
}

export function countDuplicates(groups) {
    let count = 0;
    for (const group of Array.isArray(groups) ? groups : []) {
        count += group.binds.filter(function(bind) { return bind.duplicate === true; }).length;
    }
    return count;
}

// [{ name, count }] for each modifier that at least one visible bind uses, in display order.
// `options.showAll` includes the hidden Lua binds, as in filterBinds.
export function modifierCounts(groups, options) {
    const showAll = !!(options && options.showAll);
    const counts = {};
    for (const group of Array.isArray(groups) ? groups : []) {
        for (const bind of group.binds) {
            if (!showAll && isHidden(bind)) continue;
            for (const name of bindParts(bind).mods) counts[name] = (counts[name] || 0) + 1;
        }
    }
    return MODIFIER_NAMES.filter(function(name) { return counts[name] > 0; })
        .map(function(name) { return { name: name, count: counts[name] }; });
}

export function hiddenCount(groups) {
    let count = 0;
    for (const group of Array.isArray(groups) ? groups : []) count += group.binds.filter(isHidden).length;
    return count;
}

// The "Key shortcuts" tiles above the list: at most four binds worth learning first, or none when
// fewer than two qualify. On a reference sheet (`options.reference`) they come from its first
// group; on the live bindings from the group named "Pentad" (any case) when the config has one,
// otherwise from every group in list order (groups in the order the config first uses them, binds
// in config order). Only described binds outside submaps count on the live bindings. A bind is
// skipped when it has more than three keys, when its keys joined with "+" run longer than 12
// characters (it would not set large), and when an earlier tile already has its description.
// [{ keys, description, groupId }].
const SHORTCUT_TILES = 4;
const SHORTCUT_KEYS = 3;
const SHORTCUT_LABEL = 12;
export function keyShortcuts(groups, options) {
    const reference = !!(options && options.reference);
    const list = (Array.isArray(groups) ? groups : []).filter(function(group) {
        return !!group && typeof group === 'object' && Array.isArray(group.binds);
    });
    let source = list;
    if (reference) source = list.slice(0, 1);
    else {
        const named = list.filter(function(group) {
            return group.kind === 'described' && String(group.name || '').toLowerCase() === 'pentad';
        });
        if (named.length) source = named;
    }
    const tiles = [];
    const seen = [];
    for (const group of source) {
        if (!reference && group.kind === 'submap') continue;
        for (const bind of group.binds) {
            if (tiles.length >= SHORTCUT_TILES) break;
            if (!bind || typeof bind !== 'object' || !Array.isArray(bind.keys) || isHidden(bind)) continue;
            if (!reference && (bind.described !== true || (typeof bind.submap === 'string' && bind.submap !== ''))) continue;
            const keys = bind.keys.filter(function(label) { return typeof label === 'string' && label !== ''; });
            const description = typeof bind.description === 'string' ? bind.description.trim() : '';
            if (!keys.length || keys.length > SHORTCUT_KEYS || keys.join('+').length > SHORTCUT_LABEL || !description) continue;
            if (seen.indexOf(description.toLowerCase()) >= 0) continue;
            seen.push(description.toLowerCase());
            tiles.push({ keys: keys, description: description, groupId: String(group.id || '') });
        }
    }
    return tiles.length >= 2 ? tiles : [];
}

// The heading of a group. `text(uk, en)` is the shell's translation function; the dispatcher
// groups and submaps are Pentad's words, a group named in descriptions is shown as written.
export function labelFor(group, text) {
    const tr = typeof text === 'function' ? text : function(uk, en) { return text === 'uk' ? uk : en; };
    if (!group) return '';
    if (group.kind === 'builtin' && BUILTIN_LABELS[group.id]) return tr(BUILTIN_LABELS[group.id][0], BUILTIN_LABELS[group.id][1]);
    if (group.kind === 'submap') return tr('Режим клавіш: ' + group.name, 'Submap: ' + group.name);
    return group.label;
}

// Why the bind list could not be read, for the line under "Hyprland is not answering".
export function reasonText(reason, text) {
    const tr = typeof text === 'function' ? text : function(uk, en) { return text === 'uk' ? uk : en; };
    if (reason === 'missing') return tr('Не знайдено hyprctl.', 'hyprctl was not found.');
    if (reason === 'failed') return tr('hyprctl завершився з помилкою.', 'hyprctl exited with an error.');
    if (reason === 'timeout') return tr('hyprctl не відповів за 5 секунд.', 'hyprctl did not answer within 5 seconds.');
    if (reason === 'too-large') return tr('Відповідь більша за 1 МіБ.', 'The answer is larger than 1 MiB.');
    if (reason === 'invalid-json' || reason === 'not-a-list')
        return tr('Відповідь hyprctl не вдалося прочитати.', 'The answer from hyprctl could not be read.');
    return '';
}

// Three columns from 860 px, two from 560 px, one below.
export function columnCount(width) {
    return width >= 860 ? 3 : width >= 560 ? 2 : 1;
}

// Spreads groups over `count` columns, each into the currently shortest one (a heading counts
// as one row), so the columns end at about the same height. Groups keep their order.
export function layoutColumns(groups, count) {
    const columns = [];
    const heights = [];
    const total = Math.max(1, Math.min(6, Math.floor(Number(count)) || 1));
    for (let index = 0; index < total; index++) { columns.push([]); heights.push(0); }
    for (const group of Array.isArray(groups) ? groups : []) {
        let target = 0;
        for (let index = 1; index < total; index++) if (heights[index] < heights[target]) target = index;
        columns[target].push(group);
        heights[target] += 1 + group.binds.length;
    }
    return columns.filter(function(column, index) { return index === 0 || column.length > 0; });
}
