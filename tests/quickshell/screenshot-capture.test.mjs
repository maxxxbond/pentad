import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const service = readFileSync(new URL('../../quickshell/services/Screenshot.qml', import.meta.url), 'utf8');
const methods = [...service.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
function fixture() {
  const events = [], requests = [], proposalRequests = [], deferred = [];
  const timer = () => ({ restart() {}, stop() {} });
  const context = vm.createContext({
    active: false, phase: 'idle', outputId: '', imagePath: '', imageWidth: 0, imageHeight: 0,
    frames: {}, choosingOutput: false, captureTokens: [], error: '', lastExport: null,
    mode: '', session: '', pendingOutput: '', generation: 0, worker: null, cancellingProcess: null,
    windowRegions: [], frozenWindowSnapshot: null, settingsOpen: true,
    selectionPending: false, pendingInitialCrop: null, helperPath: '/fake/pentad_screenshot.py',
    pickToken: '', pickLabel: '', pickScale: 1, analysis: null, analysisQueue: [],
    captureGateDeadline: timer(), cancellationKillTimer: timer(),
    overlayOutputs: {}, focusReturnTarget: null, focusReturnPending: false, focusReturnScheduled: false, focusReturnSerial: 0,
    Qt: { callLater(callback) { deferred.push(callback); } },
    Quickshell: { screens: [{ name: 'DP-1' }, { name: 'DP-2' }] },
    services: {
      safeMode: false, preview: false,
      config: { documents: { screenshots: {}, theme: {} } },
      hyprland: {
        overviewSnapshot: { kind: 'ready', value: { activeAddress: '0xa', mru: ['window-a'], clients: [{ address: '0xa', instanceId: 'window-a' }] } },
        currentOverviewSnapshot() { return this.overviewSnapshot; },
        focusWindow(target, forceDispatch) { events.push({ focus: target, forceDispatch }); },
        state: { kind: 'ready', value: { focusedOutputId: 'DP-1', outputs: [{ id: 'DP-1', name: 'DP-1' }] } } },
      navigation: { cancel() { events.push('cancel-navigation'); } },
      popups: { prepareCapture() { events.push('close-menus'); } },
    },
    Windows: { capturedWindowRegions() { return []; }, activeWindowCrop() { return null; } },
    requestComponent: { createObject(_parent, { payload }) {
      let complete;
      const process = { watchdog: timer(), running: false, completed: { connect(callback) { complete = callback; } }, destroy() {}, signal() {} };
      // Suggestions are fetched on their own and must not disturb the capture/export sequence under test.
      if (payload.operation === 'proposals') {
        proposalRequests.push({ payload, process, complete(result) { process.running = false; complete(result); } });
        return process;
      }
      requests.push({ payload, complete(result) { process.running = false; complete(result); } });
      events.push(payload.operation);
      return process;
    } },
    captured(mode, crop) { events.push({ selector: mode, crop }); },
    exported(closeAfter) { events.push({ exported: closeAfter }); },
    picked(token, result) { events.push({ picked: token, result }); },
    pickCancelled(token) { events.push({ pickCancelled: token }); },
  });
  Object.defineProperty(context, 'busy', { get() { return context.phase === 'preparing' || context.worker !== null; } });
  context.root = context;
  vm.runInContext(methods, context, { timeout: 1000 });
  return { context, events, requests, proposalRequests, flush() { while (deferred.length) deferred.shift()(); } };
}
// Objects made inside the vm context have another Object prototype, so they are compared as plain data.
const plain = value => JSON.parse(JSON.stringify(value));
function capturedResult(request) {
  return { ok: true, frames: request.payload.outputs.map((output, index) => ({
    output, session: request.payload.sessions[index], path: '/fake/' + output + '.png', width: 100, height: 80,
  })) };
}

for (const mode of ['edit', 'copy', 'monitor', 'window']) test(`${mode} freezes open menus before dismissal and waits before showing selector`, () => {
  const { context: s, events, requests } = fixture();
  assert.equal(s.open(mode, ''), true);
  assert.deepEqual(events, [mode === 'edit' || mode === 'copy' ? 'capture-all' : 'capture']);
  assert.equal(s.settingsOpen, true, 'settings must remain visible in the source capture');
  assert.equal(s.open('copy', ''), false, 'repeat request must not replace an active capture');
  const request = requests[0];
  request.complete(request.payload.operation === 'capture-all' ? capturedResult(request)
    : { ok: true, path: '/fake/DP-1.png', width: 100, height: 80, session: request.payload.session });
  assert.deepEqual(events.slice(1), ['cancel-navigation', 'close-menus']);
  assert.equal(s.settingsOpen, false);
  assert.equal(s.phase, 'preparing');
  s.onCaptureReady();
  assert.equal(s.phase, 'selecting');
  assert.equal(events.at(-1).selector, mode);
  if (mode === 'monitor') assert.equal(events.at(-1).crop.width, 100);
  const count = events.length;
  s.onCaptureReady();
  assert.equal(events.length, count, 'duplicate readiness must not reopen the selector');
});

test('capture failure leaves open menus intact and permits a fresh request after close', () => {
  const { context: s, events, requests } = fixture();
  s.open('copy', '');
  requests[0].complete({ ok: false, error: 'fake capture failure' });
  assert.equal(s.phase, 'error');
  assert.equal(s.error, 'fake capture failure');
  assert.equal(events.includes('close-menus'), false);
  s.onCaptureReady();
  assert.equal(events.some(event => event.selector), false);
  s.close();
  assert.equal(s.open('copy', ''), true);
});

test('cancelled capture cleans its stale result without dismissing menus or reopening selection', () => {
  const { context: s, events, requests } = fixture();
  s.open('edit', '');
  const request = requests[0];
  s.close();
  request.complete(capturedResult(request));
  s.onCaptureReady();
  assert.equal(s.active, false);
  assert.equal(s.phase, 'idle');
  assert.equal(events.includes('close-menus'), false);
  assert.equal(events.some(event => event.selector), false);
  assert.equal(requests.filter(request => request.payload.operation === 'cleanup').length, 2);
});

test('cancellation while menus dismiss prevents a late ready signal from showing selection', () => {
  const { context: s, events, requests } = fixture();
  s.open('copy', '');
  requests[0].complete(capturedResult(requests[0]));
  s.close();
  s.onCaptureReady();
  assert.equal(s.active, false);
  assert.equal(events.some(event => event.selector), false);
});

test('readiness before capture completion and after a dismissal timeout cannot reveal an overlay', () => {
  const { context: s, events, requests } = fixture();
  s.open('edit', '');
  s.onCaptureReady();
  assert.equal(s.phase, 'preparing');
  requests[0].complete(capturedResult(requests[0]));
  s.fail('Timed out waiting for Pentad menus to close.');
  s.onCaptureReady();
  assert.equal(s.phase, 'error');
  assert.equal(events.some(event => event.selector), false);
});

test('preview, missing outputs and empty capture results never dismiss menus', () => {
  for (const scenario of ['preview', 'no-output', 'empty-result']) {
    const { context: s, events, requests } = fixture();
    if (scenario === 'preview') s.services.preview = true;
    if (scenario === 'no-output') s.Quickshell.screens = [];
    s.open('edit', '');
    if (scenario === 'empty-result') requests[0].complete({ ok: true, frames: [] });
    assert.equal(s.phase, 'error');
    assert.equal(events.includes('close-menus'), false);
    assert.equal(events.some(event => event.selector), false);
  }
});

function quickCopy() {
  const fixtureState = fixture();
  const { context: s, requests } = fixtureState;
  s.open('copy', '');
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  s.overlayVisibility('DP-1', true);
  s.overlayVisibility('DP-2', true);
  s.chooseOutput('DP-1');
  s.overlayVisibility('DP-2', false);
  assert.equal(s.exportImage({ width: 100, height: 80 }, 'copy', true), true);
  return fixtureState;
}

test('quick copy closes, clears its session and restores focus only after all overlays release input', () => {
  const { context: s, requests, events, flush } = quickCopy();
  requests.find(request => request.payload.operation === 'export').complete({ ok: true, copied: true, saved: false });
  assert.equal(s.active, false);
  assert.equal(s.phase, 'idle');
  assert.equal(s.session, '');
  assert.equal(s.worker, null);
  assert.equal(Object.keys(s.frames).length, 0);
  assert.equal(requests.filter(request => request.payload.operation === 'cleanup').length, 2);
  flush();
  assert.equal(events.some(event => event.focus), false);
  s.overlayVisibility('DP-1', false);
  flush();
  const focus = events.filter(event => event.focus);
  assert.equal(focus.length, 1);
  assert.equal(focus[0].focus.instanceId, 'window-a');
  assert.equal(focus[0].forceDispatch, true);
  s.overlayVisibility('DP-1', false);
  flush();
  assert.equal(events.filter(event => event.focus).length, 1);
});

test('copy errors keep the editor recoverable, then retry succeeds and returns focus', () => {
  const { context: s, requests, events, flush } = quickCopy();
  requests.find(request => request.payload.operation === 'export').complete({ ok: false, copied: false, copyError: 'fake clipboard error' });
  flush();
  assert.equal(s.active, true);
  assert.equal(s.phase, 'error');
  assert.equal(s.error, 'fake clipboard error');
  assert.equal(events.some(event => event.focus), false);
  assert.equal(s.exportImage({}, 'copy', true), true);
  requests.filter(request => request.payload.operation === 'export').at(-1).complete({ ok: true, copied: true });
  s.overlayVisibility('DP-1', false);
  flush();
  assert.equal(s.active, false);
  assert.equal(events.filter(event => event.focus).length, 1);
});

for (const changed of ['reopened', 'removed', 'reused-address', 'new-menu', 'preview']) test(`deferred focus return ignores ${changed} sessions or targets`, () => {
  const { context: s, requests, events, flush } = quickCopy();
  requests.find(request => request.payload.operation === 'export').complete({ ok: true, copied: true });
  s.overlayVisibility('DP-1', false);
  if (changed === 'reopened') s.open('edit', '');
  if (changed === 'removed') s.services.hyprland.overviewSnapshot.value.clients = [];
  if (changed === 'reused-address') s.services.hyprland.overviewSnapshot.value.clients[0].instanceId = 'replacement';
  if (changed === 'new-menu') s.services.popups.surface = 'activity';
  if (changed === 'preview') s.services.preview = true;
  flush();
  assert.equal(events.some(event => event.focus), false);
});

test('close releases the active layer state before clearing frame data', () => {
  const { context: s, requests } = quickCopy();
  let frames = s.frames;
  const clearingStates = [];
  Object.defineProperty(s, 'frames', {
    configurable: true,
    get() { return frames; },
    set(value) { if (!Object.keys(value).length) clearingStates.push(s.active); frames = value; },
  });
  requests.find(request => request.payload.operation === 'export').complete({ ok: true, copied: true });
  assert.deepEqual(clearingStates, [false]);
});

test('focus restoration dispatches even when activeToplevel still reports the previous client', () => {
  const source = readFileSync(new URL('../../quickshell/services/Hyprland.qml', import.meta.url), 'utf8');
  const method = source.match(/^    function focusWindow\([^\n]*\) \{.*?^    \}/ms)[0];
  const calls = [];
  const client = { address: '0xa', instanceId: 'window-a' };
  const context = vm.createContext({
    preview: false, safeMode: false,
    overviewSnapshot: { kind: 'ready', value: { activeAddress: client.address } },
    currentOverviewSnapshot() { return context.overviewSnapshot; },
    newRequestId() { return 'request'; },
    findClient() { return client; },
    finish() {},
    dispatch(lua, legacy) { calls.push({ lua, legacy }); },
    addPending() {},
  });
  vm.runInContext(method, context, { timeout: 1000 });
  context.focusWindow(client);
  assert.equal(calls.length, 0, 'normal window focus keeps its current no-op behavior');
  context.focusWindow(client, true);
  assert.equal(calls.length, 1, 'layer focus return must dispatch despite stale activeToplevel');
  assert.equal(calls[0].legacy, 'focuswindow address:0xa');
  context.safeMode = true;
  context.focusWindow(client, true);
  assert.equal(calls.length, 1, 'forced dispatch respects safe mode');
});

test('a menu-focused capture can return to the previous application from MRU', () => {
  const { context: s, events, requests, flush } = fixture();
  s.services.hyprland.overviewSnapshot.value.activeAddress = null;
  s.open('copy', '');
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  s.overlayVisibility('DP-1', true);
  s.close();
  s.overlayVisibility('DP-1', false);
  flush();
  assert.equal(events.filter(event => event.focus).length, 1);
  assert.equal(events.find(event => event.focus).focus.instanceId, 'window-a');
});

test('focus return waits for the last native overlay on another monitor', () => {
  const { context: s, requests, events, flush } = quickCopy();
  s.overlayVisibility('DP-2', true);
  requests.find(request => request.payload.operation === 'export').complete({ ok: true, copied: true });
  s.overlayVisibility('DP-1', false);
  flush();
  assert.equal(events.some(event => event.focus), false);
  s.overlayVisibility('DP-2', false);
  flush();
  assert.equal(events.filter(event => event.focus).length, 1);
});

for (const mode of ['edit', 'monitor']) test(`${mode} window regions use geometry refreshed after the request, not the open-time cache`, () => {
  const { context: s, requests } = fixture();
  const stale = { activeAddress: '0xa', mru: [], clients: [{ address: '0xa', instanceId: 'window-a', width: 640 }] };
  const fresh = { activeAddress: '0xa', mru: [], clients: [{ address: '0xa', instanceId: 'window-a', width: 1269 }] };
  let refreshes = 0;
  s.services.hyprland.overviewSnapshot = { kind: 'ready', value: stale };
  s.services.hyprland.refreshNativeCatalogNow = () => {
    refreshes++;
    s.services.hyprland.overviewSnapshot = { kind: 'ready', value: fresh };
  };
  const seen = [];
  s.Windows.capturedWindowRegions = snapshot => { seen.push(snapshot.clients[0].width); return []; };
  s.open(mode, '');
  assert.equal(refreshes, 1, 'opening a screenshot must request current window geometry');
  const request = requests[0];
  request.complete(request.payload.operation === 'capture-all' ? capturedResult(request)
    : { ok: true, path: '/fake/DP-1.png', width: 100, height: 80, session: request.payload.session });
  assert.ok(seen.length > 0 && seen.every(width => width === 1269), JSON.stringify(seen));
});

test('pick needs a token, captures every monitor and announces itself as a pick', () => {
  const { context: s, events, requests } = fixture();
  assert.equal(s.open('pick', ''), false, 'a pick without a token is refused');
  assert.equal(s.pick('', { label: 'x' }), false);
  assert.equal(s.pick('tool-1', { label: 'Recognize text', scale: 3 }), true);
  assert.equal(s.mode, 'pick');
  assert.equal(s.pickToken, 'tool-1');
  assert.equal(s.pickLabel, 'Recognize text');
  assert.equal(s.pickScale, 3);
  assert.equal(requests[0].payload.operation, 'capture-all');
  assert.equal(s.pick('tool-2', {}), false, 'a second pick cannot replace the active one');
  assert.equal(s.pickToken, 'tool-1');
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  assert.equal(events.at(-1).selector, 'pick');
});

test('an invalid scale falls back to 1 and a refused pick leaves no state behind', () => {
  const { context: s } = fixture();
  s.services.safeMode = true;
  assert.equal(s.pick('tool-1', { scale: 99 }), false);
  assert.equal(s.pickToken, '');
  assert.equal(s.pickScale, 1);
  s.services.safeMode = false;
  assert.equal(s.pick('tool-2', { scale: 99 }), true);
  assert.equal(s.pickScale, 1);
  assert.equal(s.pick('tool-3', { scale: 2.5 }), false);
});

test('choosing an area crops the frozen frame and hands it over with its geometry, then closes', () => {
  const { context: s, events, requests } = fixture();
  s.services.hyprland.overviewSnapshot = { kind: 'ready', value: { clients: [], desktop: { outputs: [
    { id: 'DP-1', name: 'DP-1', x: 1920, y: 0, width: 100, height: 80 }] } } };
  s.pick('tool-1', { scale: 1 });
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  s.chooseOutput('DP-1');
  assert.equal(s.finishPick({ x: 20, y: 10, width: 40, height: 30 }), true);
  assert.equal(s.phase, 'exporting');
  const crop = requests[1];
  assert.equal(crop.payload.operation, 'crop');
  assert.deepEqual(plain(crop.payload.rect), { x: 20, y: 10, width: 40, height: 30 });
  assert.equal(crop.payload.scale, 1);
  assert.equal(s.finishPick({ x: 0, y: 0, width: 5, height: 5 }), false, 'only one crop at a time');
  crop.complete({ ok: true, path: '/run/pentad-pick-' + 'a'.repeat(32) + '.png', width: 40, height: 30, x: 20, y: 10, cropWidth: 40, cropHeight: 30, scale: 1 });
  const done = events.find(event => event.picked);
  assert.equal(done.picked, 'tool-1');
  assert.equal(done.result.path.endsWith('.png'), true);
  assert.deepEqual(plain(done.result.rect), { x: 20, y: 10, width: 40, height: 30 });
  assert.equal(done.result.outputId, 'DP-1');
  assert.deepEqual(plain(done.result.logical), { x: 1940, y: 10, width: 40, height: 30 });
  assert.equal(s.active, false);
  assert.equal(s.phase, 'idle');
  assert.equal(s.pickToken, '');
  assert.equal(events.some(event => event.pickCancelled), false, 'a finished pick is not also cancelled');
});

test('the logical geometry accounts for a scaled monitor and is absent without a layout', () => {
  const { context: s, requests } = fixture();
  s.services.hyprland.overviewSnapshot = { kind: 'ready', value: { clients: [], desktop: { outputs: [
    { id: 'DP-1', name: 'DP-1', x: 100, y: 50, width: 50, height: 40 }] } } };
  s.pick('t', {});
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  s.chooseOutput('DP-1');
  assert.deepEqual(plain(s.logicalRect({ x: 20, y: 10, width: 40, height: 30 })), { x: 110, y: 55, width: 20, height: 15 });
  s.services.hyprland.overviewSnapshot = { kind: 'ready', value: { clients: [] } };
  s.frozenWindowSnapshot = null;
  assert.equal(s.logicalRect({ x: 20, y: 10, width: 40, height: 30 }), null);
});

test('a failed crop shows the error and does not report a pick', () => {
  const { context: s, events, requests } = fixture();
  s.pick('tool-1', {});
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  s.chooseOutput('DP-1');
  s.finishPick({ x: 0, y: 0, width: 10, height: 10 });
  requests[1].complete({ ok: false, error: 'crop is outside screenshot' });
  assert.equal(s.phase, 'error');
  assert.equal(s.error, 'crop is outside screenshot');
  assert.equal(events.some(event => event.picked), false);
  s.close();
  assert.deepEqual(events.filter(event => event.pickCancelled), [{ pickCancelled: 'tool-1' }]);
});

test('closing before choosing cancels the pick exactly once', () => {
  const { context: s, events, requests } = fixture();
  s.pick('tool-1', {});
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  s.close();
  s.close();
  assert.deepEqual(events.filter(event => event.pickCancelled), [{ pickCancelled: 'tool-1' }]);
  assert.equal(s.pickToken, '');
  assert.equal(s.open('copy', ''), true, 'the overlay is free again');
});

test('ordinary screenshots never report picks', () => {
  const { context: s, events, requests } = fixture();
  s.open('edit', '');
  requests[0].complete(capturedResult(requests[0]));
  s.onCaptureReady();
  s.close();
  assert.equal(events.some(event => event.picked || event.pickCancelled), false);
  assert.equal(s.finishPick({ x: 0, y: 0, width: 5, height: 5 }), false);
});

test('suggestions are fetched one monitor at a time without blocking the selection', () => {
  const { context: s, requests, proposalRequests } = fixture();
  s.open('copy', '');
  requests[0].complete(capturedResult(requests[0]));
  assert.equal(proposalRequests.length, 1, 'one request at a time');
  assert.equal(proposalRequests[0].payload.session, requests[0].payload.sessions[0]);
  s.onCaptureReady();
  assert.equal(s.phase, 'selecting');
  assert.equal(s.busy, false, 'analysis must not make the overlay busy');
  assert.equal(s.worker, null);
  // The signal hands arrays over as Qt lists, which are not JS arrays.
  const list = { length: 2, 0: { x: 1, y: 2, width: 30, height: 40, kind: 'image' }, 1: { x: 5, y: 6, width: 7, height: 8, kind: 'text' } };
  proposalRequests[0].complete({ ok: true, regions: list });
  const first = s.frames['DP-1'].contentRegions;
  assert.equal(Array.isArray(first), true);
  assert.deepEqual(plain(first.map(region => region.kind)), ['image', 'text']);
  assert.equal(proposalRequests.length, 2);
  assert.equal(proposalRequests[1].payload.session, requests[0].payload.sessions[1]);
  proposalRequests[1].complete({ ok: true, regions: [] });
  assert.equal(s.frames['DP-2'].contentRegions.length, 0);
  assert.equal(proposalRequests.length, 2);
  assert.equal(s.analysis, null);
});

test('failed or stale suggestions are ignored and do not stop the next monitor', () => {
  const { context: s, requests, proposalRequests } = fixture();
  s.open('edit', '');
  requests[0].complete(capturedResult(requests[0]));
  proposalRequests[0].complete({ ok: false, error: 'boom' });
  assert.equal(s.frames['DP-1'].contentRegions, undefined);
  assert.equal(proposalRequests.length, 2);
  s.close();
  proposalRequests[1].complete({ ok: true, regions: [{ x: 0, y: 0, width: 9, height: 9, kind: 'panel' }] });
  assert.equal(Object.keys(s.frames).length, 0, 'a result arriving after the overlay closed is dropped');
  assert.equal(s.analysisQueue.length, 0);
});

test('closing stops the analysis and forgets the queue', () => {
  const { context: s, requests, proposalRequests } = fixture();
  s.open('edit', '');
  requests[0].complete(capturedResult(requests[0]));
  let signalled = 0;
  proposalRequests[0].process.running = true;
  proposalRequests[0].process.signal = () => { signalled++; };
  s.close();
  assert.equal(signalled, 1);
  assert.equal(s.analysisQueue.length, 0);
});
