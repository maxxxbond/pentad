import assert from 'node:assert/strict';
import test from 'node:test';
import { beginSwitcherSession, stepSwitcherSession, changeSwitcherMode, reconcileSwitcherSession, selectedWindow }
    from '../../quickshell/logic/windowswitcher.mjs';

const clients = ['a', 'b', 'c'].map((id, index) => ({
    address: '0x' + id, instanceId: id + ':1', workspaceId: index === 1 ? '2' : '1',
    monitorId: 'DP-1', title: id, appClass: index === 1 ? 'browser' : 'editor',
    mapped: true, hidden: false, pinned: false,
}));
function snapshot(windows = clients) {
    return { clients: windows, activeAddress: '0xa', desktop: {
        focusedOutputId: '0', outputs: [
            { id: '0', name: 'DP-1', activeWorkspaceId: '1' },
            { id: '1', name: 'HDMI-A-1', activeWorkspaceId: '2' },
        ], workspaces: [{ id: '1', special: false }, { id: '2', special: false }],
    } };
}
function begin(options = {}) {
    return beginSwitcherSession({ id: 1, snapshot: snapshot(), mru: ['a:1', 'b:1', 'c:1'], ...options });
}

test('switcher preserves frozen MRU order, reverse cycling and wraparound', () => {
    const session = begin({ mru: ['gone:1', 'a:1', 'c:1', 'a:1', 'b:1'] });
    assert.deepEqual(session.candidates.map(item => item.address), ['0xa', '0xc', '0xb']);
    assert.equal(selectedWindow(session).address, '0xc');
    assert.equal(selectedWindow(stepSwitcherSession(session, -1)).address, '0xa');
    assert.equal(selectedWindow(stepSwitcherSession(stepSwitcherSession(session, 1), 1)).address, '0xa');
    assert.equal(selectedWindow(begin({ direction: -1 })).address, '0xc');
});

test('switcher anchors application filtering and handles absent anchors and empty desktops', () => {
    assert.deepEqual(begin({ mode: 'application' }).candidates.map(item => item.address), ['0xa', '0xc']);
    assert.equal(selectedWindow(begin({ advance: false })).address, '0xa');
    const noAnchor = { ...snapshot(), activeAddress: null };
    assert.equal(selectedWindow(begin({ snapshot: noAnchor })).address, '0xa');
    assert.equal(selectedWindow(begin({ snapshot: noAnchor, direction: -1 })).address, '0xc');
    assert.equal(selectedWindow(begin({ snapshot: noAnchor, mode: 'application' })), null);
    const empty = begin({ snapshot: snapshot([]) });
    assert.equal(selectedWindow(stepSwitcherSession(empty, 1)), null);
});

test('workspace scope includes pinned windows only on the focused output and excludes hidden windows', () => {
    const windows = clients.concat([
        { ...clients[1], address: '0xd', instanceId: 'd:1', hidden: true, pinned: true },
        { ...clients[1], address: '0xe', instanceId: 'e:1', hidden: true, pinned: true, monitorId: 'HDMI-A-1' },
        { ...clients[0], address: '0xf', instanceId: 'f:1', hidden: true },
        { ...clients[0], address: '0xg', instanceId: 'g:1', mapped: false },
    ]);
    assert.deepEqual(begin({ snapshot: snapshot(windows), scope: 'workspace' }).candidates
        .map(item => item.address), ['0xa', '0xc', '0xd']);
});

test('closing selected window preserves order and never substitutes a recycled address', () => {
    const session = begin();
    const recycled = { ...clients[1], instanceId: 'b:2' };
    const newcomer = { ...clients[0], address: '0xd', instanceId: 'd:1' };
    const next = reconcileSwitcherSession(session, snapshot([clients[0], recycled, clients[2], newcomer]));
    assert.deepEqual(next.candidates.map(item => item.instanceId), ['a:1', 'c:1']);
    assert.equal(selectedWindow(next).address, '0xc');
    assert.equal(selectedWindow(reconcileSwitcherSession(next, snapshot([]))), null);
});

test('mode changes retain the original app and frozen all-window order', () => {
    const terminal = { ...clients[0], appClass: 'terminal' };
    const browser = { ...clients[1], appClass: 'browser' };
    const secondTerminal = { ...clients[2], appClass: 'terminal' };
    const opened = begin({ snapshot: snapshot([terminal, browser, secondTerminal]),
        mru: ['a:1', 'b:1', 'c:1'] });
    assert.equal(selectedWindow(opened).instanceId, 'b:1');
    const sameApp = changeSwitcherMode(opened, 'application');
    assert.deepEqual(sameApp.candidates.map(item => item.instanceId), ['a:1', 'c:1']);
    assert.equal(selectedWindow(sameApp).instanceId, 'a:1');
    const expanded = changeSwitcherMode(sameApp, 'all');
    assert.deepEqual(expanded.candidates.map(item => item.instanceId), ['a:1', 'b:1', 'c:1']);
    const newcomer = { ...browser, address: '0xd', instanceId: 'd:1' };
    const live = reconcileSwitcherSession(expanded, snapshot([terminal, browser, secondTerminal, newcomer]));
    assert.deepEqual(live.candidates.map(item => item.instanceId), ['a:1', 'b:1', 'c:1']);
    assert.equal(selectedWindow(stepSwitcherSession(live, 1)).instanceId, 'b:1');
});

test('hidden special workspaces are excluded using workspace visibility at begin and reconcile', () => {
    const hidden = { ...clients[1], address: '0xd', instanceId: 'd:1', workspaceId: 'special:drawer', hidden: false };
    const visible = { ...clients[2], address: '0xe', instanceId: 'e:1', workspaceId: 'special:game', hidden: false };
    const orphan = { ...clients[2], address: '0xf', instanceId: 'f:1', workspaceId: 'special:missing', hidden: false };
    const desktop = snapshot([clients[0], hidden, visible, orphan]);
    desktop.desktop.workspaces.push(
        { id: 'special:drawer', special: true, active: false },
        { id: 'special:game', special: true, active: true },
    );
    const opened = begin({ snapshot: desktop, mru: ['a:1', 'd:1', 'e:1', 'f:1'] });
    assert.deepEqual(opened.allCandidates.map(item => item.instanceId), ['a:1', 'e:1']);
    const changed = snapshot([clients[0], hidden, visible, orphan,
        { ...clients[1], address: '0xg', instanceId: 'g:1' }]);
    changed.desktop.workspaces.push(
        { id: 'special:drawer', special: true, active: true },
        { id: 'special:game', special: true, active: false },
    );
    const reconciled = reconcileSwitcherSession(opened, changed);
    assert.deepEqual(reconciled.allCandidates.map(item => item.instanceId), ['a:1']);
    assert.equal(selectedWindow(reconciled).instanceId, 'a:1');
});
