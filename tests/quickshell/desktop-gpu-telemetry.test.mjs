import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as Telemetry from '../../quickshell/logic/telemetry.mjs';

const source = readFileSync(new URL('../../quickshell/services/Desktop.qml', import.meta.url), 'utf8');
function method(name) {
  const start = source.search(new RegExp(`^    function ${name}\\(`, 'm'));
  assert.ok(start >= 0, `${name} exists`);
  let depth = 1, end = source.indexOf('{', start) + 1;
  for (; depth && end < source.length; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  return source.slice(start, end);
}
// Values made inside the vm context have its own Array prototype.
const plain = value => JSON.parse(JSON.stringify(value));
const methods = ['startGpuSample', 'listGpuCards', 'applyGpuCards', 'readGpuFiles', 'settleGpuReader',
  'finishGpuSample', 'cancelGpuSample', 'destroyGpuReaders'].map(method).join('\n');

// sysfs content by path; a missing key is a failed read.
function harness(files = {}) {
  const spawned = [];
  const desktop = vm.createContext({
    Telemetry, telemetryActive: true, drmRoot: '/sys/class/drm',
    gpuGeneration: 0, gpuExpected: 0, gpuSettled: 0, gpuCards: null, gpuCardsListed: true,
    gpuReaders: [], gpuSamples: [], gpuPercent: null, finished: 0,
    finishSampleIfReady() { desktop.finished++; },
    gpuDeadline: { running: false, start() { this.running = true; }, stop() { this.running = false; } },
    gpuCardReader: { _running: false, get running() { return this._running; },
      set running(value) { if (value && !this._running) spawned.push('ls'); this._running = value; } },
    gpuReaderComponent: { createObject(parent, props) {
      return { ...props, waiting: false, ok: false, value: '', failures: 0, skipTicks: 0, destroyed: false, reloads: 0,
        reload() { this.reloads++; }, text() { return files[this.path]; }, destroy() { this.destroyed = true; } };
    } },
  });
  desktop.root = desktop;
  vm.runInContext(methods, desktop, { timeout: 1000 });
  const listed = text => { desktop.gpuCardReader.running = false; desktop.applyGpuCards(text); };
  // Delivers every pending read the way FileView's loaded/loadFailed signals would.
  const settle = () => {
    for (const reader of desktop.gpuReaders.filter(item => item.waiting))
      desktop.settleGpuReader(reader, Object.hasOwn(files, reader.path));
  };
  return { desktop, spawned, listed, settle, files };
}
const card = (name, load, used, total) => ({
  [`/sys/class/drm/${name}/device/gpu_busy_percent`]: load,
  [`/sys/class/drm/${name}/device/mem_info_vram_used`]: used,
  [`/sys/class/drm/${name}/device/mem_info_vram_total`]: total,
});

test('lists DRM cards once and reads sysfs files on later ticks without spawning', () => {
  const { desktop, spawned, listed, settle } = harness({ ...card('card0', '22\n', '100\n', '1000\n'), ...card('card1', '64\n', '300\n', '2000\n') });
  desktop.startGpuSample();
  assert.deepEqual(spawned, ['ls']);
  listed('card1\ncard0\ncard0-DP-1\nrenderD128\n');
  assert.equal(desktop.gpuReaders.length, 6);
  assert.equal(desktop.gpuExpected, 6);
  settle();
  assert.equal(desktop.gpuDeadline.running, false);
  assert.deepEqual(plain(desktop.gpuSamples.map(sample => sample.id)), ['card0', 'card1']);
  assert.equal(desktop.gpuPercent, 0.64);
  assert.deepEqual(plain(desktop.gpuSamples[1].memory), { used: 300, total: 2000 });
  for (let tick = 0; tick < 5; tick++) { desktop.startGpuSample(); settle(); }
  assert.deepEqual(spawned, ['ls'], 'ticks after the listing start no process');
  assert.equal(desktop.gpuReaders[0].reloads, 6);
  assert.equal(desktop.finished, 6);
});

test('cards without gpu_busy_percent or any readable file keep the old semantics', () => {
  const files = { '/sys/class/drm/card0/device/mem_info_vram_used': '5', '/sys/class/drm/card0/device/mem_info_vram_total': '10' };
  const { desktop, listed, settle } = harness(files);
  desktop.startGpuSample();
  listed('card0\ncard1\n');
  settle();
  assert.deepEqual(plain(desktop.gpuSamples), [{ id: 'card0', load: null, memory: { used: 5, total: 10 } }]);
  assert.equal(desktop.gpuPercent, null);
});

test('no cards or a failed listing completes the GPU part empty', () => {
  const { desktop, listed } = harness();
  desktop.startGpuSample();
  listed('');
  assert.deepEqual(plain(desktop.gpuCards), []);
  assert.equal(desktop.gpuDeadline.running, false);
  assert.deepEqual(plain(desktop.gpuSamples), []);
  desktop.startGpuSample();
  assert.equal(desktop.gpuDeadline.running, false, 'later ticks finish at once without listing again');
});

test('a file that keeps failing is retried less often and recovers', () => {
  const { desktop, listed, settle, files } = harness(card('card0', undefined, '1', '2'));
  delete files['/sys/class/drm/card0/device/gpu_busy_percent'];
  desktop.startGpuSample();
  listed('card0');
  settle();
  const load = desktop.gpuReaders.find(reader => reader.field === 'load');
  const reads = [];
  for (let tick = 0; tick < 12; tick++) {
    const before = load.reloads;
    desktop.startGpuSample(); settle();
    reads.push(load.reloads - before);
    assert.equal(desktop.gpuSamples[0].load, null);
  }
  assert.deepEqual(reads, [1, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0]);
  files['/sys/class/drm/card0/device/gpu_busy_percent'] = '40';
  for (let tick = 0; tick < 8 && desktop.gpuSamples[0].load === null; tick++) { desktop.startGpuSample(); settle(); }
  assert.equal(desktop.gpuSamples[0].load, 0.4);
  assert.equal(load.failures, 0);
  assert.equal(load.skipTicks, 0);
});

test('a refresh with the same cards keeps the readers, a changed list replaces them', () => {
  const { desktop, listed, settle } = harness({ ...card('card0', '1', '1', '2'), ...card('card1', '2', '1', '2') });
  desktop.startGpuSample(); listed('card0'); settle();
  const first = desktop.gpuReaders.slice();
  desktop.listGpuCards(); listed('card0');
  assert.ok(desktop.gpuReaders.length === first.length && desktop.gpuReaders.every((reader, i) => reader === first[i]));
  assert.ok(first.every(reader => !reader.destroyed));
  desktop.listGpuCards(); listed('card0\ncard1');
  assert.ok(first.every(reader => reader.destroyed));
  assert.equal(desktop.gpuReaders.length, 6);
  desktop.startGpuSample(); settle();
  assert.deepEqual(plain(desktop.gpuSamples.map(sample => sample.id)), ['card0', 'card1']);
});

test('reads that finish after a cancel or a deadline do not publish', () => {
  const { desktop, listed, settle } = harness(card('card0', '50', '1', '2'));
  desktop.startGpuSample(); listed('card0'); settle();
  desktop.startGpuSample();
  desktop.finishGpuSample(desktop.gpuGeneration, false);
  assert.deepEqual(plain(desktop.gpuSamples), []);
  assert.equal(desktop.gpuPercent, null);
  settle();
  assert.deepEqual(plain(desktop.gpuSamples), [], 'late reads are ignored');
  desktop.startGpuSample();
  desktop.telemetryActive = false;
  desktop.cancelGpuSample(); desktop.destroyGpuReaders(); desktop.gpuCards = null;
  assert.equal(desktop.gpuDeadline.running, false);
  assert.deepEqual(plain(desktop.gpuReaders), []);
});

test('a listing that finishes after telemetry was disabled creates no readers', () => {
  const { desktop, listed } = harness(card('card0', '50', '1', '2'));
  desktop.startGpuSample();
  desktop.telemetryActive = false;
  desktop.cancelGpuSample(); desktop.destroyGpuReaders(); desktop.gpuCards = null;
  listed('card0');
  assert.deepEqual(plain(desktop.gpuReaders), []);
  assert.equal(desktop.gpuCards, null);
  assert.equal(desktop.gpuCardsListed, true);
});
