import test from 'node:test';
import assert from 'node:assert/strict';
import { dropPlacement, projectWindow, unprojectPoint } from '../../quickshell/logic/overview-layout.mjs';
import { placementPlan } from '../../quickshell/logic/overview.mjs';

const workarea = { x: 1920, y: 40, width: 1920, height: 1040 };
const tile = { width: 384, height: 208 };
const client = (address, x, y, width, height, extra = {}) => ({ address, workspaceId: '4', x, y, width, height,
    mapped: true, hidden: false, floating: false, fullscreen: false, ...extra });
const left = client('0xa', 1920, 40, 960, 1040);
const right = client('0xb', 2880, 40, 960, 1040);
const moved = client('0xc', 0, 40, 1920, 1040, { workspaceId: '1' });

test('a drop point in a card maps back to the workspace it shows', () => {
    const rect = projectWindow(right, workarea, tile);
    const point = unprojectPoint({ x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 }, workarea, tile);
    assert.ok(Math.abs(point.x - (right.x + right.width / 2)) < 6 && Math.abs(point.y - (right.y + right.height / 2)) < 6);
    assert.deepEqual(unprojectPoint({ x: -50, y: 999 }, workarea, tile), { x: 1920, y: 1080 });
    assert.equal(unprojectPoint({ x: 1, y: 1 }, workarea, { width: 0, height: 10 }), null);
});

test('the dropped window lands beside the window under the point, on the nearer side', () => {
    const clients = [left, right, moved];
    assert.deepEqual(dropPlacement(clients, '0xc', '4', { x: 2000, y: 560 }), { target: '0xa', direction: 'l' });
    assert.deepEqual(dropPlacement(clients, '0xc', '4', { x: 2800, y: 560 }), { target: '0xa', direction: 'r' });
    assert.deepEqual(dropPlacement(clients, '0xc', '4', { x: 3360, y: 60 }), { target: '0xb', direction: 'u' });
    assert.deepEqual(dropPlacement(clients, '0xc', '4', { x: 3360, y: 1060 }), { target: '0xb', direction: 'd' });
    assert.equal(dropPlacement([moved], '0xc', '4', { x: 2000, y: 500 }), null);
    assert.equal(dropPlacement([client('0xf', 1920, 40, 400, 300, { floating: true })], '0xc', '4', { x: 2000, y: 100 }), null);
});

test('placement focuses the neighbour, then gives back the monitor workspace and the original focus', () => {
    const snapshot = {
        activeAddress: '0xd',
        clients: [left, right, moved, client('0xd', 0, 40, 100, 100, { workspaceId: '1' })],
        desktop: {
            focusedOutputId: '0',
            outputs: [{ id: '0', name: 'DP-1', activeWorkspaceId: '1' }, { id: '1', name: 'HDMI-A-1', activeWorkspaceId: '6' }],
            workspaces: [{ id: '1', monitor: 'DP-1' }, { id: '4', monitor: 'HDMI-A-1' }, { id: '6', monitor: 'HDMI-A-1' }],
        },
    };
    assert.deepEqual(placementPlan(snapshot, moved, '4', { target: '0xb', direction: 'r' }), {
        target: '0xb', direction: 'r', restoreWorkspaceId: '6', restoreFocusAddress: '0xd', restoreFocusWorkspaceId: '',
    });
    const selfActive = Object.assign({}, snapshot, { activeAddress: '0xc' });
    assert.deepEqual(placementPlan(selfActive, moved, '4', { target: '0xa', direction: 'l' }).restoreFocusWorkspaceId, '1');
    assert.equal(placementPlan(snapshot, Object.assign({}, moved, { floating: true }), '4', { target: '0xa', direction: 'l' }), null);
    assert.equal(placementPlan(snapshot, moved, '4', { target: '0xa', direction: 'x' }), null);
    assert.equal(placementPlan(snapshot, moved, '9', { target: '0xa', direction: 'l' }), null);
    assert.equal(placementPlan(snapshot, moved, '4', { target: '0xd', direction: 'l' }), null);
});
