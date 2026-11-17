import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
    KEYS, LAYOUT, UNITS, bindId, comboLabel, detailLines, firstKey, keyById, keyId, layer, layers, neighbor,
    normalizeMods, sameMods, splitBind, usable,
} from '../../quickshell/logic/keyboard-map.mjs';
import { filterBinds, parseBinds } from '../../quickshell/logic/keybinds.mjs';
import { groupsFor } from '../../quickshell/logic/cheatsheets.mjs';
import { SAMPLE_BINDS } from '../../quickshell/logic/keybinds-sample.mjs';

const uk = (ukText, enText) => ukText;

function entry(keys, description, extra) {
    return Object.assign({ keys, description, described: true, lua: false, submap: '' }, extra || {});
}
function groups() {
    return [
        { id: 'group:apps', kind: 'described', label: 'Apps', name: 'Apps', binds: [
            entry(['Super', 'Enter'], 'Terminal'),
            entry(['Super', 'Q'], 'Close window'),
            entry(['Super', 'Shift', 'Q'], 'Quit Hyprland'),
            entry(['Super', 'Q'], 'Second bind on Q'),
            entry(['Super', 'LMB'], 'Move window'),
            entry(['Super', 'Scroll ↓'], 'Next workspace'),
            entry(['Super'], 'Launcher on release'),
            entry(['Alt', 'Tab'], 'Next window'),
            entry(['Vol +'], 'Louder'),
            entry(['Print'], 'Screenshot'),
        ] },
        { id: 'windows', kind: 'builtin', label: 'Windows', name: '', binds: [
            entry(['Shift', 'Super', 'Q'], 'Same layer in another order'),
            entry(['Super', '←'], 'movefocus l', { described: false }),
            entry(['Super', 'F'], '', { described: false, lua: true }),
        ] },
        { id: 'submap:resize', kind: 'submap', label: 'Submap: resize', name: 'resize', binds: [
            entry(['←'], 'resizeactive -10 0', { submap: 'resize' }),
            entry(['Esc'], 'submap reset', { submap: 'resize' }),
        ] },
    ];
}

test('every row of the layout is as wide as UNITS and every key id is unique', () => {
    assert.equal(LAYOUT.length, 6);
    assert.equal(UNITS, 16);
    for (const [index, row] of LAYOUT.entries()) {
        const width = row.reduce((sum, item) => sum + item.w, 0);
        assert.ok(Math.abs(width - UNITS) < 1e-9, `row ${index} is ${width} units`);
        for (const item of row) {
            assert.equal(typeof item.label, 'string');
            assert.ok(item.w > 0);
        }
    }
    const ids = KEYS.map(item => item.id);
    assert.equal(new Set(ids).size, ids.length);
    assert.ok(ids.every(id => id !== ''));
    assert.equal(KEYS.length, LAYOUT.reduce((sum, row) => sum + row.filter(item => item.id).length, 0));
});

