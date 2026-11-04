import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
    MAX_BINDS, MAX_INPUT_LENGTH, columnCount, countBinds, dispatcherGroup, filterBinds, hiddenCount, isHidden, keyLabel,
    keyLabels, labelFor, layoutColumns, parseBinds, reasonText, splitDescription,
} from '../../quickshell/logic/keybinds.mjs';
import { SAMPLE_BINDS } from '../../quickshell/logic/keybinds-sample.mjs';

// 35 entries cut from a real Hyprland 0.56 Lua config (`hyprctl binds -j`), plus invented
// traditional binds (exec, killactive, code:NN, a submap reset).
const FIXTURE = readFileSync(new URL('../fixtures/hyprland-binds.json', import.meta.url), 'utf8');
const uk = (ukText, enText) => ukText;
const en = (ukText, enText) => enText;

function bind(modmask, key, dispatcher, arg, description, extra) {
    return Object.assign({ modmask, key, keycode: 0, dispatcher, arg, description: description || '',
        has_description: !!description, submap: '' }, extra || {});
}
function group(groups, id) { return groups.find(item => item.id === id); }
function rows(item) { return item.binds.map(entry => entry.keys.join(' + ') + ' | ' + entry.description); }

test('modifier masks become names in a fixed order, only for the bits that are set', () => {
    assert.deepEqual(keyLabels(64, 'Q'), ['Super', 'Q']);
    assert.deepEqual(keyLabels(1 | 4 | 8 | 64, 'T'), ['Super', 'Ctrl', 'Alt', 'Shift', 'T']);
    assert.deepEqual(keyLabels(16 | 32 | 128, 'a'), ['Mod2', 'Mod3', 'Mod5', 'A']);
    assert.deepEqual(keyLabels(2, 'x'), ['Caps', 'X']);
    assert.deepEqual(keyLabels(0, 'Print'), ['Print']);
    assert.deepEqual(keyLabels(64, ''), ['Super']);
    // A key that repeats a held modifier shows once.
    assert.deepEqual(keyLabels(64, 'SUPER_L'), ['Super']);
    assert.deepEqual(keyLabels(0, 'Alt_R'), ['Alt']);
    assert.deepEqual(keyLabels(-1, 'A'), ['A']);
    assert.deepEqual(keyLabels(1.5, 'A'), ['A']);
});

test('key names read the way keycaps do', () => {
    const cases = {
        Slash: '/', Comma: ',', Period: '.', Return: 'Enter', space: 'Space', Space: 'Space', Escape: 'Esc', Tab: 'Tab',
        grave: '`', Minus: '-', Equal: '=', BracketLeft: '[', Backslash: '\\', Page_Up: 'PgUp', Page_down: 'PgDn',
        Left: '←', Down: '↓', 'mouse:272': 'LMB', 'mouse:273': 'RMB', 'mouse:274': 'MMB', 'mouse:275': 'Mouse 4',
        'mouse:276': 'Mouse 5', mouse_down: 'Scroll ↓', mouse_up: 'Scroll ↑', 'code:49': '`', 'code:10': '1',
        'code:19': '0', 'code:24': 'Q', 'code:61': '/', 'code:200': 'Key 200', XF86AudioRaiseVolume: 'Vol +',
        XF86AudioLowerVolume: 'Vol −', XF86AudioMute: 'Mute', XF86AudioMicMute: 'Mic mute', XF86AudioPlay: 'Play',
        XF86AudioNext: 'Next', XF86AudioRecord: 'Record', XF86MonBrightnessUp: 'Bright +', XF86MonBrightnessDown: 'Bright −',
        a: 'A', f1: 'F1', F11: 'F11', Delete: 'Delete', XF86Calculator: 'XF86Calculator', Print: 'Print',
    };
    for (const [key, label] of Object.entries(cases)) assert.equal(keyLabel(key, 0), label, key);
    assert.equal(keyLabel('', 49), '`');
    assert.equal(keyLabel('', 0), '');
    assert.equal(keyLabel(undefined, undefined), '');
    assert.equal(keyLabel('x'.repeat(100), 0).length, 32);
});

