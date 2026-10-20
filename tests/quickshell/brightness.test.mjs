import test from 'node:test';
import assert from 'node:assert/strict';
import {
    clampBrightness, parseBacklightList, parseBacklightBrightness,
    parseDdcBus, parseDdcBrightness, stepsFromDelta, isInternalOutput, brightnessIntent
} from '../../quickshell/logic/brightness.mjs';

test('parses only brightnessctl backlight devices and machine-readable levels', () => {
    assert.deepEqual(parseBacklightList([
        'amdgpu_bl0,backlight,42,42%,100',
        'kbd::capslock,leds,1,100%,1',
        'broken,backlight,1,200%,100'
    ].join('\n')), [{ id: 'amdgpu_bl0', value: 0.42 }]);
    assert.equal(parseBacklightBrightness('amdgpu_bl0,backlight,42,42%,100'), 0.42);
    assert.throws(() => parseBacklightBrightness('kbd::capslock,leds,1,100%,1'));
});

test('maps DDC bus uniquely to the requested DRM output', () => {
    const detect = [
        'Display 1', ' I2C bus: /dev/i2c-7', ' DRM connector: card1-DP-2',
        'Display 2', ' I2C bus: /dev/i2c-8', ' DRM connector: card1-HDMI-A-1'
    ].join('\n');
    assert.equal(parseDdcBus(detect, 'DP-2'), '7');
    assert.equal(parseDdcBus(detect, 'HDMI-A-1'), '8');
    assert.equal(parseDdcBus(detect, 'eDP-1'), null);
    assert.equal(parseDdcBus(`${detect}\nDisplay 3\n I2C bus: /dev/i2c-9\n DRM connector: DP-2`, 'DP-2'), null);
});

test('parses DDC VCP brightness and clamps safe values', () => {
    assert.deepEqual(parseDdcBrightness('VCP 10 C 45 100'), { current: 45, max: 100, value: 0.45 });
    assert.throws(() => parseDdcBrightness('VCP 10 C 101 100'));
    assert.equal(clampBrightness(-1), 0.01);
    assert.equal(clampBrightness(0.6), 0.6);
    assert.equal(clampBrightness(Number.NaN), null);
});

test('converts wheel deltas to integral signed steps', () => {
    assert.equal(stepsFromDelta(-2.8), 2);
    assert.equal(stepsFromDelta(2.8), -2);
    assert.equal(stepsFromDelta(Infinity), 0);
});

test('routes internal panels to backlight and external outputs to DDC', () => {
    assert.equal(isInternalOutput('eDP-1'), true);
    assert.equal(isInternalOutput('LVDS-1'), true);
    assert.equal(isInternalOutput('DP-2'), false);
});

test('brightness intent clamps to hardware range and keeps the latest target quantized', () => {
    assert.deepEqual(brightnessIntent(0.4, 0.8), { steps: 8, target: 0.8 });
    assert.deepEqual(brightnessIntent(0.8, 0.3), { steps: -10, target: 0.30000000000000004 });
    assert.deepEqual(brightnessIntent(0.02, 0), { steps: 0, target: 0.02 });
    assert.equal(brightnessIntent(Number.NaN, 0.5), null);
});