test('the layout has the 75 % rows with modifiers marked', () => {
    const labels = row => LAYOUT[row].filter(item => item.id).map(item => item.label);
    assert.deepEqual(labels(0), ['Esc', 'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12',
        'Print', 'Delete']);
    assert.deepEqual(labels(1), ['`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 'Backspace', 'Home']);
    assert.equal(labels(2)[0], 'Tab');
    assert.equal(labels(2).at(-1), 'PgUp');
    assert.deepEqual(labels(3).slice(-2), ['Enter', 'PgDn']);
    assert.deepEqual(labels(4).slice(-3), ['Shift', '↑', 'End']);
    assert.deepEqual(labels(5), ['Ctrl', 'Super', 'Alt', 'Space', 'Alt', 'Ctrl', '←', '↓', '→']);
    const mods = KEYS.filter(item => item.mod).map(item => item.id + ':' + item.mod);
    assert.deepEqual(mods, ['caps:Caps', 'shift:Shift', 'shift-r:Shift', 'ctrl:Ctrl', 'super:Super', 'alt:Alt',
        'alt-r:Alt', 'ctrl-r:Ctrl']);
    // The arrow cluster lines up: ↓ sits under ↑.
    assert.equal(keyById('up').x, keyById('down').x);
    assert.equal(keyById('home').x, 15);
    assert.equal(keyById('end').x, 15);
});

test('keycap labels map to layout keys, case-insensitive for letters', () => {
    const cases = {
        Q: 'q', q: 'q', A: 'a', z: 'z', 1: '1', 0: '0', '/': 'slash', '\\': 'backslash', ',': 'comma', '.': 'period',
        '-': 'minus', '=': 'equal', ';': 'semicolon', '\'': 'apostrophe', '`': 'grave', '[': 'bracketleft',
        ']': 'bracketright', Enter: 'enter', Space: 'space', Esc: 'esc', Tab: 'tab', Backspace: 'backspace',
        Delete: 'delete', Home: 'home', End: 'end', PgUp: 'pgup', PgDn: 'pgdn', '←': 'left', '→': 'right',
        '↑': 'up', '↓': 'down', Print: 'print', F1: 'f1', f12: 'f12', Super: 'super', Ctrl: 'ctrl', Alt: 'alt',
        Shift: 'shift', Caps: 'caps',
    };
    for (const [label, id] of Object.entries(cases)) assert.equal(keyId(label), id, label);
    // Raw Hyprland names and keycodes resolve through keyLabel; a few common spellings too.
    assert.equal(keyId('slash'), 'slash');
    assert.equal(keyId('code:49'), 'grave');
    assert.equal(keyId('Page_Up'), 'pgup');
    assert.equal(keyId('Return'), 'enter');
    assert.equal(keyId('PageDown'), 'pgdn');
    assert.equal(keyId(' Q '), 'q');
    assert.equal(keyId(5), '5');
});

test('labels that are not one key on the layout have no place', () => {
    for (const label of ['LMB', 'RMB', 'MMB', 'Mouse 4', 'Scroll ↓', 'Scroll ↑', 'Vol +', 'Vol −', 'Mute', 'Play',
        'Bright +', 'Key 123', 'code:200', 'Insert', 'Pause', 'Mod2', 'h / j / k / l', '1…9', '↓ / ↑', 'status',
        'PageUp / PageDown', 'Ctrl+w', 'dd', ':wq', '+', 'F13', '', '   '])
        assert.equal(keyId(label), '', label);
    for (const value of [null, undefined, {}, [], true, NaN, Symbol.iterator, () => 'Q'])
        assert.equal(keyId(value), '', String(typeof value));
    assert.equal(keyId('x'.repeat(10000)), '');
});

test('the right-hand modifiers file their binds under the left key', () => {
    assert.equal(bindId('alt-r'), 'alt');
    assert.equal(bindId('ctrl-r'), 'ctrl');
    assert.equal(bindId('shift-r'), 'shift');
    assert.equal(bindId('q'), 'q');
    assert.equal(bindId('nope'), '');
    assert.equal(bindId(undefined), '');
    assert.equal(keyById('nope'), null);
});

test('modifier lists compare as sets in display order', () => {
    assert.deepEqual(normalizeMods(['Shift', 'super', 'Super', 'Foo', 7, null]), ['Super', 'Shift']);
    assert.deepEqual(normalizeMods(['Control', 'MOD5', 'Caps']), ['Ctrl', 'Caps', 'Mod5']);
    assert.deepEqual(normalizeMods(null), []);
    assert.ok(sameMods(['Super', 'Shift'], ['Shift', 'Super']));
    assert.ok(sameMods([], undefined));
    assert.ok(!sameMods(['Super'], ['Super', 'Shift']));
    assert.ok(!sameMods(['Super'], []));
});

test('a bind splits into its layer and its key', () => {
    assert.deepEqual(splitBind(['Super', 'Shift', 'Q']), { mods: ['Super', 'Shift'], key: 'Q' });
    assert.deepEqual(splitBind(['Q']), { mods: [], key: 'Q' });
    assert.deepEqual(splitBind(['Super']), { mods: [], key: 'Super' });
    assert.deepEqual(splitBind(['Super', 'Alt']), { mods: ['Super'], key: 'Alt' });
    assert.deepEqual(splitBind(['Super', 'Super']), { mods: [], key: 'Super' });
    assert.deepEqual(splitBind(['Ctrl+w', 'w']), { mods: [], key: '' });
    assert.deepEqual(splitBind(['Ctrl', 'K', 'Ctrl', 'S']), { mods: ['Ctrl'], key: '' });
    assert.deepEqual(splitBind([null]), { mods: [], key: '' });
    assert.equal(splitBind([]), null);
    assert.equal(splitBind('Super+Q'), null);
});

test('a layer holds exactly the binds with its modifiers, outside submaps, in config order', () => {
    const superLayer = layer(groups(), ['Super']);
    assert.deepEqual(Object.keys(superLayer.keys).sort(), ['enter', 'f', 'left', 'q']);
    assert.deepEqual(superLayer.keys.q.map(item => item.description), ['Close window', 'Second bind on Q']);
    assert.deepEqual(superLayer.keys.q[0], { description: 'Close window', group: 'Apps', groupId: 'group:apps',
        described: true, lua: false, label: 'Q' });
    assert.deepEqual(superLayer.keys.left[0], { description: 'movefocus l', group: 'Windows', groupId: 'windows',
        described: false, lua: false, label: '←' });
    assert.equal(superLayer.keys.f[0].lua, true);
    assert.equal(superLayer.bound, 5);
    // LMB and Scroll ↓ are Super binds with no key on the layout.
    assert.equal(superLayer.unplaced, 2);

    const superShift = layer(groups(), ['Shift', 'Super']);
    assert.deepEqual(Object.keys(superShift.keys), ['q']);
    assert.deepEqual(superShift.keys.q.map(item => item.description), ['Quit Hyprland', 'Same layer in another order']);
    assert.equal(superShift.bound, 2);
    assert.equal(superShift.unplaced, 0);

    // The submap's ← and Esc stay out of the plain layer; Vol + is a plain bind with no key.
    const plain = layer(groups(), []);
    assert.deepEqual(Object.keys(plain.keys).sort(), ['print', 'super']);
    assert.equal(plain.keys.super[0].description, 'Launcher on release');
    assert.equal(plain.bound, 2);
    assert.equal(plain.unplaced, 1);

    assert.deepEqual(layer(groups(), ['Ctrl']), { keys: {}, bound: 0, unplaced: 0 });
    assert.equal(layer(groups(), ['Alt']).keys.tab[0].description, 'Next window');
});

test('group headings follow the translation function', () => {
    assert.equal(layer(groups(), ['Super'], uk).keys.left[0].group, 'Вікна');
    assert.equal(layer(groups(), ['Super'], uk).keys.q[0].group, 'Apps');
});

test('layers lists the modifier sets by use', () => {
    assert.deepEqual(layers(groups()), [
        { mods: ['Super'], count: 7 },
        { mods: [], count: 3 },
        { mods: ['Super', 'Shift'], count: 2 },
        { mods: ['Alt'], count: 1 },
    ]);
    // A tie goes to fewer modifiers, then to the set the config uses first.
    const tie = [{ id: 'x', binds: [entry(['Super', 'Shift', 'A'], 'a'), entry(['Alt', 'B'], 'b'), entry(['Ctrl', 'C'], 'c')] }];
    assert.deepEqual(layers(tie).map(item => item.mods.join('+')), ['Alt', 'Ctrl', 'Super+Shift']);
    assert.deepEqual(layers([]), []);
});

test('hostile input does not throw', () => {
    const hostile = [
        null, 7, 'text', [], { id: 'a' }, { id: 'b', binds: 'nope' },
        { id: 'c', binds: [null, 3, {}, { keys: 'Super+Q' }, { keys: [] }, { keys: [null, undefined] },
            { keys: [{}, 'Q'] }, { keys: ['Super', 42] }, { keys: ['Super', 'Q'], description: { toString: null } },
            { keys: ['Super', 'W'], submap: 12 }] },
    ];
    const empty = { keys: {}, bound: 0, unplaced: 0 };
    for (const value of [null, undefined, 'x', 42, {}, [null]]) {
        assert.deepEqual(layer(value, ['Super']), empty);
        assert.deepEqual(layers(value), []);
    }
    const plain = layer(hostile, []);
    assert.equal(plain.bound, 0);
    // [null, undefined] and [{}, 'Q'] are plain binds without a placeable key.
    assert.equal(plain.unplaced, 2);
    const superLayer = layer(hostile, ['Super'], 'not a function');
    assert.deepEqual(Object.keys(superLayer.keys).sort(), ['q']);
    assert.equal(superLayer.keys.q[0].description, '');
    assert.equal(superLayer.unplaced, 1);
    assert.equal(layer(hostile, 'Super').bound, 0);
});

test('a layer from parsed Hyprland output places the fixture binds', () => {
    const parsed = parseBinds(readFileSync(new URL('../fixtures/hyprland-binds.json', import.meta.url), 'utf8'));
    const all = layers(parsed.groups);
    assert.ok(all.length > 0);
    const total = all.reduce((sum, item) => sum + item.count, 0);
    let placed = 0;
    let unplaced = 0;
    for (const item of all) {
        const result = layer(parsed.groups, item.mods);
        assert.equal(result.bound + result.unplaced, item.count, item.mods.join('+'));
        for (const id of Object.keys(result.keys)) assert.ok(keyById(id), id);
        placed += result.bound;
        unplaced += result.unplaced;
    }
    const outsideSubmaps = parsed.groups.filter(item => item.kind !== 'submap')
        .reduce((sum, item) => sum + item.binds.filter(bindItem => !bindItem.submap).length, 0);
    assert.equal(placed + unplaced, total);
    assert.equal(total, outsideSubmaps);
});

test('arrow moves follow the rows and the nearest key above or below', () => {
    assert.equal(neighbor('q', 'right'), 'w');
    assert.equal(neighbor('q', 'left'), 'tab');
    assert.equal(neighbor('tab', 'left'), 'tab');
    assert.equal(neighbor('pgup', 'right'), 'pgup');
    assert.equal(neighbor('esc', 'up'), 'esc');
    assert.equal(neighbor('space', 'down'), 'space');
    assert.equal(neighbor('q', 'up'), '1');
    assert.equal(neighbor('1', 'down'), 'q');
    assert.equal(neighbor('up', 'down'), 'down');
    assert.equal(neighbor('down', 'up'), 'up');
    assert.equal(neighbor('space', 'up'), 'b');
    assert.equal(neighbor('home', 'down'), 'pgup');
    assert.equal(neighbor('end', 'down'), 'right');
    assert.equal(neighbor('backspace', 'up'), 'print');
    assert.equal(neighbor('home', 'up'), 'delete');
    assert.equal(neighbor('q', 'sideways'), 'q');
    assert.equal(neighbor('nope', 'left'), '');
    // Every move lands on a key.
    for (const item of KEYS)
        for (const direction of ['left', 'right', 'up', 'down']) assert.ok(keyById(neighbor(item.id, direction)));
});

test('the module avoids JavaScript the QML engine lacks', () => {
    const source = readFileSync(new URL('../../quickshell/logic/keyboard-map.mjs', import.meta.url), 'utf8');
    const code = source.split('\n').filter(line => !line.trim().startsWith('//')).join('\n');
    assert.doesNotMatch(code, /structuredClone/);
    assert.doesNotMatch(code, /\.\.\./);
    assert.doesNotMatch(code, /\?\?/);
    assert.doesNotMatch(code, /\?\./);
    assert.doesNotMatch(code, /\bcatch\s*\{/);
});

test('the map is offered where most binds land on a key', () => {
    const en = (ukText, enText) => enText;
    assert.equal(usable(groups()), true);
    assert.equal(usable(filterBinds(parseBinds(SAMPLE_BINDS).groups, '')), true);
    for (const id of ['pentad', 'browser', 'terminal', 'kitty']) assert.equal(usable(groupsFor(id, en)), true, id);
    // Typed commands and key sequences have (almost) nothing to place.
    assert.equal(usable(groupsFor('git', en)), false);
    assert.equal(usable(groupsFor('neovim', en)), false);
    // Exactly half placed is enough; less is not. Submap binds do not count either way.
    const half = [{ id: 'h', binds: [entry(['Super', 'Q'], 'q'), entry(['Super', 'LMB'], 'lmb'),
        entry(['Vol +'], 'vol', { submap: 'audio' }), entry(['Mute'], 'mute', { submap: 'audio' })] }];
    assert.equal(usable(half), true);
    half[0].binds.push(entry(['Play'], 'play'));
    assert.equal(usable(half), false);
    // Only submap binds, or nothing at all, leave nothing to show.
    assert.equal(usable([{ id: 's', binds: [entry(['Q'], 'q', { submap: 'resize' })] }]), false);
    for (const value of [[], null, undefined, 'x', 42, {}, [null], [{ id: 'z', binds: 'nope' }]]) assert.equal(usable(value), false);
});

test('the first bound key and the detail lines', () => {
    assert.equal(firstKey(layer(groups(), ['Super']).keys), 'q');
    assert.equal(firstKey(layer(groups(), []).keys), 'print');
    assert.equal(firstKey({ alt: [{}] }), 'alt');
    assert.equal(firstKey({}), 'esc');
    assert.equal(firstKey(null), 'esc');
    assert.deepEqual(detailLines([1, 2, 3], 4), { binds: [1, 2, 3], more: 0 });
    assert.deepEqual(detailLines([1, 2, 3, 4], 4), { binds: [1, 2, 3, 4], more: 0 });
    assert.deepEqual(detailLines([1, 2, 3, 4, 5, 6], 4), { binds: [1, 2, 3], more: 3 });
    assert.deepEqual(detailLines(null, 4), { binds: [], more: 0 });
    assert.deepEqual(detailLines([1, 2], 'x'), { binds: [1, 2], more: 0 });
    assert.deepEqual(detailLines([1, 2, 3], 1), { binds: [1], more: 2 });
    assert.equal(comboLabel(['Shift', 'Super'], 'Q'), 'Super + Shift + Q');
    assert.equal(comboLabel([], 'Q'), 'Q');
    assert.equal(comboLabel(['Alt'], null), 'Alt');
});
