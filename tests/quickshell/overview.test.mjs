import assert from 'node:assert/strict';
import test from 'node:test';
import {
    canMoveClient,
    captureHandle,
    confirmOverviewCommand,
    createOverviewIdentityTracker,
    findWorkspace,
    groupOverview,
    nativeSequenceToArray,
    normalizeOverviewClients,
    workspaceSelector,
} from '../../quickshell/logic/overview.mjs';
import { fitPreview, workspaceColumns } from '../../quickshell/logic/overview-layout.mjs';

const desktop = {
    outputs: [
        { id: '0', name: 'DP-1', activeWorkspaceId: '1' },
        { id: '1', name: 'HDMI-A-1', activeWorkspaceId: 'Web' },
    ],
    workspaces: [
        { id: '1', name: '1', monitor: 'DP-1', special: false, active: true },
        { id: '2', name: '2', monitor: 'DP-1', special: false, active: false },
        { id: '-99', name: 'special:scratch', monitor: 'DP-1', special: true, active: false },
        { id: '22', name: 'Web', monitor: 'HDMI-A-1', special: false, active: true },
        { id: '77', name: 'lost', monitor: '', special: false, active: false },
    ],
    focusedOutputId: '0',
};

test('normalizes valid client metadata, resolving monitor indexes and clamping dimensions', () => {
    const clients = normalizeOverviewClients([
        { address: '0xabc', workspace: { id: 1 }, monitor: 0, title: ' Browser ', class: 'browser', appId: ' browser.desktop ', at: [-1920, 24], size: [40000.8, 720], fullscreen: 2, group: ['0xdef', 7] },
        { address: '0xdef', workspace: { id: 2 }, mapped: false },
        { address: 'bad', workspace: { id: 1 } },
        { address: '0x123', workspace: {}, title: 'orphan' },
        { address: '0x456', workspace: { id: 'Web' }, class: 'editor', pinned: true },
        { address: '0xabc', workspace: { id: 9 }, title: 'duplicate' },
    ], desktop.outputs);
    assert.equal(clients.length, 2);
    assert.deepEqual(clients[0], {
        address: '0xabc', appId: 'browser.desktop', workspaceId: '1', monitorId: 'DP-1',
        title: 'Browser', appClass: 'browser', x: -1920, y: 24, width: 32768, height: 720, mapped: true, hidden: false,
        pinned: false, floating: false, fullscreen: true, grouped: ['0xdef'],
    });
    assert.deepEqual(clients[1], {
        address: '0x456', appId: '', workspaceId: 'Web', monitorId: '',
        title: 'editor', appClass: 'editor', x: 0, y: 0, width: 0, height: 0, mapped: true, hidden: false,
        pinned: true, floating: false, fullscreen: false, grouped: [],
    });
});

test('uses optional label fallbacks and preserves fullscreen/grouped normalization', () => {
    const [fallback, custom] = normalizeOverviewClients([
        { address: '0xa', workspace: { id: '1' } },
        { address: '0xb', workspace: { id: '1' }, fullscreenClient: true, grouped: null, group: ['0xc'] },
    ]);
    assert.equal(fallback.title, 'Untitled');
    assert.equal(custom.title, 'Untitled');
    assert.equal(custom.fullscreen, true);
    assert.deepEqual(custom.grouped, ['0xc']);
    assert.equal(normalizeOverviewClients([{ address: '0xa', workspace: { id: 1 } }], [], { untitled: 'Без назви' })[0].title, 'Без назви');
    assert.equal(groupOverview({ desktop: { workspaces: [{ id: '1', name: '1', monitor: '', special: false }] }, clients: [] }, { noMonitor: 'Без монітора' })[0].outputName, 'Без монітора');
    assert.equal(groupOverview({ desktop: { workspaces: [{ id: '1', name: '1', monitor: '', special: false }] }, clients: [] })[0].outputName, 'No monitor');
});

test('keeps clients with missing or invalid coordinates and never invents a lifetime identity', () => {
    const clients = normalizeOverviewClients([
        { address: '0xabc', workspace: { id: 1 }, at: [-1920, 24], size: [800, 600] },
        { address: '0xdef', workspace: { id: 1 }, at: [Number.NaN, 'bad'], size: [800, 600] },
    ]);
    assert.deepEqual(clients.map(({ x, y }) => [x, y]), [[-1920, 24], [0, 0]]);
    assert.equal(Object.hasOwn(clients[0], 'instanceId'), false);
});

test('copies QML QVariantList-style sequences before applying plain-data normalization', () => {
    const qmlSequence = { 0: -1920, 1: 24, length: 2,
        toString: () => '[object V4Sequence]' };
    const copied = nativeSequenceToArray(qmlSequence);
    assert.deepEqual(copied, [-1920, 24]);
    assert.notEqual(copied, qmlSequence);
    assert.deepEqual(nativeSequenceToArray([800, 600]), [800, 600]);
    assert.deepEqual(nativeSequenceToArray({ length: 5000 }), []);
    assert.deepEqual(normalizeOverviewClients([
        { address: '0xabc', workspace: { id: '1' }, at: copied, size: nativeSequenceToArray({ 0: 800, 1: 600, length: 2 }) },
    ])[0], {
        address: '0xabc', appId: '', workspaceId: '1', monitorId: '', title: 'Untitled', appClass: '',
        x: -1920, y: 24, width: 800, height: 600, mapped: true, hidden: false, pinned: false,
        floating: false, fullscreen: false, grouped: [],
    });
});

