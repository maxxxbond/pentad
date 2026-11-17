import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
    MAX_BINDS, MAX_INPUT_LENGTH, MODIFIER_NAMES, columnCount, countBinds, countDuplicates, dispatcherGroup, filterBinds,
    hiddenCount, isHidden, keyLabel, keyLabels, keyShortcuts, labelFor, layoutColumns, modifierCounts, parseBinds, reasonText,
    splitDescription, splitKeys,
} from '../../quickshell/logic/keybinds.mjs';
import { SAMPLE_BINDS } from '../../quickshell/logic/keybinds-sample.mjs';
import { groupsFor, sheetIds } from '../../quickshell/logic/cheatsheets.mjs';

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

test('Lua binds reported as HL.Dispatcher(...) or function: 0x... are hidden like __lua ones', () => {
    const groups = parseBinds([
        bind(64, 'A', 'HL.Dispatcher(global)', '46'),
        bind(64, 'B', 'function: 0x56323a0d2fe0', '49'),
        bind(64, 'C', 'HL.Dispatcher(global)', '50', 'Pentad: Open'),
    ]).groups;
    assert.equal(countBinds(filterBinds(groups, '')), 1);
    assert.equal(countBinds(filterBinds(groups, '', { showAll: true })), 3);
    assert.deepEqual(filterBinds(groups, '').map(item => item.id), ['group:pentad']);
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
    // One duplicate pair, Super+P, both rows visible without "Show all"; the press and release
    // binds around Super are not duplicates.
    assert.deepEqual(filterBinds(parsed.groups, '', { duplicates: true }).flatMap(item => rows(item)),
        ['Super + P | pin', 'Super + P | exec hyprpicker -a']);
    assert.equal(countDuplicates(parsed.groups), 2);
});

test('modifier names are listed in display order', () => {
    assert.deepEqual(MODIFIER_NAMES, ['Super', 'Ctrl', 'Alt', 'Shift', 'Caps', 'Mod2', 'Mod3', 'Mod5']);
});

test('keycap labels split into modifiers and a key', () => {
    assert.deepEqual(splitKeys(['Super', 'Shift', 'Q']), { mods: ['Super', 'Shift'], key: 'Q' });
    assert.deepEqual(splitKeys(['Q']), { mods: [], key: 'Q' });
    assert.deepEqual(splitKeys(['Super']), { mods: ['Super'], key: '' });
    assert.deepEqual(splitKeys(['Alt', 'Shift']), { mods: ['Alt', 'Shift'], key: '' });
    assert.deepEqual(splitKeys([]), { mods: [], key: '' });
    // Out-of-order modifiers read in display order; later labels join the key with one space.
    assert.deepEqual(splitKeys(['Shift', 'Super', 'P', 'F']), { mods: ['Super', 'Shift'], key: 'P F' });
    // A modifier after the key belongs to the key.
    assert.deepEqual(splitKeys(['Ctrl', 'K', 'Alt']), { mods: ['Ctrl'], key: 'K Alt' });
    for (const garbage of [null, undefined, 5, 'Super', {}, { length: 2 }, true])
        assert.deepEqual(splitKeys(garbage), { mods: [], key: '' });
    assert.deepEqual(splitKeys([null, 'Super']), { mods: ['Super'], key: '' });
    assert.deepEqual(splitKeys(['Super', 3, 'A']), { mods: ['Super'], key: 'A' });
});

