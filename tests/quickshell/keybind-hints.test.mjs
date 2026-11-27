import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
    MAX_COLUMNS, MAX_ROWS, columnCount, splitColumns, submapHint, submapName,
} from '../../quickshell/logic/keybind-hints.mjs';
import { parseBinds } from '../../quickshell/logic/keybinds.mjs';
import { SAMPLE_BINDS } from '../../quickshell/logic/keybinds-sample.mjs';

// 35 entries cut from a real Hyprland 0.56 Lua config; its `passthrough` submap holds a Lua bind
// without a description and an Escape that resets.
const FIXTURE = readFileSync(new URL('../fixtures/hyprland-binds.json', import.meta.url), 'utf8');
const uk = (ukText, enText) => ukText;
const en = (ukText, enText) => enText;

function bind(modmask, key, dispatcher, arg, description, extra) {
    return Object.assign({ modmask, key, keycode: 0, dispatcher, arg, description: description || '',
        has_description: !!description, submap: '' }, extra || {});
}
function rows(hint) { return hint.rows.map(row => row.keys.join('+') + ' | ' + row.description + (row.described ? '' : ' (muted)')); }

test('the sample resize submap lists its binds in config order', () => {
    const hint = submapHint(parseBinds(SAMPLE_BINDS).groups, 'resize', { text: en });
    assert.equal(hint.title, 'Submap: resize');
    assert.deepEqual(rows(hint), ['→ | resizeactive 20 0 (muted)', '← | resizeactive -20 0 (muted)', 'Esc | submap reset (muted)']);
    assert.equal(hint.total, 3);
    assert.equal(hint.overflow, 0);
    assert.deepEqual(Object.keys(hint.rows[0]).sort(), ['described', 'description', 'keys']);
});

test('the title follows the language and the name as Hyprland reports it', () => {
    const groups = parseBinds(SAMPLE_BINDS).groups;
    assert.equal(submapHint(groups, 'resize', { text: uk }).title, 'Режим клавіш: resize');
    assert.equal(submapHint(groups, 'resize', { text: 'uk' }).title, 'Режим клавіш: resize');
    assert.equal(submapHint(groups, 'resize').title, 'Submap: resize');
    assert.equal(submapHint(groups, 'RESIZE', { text: en }).title, 'Submap: RESIZE');
});

test('the submap is matched case-insensitively and only among submap groups', () => {
    const groups = parseBinds([
        bind(0, 'H', 'movefocus', 'l', '', { submap: 'Move' }),
        bind(64, 'M', 'exec', 'foot', 'Move: Open a terminal'),
    ]).groups;
    assert.deepEqual(rows(submapHint(groups, 'move', { text: en })), ['H | movefocus l (muted)']);
    assert.deepEqual(rows(submapHint(groups, 'MOVE', { text: en })), ['H | movefocus l (muted)']);
    // "Move: …" names a described group, not a submap.
    assert.equal(groups.some(group => group.kind === 'described' && group.name === 'Move'), true);
    assert.deepEqual(submapHint(groups, 'open', { text: en }).rows, []);
});

test('described binds read as their text, others as their dispatcher', () => {
    const groups = parseBinds([
        bind(0, 'L', 'resizeactive', '20 0', 'Grow to the right', { submap: 'resize' }),
        bind(0, 'Escape', 'submap', 'reset', '', { submap: 'resize' }),
    ]).groups;
    const hint = submapHint(groups, 'resize', { text: en });
    assert.deepEqual(rows(hint), ['L | Grow to the right', 'Esc | submap reset (muted)']);
    assert.equal(hint.rows[0].described, true);
});

test('Lua binds without a description are left out unless nothing else exists', () => {
    const mixed = parseBinds(FIXTURE).groups;
    assert.deepEqual(rows(submapHint(mixed, 'passthrough', { text: en })), ['Esc | submap reset (muted)']);
    const luaOnly = parseBinds([
        bind(72, 'F1', '__lua', '277', '', { submap: 'passthrough' }),
        bind(64, 'F2', 'HL.Dispatcher(exec)', '12', 'Leave passthrough', { submap: 'passthrough' }),
        bind(64, 'F3', 'function: 0x55d0', '13', '', { submap: 'passthrough' }),
    ]).groups;
    assert.deepEqual(rows(submapHint(luaOnly, 'passthrough', { text: en })), ['Super+F2 | Leave passthrough']);
    const unreadable = parseBinds([
        bind(72, 'F1', '__lua', '277', '', { submap: 'passthrough' }),
        bind(0, 'Escape', 'function: 0x55d0', '13', '', { submap: 'passthrough' }),
    ]).groups;
    assert.deepEqual(rows(submapHint(unreadable, 'passthrough', { text: en })),
        ['Super+Alt+F1 | Lua function without a description (muted)', 'Esc | Lua function without a description (muted)']);
    assert.equal(submapHint(unreadable, 'passthrough', { text: uk }).rows[0].description, 'Функція Lua без опису');
});

