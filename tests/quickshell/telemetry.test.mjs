import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCpu, cpuUsage, memoryUsage, networkBytes, rates, compactByteRate, compactDetailByteRate, gpuSample, gpuPercent } from '../../quickshell/logic/telemetry.mjs';

test('parses CPU deltas and clamps utilization', () => {
    const before = parseCpu('cpu  10 2 8 70 10 0 0 0\ncpu0 1 0 1 8');
    const after = parseCpu('cpu  20 2 18 130 10 0 0 0');
    assert.equal(cpuUsage(before, after), 0.25);
    assert.equal(parseCpu('not proc stat'), null);
    assert.equal(cpuUsage(before, parseCpu('cpu  20 2 18 40 10 0 0 0')), null);
    assert.equal(parseCpu('cpu  1 2 invalid 4'), null);
});

test('uses MemAvailable and rejects invalid totals', () => {
    assert.deepEqual(memoryUsage('MemTotal: 100 kB\nMemAvailable: 25 kB'), { used: 75 * 1024, total: 100 * 1024 });
    assert.equal(memoryUsage('MemTotal: 10 kB\nMemAvailable: 20 kB'), null);
});

test('aggregates non-loopback interfaces and computes byte rates', () => {
    const row = (name, rx, tx) => `${name}: ${rx} 0 0 0 0 0 0 0 ${tx} 0 0 0 0 0 0 0`;
    const first = networkBytes(`${row('lo', 1000, 1000)}\n${row('eth0', 100, 200)}\n${row('wlan0', 300, 400)}`);
    const second = { received: 500, sent: 800 };
    assert.deepEqual(first, { received: 400, sent: 600 });
    assert.deepEqual(rates(first, second, 2), { rxBytesPerSecond: 50, txBytesPerSecond: 100 });
    assert.equal(rates(second, first, 2), null);
    assert.equal(rates(first, second, 0), null);
    assert.equal(compactByteRate(1024 * 1024), '1.0M');
});

test('parses optional legacy DRM load and VRAM values without inventing zeros', () => {
    assert.deepEqual(gpuSample('card0', '42\n', '256\n', '1024\n'), {
        id: 'card0', load: 0.42, memory: { used: 256, total: 1024 }
    });
    assert.deepEqual(gpuSample('card1', '', 'oops', '0'), {
        id: 'card1', load: null, memory: null
    });
    assert.equal(gpuSample('card0', '101', '3', '2').load, null);
    assert.equal(gpuSample('card0', '0', '3', '2').memory, null);
    assert.equal(gpuPercent([gpuSample('card0', '21', '', ''), gpuSample('card1', '73', '', '')]), 0.73);
    assert.equal(gpuPercent([gpuSample('card0', '', '', '')]), null);
});

test('keeps network circle rates short with explicit per-second units', () => {
    assert.equal(compactDetailByteRate(0), '0B/s');
    assert.equal(compactDetailByteRate(16 * 1024), '16K/s');
    assert.equal(compactDetailByteRate(12.3 * 1024 ** 2), '12.3M/s');
    assert.equal(compactDetailByteRate(987.6 * 1024 ** 2), '988M/s');
    for (const value of [null, undefined, NaN, -1]) assert.equal(compactDetailByteRate(value), '—');
});