test('a description splits into its group only at a colon followed by a space', () => {
    assert.deepEqual(splitDescription('Window: Close'), { group: 'Window', text: 'Close' });
    assert.deepEqual(splitDescription('  Utilities : Pick color #RRGGBB >> clipboard '),
        { group: 'Utilities', text: 'Pick color #RRGGBB >> clipboard' });
    assert.deepEqual(splitDescription('Вікно: Закрити'), { group: 'Вікно', text: 'Закрити' });
    assert.deepEqual(splitDescription('Edit user keybinds'), { group: '', text: 'Edit user keybinds' });
    assert.deepEqual(splitDescription('Open https://example.test'), { group: '', text: 'Open https://example.test' });
    assert.deepEqual(splitDescription('Alarm at 12:30'), { group: '', text: 'Alarm at 12:30' });
    assert.deepEqual(splitDescription('Window:'), { group: '', text: 'Window:' });
    assert.deepEqual(splitDescription('Two\nlines'), { group: '', text: 'Two lines' });
    assert.equal(splitDescription('x'.repeat(400)).text.length, 160);
});

test('binds without a group in their description are grouped by dispatcher', () => {
    assert.equal(dispatcherGroup('workspace'), 'workspaces');
    assert.equal(dispatcherGroup('movetoworkspace'), 'workspaces');
    assert.equal(dispatcherGroup('movetoworkspacesilent'), 'workspaces');
    for (const name of ['movefocus', 'movewindow', 'killactive', 'fullscreen', 'togglefloating', 'pin', 'swapwindow', 'resizeactive'])
        assert.equal(dispatcherGroup(name), 'windows', name);
    assert.equal(dispatcherGroup('exec'), 'launch');
    assert.equal(dispatcherGroup('__lua'), 'other');
    assert.equal(dispatcherGroup('global'), 'other');
    assert.equal(dispatcherGroup(undefined), 'other');
});

test('a real Lua config parses into described groups, dispatcher groups and submaps', () => {
    const parsed = parseBinds(FIXTURE);
    assert.equal(parsed.error, '');
    assert.equal(parsed.truncated, false);
    assert.deepEqual(parsed.groups.map(item => item.id), ['group:shell', 'group:utilities', 'group:media', 'group:window',
        'group:workspace', 'group:session', 'group:app', 'group:pentad', 'workspaces', 'windows', 'launch', 'other',
        'submap:passthrough']);
    assert.deepEqual(parsed.groups.map(item => item.kind), ['described', 'described', 'described', 'described', 'described',
        'described', 'described', 'described', 'builtin', 'builtin', 'builtin', 'builtin', 'submap']);
    assert.deepEqual(rows(group(parsed.groups, 'group:shell')), ['Super + A | Toggle left sidebar', 'Super + / | Toggle cheatsheet',
        'Ctrl + Alt + Delete | Toggle session menu']);
    assert.deepEqual(rows(group(parsed.groups, 'group:window')).slice(0, 4), ['Super + LMB | Move', 'Super + RMB | Resize',
        'Super + ← | Focus Left', 'Super + Q | Close']);
    // The same description on another key is another row; one row per key and description.
    assert.deepEqual(rows(group(parsed.groups, 'group:media')), ['Super + Shift + P | Play/pause media',
        'Super + Alt + M | Toggle mic', 'Mic mute | Toggle mic']);
    // SUPER + SUPER_L and SUPER + SUPER_R on release read the same, so they show once.
    assert.deepEqual(rows(group(parsed.groups, 'group:pentad')), ['Super | Search applications', 'Super + V | Clipboard history']);
    // Traditional binds read as dispatcher and argument; the duplicate Super + Q is dropped.
    assert.deepEqual(rows(group(parsed.groups, 'launch')), ['Super + Enter | exec kitty']);
    assert.deepEqual(rows(group(parsed.groups, 'windows')), ['Super + Q | killactive']);
    assert.deepEqual(rows(group(parsed.groups, 'workspaces')), ['Super + Shift + S | movetoworkspacesilent special:scratch',
        'Super + 1 | workspace 1', 'Super + PgDn | workspace e+1', 'Super + Scroll ↓ | workspace e+1']);
    // A description without a group lands with its dispatcher's group, here a Lua bind in Other.
    const other = group(parsed.groups, 'other');
    assert.deepEqual(rows(other), ['Super + Ctrl + Alt + / | Edit user keybinds', 'Super | ', 'Alt | ',
        'Alt + ` | global pentad:application-next']);
    // Lua binds without a description have no readable text and stay hidden by default.
    const hidden = other.binds.filter(isHidden);
    assert.deepEqual(hidden.map(entry => entry.keys.join('+')), ['Super', 'Alt']);
    assert.ok(hidden.every(entry => entry.description === '' && entry.lua && !entry.described));
    assert.deepEqual(rows(group(parsed.groups, 'submap:passthrough')), ['Super + Alt + F1 | ', 'Esc | submap reset']);
    assert.equal(parsed.total, countBinds(parsed.groups));
    assert.equal(hiddenCount(parsed.groups), 3);
});