test('parsed binds carry mods, key and a duplicate flag', () => {
    const groups = parseBinds([
        bind(64 | 1, 'Q', 'killactive', ''),
        bind(64, '', '__lua', '1', 'Shell: Search'),
        bind(0, 'Print', 'exec', 'shot'),
    ]).groups;
    const all = groups.flatMap(item => item.binds);
    const byKeys = keys => all.find(entry => entry.keys.join('+') === keys);
    assert.deepEqual([byKeys('Super+Shift+Q').mods, byKeys('Super+Shift+Q').key], [['Super', 'Shift'], 'Q']);
    assert.deepEqual([byKeys('Super').mods, byKeys('Super').key], [['Super'], '']);
    assert.deepEqual([byKeys('Print').mods, byKeys('Print').key], [[], 'Print']);
    assert.ok(all.every(entry => entry.duplicate === false));
    const fixture = parseBinds(FIXTURE).groups.flatMap(item => item.binds);
    assert.ok(fixture.every(entry => Array.isArray(entry.mods) && typeof entry.key === 'string' && typeof entry.duplicate === 'boolean'));
});

test('the same keys with another text in one submap are duplicates; other submaps and identical text are not', () => {
    const parsed = parseBinds([
        bind(64, 'Q', 'killactive', '', 'Window: Close'),
        bind(64, 'Q', 'exec', 'quit-app'),
        bind(64, 'W', 'exec', 'one'),
        bind(64, 'W', 'exec', 'one'),
        bind(64, 'E', 'exec', 'edit'),
        bind(64, 'E', 'exec', 'edit', '', { submap: 'resize' }),
        bind(64, 'R', 'exec', 'a', '', { submap: 'resize' }),
        bind(64, 'R', 'exec', 'b', '', { submap: 'resize' }),
        bind(64, 'T', 'exec', 'only'),
        bind(0, '', 'exec', 'no keys one'),
        bind(0, '', 'exec', 'no keys two'),
    ]);
    const flagged = parsed.groups.flatMap(item => item.binds).filter(entry => entry.duplicate)
        .map(entry => entry.submap + '/' + entry.keys.join('+') + '/' + entry.description);
    assert.deepEqual(flagged.sort(), ['/Super+Q/Close', '/Super+Q/exec quit-app', 'resize/Super+R/exec a',
        'resize/Super+R/exec b']);
    assert.equal(countDuplicates(parsed.groups), 4);
    // Identical keys and text collapse into one row, which is not a duplicate of itself.
    const w = parsed.groups.flatMap(item => item.binds).filter(entry => entry.keys.join('+') === 'Super+W');
    assert.equal(w.length, 1);
    assert.equal(w[0].duplicate, false);
    // A bind with no keys is never a duplicate.
    assert.ok(parsed.groups.flatMap(item => item.binds).filter(entry => !entry.keys.length).every(entry => !entry.duplicate));
});

test('duplicates need the same trigger: exact modifiers, the same key and press or release', () => {
    // Pentad's own defaults: Super_L press and release track the modifier, SUPER + SUPER_L on
    // release opens search. All read "Super", none is a conflict.
    const defaults = parseBinds([
        bind(0, 'Super_L', 'global', 'pentad:super-left'),
        bind(0, 'Super_L', 'global', 'pentad:super-left', '', { release: true }),
        bind(0, 'Super_R', 'global', 'pentad:super-right'),
        bind(64, 'SUPER_L', 'global', 'pentad:search-release', 'Pentad: Search applications', { release: true }),
        bind(64, 'SUPER_R', 'global', 'pentad:search-release', 'Pentad: Search applications', { release: true }),
    ]);
    assert.equal(countDuplicates(defaults.groups), 0);
    // A press and a release bind on the same keys are a pair, not a conflict.
    assert.equal(countDuplicates(parseBinds([bind(64, 'A', 'exec', 'down'), bind(64, 'A', 'exec', 'up', '', { release: true })]).groups), 0);
    // The same trigger written two ways (case, a keycode) is still one trigger.
    const spelled = parseBinds([bind(64, 'p', 'pin', ''), bind(64, 'P', 'exec', 'picker'),
        bind(8, '', 'exec', 'one', '', { keycode: 49 }), bind(8, '', 'exec', 'two', '', { keycode: 49 })]);
    assert.equal(countDuplicates(spelled.groups), 4);
    // Two release binds with different texts on one trigger are duplicates; a row merged from a
    // press and a release bind takes part with both of its triggers.
    const merged = parseBinds([
        bind(64, 'B', 'exec', 'browser'),
        bind(64, 'B', 'exec', 'browser', '', { release: true }),
        bind(64, 'B', 'exec', 'other', '', { release: true }),
    ]);
    const flagged = merged.groups.flatMap(item => item.binds).map(entry => entry.description + ':' + entry.duplicate);
    assert.deepEqual(flagged, ['exec browser:true', 'exec other:true']);
});