test('validates capture handles and workspace selectors, including special and named workspaces', () => {
    assert.equal(captureHandle('0xffffffff'), 4294967295);
    assert.equal(captureHandle('0x100000000'), null);
    assert.equal(captureHandle('0x0'), null);
    assert.equal(captureHandle('0xg1'), null);
    assert.equal(workspaceSelector(desktop.workspaces[0]), '1');
    assert.equal(workspaceSelector(desktop.workspaces[2]), 'special:scratch');
    assert.equal(workspaceSelector({ id: '0', name: 'Web', special: false }), 'name:Web');
    assert.equal(workspaceSelector({ id: '2147483648', name: 'Big', special: false }), 'name:Big');
    assert.equal(workspaceSelector({ id: '-1', name: 'special:bad,selector', special: true }), null);
    assert.equal(workspaceSelector({ id: '0', name: 'bad\nname', special: false }), null);
});

test('groups clients by sorted workspace, excluding pinned clients and allowing only ungrouped moves', () => {
    const clients = normalizeOverviewClients([
        { address: '0x1', workspace: { id: '1' }, title: 'One' },
        { address: '0x2', workspace: { id: '22' }, title: 'Two' },
        { address: '0x3', workspace: { id: '1' }, pinned: true },
        { address: '0x4', workspace: { id: '1' }, group: ['0x5'] },
    ]);
    const groups = groupOverview({ revision: 1, desktop, clients, activeAddress: '0x1' });
    assert.deepEqual(groups.map(group => group.workspace.id), ['77', '1', '2', '-99', '22']);
    assert.deepEqual(groups.find(group => group.workspace.id === '1').clients.map(client => client.address), ['0x1', '0x4']);
    assert.equal(groups.find(group => group.workspace.id === '22').outputName, 'HDMI-A-1');
    assert.equal(canMoveClient(clients[0]), true);
    assert.equal(canMoveClient(clients[2]), false);
    assert.equal(canMoveClient(clients[3]), false);
    assert.equal(findWorkspace(desktop.workspaces, '22'), desktop.workspaces[3]);
    assert.equal(findWorkspace(desktop.workspaces, 'missing'), undefined);
});

test('clamps workspace columns and fits preview dimensions without changing aspect ratio', () => {
    assert.equal(workspaceColumns(0), 1);
    assert.equal(workspaceColumns(630), 2);
    assert.equal(workspaceColumns(1600), 3);
    assert.equal(workspaceColumns(Number.NaN), 1);
    assert.deepEqual(fitPreview(1600, 900, 320, 200), { width: 320, height: 180 });
    assert.deepEqual(fitPreview(0, 900, 320, 200), { width: 320, height: 200 });
    assert.deepEqual(fitPreview(1600, 900, 0, 200), { width: 1, height: 200 });
});

test('tracks stable window lifetimes, activation MRU, address reuse, and closed-window pruning', () => {
    const tracker = createOverviewIdentityTracker(2);
    const firstWindow = {};
    const secondWindow = {};
    const initial = tracker.sync([firstWindow, secondWindow], ['0xabc', '0xdef']);
    const firstId = initial.instanceIds[0];
    const secondId = initial.instanceIds[1];
    assert.notEqual(firstId, secondId);
    assert.deepEqual(tracker.activate('0xabc'), [firstId]);

    const reordered = tracker.sync([secondWindow, firstWindow], ['0xdef', '0xabc']);
    assert.deepEqual(reordered.instanceIds, [secondId, firstId]);
    assert.deepEqual(reordered.mru, [firstId]);
    assert.deepEqual(tracker.activate('0xdef'), [secondId, firstId]);

    const replacement = {};
    const recycled = tracker.sync([secondWindow, replacement], ['0xdef', '0xabc']);
    assert.notEqual(recycled.instanceIds[1], firstId);
    assert.deepEqual(recycled.mru, [secondId]);
    assert.deepEqual(tracker.activate('0xabc'), [recycled.instanceIds[1], secondId]);
    assert.deepEqual(tracker.sync([replacement], ['0xabc']).mru, [recycled.instanceIds[1]]);
});

test('confirms navigation requests only from matching fresh identity and destination snapshots', () => {
    const client = { address: '0xabc', instanceId: 'life:1', workspaceId: '1' };
    const snapshot = { clients: [client], activeAddress: null };
    const ref = { address: client.address, instanceId: client.instanceId };
    const focus = { kind: 'focus', ref, deadline: 1000 };
    assert.deepEqual(confirmOverviewCommand({ ...focus, ref: { ...ref, instanceId: 'life:old' } }, snapshot, null, 100),
        { ok: false, reason: 'device-removed' });
    assert.equal(confirmOverviewCommand(focus, snapshot, null, 100), null);
    assert.deepEqual(confirmOverviewCommand(focus, { ...snapshot, activeAddress: client.address }, null, 110),
        { ok: true });
    assert.deepEqual(confirmOverviewCommand(focus, snapshot, null, 1000),
        { ok: false, reason: 'timeout' });
    assert.deepEqual(confirmOverviewCommand({ kind: 'move', ref, destinationId: '2', deadline: 1000 },
        { ...snapshot, clients: [{ ...client, workspaceId: '2' }] }, null, 100), { ok: true });
    assert.deepEqual(confirmOverviewCommand({ kind: 'workspace', destinationId: '22' }, snapshot, '22', 100),
        { ok: true });
});
