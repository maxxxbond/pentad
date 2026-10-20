import test from 'node:test';
import assert from 'node:assert/strict';
import { accessSync } from 'node:fs';
import { audioDevicePresentation, disambiguateAudioDevices, parseWpctlVolume, volumeMatches } from '../../quickshell/logic/audio.mjs';

test('wpctl readback parses volume and mute state without assuming setter success', () => {
  assert.deepEqual(parseWpctlVolume('Volume: 0.74\n'), { volume: 0.74, muted: false });
  assert.deepEqual(parseWpctlVolume('Volume: 1.00 [MUTED]\n'), { volume: 1, muted: true });
  assert.equal(volumeMatches(parseWpctlVolume('Volume: 0.70').volume, 0.7), true);
  assert.equal(volumeMatches(0.68, 0.7), false);
});

test('wpctl readback rejects malformed or out-of-range values', () => {
  for (const value of ['', 'Volume: NaN', 'Volume: 1.1', 'Volume: 0.4 extra', 'Volume: -0.2'])
    assert.throws(() => parseWpctlVolume(value), /invalid-response/);
});

test('audio device icons use form factor before name heuristics and keep input microphones', () => {
  const cases = [
    [{ description: 'USB DAC', properties: { 'device.form-factor': 'headphone' } }, 'material/headphones-symbolic.svg'],
    [{ description: 'Bluetooth headset', properties: { 'device.form-factor': 'speaker' } }, 'material/volume-up-symbolic.svg'],
    [{ description: 'HDMI headphones', properties: { 'device.form-factor': 'headset' } }, 'material/headphones-symbolic.svg'],
    [{ description: 'Dell Digital Stereo (HDMI 2)' }, 'audio/display-speaker-symbolic.svg'],
    [{ name: 'alsa_output.card.hdmi-stereo' }, 'audio/display-speaker-symbolic.svg'],
    [{ description: 'DisplayPort monitor' }, 'audio/display-speaker-symbolic.svg'],
    [{ description: 'External output', properties: { 'device.form-factor': 'monitor' } }, 'audio/display-speaker-symbolic.svg'],
    [{ description: 'USB Headphones' }, 'material/headphones-symbolic.svg'],
    [{ description: 'Sound card', properties: { 'device.icon-name': 'audio-headset' } }, 'material/headphones-symbolic.svg'],
    [{ description: 'Wireless speaker', properties: { 'device.api': 'bluez5' } }, 'material/volume-up-symbolic.svg'],
    [{ description: 'WH-1000XM5', properties: { 'device.api': 'bluez5' } }, 'material/bluetooth-symbolic.svg'],
    [{}, 'material/volume-up-symbolic.svg'],
    [{ isSink: false, description: 'USB Headset' }, 'material/media/mic-symbolic.svg'],
  ];
  for (const [data, expected] of cases) {
    const node = { isSink: true, ...data };
    const before = structuredClone(node);
    const result = audioDevicePresentation(node);
    assert.equal(result.icon, expected, JSON.stringify(data));
    accessSync(new URL(`../../quickshell/assets/icons/${result.icon}`, import.meta.url));
    assert.deepEqual(node, before);
  }
});

test('short names prefer nicknames, preserve HDMI ports, and retain full labels', () => {
  assert.deepEqual(audioDevicePresentation({ isSink: true, nickname: 'Desk DAC', description: 'USB Sound Card Analog Stereo' }), {
    label: 'USB Sound Card Analog Stereo', shortLabel: 'Desk DAC', icon: 'material/volume-up-symbolic.svg',
  });
  assert.equal(audioDevicePresentation({ description: 'Built-in Audio Analog Stereo' }).shortLabel, 'Built-in Audio');
  assert.equal(audioDevicePresentation({ description: 'Dell Digital Stereo (HDMI 2)' }).shortLabel, 'Dell (HDMI 2)');
  assert.equal(audioDevicePresentation({ name: 'fallback' }).shortLabel, 'fallback');
  assert.equal(audioDevicePresentation({}).shortLabel, 'Audio device');
});

test('duplicate short names fall back to full labels without changing IDs or the source', () => {
  const devices = [
    { id: '1', shortLabel: 'Dell', label: 'Dell HDMI 1' },
    { id: '2', shortLabel: 'Dell', label: 'Dell HDMI 2' },
    { id: '3', shortLabel: 'USB', label: 'USB Analog Stereo' },
  ];
  const before = structuredClone(devices);
  assert.deepEqual(disambiguateAudioDevices(devices).map(item => [item.id, item.shortLabel]), [
    ['1', 'Dell HDMI 1'], ['2', 'Dell HDMI 2'], ['3', 'USB'],
  ]);
  assert.deepEqual(devices, before);
  assert.deepEqual(disambiguateAudioDevices([]), []);
});