test('a Lua bind without a description still takes its keys for duplicate detection', () => {
    const parsed = parseBinds([bind(64, 'A', '__lua', '1'), bind(64, 'A', '__lua', '2', 'Shell: Sidebar')]);
    assert.equal(countDuplicates(parsed.groups), 2);
    assert.equal(countDuplicates(null), 0);
});

test('mods, key and duplicates narrow the list alone and together', () => {
    const groups = parseBinds([
        bind(64, 'Q', 'killactive', '', 'Window: Close'),
        bind(64 | 1, 'Q', 'exec', 'quit-app'),
        bind(64 | 4, 'Q', 'exec', 'ctrl-q'),
        bind(64, 'W', 'exec', 'one'),
        bind(64, 'W', 'exec', 'two'),
        bind(1, 'a', 'exec', 'shift-a'),
        bind(0, 'Print', 'exec', 'shot'),
        bind(64, '', '__lua', '1'),
    ]).groups;
    const keys = options => filterBinds(groups, options.query || '', options).flatMap(item => item.binds)
        .map(entry => entry.keys.join('+'));
    assert.deepEqual(keys({ mods: ['Super'] }), ['Super+Q', 'Super+Shift+Q', 'Super+Ctrl+Q', 'Super+W', 'Super+W']);
    assert.deepEqual(keys({ mods: ['Super', 'Shift'] }), ['Super+Shift+Q']);
    assert.deepEqual(keys({ mods: ['Shift', 'Super'] }), ['Super+Shift+Q']);
    assert.equal(keys({ mods: [] }).length, 7);
    assert.equal(keys({ mods: undefined, key: '' }).length, 7);
    assert.deepEqual(keys({ key: 'q' }), ['Super+Q', 'Super+Shift+Q', 'Super+Ctrl+Q']);
    assert.deepEqual(keys({ key: 'PRINT' }), ['Print']);
    assert.deepEqual(keys({ key: 'Super' }), []);
    assert.deepEqual(keys({ mods: ['Ctrl'], key: 'Q' }), ['Super+Ctrl+Q']);
    assert.deepEqual(keys({ duplicates: true }), ['Super+W', 'Super+W']);
    assert.deepEqual(keys({ duplicates: false }).length, 7);
    assert.deepEqual(keys({ duplicates: true, mods: ['Shift'] }), []);
    assert.deepEqual(keys({ duplicates: true, key: 'w', query: 'two' }), ['Super+W']);
    assert.deepEqual(keys({ mods: ['Super'], query: 'quit' }), ['Super+Shift+Q']);
    assert.deepEqual(keys({ key: 'q', query: 'ctrl' }), ['Super+Ctrl+Q']);
    assert.deepEqual(keys({ mods: ['Shift'], query: 'nothing-like-this' }), []);
    // The bare-modifier Lua bind is hidden until showAll, and the new options respect that.
    assert.deepEqual(keys({ mods: ['Super'], showAll: true }).filter(entry => entry === 'Super'), ['Super']);
    assert.equal(keys({ mods: ['Super'] }).includes('Super'), false);
});

