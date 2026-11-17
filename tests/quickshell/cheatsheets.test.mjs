import assert from 'node:assert/strict';
import test from 'node:test';
import { sheets, groupsFor, sheetIds, sheetForWindow } from '../../quickshell/logic/cheatsheets.mjs';
import { filterBinds, countBinds, labelFor } from '../../quickshell/logic/keybinds.mjs';

test('offline sheets supply translated groups and rows compatible with keybind rendering', () => {
    assert.deepEqual(sheets('en').map(sheet => sheet.id), ['pentad', 'neovim', 'browser', 'git', 'terminal', 'kitty']);
    for (const sheet of sheets('en')) {
        const en = groupsFor(sheet.id, 'en');
        const uk = groupsFor(sheet.id, 'uk');
        assert.ok(countBinds(en) >= 20);
        assert.equal(countBinds(en), countBinds(uk));
        assert.equal(new Set(en.map(group => group.id)).size, en.length);
        en.forEach((group, i) => {
            assert.notEqual(group.label, uk[i].label);
            assert.equal(labelFor(group, 'en'), group.label);
            group.binds.forEach((bind, j) => {
                assert.ok(bind.keys.length && bind.keys.every(key => typeof key === 'string'));
                assert.notEqual(bind.description, uk[i].binds[j].description);
                assert.equal(bind.described, true);
            });
        });
        assert.equal(countBinds(filterBinds(en, '', {showAll: false})), countBinds(en));
        assert.deepEqual(filterBinds(en, 'no-such-shortcut-xyz', {}), []);
    }
});

test('search works in both languages regardless of display language', () => {
    assert.ok(countBinds(filterBinds(groupsFor('browser', 'en'), 'закладку', {})));
    assert.ok(countBinds(filterBinds(groupsFor('neovim', 'uk'), 'undo', {})));
    assert.ok(countBinds(filterBinds(groupsFor('pentad', 'uk'), 'Super+/', {})));
    assert.ok(countBinds(filterBinds(groupsFor('git', 'en'), 'сховати', {})));
    assert.ok(countBinds(filterBinds(groupsFor('terminal', 'uk'), 'history', {})));
    assert.ok(countBinds(filterBinds(groupsFor('git', 'uk'), 'blame', {})));
    assert.ok(countBinds(filterBinds(groupsFor('git', 'en'), 'скасувати', {})));
    assert.ok(countBinds(filterBinds(groupsFor('kitty', 'uk'), 'new tab', {})));
    assert.ok(countBinds(filterBinds(groupsFor('kitty', 'en'), 'вкладку', {})));
    assert.ok(countBinds(filterBinds(groupsFor('kitty', 'en'), 'ctrl+shift+t', {})));
});

test('unknown sheets are empty and callers cannot mutate shared data', () => {
    assert.deepEqual(groupsFor('unknown', 'en'), []);
    const first = groupsFor('pentad', 'en');
    first[0].binds[0].keys[0] = 'changed';
    first[0].binds.length = 0;
    assert.equal(groupsFor('pentad', 'en')[0].binds[0].keys[0], 'Super');
    assert.equal(sheets((uk, en) => uk)[2].label, 'Браузер');
});

test('every offline bind carries mods, key and a false duplicate flag', () => {
    const pentad = groupsFor('pentad', 'en');
    const rows = pentad.flatMap(group => group.binds);
    const find = keys => rows.find(entry => entry.keys.join('+') === keys);
    assert.deepEqual([find('Super').mods, find('Super').key], [['Super'], '']);
    assert.deepEqual([find('Alt+Shift+Tab').mods, find('Alt+Shift+Tab').key], [['Alt', 'Shift'], 'Tab']);
    assert.deepEqual([find('Esc').mods, find('Esc').key], [[], 'Esc']);
    for (const id of sheetIds()) {
        for (const group of groupsFor(id, 'en')) {
            for (const entry of group.binds) {
                assert.ok(Array.isArray(entry.mods) && typeof entry.key === 'string', id);
                assert.equal(entry.duplicate, false);
            }
        }
    }
    // The modifier option of the shared filter works on catalog rows.
    assert.ok(countBinds(filterBinds(groupsFor('kitty', 'en'), '', { mods: ['Ctrl', 'Shift'] })) > 10);
    assert.deepEqual(filterBinds(groupsFor('kitty', 'en'), '', { duplicates: true }), []);
});

