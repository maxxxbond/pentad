import test from 'node:test';
import assert from 'node:assert/strict';
import { keyboardLayoutState } from '../../quickshell/logic/keyboard-layout.mjs';

const devices = keyboards => JSON.stringify({ mice: [], keyboards });

test('reads the active layout of the main keyboard', () => {
    const text = devices([
        { name: 'power-button', main: false, layout: 'de,ua', active_keymap: 'German (US)', active_layout_index: 0 },
        { name: 'razer', main: true, layout: 'de,ua', active_keymap: 'Ukrainian', active_layout_index: 1 },
    ]);
    assert.deepEqual(keyboardLayoutState(text), { label: 'UA', name: 'Ukrainian', count: 2 });
});

test('falls back to the first keyboard and the keymap name', () => {
    assert.deepEqual(keyboardLayoutState(devices([{ layout: 'us', active_keymap: 'English (US)', active_layout_index: 0 }])),
        { label: 'US', name: 'English (US)', count: 1 });
    assert.deepEqual(keyboardLayoutState(devices([{ layout: '', active_keymap: 'English (US)', active_layout_index: 3 }])),
        { label: 'EN', name: 'English (US)', count: 0 });
});

test('returns null for missing or broken data', () => {
    assert.equal(keyboardLayoutState('not json'), null);
    assert.equal(keyboardLayoutState(devices([])), null);
    assert.equal(keyboardLayoutState(JSON.stringify({})), null);
    assert.equal(keyboardLayoutState(devices([{ main: true, layout: '', active_keymap: '' }])), null);
});
