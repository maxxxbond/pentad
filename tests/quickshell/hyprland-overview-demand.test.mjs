import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as Overview from '../../quickshell/logic/overview.mjs';
import * as OverviewLayout from '../../quickshell/logic/overview-layout.mjs';
import * as HyprlandPreview from '../../quickshell/logic/hyprland-preview.mjs';

const source = readFileSync(new URL('../../quickshell/services/Hyprland.qml', import.meta.url), 'utf8');
const methods = [...source.matchAll(/^    function \w+\([^\n]*\) \{.*?^    \}/gms)].map(match => match[0]).join('\n');
const rawEventHandler = source.match(/^        function onRawEvent\(event\) \{.*?^        \}/ms)[0];

function nativeDesktop() {
  const monitor = { id: 0, name: 'DP-1', scale: 1, width: 1920, height: 1080, x: 0, y: 0,
    lastIpcObject: { reserved: [0, 0, 0, 0], transform: 0 } };
  const workspace = { id: 1, name: '1', monitor, active: true, toplevels: { values: [] } };
  monitor.activeWorkspace = workspace;
  const window = (address, x) => ({ address, title: address, workspace, monitor,
    lastIpcObject: { class: 'editor', at: [x, 40], size: [800, 600], mapped: true } });
  const toplevels = [window('0xa', 0), window('0xb', 900)];
  workspace.toplevels.values = toplevels;
  const counts = { monitors: 0, workspaces: 0, toplevels: 0 };
  const hyprland = {
    monitors: { values: [monitor] }, workspaces: { values: [workspace] }, toplevels: { values: toplevels },
    focusedMonitor: monitor, activeToplevel: toplevels[0],
    refreshMonitors() { counts.monitors++; }, refreshWorkspaces() { counts.workspaces++; },
    refreshToplevels() { counts.toplevels++; },
  };
  return { hyprland, workspace, window, counts };
}

function fixture() {
  const native = nativeDesktop();
  const deferred = [];
  const timer = () => ({ running: false, restart() { this.running = true; }, start() { this.running = true; },
    stop() { this.running = false; } });
  const c = vm.createContext({
    Overview, OverviewLayout, HyprlandPreview, Hyprland: native.hyprland,
    Qt: { callLater(callback) { deferred.push(callback); } },
    preview: false, safeMode: false, serial: 0, overviewDemanded: false,
    identityTracker: Overview.createOverviewIdentityTracker(128),
    overviewCache: { dirty: true, state: null, revision: 0, publishQueued: false,
      identityQueued: false, identities: { byAddress: {}, mru: [] }, lastActiveInstanceId: '' },
    pendingCommands: [], settleRefreshesLeft: 0, settleSignature: null, placementRun: null,
    nativeRefreshTimer: timer(), settleRefreshTimer: timer(),
  });
  c.root = c;
  vm.runInContext(methods, c, { timeout: 1000 });
  c.nativeOverviewState = c.unavailableOverviewSnapshot();
  // The QML bindings: `snapshot` follows the native model, `overviewSnapshot` the published state.
  Object.defineProperty(c, 'snapshot', { get() { return c.nativeDesktopSnapshot(); } });
  Object.defineProperty(c, 'overviewSnapshot', { get() { return c.nativeOverviewState; } });
  const stats = { builds: 0, identitySyncs: 0, publishes: 0 };
  const build = c.buildNativeOverviewSnapshot;
  c.buildNativeOverviewSnapshot = (...args) => { stats.builds++; return build(...args); };
  const sync = c.refreshNativeIdentities;
  c.refreshNativeIdentities = (...args) => { stats.identitySyncs++; return sync(...args); };
  const handler = vm.runInContext(`(${rawEventHandler.replace(/^\s*function onRawEvent/, 'function')})`, c);
  return {
    c, native, stats,
    raw(name) { handler({ name }); },
    flush() {
      while (deferred.length) deferred.shift()();
    },
    publishCount() {
      let last = c.nativeOverviewState;
      let count = 0;
      Object.defineProperty(c, 'nativeOverviewState', { configurable: true,
        get() { return last; }, set(value) { count++; last = value; } });
      return () => count;
    },
  };
}

test('a burst of raw events resyncs identities once and builds nothing without demand', () => {
  const { c, stats, raw, flush } = fixture();
  for (const name of ['activewindow', 'activewindowv2', 'workspacev2', 'focusedmon', 'openlayer'])
    raw(name);
  assert.equal(stats.identitySyncs, 0, 'identity sync is deferred to the end of the turn');
  flush();
  assert.equal(stats.identitySyncs, 1);
  assert.equal(stats.builds, 0, 'nobody asked for the overview model');
  assert.equal(c.overviewCache.dirty, true);
});

test('title-only events skip identity sync but still invalidate the overview model', () => {
  const { c, stats, raw, flush } = fixture();
  const first = c.currentOverviewSnapshot();
  const syncsBefore = stats.identitySyncs;
  for (const name of ['windowtitle', 'windowtitlev2', 'windowtitlev2', 'urgent'])
    raw(name);
  flush();
  assert.equal(stats.identitySyncs, syncsBefore);
  assert.equal(c.overviewCache.identityQueued, false);
  c.Hyprland.toplevels.values[1].title = 'renamed';
  const second = c.currentOverviewSnapshot();
  assert.notEqual(second, first);
  assert.equal(second.value.clients.find(client => client.address === '0xb').title, 'renamed');
});

