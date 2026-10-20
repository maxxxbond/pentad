import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../quickshell/tests/menu-motion.qml', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^    function (?:frame|finishSample|beginSample)\([^\n]*\) \{.*?^    \}/gms)]
  .map(match => match[0]).join('\n');

function fixture() {
  let now = 1000;
  const root = { collecting: false, step: 1, samples: [], measurements: [], positions: [],
    host: { visible: true, slideProgress: 0 }, Date: { now: () => now } };
  root.root = root;
  const context = vm.createContext(root);
  vm.runInContext(methods, context, { timeout: 1000 });
  Object.assign(root, vm.runInContext('({ frame, finishSample, beginSample })', context));
  return { root, advance(ms) { now += ms; } };
}

test('motion profiling keeps a stalled first frame separate from frame gaps', () => {
  const { root, advance } = fixture();
  root.beginSample('right', 'open');
  for (const delay of [80, 16, 48, 16]) { advance(delay); root.host.slideProgress += 0.1; root.frame(); }
  root.finishSample();
  assert.deepEqual(JSON.parse(JSON.stringify(root.measurements)), [{
    side: 'right', direction: 'open', cycle: 0, frames: 4,
    frameGapsMs: [80, 16, 48, 16], positions: [0.1, 0.2, 0.30000000000000004, 0.4],
    firstFrameMs: 80, p95GapMs: 48, maxGapMs: 48,
  }]);
});

test('a missed opening produces null timing instead of pretending to be smooth', () => {
  const { root } = fixture();
  root.beginSample('left', 'open');
  root.finishSample();
  assert.equal(root.measurements[0].frames, 0);
  assert.equal(root.measurements[0].firstFrameMs, null);
  assert.equal(root.measurements[0].maxGapMs, null);
  root.finishSample();
  assert.equal(root.measurements.length, 1);
});

test('profiling ignores hidden-host and idle frames and resets between sides', () => {
  const { root, advance } = fixture();
  root.frame();
  root.beginSample('right', 'close');
  root.host.visible = false;
  advance(100);
  root.frame();
  assert.equal(root.samples.length, 0);
  root.finishSample();
  root.host.visible = true;
  root.beginSample('left', 'open');
  advance(16);
  root.frame();
  root.finishSample();
  assert.equal(root.measurements[1].firstFrameMs, 16);
  assert.equal(root.measurements[1].frames, 1);
});

test('frames after the final position do not inflate animation gaps', () => {
  const { root, advance } = fixture();
  root.beginSample('right', 'open');
  root.host.slideProgress = 0.5;
  advance(16); root.frame();
  root.host.slideProgress = 1;
  advance(16); root.frame();
  advance(140); root.frame();
  root.finishSample();
  assert.equal(root.measurements[0].frames, 2);
  assert.equal(root.measurements[0].maxGapMs, 16);
});