test('filtering by modifier works on binds that lack the mods and key fields', () => {
    const groups = [{ id: 'g', search: 'g', binds: [
        { keys: ['Ctrl', 'Shift', 'T'], description: 'New tab', described: true, lua: false, search: 'new tab' },
        { keys: ['Ctrl', 'T'], description: 'Transpose', described: true, lua: false, search: 'transpose' },
    ] }];
    assert.deepEqual(filterBinds(groups, '', { mods: ['Shift'] })[0].binds.map(entry => entry.description), ['New tab']);
    assert.deepEqual(filterBinds(groups, '', { mods: ['Ctrl'], key: 't' })[0].binds.length, 2);
    assert.deepEqual(filterBinds(groups, '', { duplicates: true }), []);
    assert.equal(countDuplicates(groups), 0);
});

test('modifier counts list only the modifiers a visible bind uses, in display order', () => {
    const groups = parseBinds([
        bind(64, 'Q', 'killactive', ''),
        bind(64 | 1, 'W', 'exec', 'w'),
        bind(8, 'E', 'exec', 'e'),
        bind(0, 'Print', 'exec', 'shot'),
        bind(2, '', '__lua', '1'),
    ]).groups;
    assert.deepEqual(modifierCounts(groups), [{ name: 'Super', count: 2 }, { name: 'Alt', count: 1 }, { name: 'Shift', count: 1 }]);
    assert.deepEqual(modifierCounts(groups, { showAll: true }), [{ name: 'Super', count: 2 }, { name: 'Alt', count: 1 },
        { name: 'Shift', count: 1 }, { name: 'Caps', count: 1 }]);
    assert.deepEqual(modifierCounts([]), []);
    assert.deepEqual(modifierCounts(null), []);
    // A bare-modifier bind counts its modifier.
    assert.deepEqual(modifierCounts(parseBinds([bind(0, 'Super_L', 'exec', 'x')]).groups), [{ name: 'Super', count: 1 }]);
});

test('two actions on one trigger are a duplicate even with the same description', () => {
    const entry = (dispatcher, arg, extra) => Object.assign({ modmask: 64, key: 'P', keycode: 0, submap: '', dispatcher, arg,
        description: 'Pin', has_description: true }, extra || {});
    const same = parseBinds([entry('pin', ''), entry('exec', 'hyprpicker')]);
    assert.equal(same.total, 1);
    assert.equal(countDuplicates(same.groups), 1);
    // The very same line twice is one action, and a press and release pair is two triggers.
    assert.equal(countDuplicates(parseBinds([entry('pin', ''), entry('pin', '')]).groups), 0);
    assert.equal(countDuplicates(parseBinds([entry('pin', ''), entry('exec', 'x', { release: true })]).groups), 0);
});

test('the duplicates filter shows a hidden Lua partner without "Show all"', () => {
    const parsed = parseBinds([
        { modmask: 64, key: 'X', keycode: 0, submap: '', dispatcher: 'exec', arg: 'foot', description: 'Do X', has_description: true },
        { modmask: 64, key: 'X', keycode: 0, submap: '', dispatcher: '__lua', arg: '12', description: '', has_description: false },
    ]);
    assert.equal(countBinds(filterBinds(parsed.groups, '', {})), 1);
    assert.equal(countBinds(filterBinds(parsed.groups, '', { duplicates: true })), 2);
});

const tiles = list => list.map(tile => tile.keys.join('+') + ' | ' + tile.description);

test('key shortcuts on the live bindings come from the Pentad group, one per description', () => {
    const shortcuts = keyShortcuts(parseBinds(SAMPLE_BINDS).groups);
    // Super alone and Super+Space both search applications: the second is skipped.
    assert.deepEqual(tiles(shortcuts), ['Super | Search applications', 'Super+Tab | Workspace overview',
        'Super+V | Clipboard history', 'Super+. | Emoji']);
    assert.ok(shortcuts.every(tile => tile.groupId === 'group:pentad'));
    // The group's name may be written in any case.
    const lower = parseBinds([bind(64, 'A', 'exec', 'a', 'pentad: One'), bind(64, 'B', 'exec', 'b', 'Apps: Two'),
        bind(64, 'C', 'exec', 'c', 'pentad: Three')]).groups;
    assert.deepEqual(tiles(keyShortcuts(lower)), ['Super+A | One', 'Super+C | Three']);
});