test('the on-demand accessor builds once per change and keeps stable instance ids', () => {
  const { c, stats } = fixture();
  const first = c.currentOverviewSnapshot();
  assert.equal(first.kind, 'ready');
  assert.equal(stats.builds, 1);
  assert.equal(c.currentOverviewSnapshot(), first, 'unchanged model is served from cache');
  assert.equal(stats.builds, 1);
  const ids = first.value.clients.map(client => client.instanceId);
  assert.ok(ids.every(Boolean));
  assert.equal(first.value.mru[0], ids[0], 'the active window leads the MRU');
  c.invalidateOverview();
  const second = c.currentOverviewSnapshot();
  assert.equal(stats.builds, 2);
  assert.deepEqual(second.value.clients.map(client => client.instanceId), ids);
  assert.ok(second.value.revision > first.value.revision);
});

test('a window that appeared before its identity sync ran still gets an instance id', () => {
  const { c, native } = fixture();
  c.currentOverviewSnapshot();
  const added = native.window('0xc', 1800);
  native.workspace.toplevels.values = native.workspace.toplevels.values.concat([added]);
  native.hyprland.toplevels.values = native.workspace.toplevels.values;
  c.invalidateOverview();
  const snapshot = c.currentOverviewSnapshot();
  const client = snapshot.value.clients.find(item => item.address === '0xc');
  assert.ok(client && client.instanceId, 'missing identity is synced before the build');
});

test('with demand, a burst publishes one fresh snapshot per turn', () => {
  const { c, stats, raw, flush, publishCount } = fixture();
  const publishes = publishCount();
  c.overviewDemanded = true;
  for (let i = 0; i < 20; i++) raw(i % 2 ? 'windowtitlev2' : 'activewindowv2');
  assert.equal(publishes(), 0, 'publishing waits for the end of the turn');
  flush();
  assert.equal(publishes(), 1);
  assert.equal(stats.builds, 1);
  assert.equal(c.overviewSnapshot.kind, 'ready');
  flush();
  assert.equal(publishes(), 1, 'no change, no republish');
  c.overviewDemanded = false;
  raw('activewindowv2');
  flush();
  assert.equal(publishes(), 1, 'released demand stops publishing');
  assert.equal(stats.builds, 1);
});

test('without outputs the overview is unavailable', () => {
  const { c } = fixture();
  c.Hyprland.monitors.values = [];
  c.invalidateOverview();
  assert.deepEqual({ ...c.currentOverviewSnapshot() }, { kind: 'unavailable', reason: 'disconnected' });
});

test('geometry settle stops once two consecutive reads agree', () => {
  const { c, native } = fixture();
  c.refreshNavigationCatalog();
  assert.equal(c.settleRefreshesLeft, 3);
  c.refreshNativeCatalogNow();
  c.settleRefreshTick();
  c.settleRefreshTick();
  assert.equal(c.settleRefreshTimer.running, false);
  assert.equal(native.counts.toplevels, 2, 'the first read plus one confirming read');
});

test('geometry settle keeps re-reading while the layout still moves, up to three rounds', () => {
  const { c, native } = fixture();
  c.refreshNavigationCatalog();
  c.refreshNativeCatalogNow();
  for (let round = 0; round < 5; round++) {
    native.hyprland.toplevels.values[0].lastIpcObject = { ...native.hyprland.toplevels.values[0].lastIpcObject,
      at: [round * 10, 40] };
    c.settleRefreshTick();
  }
  assert.equal(native.counts.toplevels, 4, 'never more rounds than before');
  assert.equal(c.settleRefreshTimer.running, false);
});

test('a new geometry event restarts the settle comparison', () => {
  const { c } = fixture();
  c.refreshNavigationCatalog();
  c.settleRefreshTick();
  assert.notEqual(c.settleSignature, null);
  c.refreshNavigationCatalog();
  assert.equal(c.settleSignature, null);
  assert.equal(c.settleRefreshesLeft, 3);
});

test('layout signatures ignore titles and see geometry, workspace and output changes', () => {
  const rows = [{ address: '0xa', workspace: { id: '1' }, monitor: 'DP-1', at: [0, 0], size: [10, 10], title: 'a' }];
  const outputs = [{ id: '0', x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0,
    reserved: [0, 40, 0, 0], activeWorkspaceId: '1' }];
  const base = Overview.nativeLayoutSignature(rows, outputs);
  assert.equal(Overview.nativeLayoutSignature([{ ...rows[0], title: 'b' }], outputs), base);
  assert.notEqual(Overview.nativeLayoutSignature([{ ...rows[0], at: [1, 0] }], outputs), base);
  assert.notEqual(Overview.nativeLayoutSignature([{ ...rows[0], workspace: { id: '2' } }], outputs), base);
  assert.notEqual(Overview.nativeLayoutSignature(rows, [{ ...outputs[0], reserved: [0, 0, 0, 0] }]), base);
  assert.equal(Overview.nativeLayoutSignature(null, undefined), '[[],[]]');
});

test('only title-like events are identity neutral', () => {
  for (const name of ['windowtitle', 'windowtitlev2', 'urgent', 'activelayout', 'submap', 'bell'])
    assert.equal(Overview.nativeIdentityEvent(name), false, name);
  for (const name of ['openwindow', 'closewindow', 'activewindow', 'activewindowv2', 'movewindowv2',
    'monitorremoved', 'workspacev2', '', undefined])
    assert.equal(Overview.nativeIdentityEvent(name), true, String(name));
});
