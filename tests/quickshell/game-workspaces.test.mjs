import assert from 'node:assert/strict';
import test from 'node:test';
import {
    createGameWorkspaceCoordinator,
    createGameWorkspaceIpcPort,
    isRecognizedGameClass,
} from '../../quickshell/logic/game-workspaces.mjs';

const desktop = (activeWorkspaceId, focusedOutputId = '0') => ({
    outputs: [
        { id: '0', name: 'DP-1', activeWorkspaceId },
        { id: '1', name: 'HDMI-A-1', activeWorkspaceId: '2' },
    ],
    workspaces: [
        { id: '1', name: '1', monitor: 'DP-1', special: false, active: activeWorkspaceId === '1' },
        { id: '2', name: '2', monitor: 'HDMI-A-1', special: false, active: true },
        ...(activeWorkspaceId === '9000' ? [{ id: '9000', name: '9000', monitor: 'DP-1', special: false, active: true }] : []),
    ],
    focusedOutputId,
});

const client = (overrides = {}) => Object.assign({
    address: '0x1234', workspaceId: '1', monitorId: 'DP-1', title: 'Counter-Strike 2',
    appClass: 'cs2', width: 2560, height: 1440, mapped: true, hidden: false, pinned: false,
    floating: false, fullscreen: true,
}, overrides);

const snapshot = (activeWorkspaceId, clients, activeAddress, focusedOutputId = '0') => ({
    revision: 1, desktop: desktop(activeWorkspaceId, focusedOutputId), clients, activeAddress,
});

const flush = async () => { await new Promise(resolve => setTimeout(resolve, 0)); await new Promise(resolve => setTimeout(resolve, 0)); };

test('recognizes supported game classes and Steam app classes only', () => {
    assert.equal(isRecognizedGameClass('  Dota 2 '), true);
    assert.equal(isRecognizedGameClass('steam_app_730'), true);
    assert.equal(isRecognizedGameClass('steam_app_'), false);
    assert.equal(isRecognizedGameClass('firefox'), false);
});

test('IPC port sends the window move and best-effort monitor placement in both modes', async () => {
    for (const mode of ['lua', 'legacy']) {
        const dispatched = [];
        const port = createGameWorkspaceIpcPort(async (lua, legacy) => {
            dispatched.push(mode === 'lua' ? lua : legacy);
            return true;
        }, async () => mode);
        assert.equal(await port.moveWindow('0x1234', '9000', 'DP-1', true), true);
        assert.deepEqual(dispatched, mode === 'lua' ? [
            'hl.dsp.window.move({ window = "address:0x1234", workspace = "9000", follow = true })',
            'hl.dsp.workspace.move({ workspace = "9000", monitor = "DP-1" })',
        ] : ['movetoworkspace 9000,address:0x1234', 'moveworkspacetomonitor 9000 DP-1']);
    }
});

test('IPC port validates identifiers and retains a successful move if placement fails', async () => {
    let attempts = 0;
    const port = createGameWorkspaceIpcPort(async () => ++attempts === 1, async () => 'lua');
    assert.equal(await port.moveWindow('bad address', '9000', 'DP-1', false), false);
    assert.equal(await port.moveWindow('0x1234', '0', 'DP-1', false), false);
    assert.equal(attempts, 0);
    assert.equal(await port.moveWindow('0x1234', '9000', 'DP-1', false), true);
    assert.equal(attempts, 2);
});

test('routes fullscreen games to unused workspaces and restores the source workspace on close', async () => {
    const commands = [];
    const coordinator = createGameWorkspaceCoordinator({
        moveWindow: async (address, workspace, monitor, follow) => (commands.push(`move ${workspace} ${monitor} ${address} follow:${follow}`), true),
        activateWorkspace: async (workspace, monitor) => (commands.push(`activate ${workspace} ${monitor}`), true),
    }, () => {});
    coordinator.update(snapshot('1', [client()], '0x1234'));
    await flush();
    assert.deepEqual(commands, ['move 9000 DP-1 0x1234 follow:true']);
    coordinator.update(snapshot('9000', [client({ workspaceId: '9000' })], '0x1234'));
    coordinator.update(snapshot('9000', [], null));
    await flush();
    assert.equal(commands.at(-1), 'activate 1 DP-1');
    coordinator.dispose();
});

test('allocates distinct IDs, retries failed moves, and does not reclaim manual moves', async () => {
    const commands = [];
    let failFirst = true;
    const coordinator = createGameWorkspaceCoordinator({
        moveWindow: async (address, workspace) => {
            commands.push(`${address}:${workspace}`);
            if (failFirst) { failFirst = false; return false; }
            return true;
        },
        activateWorkspace: async () => true,
    }, () => {});
    const first = client({ instanceId: 'first' });
    const second = client({ address: '0xbeef', instanceId: 'second', appClass: 'steam_app_730' });
    coordinator.update(snapshot('1', [first, second], '0x1234'));
    await flush();
    assert.deepEqual(commands, ['0x1234:9000', '0xbeef:9001']);
    coordinator.update(snapshot('1', [first, second], '0x1234'));
    await flush();
    assert.deepEqual(commands, ['0x1234:9000', '0xbeef:9001', '0x1234:9002']);
    coordinator.update(snapshot('3', [client({ instanceId: 'second', address: '0xbeef', workspaceId: '3' })], '0xbeef'));
    coordinator.update(snapshot('3', [client({ instanceId: 'second', address: '0xbeef', workspaceId: '3' })], '0xbeef'));
    await flush();
    assert.equal(commands.length, 3);
    coordinator.dispose();
});

test('publishes fullscreen outputs and guards focus restoration after user navigation', async () => {
    const published = [];
    const commands = [];
    const coordinator = createGameWorkspaceCoordinator({
        moveWindow: async () => (commands.push('move'), true),
        activateWorkspace: async () => (commands.push('activate'), true),
    }, outputs => published.push(new Set(outputs)));
    coordinator.update(snapshot('1', [client()], '0x1234'));
    assert.deepEqual(published.at(-1), new Set(['DP-1']));
    await flush();
    coordinator.update(snapshot('9000', [client({ workspaceId: '9000' })], '0x1234'));
    coordinator.update(snapshot('9000', [], null, '1'));
    await flush();
    assert.deepEqual(commands, ['move']);
    coordinator.update(snapshot('1', [client({ appClass: 'firefox' })], '0x1234'));
    assert.deepEqual(published.at(-1), new Set());
    coordinator.dispose();
});
