import test from 'node:test';
import assert from 'node:assert/strict';
import { barMenuModes, nextPrebuild, prebuildEnabled, prebuildOrder } from '../../quickshell/logic/menu-prebuild.mjs';

const none = () => ({ right: false, left: false, activity: false });
const bar = (due, prepared = none()) => ({ due, prepared });

test('speed is the default and only memory turns building ahead of time off', () => {
  assert.deepEqual(barMenuModes, ['speed', 'memory']);
  assert.equal(prebuildEnabled(undefined), true);
  assert.equal(prebuildEnabled({}), true, 'an old document without the key keeps the default');
  assert.equal(prebuildEnabled({ barMenus: 'speed' }), true);
  assert.equal(prebuildEnabled({ barMenus: 'memory' }), false);
});

test('control centers come first on every output, then sidebars, then activity menus', () => {
  assert.deepEqual(prebuildOrder, ['right', 'left', 'activity']);
  const outputs = [bar(true), bar(true)];
  const steps = [];
  for (let next = nextPrebuild(outputs); next; next = nextPrebuild(outputs)) {
    steps.push(`${next.index}:${next.side}`);
    outputs[next.index].prepared[next.side] = true;
  }
  assert.deepEqual(steps, ['0:right', '1:right', '0:left', '1:left', '0:activity', '1:activity']);
});

test('menus already built by hover or open are skipped', () => {
  assert.deepEqual(nextPrebuild([bar(true, { right: true, left: false, activity: true })]), { index: 0, side: 'left' });
  assert.equal(nextPrebuild([bar(true, { right: true, left: true, activity: true })]), null);
});

test('an output waits until it has settled; missing or foreign bars are ignored', () => {
  assert.equal(nextPrebuild([bar(false)]), null);
  assert.deepEqual(nextPrebuild([bar(false), bar(true)]), { index: 1, side: 'right' });
  assert.deepEqual(nextPrebuild([null, { due: true }, bar(true)]), { index: 2, side: 'right' });
  assert.equal(nextPrebuild(undefined), null);
  assert.equal(nextPrebuild([]), null);
});
