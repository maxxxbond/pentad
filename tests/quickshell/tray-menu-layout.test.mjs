import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { modelListHeight } from '../../quickshell/logic/tray-menu-layout.mjs';

test('model-derived menu extent handles empty, one-row and asynchronously filled Handy models', () => {
  assert.equal(modelListHeight([]), 0);
  assert.equal(modelListHeight([{ text: 'One' }]), 30);
  assert.equal(modelListHeight({ 0: { text: 'One' }, length: 1 }), 30);
  const handyRows = [
    { text: 'Open' }, { text: 'Pause' }, { text: 'Next' }, { isSeparator: true },
    { text: 'Repeat' }, { text: 'Shuffle' }, { isSeparator: true },
    { text: 'Player A' }, { isSeparator: true }, { text: 'Player B' }, { isSeparator: true },
  ];
  assert.equal(modelListHeight(handyRows), 246);
  assert.equal(modelListHeight(null), 0);
});

test('attached popover bounds resize frame retries and stops when closed or dimensions match', () => {
  const source = readFileSync(new URL('../../quickshell/components/AttachedPopover.qml', import.meta.url), 'utf8');
  const timer = source.match(/Timer \{\s+id: resizeFrameRetry([\s\S]*?)\n    \}/)[1];
  const callback = timer.match(/onTriggered: \{([\s\S]*?)\n        \}/)[1];
  let stopped = false;
  const context = vm.createContext({
    popup: { visible: true, height: 64, implicitHeight: 278, width: 332, implicitWidth: 332 },
    root: { resizeRetryCount: 0, frames: 0, requestWindowFrame() { this.frames++; } },
    running: true, stop: () => { stopped = true; },
  });
  for (let index = 0; index < 8; index++)
    vm.runInContext(`(function() { ${callback} }).call(this)`, context, { timeout: 1000 });
  assert.equal(context.root.frames, 8);
  assert.equal(context.root.resizeRetryCount, 8);
  vm.runInContext(`(function() { ${callback} }).call(this)`, context, { timeout: 1000 });
  assert.equal(context.root.frames, 8);
  context.popup.visible = false;
  context.root.resizeRetryCount = 0;
  context.running = true;
  vm.runInContext(`(function() { ${callback} }).call(this)`, context, { timeout: 1000 });
  assert.equal(context.root.frames, 8);
  assert.equal(stopped, true);
  context.popup.visible = true;
  context.popup.height = context.popup.implicitHeight;
  context.root.resizeRetryCount = 0;
  context.running = true;
  stopped = false;
  const framesBefore = context.root.frames;
  vm.runInContext(`(function() { ${callback} })()`, context, { timeout: 1000 });
  assert.equal(context.root.frames, framesBefore + 1);
  assert.equal(stopped, true);
});
