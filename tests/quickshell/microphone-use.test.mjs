import test from 'node:test';
import assert from 'node:assert/strict';
import { captureAppKey, microphoneUsers, newCaptureKeys } from '../../quickshell/logic/microphone-use.mjs';

test('captureAppKey prefers the binary, then the ALSA bracket, then names', () => {
    assert.equal(captureAppKey({ 'application.process.binary': 'Discord' }), 'discord');
    assert.equal(captureAppKey({ 'application.name': 'PipeWire ALSA [handy]' }), 'handy');
    assert.equal(captureAppKey({ 'application.name': 'OBS Studio' }), 'obs studio');
    assert.equal(captureAppKey({ 'node.name': 'arecord' }), 'arecord');
    assert.equal(captureAppKey({}), '');
    assert.equal(captureAppKey({
        'application.process.binary': 'Handy',
        'application.name': 'PipeWire ALSA [other]',
    }), 'handy');
});

const stream = (id, props) => ({ id, props: { 'media.class': 'Stream/Input/Audio', ...props } });
const micLink = (targetId, extra = {}) => ({
    sourceId: 'm', targetId, sourceClass: 'Audio/Source', sourceIsStream: false, sourceMuted: false, ...extra,
});
const handy = () => stream('s1', { 'application.name': 'PipeWire ALSA [handy]' });

test('microphoneUsers reports a stream linked to a hardware source', () => {
    assert.deepEqual(microphoneUsers([handy()], [micLink('s1')]), [{ key: 'handy', muted: false }]);
});

test('microphoneUsers ignores unlinked streams, monitors and stream-to-stream links', () => {
    assert.deepEqual(microphoneUsers([handy()], []), []);
    assert.deepEqual(microphoneUsers([handy()], [micLink('s1', { sourceClass: 'Audio/Sink' })]), []);
    assert.deepEqual(microphoneUsers([handy()], [micLink('s1', { sourceIsStream: true })]), []);
});

test('microphoneUsers accepts Audio/Duplex sources', () => {
    assert.equal(microphoneUsers([handy()], [micLink('s1', { sourceClass: 'Audio/Duplex' })]).length, 1);
});

test('microphoneUsers ignores video streams and Pentad itself', () => {
    const video = stream('s1', { 'application.name': 'cam' });
    video.props['media.class'] = 'Stream/Input/Video';
    assert.deepEqual(microphoneUsers([video], [micLink('s1')]), []);
    for (const binary of ['qs', 'quickshell'])
        assert.deepEqual(microphoneUsers([stream('s1', { 'application.process.binary': binary })], [micLink('s1')]), []);
});

test('microphoneUsers collapses streams with the same key', () => {
    const streams = [
        stream('s1', { 'application.process.binary': 'firefox' }),
        stream('s2', { 'application.process.binary': 'firefox' }),
    ];
    assert.deepEqual(microphoneUsers(streams, [micLink('s1'), micLink('s2')]), [{ key: 'firefox', muted: false }]);
});

test('microphoneUsers is muted only when every linked mic is muted', () => {
    const s = [stream('s1', { 'application.process.binary': 'firefox' })];
    const links = (a, b) => [micLink('s1', { sourceId: 'a', sourceMuted: a }), micLink('s1', { sourceId: 'b', sourceMuted: b })];
    assert.equal(microphoneUsers(s, links(true, false))[0].muted, false);
    assert.equal(microphoneUsers(s, links(true, true))[0].muted, true);
});

test('microphoneUsers sorts by key', () => {
    const streams = [
        stream('s1', { 'application.process.binary': 'zoom' }),
        stream('s2', { 'application.process.binary': 'arecord' }),
    ];
    const keys = microphoneUsers(streams, [micLink('s1'), micLink('s2')]).map(u => u.key);
    assert.deepEqual(keys, ['arecord', 'zoom']);
});

test('newCaptureKeys returns keys new in next, in next order', () => {
    assert.deepEqual(newCaptureKeys([], ['a']), ['a']);
    assert.deepEqual(newCaptureKeys(['a'], ['a', 'b']), ['b']);
    assert.deepEqual(newCaptureKeys(['a', 'b'], ['a']), []);
    assert.deepEqual(newCaptureKeys(['a'], ['a']), []);
});
