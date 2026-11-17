// Group hues of the keybind cheatsheet: a small categorical palette, one hue per group, so a group's
// heading, its main keys and its keys on the keyboard map share a colour. Qt-free.
//
// The palette is the cheatsheet's own and deliberately not a theme token: Theme.tokens is reachable
// from external widgets through `qs.theme`, and these colours are not part of that contract. Each
// hue is tuned per appearance to read as 12 px text on a keycap face and on a card tinted with it
// (tests/quickshell/keybind-hues.test.mjs checks the contrast against the theme's own surfaces).
//
// Written for the QML JavaScript engine too: no object spread, no structuredClone, no `??`, no
// optional chaining.

export const HUE_COUNT = 8;

// Index: 0 mint, 1 sky, 2 amber, 3 lavender, 4 rose, 5 teal, 6 coral, 7 slate.
export const PALETTE = {
    dark: ['#8FD3AE', '#97BFFA', '#F2C078', '#CDB4F7', '#F2A0BE', '#74CFD6', '#F5A285', '#AEB8C6'],
    light: ['#1E7148', '#2459AE', '#835500', '#6544A8', '#A02E63', '#0B6870', '#A9431D', '#4B5868'],
};

// The keyboard map colours a bound key more strongly than a list keycap, so the layer reads at a
// glance: the key's top face takes MAP_FACE_TINT of the hue (a list keycap takes 0.14), and its
// legend is the hue moved MAP_INK_LIFT of the way toward the theme's text colour (lighter on the
// dark theme, darker on the light one) so that it still reads on that face.
export const MAP_FACE_TINT = 0.22;
export const MAP_INK_LIFT = 0.3;

// Pentad's dispatcher groups keep one hue each on every config; every submap shares one.
const FIXED = { workspaces: 3, windows: 1, launch: 2, other: 7 };
const SUBMAP = 6;
const MAX_ID = 200;

function idOf(group) {
    return group && (typeof group.id === 'string' || typeof group.id === 'number') ? String(group.id).slice(0, MAX_ID) : '';
}

function fixedIndex(group) {
    if (!group) return -1;
    if (group.kind === 'submap') return SUBMAP;
    if (group.kind === 'builtin' && Object.prototype.hasOwnProperty.call(FIXED, idOf(group))) return FIXED[idOf(group)];
    return -1;
}

// A stable index for a group named in descriptions or a reference group: a string hash of its id.
export function preferredIndex(id) {
    const text = String(id || '').toLowerCase();
    let hash = 7;
    for (let index = 0; index < text.length; index++) hash = (hash * 31 + text.charCodeAt(index)) >>> 0;
    return hash % HUE_COUNT;
}

// { [groupId]: index } for the groups of one sheet, in the order the sheet lists them. The dispatcher
// groups and the submaps take their fixed index. Every other group starts from preferredIndex() of
// its id and moves on to the next index until it finds one that no other group of the sheet has and
// that differs from its neighbours. When the palette runs out, it shares the hue of another group
// named in descriptions (not a dispatcher group's or the submaps', whose hues mean the same on every
// config) that is not its neighbour, and only then any hue its neighbours do not have. The same
// groups always get the same hues.
export function groupHues(groups) {
    const list = (Array.isArray(groups) ? groups : []).filter(function(group) { return idOf(group) !== ''; });
    const indices = list.map(fixedIndex);
    const taken = {};
    const fixed = {};
    indices.forEach(function(index) { if (index >= 0) taken[index] = fixed[index] = true; });
    for (let position = 0; position < list.length; position++) {
        if (indices[position] >= 0) continue;
        const before = position > 0 ? indices[position - 1] : -1;
        const after = position + 1 < list.length ? indices[position + 1] : -1;
        const start = preferredIndex(idOf(list[position]));
        const tiers = [
            function(index) { return !taken[index] && index !== before && index !== after; },
            function(index) { return !fixed[index] && index !== before && index !== after; },
            function(index) { return index !== before && index !== after; },
        ];
        let chosen = start;
        for (const fits of tiers) {
            let found = -1;
            for (let step = 0; step < HUE_COUNT && found < 0; step++) {
                const index = (start + step) % HUE_COUNT;
                if (fits(index)) found = index;
            }
            if (found >= 0) {
                chosen = found;
                break;
            }
        }
        indices[position] = chosen;
        taken[chosen] = true;
    }
    const result = {};
    list.forEach(function(group, position) {
        if (!Object.prototype.hasOwnProperty.call(result, idOf(group))) result[idOf(group)] = indices[position];
    });
    return result;
}

// The colour of a palette index for 'dark' or 'light' (anything else reads as dark); '' for an
// index outside the palette.
export function hueColor(index, appearance) {
    const set = appearance === 'light' ? PALETTE.light : PALETTE.dark;
    return Number.isInteger(index) && index >= 0 && index < set.length ? set[index] : '';
}

// { [groupId]: '#RRGGBB' } for a sheet: groupHues() resolved for one appearance.
export function hueColors(groups, appearance) {
    const indices = groupHues(groups);
    const result = {};
    for (const id of Object.keys(indices)) result[id] = hueColor(indices[id], appearance);
    return result;
}

// The group a key's binds share (a keyboard-map layer's binds carry `groupId`), or '' when the key
// has no binds or binds from more than one group: such a key stays neutral.
export function sharedGroup(binds) {
    const list = Array.isArray(binds) ? binds : [];
    let shared = '';
    for (const bind of list) {
        const id = bind && typeof bind.groupId === 'string' ? bind.groupId : '';
        if (!id || (shared && id !== shared)) return '';
        shared = id;
    }
    return shared;
}

// The groups that have a bind on a key of a keyboard-map layer (`keys`: { [keyId]: binds }), in
// the order of `groups`, for the legend under the map: [{ id, group }].
export function legendGroups(groups, keys) {
    const present = {};
    const map = keys && typeof keys === 'object' ? keys : {};
    for (const id of Object.keys(map)) {
        const binds = Array.isArray(map[id]) ? map[id] : [];
        for (const bind of binds) if (bind && typeof bind.groupId === 'string' && bind.groupId) present[bind.groupId] = true;
    }
    const result = [];
    for (const group of Array.isArray(groups) ? groups : []) {
        const id = idOf(group);
        if (id && present[id] && !result.some(function(entry) { return entry.id === id; })) result.push({ id: id, group: group });
    }
    return result;
}
