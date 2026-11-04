import test from 'node:test';
import assert from 'node:assert/strict';
import { audioFeedback, layoutFeedback } from '../../quickshell/logic/level-feedback.mjs';

const output = { id: 'speakers', label: 'Speakers', volume: 0.6, muted: false };
const input = { id: 'microphone', label: 'Microphone', volume: 0.8, muted: false };
const state = (out = output, mic = input) => ({ kind: 'ready', value: { output: out, input: mic } });

test('startup, reconnection and unrelated device list updates do not flash the OSD', () => {
    assert.equal(audioFeedback(null, state()), null);
    assert.equal(audioFeedback({ kind: 'unavailable' }, state()), null);
    assert.equal(audioFeedback(state(), state()), null);
    assert.equal(audioFeedback(state(), { kind: 'unavailable' }), null);
});

test('output volume and mute changes preserve the device name and actual level', () => {
    assert.deepEqual(audioFeedback(state(), state({ ...output, volume: 0.62 })), {
        kind: 'output', switched: false, value: 0.62, muted: false, label: 'Speakers',
    });
    assert.equal(audioFeedback(state(), state({ ...output, muted: true })).muted, true);
});

test('device switches show even when the new device has the same volume', () => {
    const headphones = { ...output, id: 'headphones', label: 'Headphones' };
    assert.deepEqual(audioFeedback(state(), state(headphones)), {
        kind: 'output', switched: true, value: 0.6, muted: false, label: 'Headphones',
    });
});

test('microphone changes win over simultaneous output changes', () => {
    const next = state({ ...output, volume: 0.5 }, { ...input, muted: true });
    assert.equal(audioFeedback(state(), next).kind, 'input');
    assert.equal(audioFeedback(state(), state(output, null)), null);
});

test('a pending wheel step shows its target and the matching readback does not re-flash', () => {
    const pending = state({ ...output, requestedVolume: 0.64 });
    assert.equal(audioFeedback(state(), pending).value, 0.64);
    assert.equal(audioFeedback(pending, state({ ...output, volume: 0.64, requestedVolume: 0.64 })), null);
});

test('an intermediate readback during a pending write does not rewind the level', () => {
    const pending = state({ ...output, requestedVolume: 0.66 });
    assert.equal(audioFeedback(pending, state({ ...output, volume: 0.62, requestedVolume: 0.66 })), null);
});

const desktop = (keyboardLayout, keyboardLayoutIndex = 0, keyboardLayoutName = '') =>
    ({ kind: 'ready', value: { keyboardLayout, keyboardLayoutIndex, keyboardLayoutName } });

test('startup and unrelated desktop updates do not flash the layout OSD', () => {
    assert.equal(layoutFeedback(null, desktop('us')), null);
    assert.equal(layoutFeedback({ kind: 'unavailable' }, desktop('us')), null);
    assert.equal(layoutFeedback(desktop('us'), { kind: 'unavailable' }), null);
    // First reading with a layout: previous had none, so it is the initial state, not a switch.
    assert.equal(layoutFeedback(desktop(null), desktop('us')), null);
    // No change in code or index.
    assert.equal(layoutFeedback(desktop('us', 0, 'English (US)'), desktop('us', 0, 'English (US)')), null);
});

test('a layout switch flashes the new short code and human name', () => {
    assert.deepEqual(layoutFeedback(desktop('us', 0, 'English (US)'), desktop('ua', 1, 'Ukrainian')),
        { label: 'UA', name: 'Ukrainian' });
    // Two variants share a code but differ by index, so switching between them still flashes.
    assert.deepEqual(layoutFeedback(desktop('us', 0, 'English (US)'), desktop('us', 1, 'English (intl.)')),
        { label: 'US', name: 'English (intl.)' });
});

test('a redundant human name equal to the code is dropped', () => {
    assert.deepEqual(layoutFeedback(desktop('us', 0, 'English'), desktop('de', 1, 'DE')),
        { label: 'DE', name: '' });
    assert.deepEqual(layoutFeedback(desktop('us', 0), desktop('de', 1)), { label: 'DE', name: '' });
});