test('sheet ids follow the catalog', () => {
    assert.deepEqual(sheetIds(), ['pentad', 'neovim', 'browser', 'git', 'terminal', 'kitty']);
    assert.deepEqual(sheetIds(), sheets('en').map(sheet => sheet.id));
    sheetIds().push('x');
    assert.equal(sheetIds().length, 6);
});

test('the focused window picks a reference sheet', () => {
    for (const title of ['nvim', 'nvim main.mjs', 'file.txt - NVIM', 'vim', '~/src (vim)', 'init.lua - nvim - kitty'])
        assert.equal(sheetForWindow('foot', title), 'neovim', title);
    assert.equal(sheetForWindow('neovide', 'anything'), 'neovim');
    assert.equal(sheetForWindow('Neovide', ''), 'neovim');
    // Words that merely contain vim do not count.
    for (const title of ['vimeo', 'improvim', 'nvidia-settings', 'avim'])
        assert.equal(sheetForWindow('foot', title), 'terminal', title);
    assert.equal(sheetForWindow('kitty', ''), 'kitty');
    assert.equal(sheetForWindow('Kitty', 'zsh'), 'kitty');
    for (const cls of ['firefox', 'Firefox', 'librewolf', 'zen', 'zen-browser', 'floorp', 'chromium', 'google-chrome', 'Brave-browser',
        'vivaldi-stable', 'opera', 'epiphany', 'org.qutebrowser.qutebrowser'])
        assert.equal(sheetForWindow(cls, 'Some page'), 'browser', cls);
    for (const cls of ['foot', 'footclient', 'Alacritty', 'org.wezfurlong.wezterm', 'com.mitchellh.ghostty', 'ghostty', 'konsole',
        'org.kde.konsole', 'gnome-terminal-server', 'org.gnome.ptyxis', 'xterm', 'st'])
        assert.equal(sheetForWindow(cls, 'user@host: ~'), 'terminal', cls);
    for (const cls of ['', 'code', 'steam', 'st-link', 'stalker', 'nautilus', 'zenity', 'operator'])
        assert.equal(sheetForWindow(cls, 'Window'), '', cls);
});

test('sheet choice has a fixed precedence', () => {
    assert.equal(sheetForWindow('kitty', 'nvim README.md'), 'neovim');
    assert.equal(sheetForWindow('foot', 'vim notes'), 'neovim');
    // Outside a terminal the title says nothing about the program: a browser tab about vim is a browser.
    assert.equal(sheetForWindow('firefox', 'vim cheatsheet - Mozilla Firefox'), 'browser');
    assert.equal(sheetForWindow('code', 'nvim notes'), '');
    assert.equal(sheetForWindow('st-256color', 'nvim'), 'neovim');
    assert.equal(sheetForWindow('kitty', 'zsh'), 'kitty');
});

test('window class and title are untrusted: nothing throws and long input is capped', () => {
    assert.equal(sheetForWindow(), '');
    assert.equal(sheetForWindow(null, null), '');
    assert.equal(sheetForWindow(undefined, undefined), '');
    assert.equal(sheetForWindow(42, 7), '');
    assert.equal(sheetForWindow({}, []), '');
    assert.equal(sheetForWindow({ toString() { throw new Error('boom'); } }, { toString() { throw new Error('boom'); } }), '');
    assert.equal(sheetForWindow(Symbol('x'), Symbol('y')), '');
    assert.equal(sheetForWindow(0, 0), '');
    assert.equal(sheetForWindow(false, false), '');
    assert.equal(sheetForWindow('foot', 'nvim'.padStart(10000, 'x')), 'terminal');
    // Text past 200 characters is not looked at.
    assert.equal(sheetForWindow('foot', 'x'.repeat(10000) + ' nvim'), 'terminal');
    assert.equal(sheetForWindow('foot', 'x'.repeat(190) + ' nvim'), 'neovim');
    assert.equal(sheetForWindow('x'.repeat(10000) + 'firefox', ''), '');
    assert.equal(sheetForWindow('x'.repeat(190) + 'firefox', ''), 'browser');
    assert.equal(sheetForWindow('foot', ' '.repeat(10000)), 'terminal');
    assert.equal(sheetForWindow('foot', '-'.repeat(10000)), 'terminal');
});