test('App and Session groups keep their own binds, and Ctrl + Shift + Esc stays with App', () => {
    const parsed = parseBinds(FIXTURE);
    assert.deepEqual(rows(group(parsed.groups, 'group:app')), ['Super + Enter | Terminal', 'Ctrl + Shift + Esc | Task manager']);
    assert.deepEqual(rows(group(parsed.groups, 'group:session')), ['Super + L | Lock']);
});

test('parsed and raw input agree, and malformed input yields an error instead of throwing', () => {
    assert.deepEqual(parseBinds(JSON.parse(FIXTURE)), parseBinds(FIXTURE));
    assert.deepEqual(parseBinds('{not json'), { groups: [], total: 0, truncated: false, error: 'invalid-json' });
    assert.deepEqual(parseBinds('{"binds": []}'), { groups: [], total: 0, truncated: false, error: 'not-a-list' });
    assert.deepEqual(parseBinds(null), { groups: [], total: 0, truncated: false, error: 'not-a-list' });
    assert.deepEqual(parseBinds('[]'), { groups: [], total: 0, truncated: false, error: '' });
    const odd = parseBinds([null, 3, 'x', [], { key: 5, modmask: 'x', dispatcher: { a: 1 }, description: 7 },
        bind(64, 'Q', 'killactive', '')]);
    assert.equal(odd.error, '');
    assert.deepEqual(odd.groups.map(item => rows(item)), [['Super + Q | killactive']]);
});

test('input is bounded: over 1 MiB of text is refused, and only the first binds are read', () => {
    assert.equal(MAX_INPUT_LENGTH, 1024 * 1024);
    const huge = '[' + ' '.repeat(MAX_INPUT_LENGTH) + ']';
    assert.deepEqual(parseBinds(huge), { groups: [], total: 0, truncated: false, error: 'too-large' });
    const many = [];
    for (let index = 0; index < MAX_BINDS + 50; index++) many.push(bind(64, 'code:' + (index + 100), 'exec', 'app-' + index));
    const parsed = parseBinds(many);
    assert.equal(parsed.truncated, true);
    assert.equal(parsed.total, MAX_BINDS);
    const long = parseBinds([bind(64, 'Q', 'exec', 'x'.repeat(5000), 'G'.repeat(90) + ': ' + 'y'.repeat(5000))]);
    const entry = long.groups[0].binds[0];
    assert.ok(entry.description.length <= 160 && entry.arg.length <= 120 && long.groups[0].label.length <= 40);
});

test('the search matches descriptions, key names, dispatchers and group names in either language', () => {
    const groups = parseBinds(FIXTURE).groups;
    const texts = query => filterBinds(groups, query).map(item => item.id + ' ' + rows(item).join(' / '));
    assert.deepEqual(texts('TERMINAL'), ['group:app Super + Enter | Terminal']);
    // Every word must match: "/" alone would also match "Play/pause media".
    assert.deepEqual(texts('super /'), ['group:shell Super + / | Toggle cheatsheet', 'group:media Super + Shift + P | Play/pause media',
        'other Super + Ctrl + Alt + / | Edit user keybinds']);
    assert.deepEqual(texts('ctrl alt /'), ['other Super + Ctrl + Alt + / | Edit user keybinds']);
    assert.deepEqual(texts('super+v'), ['group:pentad Super + V | Clipboard history']);
    // The raw key name matches as well as its keycap.
    assert.deepEqual(texts('slash cheat'), ['group:shell Super + / | Toggle cheatsheet']);
    assert.deepEqual(texts('kitty'), ['launch Super + Enter | exec kitty']);
    assert.deepEqual(texts('killactive'), ['windows Super + Q | killactive']);
    // Built-in group names match in Ukrainian and English: every bind of the group stays.
    assert.deepEqual(texts('запуск'), texts('launch'));
    assert.deepEqual(texts('Вікна').map(text => text.split(' ')[0]), ['windows']);
    assert.deepEqual(texts('режим клавіш').map(text => text.split(' ')[0]), ['submap:passthrough']);
    assert.deepEqual(texts('nothing like this'), []);
    assert.equal(filterBinds(groups, '').length, groups.length);
    assert.equal(filterBinds(groups, '   ').length, groups.length);
    assert.deepEqual(filterBinds(null, 'x'), []);
});