test('at most 12 rows are listed and the rest are counted', () => {
    const list = Array.from({ length: 15 }, (unused, index) =>
        bind(0, 'code:' + (10 + index), 'exec', 'app-' + index, 'Open app ' + index, { submap: 'launch' }));
    const hint = submapHint(parseBinds(list).groups, 'launch', { text: en });
    assert.equal(MAX_ROWS, 12);
    assert.equal(hint.rows.length, 12);
    assert.equal(hint.overflow, 3);
    assert.equal(hint.total, 15);
    assert.equal(hint.rows[0].description, 'Open app 0');
    assert.equal(hint.rows[11].description, 'Open app 11');
    const short = submapHint(parseBinds(list).groups, 'launch', { text: en, limit: 4 });
    assert.equal(short.rows.length, 4);
    assert.equal(short.overflow, 11);
    for (const limit of [0, -1, 2.5, 'x', null])
        assert.equal(submapHint(parseBinds(list).groups, 'launch', { limit }).rows.length, 12, String(limit));
});

test('an unknown submap, no binds yet or a failed read give just the title', () => {
    for (const groups of [[], null, undefined, 'x', [null, { kind: 'submap' }], parseBinds(SAMPLE_BINDS).groups]) {
        const hint = submapHint(groups, 'no-such-mode', { text: en });
        assert.equal(hint.title, 'Submap: no-such-mode');
        assert.deepEqual(hint.rows, []);
        assert.equal(hint.overflow, 0);
        assert.equal(hint.total, 0);
    }
    const broken = [{ kind: 'submap', name: 'resize', binds: [null, { keys: 'Q' }, { keys: ['Q', 3], description: 7 }] }];
    assert.deepEqual(submapHint(broken, 'resize', { text: en }).rows, [{ keys: ['Q'], description: '', described: false }]);
});

test('no submap means no title and no rows', () => {
    const groups = parseBinds(SAMPLE_BINDS).groups;
    for (const name of ['', '   ', 'reset', null, undefined, {}, []])
        assert.deepEqual(submapHint(groups, name, { text: en }), { title: '', rows: [], overflow: 0, total: 0 }, String(name));
});

test('the submap name from the event is plain, clipped text', () => {
    assert.equal(submapName('resize'), 'resize');
    assert.equal(submapName('  move  windows '), 'move windows');
    assert.equal(submapName('a\nb\u0007c'), 'a b c');
    assert.equal(submapName('‮esrever'), 'esrever');
    assert.equal(submapName('<b>bold</b>'), '<b>bold</b>');
    assert.equal(submapName(''), '');
    assert.equal(submapName('reset'), '');
    assert.equal(submapName('Reset'), 'Reset');
    assert.equal(submapName(null), '');
    assert.equal(submapName(42), '42');
    const long = submapName('x'.repeat(200));
    assert.equal(long.length, 40);
    assert.equal(long.endsWith('…'), true);
});

test('a long submap name finds the group parseBinds clipped the same way', () => {
    const name = 'a very long submap name that goes on and on and on';
    const groups = parseBinds([bind(0, 'Escape', 'submap', 'reset', '', { submap: name })]).groups;
    const hint = submapHint(groups, name, { text: en });
    assert.deepEqual(rows(hint), ['Esc | submap reset (muted)']);
    assert.equal(hint.title, 'Submap: ' + submapName(name));
});

test('rows flow into one column up to 4, two up to 8, three above, as the width allows', () => {
    assert.equal(MAX_COLUMNS, 3);
    assert.deepEqual([0, 1, 4, 5, 8, 9, 12, 40].map(count => columnCount(count, 3)), [1, 1, 1, 2, 2, 3, 3, 3]);
    assert.deepEqual([1, 5, 9].map(count => columnCount(count, 2)), [1, 2, 2]);
    assert.deepEqual([1, 5, 9].map(count => columnCount(count, 1)), [1, 1, 1]);
    assert.deepEqual([0, -1, NaN, 'x', undefined].map(fit => columnCount(12, fit)), [1, 1, 1, 1, 1]);
    assert.equal(columnCount(12, 9), 3);
});

test('columns fill top to bottom, in config order', () => {
    const list = Array.from({ length: 12 }, (unused, index) => index);
    assert.deepEqual(splitColumns(list.slice(0, 3), 1), [[0, 1, 2]]);
    assert.deepEqual(splitColumns(list.slice(0, 5), 2), [[0, 1, 2], [3, 4]]);
    assert.deepEqual(splitColumns(list.slice(0, 8), 2), [[0, 1, 2, 3], [4, 5, 6, 7]]);
    assert.deepEqual(splitColumns(list.slice(0, 10), 3), [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9]]);
    assert.deepEqual(splitColumns(list, 3), [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11]]);
    assert.deepEqual(splitColumns(list.slice(0, 2), 3), [[0], [1]]);
    assert.deepEqual(splitColumns([], 3), []);
    assert.deepEqual(splitColumns(null, 2), []);
    // At most three columns, whatever is asked.
    assert.deepEqual(splitColumns(list.slice(0, 4), 9), [[0, 1], [2, 3]]);
});
