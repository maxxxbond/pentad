import test from 'node:test';
import assert from 'node:assert/strict';
import { keyboardLayoutState, keyboardLayoutNames, keyboardLayoutName, keyboardLayoutAfter } from '../../quickshell/logic/keyboard-layout.mjs';

const devices = keyboards => JSON.stringify({ mice: [], keyboards });

test('reads the active layout of the main keyboard with every layout it can switch to', () => {
    const text = devices([
        { name: 'power-button', main: false, layout: 'de,ua', variant: 'us,', active_keymap: 'German (US)', active_layout_index: 0 },
        { name: 'razer', main: true, layout: 'de,ua', variant: 'us,', active_keymap: 'Ukrainian', active_layout_index: 1 },
    ]);
    assert.deepEqual(keyboardLayoutState(text), { label: 'UA', name: 'Ukrainian', index: 1, count: 2, layouts: [
        { index: 0, code: 'de', variant: 'us', label: 'DE' },
        { index: 1, code: 'ua', variant: '', label: 'UA' },
    ] });
});

test('falls back to the first keyboard and the keymap name', () => {
    const single = keyboardLayoutState(devices([{ layout: 'us', active_keymap: 'English (US)', active_layout_index: 0 }]));
    assert.equal(single.label, 'US');
    assert.equal(single.count, 1);
    const unknown = keyboardLayoutState(devices([{ layout: '', active_keymap: 'English (US)', active_layout_index: 3 }]));
    assert.deepEqual(unknown, { label: 'EN', name: 'English (US)', index: -1, count: 0, layouts: [] });
});

test('returns null for missing or broken data', () => {
    assert.equal(keyboardLayoutState('not json'), null);
    assert.equal(keyboardLayoutState(devices([])), null);
    assert.equal(keyboardLayoutState(JSON.stringify({})), null);
    assert.equal(keyboardLayoutState(devices([{ main: true, layout: '', active_keymap: '' }])), null);
});

test('names layouts and variants from the XKB registry', () => {
    const names = keyboardLayoutNames([
        '! model', '  pc105           Generic 105-key PC',
        '! layout', '  us              English (US)', '  de              German', '  ua              Ukrainian',
        '! variant', '  us              de: German (US)', '  intl            us: English (US, intl., with dead keys)',
        '! option', '  grp             Switching to another layout',
    ].join('\n'));
    assert.equal(names.de, 'German');
    assert.equal(names['de(us)'], 'German (US)');
    assert.equal(names['us(intl)'], 'English (US, intl., with dead keys)');
    assert.equal(names.pc105, undefined);
    assert.equal(names.grp, undefined);
    assert.equal(keyboardLayoutName({ code: 'de', variant: 'us', label: 'DE' }, names), 'German (US)');
    assert.equal(keyboardLayoutName({ code: 'de', variant: 'nodeadkeys', label: 'DE' }, names), 'German');
    assert.equal(keyboardLayoutName({ code: 'xx', variant: '', label: 'XX' }, names), 'XX');
    assert.equal(keyboardLayoutName({ code: 'ua', variant: '', label: 'UA' }, null), 'UA');
});

test('steps through layouts with wrap-around', () => {
    assert.equal(keyboardLayoutAfter(0, 2, 1), 1);
    assert.equal(keyboardLayoutAfter(1, 2, 1), 0);
    assert.equal(keyboardLayoutAfter(0, 3, -1), 2);
    assert.equal(keyboardLayoutAfter(1, 3, 5), 0);
    assert.equal(keyboardLayoutAfter(-1, 3, 1), 1);
    assert.equal(keyboardLayoutAfter(0, 1, 1), -1);
    assert.equal(keyboardLayoutAfter(0, 2, 0), -1);
});