test('hidden Lua binds appear only with showAll, and the query still applies to them', () => {
    const groups = parseBinds(FIXTURE).groups;
    const other = filterBinds(groups, '').find(item => item.id === 'other');
    assert.equal(other.binds.some(isHidden), false);
    const all = filterBinds(groups, '', { showAll: true }).find(item => item.id === 'other');
    assert.equal(all.binds.filter(isHidden).length, 2);
    assert.equal(countBinds(filterBinds(groups, '', { showAll: true })), countBinds(groups));
    assert.deepEqual(filterBinds(groups, 'alt', { showAll: true }).find(item => item.id === 'other').binds
        .map(entry => entry.keys.join('+')), ['Super+Ctrl+Alt+/', 'Alt', 'Alt+`']);
    // Filtering does not change the parsed groups.
    assert.equal(countBinds(groups), parseBinds(FIXTURE).total);
    // A group made only of hidden binds drops out until showAll.
    const onlyLua = parseBinds([bind(0, 'Super_L', '__lua', '1'), bind(0, 'Alt_L', '__lua', '2')]).groups;
    assert.deepEqual(filterBinds(onlyLua, ''), []);
    assert.equal(filterBinds(onlyLua, '', { showAll: true })[0].binds.length, 2);
});

test('group labels come in both languages for Pentad\'s groups and as written for the config\'s', () => {
    const groups = parseBinds(FIXTURE).groups;
    assert.equal(labelFor(group(groups, 'workspaces'), uk), 'Робочі простори');
    assert.equal(labelFor(group(groups, 'workspaces'), en), 'Workspaces');
    assert.equal(labelFor(group(groups, 'windows'), uk), 'Вікна');
    assert.equal(labelFor(group(groups, 'launch'), uk), 'Запуск');
    assert.equal(labelFor(group(groups, 'other'), en), 'Other');
    assert.equal(labelFor(group(groups, 'other'), 'uk'), 'Інше');
    assert.equal(labelFor(group(groups, 'submap:passthrough'), uk), 'Режим клавіш: passthrough');
    assert.equal(labelFor(group(groups, 'submap:passthrough'), en), 'Submap: passthrough');
    assert.equal(labelFor(group(groups, 'group:utilities'), uk), 'Utilities');
    assert.equal(labelFor(null, en), '');
});

test('failure reasons have text in both languages', () => {
    for (const reason of ['missing', 'failed', 'timeout', 'too-large', 'invalid-json', 'not-a-list']) {
        assert.match(reasonText(reason, uk), /[а-яіїєґ]/i, reason);
        assert.notEqual(reasonText(reason, uk), reasonText(reason, en), reason);
    }
    assert.equal(reasonText('', en), '');
    assert.equal(reasonText('other', uk), '');
});

test('columns follow the width and end at about the same height', () => {
    assert.equal(columnCount(900), 3);
    assert.equal(columnCount(860), 3);
    assert.equal(columnCount(700), 2);
    assert.equal(columnCount(560), 2);
    assert.equal(columnCount(400), 1);
    const sized = (id, count) => ({ id, binds: new Array(count).fill({}) });
    const groups = [sized('a', 8), sized('b', 3), sized('c', 3), sized('d', 2), sized('e', 6)];
    const ids = columns => columns.map(column => column.map(item => item.id).join(''));
    assert.deepEqual(ids(layoutColumns(groups, 3)), ['a', 'bd', 'ce']);
    assert.deepEqual(ids(layoutColumns(groups, 2)), ['ae', 'bcd']);
    assert.deepEqual(ids(layoutColumns(groups, 1)), ['abcde']);
    // Fewer groups than columns leave the extra columns out; no groups still give one column.
    assert.deepEqual(ids(layoutColumns(groups.slice(0, 2), 3)), ['a', 'b']);
    assert.deepEqual(layoutColumns([], 3), [[]]);
    assert.deepEqual(ids(layoutColumns(groups, 0)), ['abcde']);
});

test('the preview sample covers every kind of group the cheatsheet draws', () => {
    const parsed = parseBinds(SAMPLE_BINDS);
    assert.equal(parsed.error, '');
    assert.deepEqual(parsed.groups.map(item => item.id), ['group:pentad', 'group:screenshot', 'group:media', 'group:shell',
        'workspaces', 'windows', 'launch', 'other', 'submap:resize']);
    assert.deepEqual(rows(group(parsed.groups, 'group:pentad')).slice(0, 2), ['Super | Search applications', 'Super + Space | Search applications']);
    assert.ok(rows(group(parsed.groups, 'group:pentad')).includes('Alt + ` | Next window of the app'));
    assert.ok(rows(group(parsed.groups, 'windows')).includes('Super + LMB | movewindow'));
    // Super_L's press and release Lua binds read the same and show once.
    assert.deepEqual(group(parsed.groups, 'other').binds.filter(isHidden).map(entry => entry.keys.join('+')),
        ['Super', 'Super+-', 'Super+=']);
    assert.ok(parsed.groups.every(item => item.binds.length > 0));
});
