import assert from 'node:assert/strict';
import test from 'node:test';
import { sheets, groupsFor } from '../../quickshell/logic/cheatsheets.mjs';
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
