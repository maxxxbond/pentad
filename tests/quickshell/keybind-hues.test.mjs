import test from 'node:test';
import assert from 'node:assert/strict';
import {
    HUE_COUNT, MAP_FACE_TINT, MAP_INK_LIFT, PALETTE, groupHues, hueColor, hueColors, legendGroups, preferredIndex, sharedGroup,
} from '../../quickshell/logic/keybind-hues.mjs';
import { filterBinds, parseBinds } from '../../quickshell/logic/keybinds.mjs';
import { SAMPLE_BINDS } from '../../quickshell/logic/keybinds-sample.mjs';
import { groupsFor, sheetIds } from '../../quickshell/logic/cheatsheets.mjs';
import { layer } from '../../quickshell/logic/keyboard-map.mjs';
import { resolveTheme } from '../../quickshell/logic/theme.mjs';

const en = (ukText, enText) => enText;

function luminance(hex) {
    const channels = [1, 3, 5].map(index => {
        const value = parseInt(hex.slice(index, index + 2), 16) / 255;
        return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}
function contrast(first, second) {
    const a = luminance(first);
    const b = luminance(second);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
// Qt.tint(base, Qt.alpha(tint, alpha)) for opaque colours.
function tint(base, color, alpha) {
    return '#' + [1, 3, 5].map(index => Math.round(parseInt(base.slice(index, index + 2), 16) * (1 - alpha)
        + parseInt(color.slice(index, index + 2), 16) * alpha).toString(16).padStart(2, '0')).join('').toUpperCase();
}

test('the palette has the same number of distinct hues for both appearances', () => {
    assert.equal(PALETTE.dark.length, HUE_COUNT);
    assert.equal(PALETTE.light.length, HUE_COUNT);
    for (const set of [PALETTE.dark, PALETTE.light]) {
        assert.equal(new Set(set).size, HUE_COUNT);
        assert.ok(set.every(color => /^#[0-9A-F]{6}$/.test(color)));
    }
    assert.equal(hueColor(0, 'dark'), PALETTE.dark[0]);
    assert.equal(hueColor(7, 'light'), PALETTE.light[7]);
    assert.equal(hueColor(2, 'anything'), PALETTE.dark[2]);
    for (const index of [-1, 8, 1.5, '1', null, undefined]) assert.equal(hueColor(index, 'dark'), '');
});

// The hues are text: a heading on the card tinted with the hue, and the legend of a keycap whose
// face carries a light tint of it. 4.5:1 is the WCAG minimum for text of this size.
test('every hue reads as text on its tinted card and keycap face in both themes', () => {
    for (const appearance of ['dark', 'light']) {
        const tokens = resolveTheme({ appearance, accent: '#869677', fontFamily: 'Geist', reducedMotion: false });
        const face = appearance === 'dark' ? tokens.surfaceOverlay : tokens.surface;
        // The lightest part of a raised face, its top, where the map puts a key's legend.
        const top = appearance === 'dark' ? tint(tokens.surfaceOverlay, tokens.text, 0.07) : '#FFFFFF';
        for (const hue of PALETTE[appearance]) {
            assert.ok(contrast(hue, tint(tokens.surfaceRaised, hue, 0.06)) >= 4.5, `${appearance} ${hue} on its card`);
            // PentadKeycap tints its face with 14 % of the hue, on the cheatsheet and on the map alike.
            assert.ok(contrast(hue, tint(face, hue, 0.16)) >= 4.5, `${appearance} ${hue} on a keycap`);
            assert.ok(contrast(hue, tint(top, hue, 0.14)) >= 4.5, `${appearance} ${hue} on a keycap's top`);
        }
    }
});

// The keyboard map's bound keys: a stronger tint of the face and a legend lifted toward the text
// colour (CheatsheetKeyboard.qml), against the lightest part of a raised face, where the legend sits.
test('every hue reads as a legend on the keyboard map\'s tinted keys in both themes', () => {
    assert.ok(MAP_FACE_TINT > 0.14 && MAP_FACE_TINT < 0.5);
    assert.ok(MAP_INK_LIFT > 0 && MAP_INK_LIFT < 0.5);
    for (const appearance of ['dark', 'light']) {
        const tokens = resolveTheme({ appearance, accent: '#869677', fontFamily: 'Geist', reducedMotion: false });
        const top = appearance === 'dark' ? tint(tokens.surfaceOverlay, tokens.text, 0.07) : '#FFFFFF';
        for (const hue of PALETTE[appearance]) {
            const ink = tint(hue, tokens.text, MAP_INK_LIFT);
            assert.ok(contrast(ink, tint(top, hue, MAP_FACE_TINT)) >= 4.5, `${appearance} ${hue} on the map`);
        }
    }
});

test('the dispatcher groups and submaps keep fixed hues; neighbours differ', () => {
    const groups = parseBinds(SAMPLE_BINDS).groups;
    const hues = groupHues(groups);
    assert.deepEqual(Object.keys(hues), groups.map(group => group.id));
    assert.equal(hues.workspaces, 3);
    assert.equal(hues.windows, 1);
    assert.equal(hues.launch, 2);
    assert.equal(hues.other, 7);
    assert.equal(hues['submap:resize'], 6);
    const order = groups.map(group => hues[group.id]);
    for (let index = 1; index < order.length; index++) assert.notEqual(order[index], order[index - 1], groups[index].id);
    // The groups named in descriptions take the free hues first; the fourth shares one of theirs
    // rather than the hue of a dispatcher group or the submaps.
    const described = groups.filter(group => group.kind === 'described').map(group => hues[group.id]);
    assert.equal(described.length, 4);
    assert.deepEqual(described.slice(0, 3).sort(), [0, 4, 5]);
    assert.ok([0, 4, 5].indexOf(described[3]) >= 0, String(described));
    // The same list always gives the same hues; a filtered copy of a group keeps its id and hue.
    assert.deepEqual(groupHues(parseBinds(SAMPLE_BINDS).groups), hues);
});

test('every reference sheet gets distinct hues while the palette lasts', () => {
    for (const id of sheetIds()) {
        const groups = groupsFor(id, en);
        const hues = Object.values(groupHues(groups));
        assert.equal(hues.length, groups.length, id);
        assert.equal(new Set(hues).size, Math.min(groups.length, HUE_COUNT), id);
    }
});

test('more groups than hues share them, but never with a neighbour', () => {
    const groups = Array.from({ length: 20 }, (unused, index) => ({ id: 'group:g' + index, kind: 'described', binds: [] }));
    const hues = groupHues(groups);
    const order = groups.map(group => hues[group.id]);
    assert.equal(new Set(order.slice(0, HUE_COUNT)).size, HUE_COUNT);
    for (let index = 1; index < order.length; index++) assert.notEqual(order[index], order[index - 1]);
    assert.ok(order.every(index => Number.isInteger(index) && index >= 0 && index < HUE_COUNT));
});

test('a group\'s preferred hue depends only on its id', () => {
    assert.equal(preferredIndex('group:apps'), preferredIndex('GROUP:Apps'));
    assert.ok(Number.isInteger(preferredIndex('')) && preferredIndex('') < HUE_COUNT);
    assert.equal(groupHues([{ id: 'group:apps', kind: 'described' }])['group:apps'], preferredIndex('group:apps'));
});

test('hue colours resolve per appearance and malformed groups are skipped', () => {
    const groups = parseBinds(SAMPLE_BINDS).groups;
    const dark = hueColors(groups, 'dark');
    const light = hueColors(groups, 'light');
    assert.equal(dark.windows, PALETTE.dark[1]);
    assert.equal(light.windows, PALETTE.light[1]);
    assert.notEqual(dark['group:pentad'], dark.windows);
    for (const value of [null, undefined, 'x', 3, {}, [null, 1, 'x', {}, { id: '' }]]) assert.deepEqual(groupHues(value), {});
});

test('a key takes the hue of the one group its binds share', () => {
    assert.equal(sharedGroup([{ groupId: 'windows' }, { groupId: 'windows' }]), 'windows');
    assert.equal(sharedGroup([{ groupId: 'windows' }, { groupId: 'launch' }]), '');
    assert.equal(sharedGroup([]), '');
    assert.equal(sharedGroup([{ groupId: '' }]), '');
    assert.equal(sharedGroup(null), '');
    assert.equal(sharedGroup([null]), '');
    // On the sample's Super layer, P is pinned and also runs a colour picker: two groups.
    const groups = parseBinds(SAMPLE_BINDS).groups;
    const superLayer = layer(groups, ['Super']);
    assert.equal(sharedGroup(superLayer.keys.q), 'windows');
    assert.equal(sharedGroup(superLayer.keys.p), '');
    assert.equal(sharedGroup(superLayer.keys.v), 'group:pentad');
});

test('the legend lists the groups with a bind on a key of the layer, in sheet order', () => {
    // The map gets the sheet after "Show all": the Lua binds without a description are not on it.
    const groups = filterBinds(parseBinds(SAMPLE_BINDS).groups, '');
    assert.deepEqual(legendGroups(groups, layer(groups, ['Super']).keys).map(entry => entry.id),
        ['group:pentad', 'group:screenshot', 'group:shell', 'workspaces', 'windows', 'launch']);
    assert.deepEqual(legendGroups(groups, layer(groups, ['Alt']).keys).map(entry => entry.id), ['group:pentad']);
    assert.deepEqual(legendGroups(groups, layer(groups, ['Ctrl']).keys), []);
    assert.equal(legendGroups(groups, layer(groups, ['Super']).keys)[0].group, groups[0]);
    for (const value of [null, undefined, 'x', 3]) {
        assert.deepEqual(legendGroups(value, layer(groups, ['Super']).keys), []);
        assert.deepEqual(legendGroups(groups, value), []);
    }
});
