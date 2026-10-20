import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import qs.plugins
import "../services"
import "../shell"
import "../logic/overview.mjs" as Overview

ShellRoot {
    id: root
    property Services services: Services { preview: true; safeMode: true }
    OutputHost { services: root.services; outputs: [] }
    IpcBridge { id: bridge; services: root.services }
    NavigationHost { services: root.services }
    property FileView clockManifest: FileView { path: Qt.resolvedUrl('widgets/clock/manifest.json') }
    property PluginHost clockView: PluginHost {
        instanceId: 'clock-main'; moduleId: 'pentad.clock'
        context: ({ outputId: 'fixture', slot: 'system', compact: false, preview: true })
        settings: ({ defaultDurationSeconds: 1500 })
        services: root.services; registry: root.services.plugins
    }
    property bool clockRegistered: false
    property bool navigationOpened: false
    Timer {
        interval: 80
        repeat: true
        running: true
        onTriggered: {
        if (!root.clockRegistered) {
            var registered = root.services.plugins.registerManifest(JSON.parse(root.clockManifest.text()), Qt.resolvedUrl('widgets/clock/'), true);
            root.services.plugins.reconcile(root.services.config.documents.layout.widgets);
            root.clockRegistered = registered.ok;
            return;
        }
        if (!root.navigationOpened) {
            bridge.request('overview', '{"action":"open"}');
            root.navigationOpened = true;
            return;
        }
        var navigationReady = root.services.navigation.active && root.services.navigation.revealed
            && root.services.navigation.mode === 'overview';
        var rejectedOverview = JSON.parse(bridge.request('overview', '{"action":"destroy"}'));
        bridge.request('workspace-super', '{"key":"Super_L","action":"press"}');
        bridge.request('workspace-super', '{"key":"Super_R","action":"press"}');
        bridge.request('overview', '{"action":"close"}');
        var retainedSuper = root.services.workspaceHeld && !root.services.navigation.active;
        bridge.request('workspace-super', '{"key":"Super_L","action":"release"}');
        retainedSuper = retainedSuper && root.services.workspaceHeld;
        bridge.request('workspace-super', '{"key":"Super_R","action":"release"}');
        retainedSuper = retainedSuper && !root.services.workspaceHeld;
        var ping = JSON.parse(bridge.request("ping", "{}"));
        var unsupported = JSON.parse(bridge.request("unknown-command", "{}"));
        var invalid = JSON.parse(bridge.request("ping", "[]"));
        var previewState = root.services.hyprland.previewStateForScreens([{ name: 'fixture-A' }, { name: 'fixture-B' }]);
        var previewIds = previewState.workspaces.map(function(item) { return item.id; });
        var previewStateMatchesScreens = previewState.outputs.map(function(item) { return item.name; }).join(',') === 'fixture-A,fixture-B'
            && previewState.workspaces.length === 10
            && previewState.workspaces.filter(function(item) { return item.monitor === 'fixture-A'; }).length === 5
            && previewState.workspaces.filter(function(item) { return item.monitor === 'fixture-B'; }).length === 5
            && new Set(previewIds).size === previewIds.length
            && previewState.focusedOutputId === 'fixture-A'
            && previewState.outputs[0].activeWorkspaceId === '1'
            && previewState.outputs[1].activeWorkspaceId === '6'
            && previewState.outputs.every(function(output) {
                var active = previewState.workspaces.filter(function(item) {
                    return item.monitor === output.name && item.active;
                });
                return active.length === 1 && active[0].id === output.activeWorkspaceId;
            });
        var livePreview = root.services.hyprland.state.value;
        var previewOverview = root.services.hyprland.overviewSnapshot.value;
        var tracker = Overview.createOverviewIdentityTracker(2);
        var firstWindow = ({});
        var secondWindow = ({});
        var firstTrack = tracker.sync([firstWindow, secondWindow], ['0xabc', '0xdef']);
        var firstMru = tracker.activate('0xabc');
        var reorderedTrack = tracker.sync([secondWindow, firstWindow], ['0xdef', '0xabc']);
        var replacementWindow = ({});
        var recycledTrack = tracker.sync([secondWindow, replacementWindow], ['0xdef', '0xabc']);
        var recycledMru = tracker.activate('0xabc');
        var overviewIdentityChecks = firstTrack.instanceIds[0] !== firstTrack.instanceIds[1]
            && firstMru[0] === firstTrack.instanceIds[0]
            && reorderedTrack.instanceIds[1] === firstTrack.instanceIds[0]
            && reorderedTrack.mru[0] === firstTrack.instanceIds[0]
            && recycledTrack.instanceIds[1] !== firstTrack.instanceIds[0]
            && recycledMru[0] === recycledTrack.instanceIds[1]
            && recycledTrack.mru.indexOf(firstTrack.instanceIds[0]) < 0;
        var previewOverviewReadOnly = previewOverview.revision === 1
            && previewOverview.clients.length === livePreview.outputs.length
            && previewOverview.clients.every(function(client) { return client.instanceId.indexOf('preview:') === 0; })
            && previewOverview.activeAddress === previewOverview.clients[0].address
            && previewOverview.mru[0] === previewOverview.clients[0].instanceId
            && previewOverview.desktop.outputs.map(function(item) { return item.name; }).join(',')
                === livePreview.outputs.map(function(item) { return item.name; }).join(',');
        var liveScreenNames = [];
        for (var screenIndex = 0; screenIndex < Quickshell.screens.length; screenIndex++)
            liveScreenNames.push(Quickshell.screens[screenIndex].name);
        var livePreviewMatchesScreens = liveScreenNames.length
            ? livePreview.outputs.map(function(item) { return item.name; }).join(',') === liveScreenNames.join(',')
                && livePreview.workspaces.every(function(item) { return liveScreenNames.indexOf(item.monitor) >= 0; })
            : livePreview.outputs.length === 1 && livePreview.outputs[0].name === 'preview';
        var emptyPreview = root.services.hyprland.previewStateForScreens([]);
        var passed = ping.ok && ping.preview && ping.safeMode && overviewIdentityChecks && previewOverviewReadOnly
            && navigationReady && retainedSuper && rejectedOverview.reason === 'invalid-payload'
            && unsupported.reason === "unsupported" && invalid.reason === "invalid-payload"
            && previewStateMatchesScreens && emptyPreview.outputs.length === 1
            && emptyPreview.outputs[0].name === 'preview' && emptyPreview.workspaces.length === 5
            && livePreviewMatchesScreens;
        var clockReady = root.clockView.view && root.clockView.view.controller === root.clockView.controllerWrapper.item
            && root.clockView.view.controller.time.length === 5 && root.clockView.view.settings.defaultDurationSeconds === 1500;
        console.log("PENTAD_TEST " + JSON.stringify({ status: passed && clockReady ? "pass" : "fail",
            checks: [{ name: "shared-container-and-ipc", passed: passed },
                { name: 'production-navigation-host-opens-through-validated-ipc', passed: navigationReady
                    && rejectedOverview.reason === 'invalid-payload' },
                { name: 'closing-navigation-preserves-both-physical-super-states', passed: retainedSuper },
                { name: 'preview-hyprland-follows-screen-names-and-keeps-global-workspace-ids', passed: previewStateMatchesScreens },
                { name: 'preview-hyprland-state-matches-attached-screens', passed: livePreviewMatchesScreens },
                { name: 'preview-overview-snapshot-is-read-only-and-deterministic', passed: previewOverviewReadOnly },
                { name: 'overview-window-identities-track-lifetimes-and-activation-mru', passed: overviewIdentityChecks },
                { name: 'preview-hyprland-falls-back-without-screens', passed: emptyPreview.outputs.length === 1
                    && emptyPreview.outputs[0].name === 'preview' && emptyPreview.workspaces.length === 5 },
                { name: 'built-in-clock-contract', passed: !!clockReady,
                detail: JSON.stringify({ loaded: !!root.clockView.view, controller: !!(root.clockView.view && root.clockView.view.controller),
                    wrapper: !!root.clockView.controllerWrapper, time: root.clockView.view && root.clockView.view.controller ? root.clockView.view.controller.time : '', diagnostic: root.clockView.diagnostic }) }] }));
        Qt.quit();
        }
    }
}
