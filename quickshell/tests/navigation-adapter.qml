import QtQuick
import Quickshell
import "../services" as Native
import "../logic/overview.mjs" as Overview

ShellRoot {
    property var results: ({})
    Native.Hyprland {
        id: adapter
        preview: true
        safeMode: true
        onCommandFinished: function(requestId, result) {
            root.results[requestId] = result;
            root.results = Object.assign({}, root.results);
        }
    }
    id: root

    Timer {
        interval: 30
        running: true
        repeat: false
        onTriggered: {
            const availability = adapter.overviewSnapshot;
            const snapshot = availability.kind === 'ready' ? availability.value : null;
            const client = snapshot && snapshot.clients.length ? snapshot.clients[0] : null;
            const focusId = client ? adapter.focusWindow({ address: client.address, instanceId: client.instanceId }) : '';
            const moveId = client ? adapter.moveWindow({ address: client.address, instanceId: client.instanceId }, client.workspaceId) : '';
            const workspaceId = snapshot && snapshot.desktop.workspaces.length
                ? adapter.activateOverviewWorkspace(snapshot.desktop.workspaces[0].id) : '';
            const ref = { address: '0xabc', instanceId: 'life:1' };
            const liveClient = { address: ref.address, instanceId: ref.instanceId, workspaceId: '1' };
            const focusPending = { kind: 'focus', ref: ref, deadline: 100 };
            const focusWaiting = Overview.confirmOverviewCommand(focusPending,
                { clients: [liveClient], activeAddress: null }, '', 50);
            const focusConfirmed = Overview.confirmOverviewCommand(focusPending,
                { clients: [liveClient], activeAddress: ref.address }, '', 60);
            const staleRejected = Overview.confirmOverviewCommand({ kind: 'focus',
                ref: { address: ref.address, instanceId: 'life:old' }, deadline: 100 },
                { clients: [liveClient], activeAddress: null }, '', 50);
            let completions = 0;
            let timed = [focusPending];
            const timeoutResult = Overview.confirmOverviewCommand(timed[0],
                { clients: [liveClient], activeAddress: null }, '', 100);
            if (timeoutResult) { completions++; timed = []; }
            const lateResult = timed.length ? Overview.confirmOverviewCommand(timed[0],
                { clients: [liveClient], activeAddress: ref.address }, '', 120) : null;
            if (lateResult) completions++;
            const moveConfirmed = Overview.confirmOverviewCommand({ kind: 'move', ref: ref,
                destinationId: '2', deadline: 100 }, { clients: [Object.assign({}, liveClient, { workspaceId: '2' })] }, '', 60);
            const qmlAt = { 0: -1920, 1: 24, length: 2 };
            const qmlSize = { 0: 800, 1: 600, length: 2 };
            const qmlReserved = { 0: 0, 1: 80, 2: 0, 3: 0, length: 4 };
            const convertedAt = adapter.nativeSequence(qmlAt);
            const convertedSize = adapter.nativeSequence(qmlSize);
            const convertedReserved = adapter.nativeSequence(qmlReserved);
            Qt.callLater(function() {
                const checks = [
                    { name: 'preview-overview-snapshot-is-wrapped-and-deterministic', passed:
                        availability.kind === 'ready' && snapshot.revision === 1
                        && snapshot.clients.length > 0 && snapshot.mru.length > 0
                        && snapshot.clients.every(function(item) {
                            return item.instanceId.indexOf('preview:') === 0
                                && Number.isFinite(item.x) && Number.isFinite(item.y)
                                && item.width > 0 && item.height > 0;
                        }) },
                    { name: 'qml-variant-sequences-convert-at-size-and-reserved-geometry', passed:
                        convertedAt.join(',') === '-1920,24'
                        && convertedSize.join(',') === '800,600'
                        && convertedReserved.join(',') === '0,80,0,0' },
                    { name: 'preview-output-geometry-is-logical-and-complete', passed:
                        snapshot.desktop.outputs.length > 0
                        && snapshot.desktop.outputs.every(function(output) {
                            return Number.isFinite(output.x) && Number.isFinite(output.y)
                                && output.width > 0 && output.height > 0 && output.scale > 0
                                && Array.isArray(output.reserved) && output.reserved.length === 4;
                        }) },
                    { name: 'preview-never-returns-a-real-capture-source', passed:
                        client !== null && adapter.captureSourceFor({ address: client.address,
                            instanceId: client.instanceId }) === null },
                    { name: 'preview-safe-mode-rejects-focus-move-and-workspace-activation', passed:
                        !!focusId && !!moveId && !!workspaceId
                        && root.results[focusId] && root.results[focusId].reason === 'preview'
                        && root.results[moveId] && root.results[moveId].reason === 'preview'
                        && root.results[workspaceId] && root.results[workspaceId].reason === 'preview' },
                    { name: 'mock-native-command-confirmation-is-identity-and-snapshot-checked', passed:
                        focusWaiting === null && focusConfirmed && focusConfirmed.ok
                        && moveConfirmed && moveConfirmed.ok && staleRejected
                        && staleRejected.reason === 'device-removed'
                        && timeoutResult && timeoutResult.reason === 'timeout'
                        && completions === 1 && lateResult === null },
                ];
                console.log('PENTAD_TEST ' + JSON.stringify({ status:
                    checks.every(function(check) { return check.passed; }) ? 'pass' : 'fail', checks: checks }));
                Qt.quit();
            });
        }
    }
}
