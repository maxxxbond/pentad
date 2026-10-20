import QtQuick
import Quickshell
import '../logic/windowswitcher.mjs' as Switcher
import '../logic/overview.mjs' as Overview
import '../logic/overview-layout.mjs' as OverviewLayout
import "../services" as Services

ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property var calls: []
    property QtObject fakeSource: QtObject {
        property var overviewSnapshot: ({ kind: 'ready', value: ({
            revision: 1, clients: ['a', 'b', 'c'].map(function(id) {
                return { address: '0x' + id, instanceId: id + ':1', appClass: 'editor',
                    mapped: true, hidden: false, pinned: false, grouped: [], workspaceId: '1', monitorId: 'fixture' };
            }), activeAddress: '0xa', mru: ['a:1', 'b:1', 'c:1'],
            desktop: { focusedOutputId: '0', outputs: [{ id: '0', name: 'fixture', activeWorkspaceId: '1' }],
                workspaces: [{ id: '1', name: '1', special: false }] }
        }) })
        signal commandFinished(string requestId, var result)
        function focusWindow(ref) { root.calls = root.calls.concat([{ kind: 'focus', ref: ref }]); return 'focus-' + root.calls.length; }
        function moveWindow(ref, destination) { root.calls = root.calls.concat([{ kind: 'move', ref: ref, destination: destination }]); return 'move-' + root.calls.length; }
        function activateOverviewWorkspace(id) { root.calls = root.calls.concat([{ kind: 'workspace', id: id }]); return 'workspace-' + root.calls.length; }
    }
    property QtObject fakePopups: QtObject {
        property string surface: ''
        signal changed()
        function close() { surface = ''; changed(); }
    }
    property QtObject fakeServices: QtObject {
        property var hyprland: root.fakeSource
        property var popups: root.fakePopups
        property bool workspaceHeld: false
        property bool preview: false
        property bool safeMode: false
    }
    property Services.WindowNavigation navigation: Services.WindowNavigation { services: root.fakeServices }
    function complete() {
        console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.every(function(check) { return check.passed; })
            ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
    Timer {
        id: sequenceTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (root.phase === 1) {
                root.navigation.modifier('Alt_L', false);
                root.checks.push({ name: 'quick-tap-focuses-once-before-reveal', passed:
                    root.calls.length === 1 && root.calls[0].kind === 'focus' && !root.navigation.visible });
                root.phase = 2;
                root.navigation.modifier('Alt_L', true);
                root.navigation.beginSwitcher('all', 1);
                interval = 100;
                restart();
            } else if (root.phase === 2) {
                root.checks.push({ name: 'hold-reveals-without-focus', passed:
                    root.navigation.revealed && root.calls.length === 1 });
                root.navigation.modifier('Alt_R', true);
                root.navigation.modifier('Alt_L', false);
                root.checks.push({ name: 'one-of-two-alt-releases-does-not-commit', passed:
                    root.navigation.active && root.calls.length === 1 });
                root.navigation.modifier('Alt_R', false);
                root.checks.push({ name: 'last-alt-release-commits-once', passed:
                    !root.navigation.active && root.calls.length === 2 });
                root.navigation.modifier('Alt_L', true);
                root.navigation.beginSwitcher('all', 1);
                root.navigation.dismissTop();
                root.navigation.modifier('Alt_L', false);
                root.checks.push({ name: 'escape-cancels-without-focus', passed: root.calls.length === 2 });
                root.navigation.modifier('Super_L', true);
                root.navigation.openOverview();
                root.navigation.cancel();
                root.navigation.modifier('Super_L', false);
                root.checks.push({ name: 'super-state-survives-modal-close', passed:
                    !root.fakeServices.workspaceHeld && !root.navigation.suppressWorkspaceExpansion });
                root.navigation.modifier('Super_L', true);
                root.navigation.modifier('Super_L', false);
                root.checks.push({ name: 'quick-super-tap-opens-search', passed: root.navigation.bareSuperTap() });
                root.navigation.modifier('Super_L', true);
                root.navigation._superPressedAt = Date.now() - root.navigation.superTapMs - 1;
                root.navigation.modifier('Super_L', false);
                root.checks.push({ name: 'long-super-hold-skips-search', passed: !root.navigation.bareSuperTap() });
                root.navigation.modifier('Alt_L', true);
                root.navigation.modifier('Alt_L', false);
                root.navigation.beginSwitcher('all', 1);
                root.checks.push({ name: 'release-before-begin-commits-without-panel', passed:
                    root.calls.length === 3 && !root.navigation.active && !root.navigation.visible });
                var oldState = root.fakeSource.overviewSnapshot;
                var changedClients = oldState.value.clients.map(function(client) {
                    return Object.assign({}, client, { appClass: client.address === '0xa' ? 'terminal' : 'browser' });
                });
                root.fakeSource.overviewSnapshot = { kind: 'ready', value: Object.assign({}, oldState.value,
                    { clients: changedClients }) };
                root.navigation.beginSwitcher('all', 1);
                var beforeSingleton = root.navigation.session;
                var singletonAccepted = root.navigation.beginSwitcher('application', 1);
                root.checks.push({ name: 'application-singleton-keeps-all-session', passed:
                    !singletonAccepted && root.navigation.mode === 'all'
                    && root.navigation.session === beforeSingleton && root.navigation.session.candidates.length === 3 });
                root.navigation.cancel();
                root.fakeSource.overviewSnapshot = oldState;
                root.navigation.openOverview();
                var stale = { address: '0xa', instanceId: 'a:old' };
                var rejected = !root.navigation.selectWindow(stale) && !root.navigation.beginDrag(stale)
                    && !root.navigation.moveWindow(stale, '2');
                root.checks.push({ name: 'stale-instance-cannot-focus-or-move', passed:
                    rejected && root.calls.length === 3 });
                var valid = { address: '0xa', instanceId: 'a:1' };
                root.navigation.selectWindow(valid);
                root.navigation.setQuery('editor');
                root.navigation.openMovePicker();
                root.navigation.dismissTop();
                var pickerFirst = !root.navigation.pickerOpen && root.navigation.query === 'editor';
                root.navigation.beginDrag(valid);
                root.navigation.dismissTop();
                var dragSecond = !root.navigation.dragToken && root.navigation.query === 'editor';
                root.navigation.dismissTop();
                var queryThird = !root.navigation.query && root.navigation.active;
                root.navigation.dismissTop();
                root.checks.push({ name: 'escape-priority-picker-drag-query-close', passed:
                    pickerFirst && dragSecond && queryThird && !root.navigation.active && root.calls.length === 3 });
                var restricted = Object.assign({}, oldState.value, { clients: oldState.value.clients.map(function(client) {
                    return client.address === '0xa' ? Object.assign({}, client, { pinned: true }) : client;
                }) });
                root.fakeSource.overviewSnapshot = { kind: 'ready', value: restricted };
                root.navigation.openOverview();
                root.navigation.selectWindow(valid);
                var pinnedBlocked = !root.navigation.openMovePicker();
                root.navigation.cancel();
                restricted = Object.assign({}, oldState.value, { clients: oldState.value.clients.map(function(client) {
                    return client.address === '0xa' ? Object.assign({}, client, { grouped: ['0xb'] }) : client;
                }) });
                root.fakeSource.overviewSnapshot = { kind: 'ready', value: restricted };
                root.navigation.openOverview();
                root.navigation.selectWindow(valid);
                var groupedBlocked = !root.navigation.openMovePicker();
                root.navigation.cancel();
                root.checks.push({ name: 'move-picker-rejects-pinned-and-grouped', passed:
                    pinnedBlocked && groupedBlocked && root.calls.length === 3 });
                root.fakeSource.overviewSnapshot = oldState;
                root.navigation.openOverview();
                var firstMove = root.navigation.moveWindow(valid, '2');
                var requestId = root.navigation.moveState.requestId;
                var secondMove = root.navigation.moveWindow(valid, '3');
                root.fakeSource.commandFinished('other-request', { ok: true });
                var stillBusy = root.navigation.moveState.kind === 'moving';
                root.fakeSource.commandFinished(requestId, { ok: true });
                root.checks.push({ name: 'move-dispatch-deduplicates-until-matching-confirmation', passed:
                    firstMove && !secondMove && stillBusy && root.navigation.moveState.kind === 'moved'
                    && root.navigation.moveState.destinationId === '2'
                    && root.navigation.selectedWindow && root.navigation.selectedWindow.address === '0xa'
                    && root.calls.length === 4 });
                var token = root.navigation.beginDrag(valid);
                var sameWorkspace = root.navigation.drop(token, '1');
                root.checks.push({ name: 'same-workspace-drop-is-noop-and-consumes-token', passed:
                    sameWorkspace && !root.navigation.dragToken && !root.navigation.drop(token, '2')
                    && root.calls.length === 4 });
                token = root.navigation.beginDrag(valid);
                root.fakeSource.overviewSnapshot = { kind: 'ready', value: Object.assign({}, oldState.value,
                    { clients: oldState.value.clients.filter(function(client) { return client.address !== '0xa'; }) }) };
                root.checks.push({ name: 'disappearing-source-clears-drag-and-rejects-drop', passed:
                    !root.navigation.dragToken && root.navigation.moveState.kind === 'idle'
                    && !root.navigation.drop(token, '2') && root.calls.length === 4 });
                root.navigation.cancel();
                root.complete();
            }
        }
    }
    Timer {
        interval: 30
        running: true
        onTriggered: {
        const clients = ['a', 'b', 'c'].map(function(id) {
            return { address: '0x' + id, instanceId: id + ':1', appClass: 'editor', mapped: true,
                hidden: false, pinned: false, monitorId: 'fixture', workspaceId: '1' };
        });
        const snapshot = { clients: clients, activeAddress: '0xa', desktop: {
            focusedOutputId: '0', outputs: [{ id: '0', name: 'fixture', activeWorkspaceId: '1' }],
            workspaces: [{ id: '1', special: false }] } };
        const session = Switcher.beginSwitcherSession({ id: 1, snapshot: snapshot,
            mru: ['a:1', 'b:1', 'c:1'], scope: 'workspace', mode: 'application' });
        const next = Switcher.stepSwitcherSession(session, -1);
        const live = Object.assign({}, snapshot, { clients: [clients[0], clients[2],
            Object.assign({}, clients[1], { instanceId: 'b:2' })] });
        const reconciled = Switcher.reconcileSwitcherSession(session, live);
        const normalized = Overview.normalizeOverviewClients([
            { address: '0xabc', workspace: { id: 1 }, monitor: 0, size: [40000, 720], fullscreen: 2 },
            { address: 'bad', workspace: { id: 1 } },
        ], snapshot.desktop.outputs, { untitled: 'Без назви' });
        const preview = OverviewLayout.fitPreview(1600, 900, 320, 200);
        const checks = [
            { name: 'qml-switcher-scoped-mru-forward-and-reverse', passed:
                session.candidates.length === 3 && Switcher.selectedWindow(session).address === '0xb'
                && Switcher.selectedWindow(next).address === '0xa' },
            { name: 'qml-switcher-rejects-recycled-instance', passed:
                reconciled.candidates.length === 2 && Switcher.selectedWindow(reconciled).address === '0xc' },
            { name: 'qml-overview-normalizes-native-metadata', passed: normalized.length === 1
                && normalized[0].title === 'Без назви' && normalized[0].monitorId === 'fixture'
                && normalized[0].width === 32768 && normalized[0].fullscreen },
            { name: 'qml-overview-selector-and-preview-layout', passed:
                Overview.workspaceSelector({ id: '-1', name: 'special:music', special: true }) === 'special:music'
                && preview.width === 320 && preview.height === 180 },
        ];
        root.checks = checks;
        root.phase = 1;
        root.navigation.modifier('Alt_L', true);
        root.navigation.beginSwitcher('all', 1);
        sequenceTimer.start();
        }
    }
}