test('without a Pentad group, key shortcuts are the first described binds outside submaps', () => {
    const groups = parseBinds([
        bind(64, 'Return', 'exec', 'foot'),
        bind(64, 'Q', 'killactive', '', 'Close window'),
        bind(0, 'Right', 'resizeactive', '20 0', 'Grow', { submap: 'resize' }),
        bind(64, 'E', 'exec', 'nautilus', 'Apps: Files'),
        bind(64, 'M', '__lua', '12'),
        bind(64, 'B', 'exec', 'firefox', 'Apps: Browser'),
        bind(64, 'F', 'fullscreen', '0', 'Fullscreen'),
        bind(64, 'G', 'exec', 'gimp', 'Apps: Paint'),
    ]).groups;
    // Groups named in descriptions come first, then the dispatcher groups.
    assert.deepEqual(tiles(keyShortcuts(groups)), ['Super+E | Files', 'Super+B | Browser', 'Super+G | Paint',
        'Super+Q | Close window']);
});

test('key shortcuts skip long combinations and need at least two tiles', () => {
    const groups = parseBinds([
        bind(64 | 1 | 4, 'L', 'exec', 'x', 'Pentad: Too many keys'),
        bind(64 | 1, 'Backspace', 'exec', 'x', 'Pentad: Label too long'),
        bind(64, 'code:200', 'exec', 'x', 'Pentad: Key 200 is too long as well'),
        bind(4 | 1, 'T', 'exec', 'x', 'Pentad: Ctrl+Shift+T fits'),
        bind(64, 'V', 'exec', 'x', 'Pentad: Fits'),
    ]).groups;
    assert.deepEqual(tiles(keyShortcuts(groups)), ['Ctrl+Shift+T | Ctrl+Shift+T fits', 'Super+V | Fits']);
    // One qualifying bind is not a strip.
    assert.deepEqual(keyShortcuts(parseBinds([bind(64, 'V', 'exec', 'x', 'Pentad: Alone')]).groups), []);
    // A traditional config without descriptions has none; a 240-bind list of long keycodes neither.
    assert.deepEqual(keyShortcuts(parseBinds([bind(64, 'Q', 'killactive', ''), bind(64, 'E', 'exec', 'files')]).groups), []);
    const long = Array.from({ length: 24 }, (unused, index) => bind(64, 'code:' + (100 + index), 'exec', 'app', 'Group: App ' + index));
    assert.deepEqual(keyShortcuts(parseBinds(long).groups), []);
});

test('key shortcuts on a reference sheet are the first rows of its first group', () => {
    assert.deepEqual(tiles(keyShortcuts(groupsFor('pentad', en), { reference: true })), ['Super | Application search on release',
        'Super+Space | Open search', 'Super+V | Clipboard history', 'Super+. | Emoji picker']);
    // "diff --staged" and "log --oneline" run past 12 characters.
    assert.deepEqual(tiles(keyShortcuts(groupsFor('git', en), { reference: true })).map(tile => tile.split(' | ')[0]),
        ['status', 'diff', 'show', 'branch']);
    assert.equal(keyShortcuts(groupsFor('browser', uk), { reference: true })[0].description, 'Нова вкладка');
    for (const id of sheetIds()) assert.ok(keyShortcuts(groupsFor(id, en), { reference: true }).length >= 2, id);
});

test('key shortcuts tolerate malformed input', () => {
    for (const value of [null, undefined, 'x', 3, {}, [null], [{ binds: 'x' }], [{ binds: [null, 1, { keys: 'Q' }] }]]) {
        assert.deepEqual(keyShortcuts(value), []);
        assert.deepEqual(keyShortcuts(value, { reference: true }), []);
    }
});
