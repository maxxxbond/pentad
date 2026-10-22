import QtQuick
import QtQml
import Quickshell
import Quickshell.Hyprland
import "../logic/overview.mjs" as Overview
import "../logic/overview-layout.mjs" as OverviewLayout
import "../logic/hyprland-preview.mjs" as HyprlandPreview

QtObject {
    id: root
    required property bool preview
    property bool safeMode: false
    property int serial: 0
    property var identityTracker: Overview.createOverviewIdentityTracker(128)
    property int snapshotRevision: 0
    property var nativeIdentityState: ({ byAddress: ({}), mru: [] })
    property string lastActiveInstanceId: ''
    property var pendingCommands: []
    property int bootstrapRefreshAttempts: 0
    property int settleRefreshesLeft: 0
    property var placementRun: null
    signal commandFinished(string requestId, var result)

    property Connections nativeConnections: Connections {
        target: Hyprland
        function onRawEvent(event) {
            root.refreshNativeIdentities();
            if (Overview.nativeGeometryEvent(event ? event.name : '')) root.refreshNavigationCatalog();
            else root.scheduleNativeRefresh();
        }
        function onActiveToplevelChanged() { root.refreshNativeIdentities(); }
    }
    property Connections modelConnections: Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root.refreshNativeIdentities(); }
    }
    property Connections workspaceConnections: Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.refreshNativeIdentities(); }
    }
    property Connections monitorConnections: Connections {
        target: Hyprland.monitors
        function onValuesChanged() { root.refreshNativeIdentities(); }
    }

    readonly property var state: preview ? ({ kind: 'ready', value: previewState })
        : (snapshot.outputs.length ? ({ kind: 'ready', value: snapshot })
            : ({ kind: 'unavailable', reason: 'disconnected' }))
    readonly property var previewState: previewStateForScreens(Quickshell.screens)
    readonly property var overviewSnapshot: preview
        ? ({ kind: 'ready', value: previewOverviewSnapshot })
        : (snapshot.outputs.length
            ? ({ kind: 'ready', value: nativeOverviewSnapshot })
            : unavailableOverviewSnapshot())
    readonly property var previewOverviewSnapshot: previewOverviewForScreens(Quickshell.screens)
    readonly property var nativeOverviewSnapshot: buildNativeOverviewSnapshot()
    readonly property var snapshot: preview ? previewState : nativeDesktopSnapshot()

    property Timer confirmationTimer: Timer {
        interval: 16
        repeat: true
        running: root.pendingCommands.length > 0
        onTriggered: root.confirmPendingCommands()
    }

    property Timer bootstrapRefreshTimer: Timer {
        interval: 300
        repeat: true
        running: false
        onTriggered: {
            if (root.bootstrapRefreshAttempts >= 2) {
                stop();
                return;
            }
            root.bootstrapRefreshAttempts++;
            root.refreshNavigationCatalog();
            if (root.bootstrapRefreshAttempts >= 2) stop();
        }
    }
    // A move or retile is reported before Hyprland finishes placing the windows, so one
    // refresh can read the old geometry. A short settle burst re-reads it until layout is final.
    property Timer settleRefreshTimer: Timer {
        interval: 240
        repeat: true
        running: false
        onTriggered: {
            if (root.preview || root.settleRefreshesLeft <= 0) { stop(); return; }
            root.settleRefreshesLeft--;
            root.refreshNativeCatalogNow();
            if (root.settleRefreshesLeft <= 0) stop();
        }
    }
    // Each dispatch travels on its own socket, so ordered steps wait for the previous one to land.
    property Timer placementTimer: Timer {
        interval: 16
        repeat: true
        running: root.placementRun !== null
        onTriggered: root.advancePlacement()
    }
    property Timer nativeRefreshTimer: Timer {
        interval: 80
        repeat: false
        running: false
        onTriggered: {
            if (!root.preview) root.refreshNativeCatalogNow();
        }
    }

    Component.onCompleted: {
        refreshNativeIdentities();
        if (!preview) bootstrapRefreshTimer.start();
    }

    function nativeSequence(value) {
        return Overview.nativeSequenceToArray(value);
    }

    function scheduleNativeRefresh() {
        if (!preview && nativeToplevelMetadataIncomplete()) nativeRefreshTimer.restart();
    }

    function refreshNavigationCatalog() {
        if (preview) return false;
        nativeRefreshTimer.restart();
        settleRefreshesLeft = 3;
        settleRefreshTimer.restart();
        return true;
    }

    function refreshNativeCatalogNow() {
        if (preview) return;
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    function nativeToplevelMetadataIncomplete() {
        var values = Hyprland.toplevels.values;
        if (!values.length) return true;
        for (var i = 0; i < values.length; i++) {
            var details = values[i] ? values[i].lastIpcObject || ({ }) : ({ });
            var at = nativeSequence(details.at);
            var size = nativeSequence(details.size);
            if (at.length !== 2 || size.length !== 2) return true;
        }
        return false;
    }

    function canonicalAddress(value) {
        var address = String(value === undefined || value === null ? '' : value).trim().toLowerCase();
        if (address.indexOf('0x') === 0) address = address.slice(2);
        if (!/^[\da-f]{1,16}$/.test(address)) return '';
        return '0x' + address;
    }

    function numberOr(value, fallback) {
        return HyprlandPreview.numberOr(value, fallback);
    }

    function previewStateForScreens(screens) {
        return HyprlandPreview.previewStateForScreens(screens);
    }

    function previewOverviewForScreens(screens) {
        return HyprlandPreview.previewOverviewForScreens(screens);
    }

    function nativeOutputs() {
        var outputs = [];
        var monitors = Hyprland.monitors.values;
        for (var i = 0; i < monitors.length; i++) {
            var monitor = monitors[i];
            if (!monitor) continue;
            var scale = Number(monitor.scale);
            if (!(scale > 0) || !Number.isFinite(scale)) scale = 1;
            var details = monitor.lastIpcObject || ({ });
            var transform = numberOr(details.transform, 0);
            var reservedRaw = nativeSequence(details.reserved);
            var reserved = [];
            for (var side = 0; side < 4; side++)
                reserved.push(numberOr(reservedRaw[side], 0));
            var width = Number(monitor.width) / scale;
            var height = Number(monitor.height) / scale;
            if (transform % 2 !== 0) {
                var swap = width; width = height; height = swap;
            }
            outputs.push({ id: String(monitor.id), name: String(monitor.name || ''),
                x: numberOr(monitor.x, 0), y: numberOr(monitor.y, 0),
                width: Number.isFinite(width) && width > 0 ? width : 0,
                height: Number.isFinite(height) && height > 0 ? height : 0,
                scale: scale, transform: transform, reserved: reserved,
                activeWorkspaceId: monitor.activeWorkspace
                    ? workspaceIdForNative(monitor.activeWorkspace) : '' });
        }
        return outputs;
    }

    function workspaceIdForNative(workspace) {
        if (!workspace) return '';
        var name = String(workspace.name || '');
        return Number(workspace.id) < 0 || name.indexOf('special:') === 0 ? name : String(workspace.id);
    }

    function nativeWorkspaces(outputs) {
        var workspaces = [];
        var values = Hyprland.workspaces.values;
        for (var i = 0; i < values.length; i++) {
            var workspace = values[i];
            if (!workspace) continue;
            var id = workspaceIdForNative(workspace);
            var monitor = workspace.monitor ? String(workspace.monitor.name || '') : '';
            var apps = [];
            var windowValues = workspace.toplevels.values;
            for (var k = 0; k < windowValues.length; k++) {
                var window = windowValues[k];
                if (!window) continue;
                var details = window.lastIpcObject || ({ });
                var appClass = String(details.class || details.initialClass || '');
                var size = nativeSequence(details.size);
                apps.push({ appId: String(details.appId || appClass), appClass: appClass,
                    width: numberOr(size[0], 0), height: numberOr(size[1], 0),
                    pinned: details.pinned === true });
            }
            workspaces.push({ id: id, name: String(workspace.name || id), monitor: monitor,
                special: String(workspace.name || '').indexOf('special:') === 0,
                active: !!workspace.active, occupied: apps.some(function(app) { return !app.pinned; }),
                apps: apps });
        }
        return workspaces;
    }

    function nativeDesktopSnapshot() {
        var outputs = nativeOutputs();
        var workspaces = nativeWorkspaces(outputs);
        return { workspaces: workspaces, outputs: outputs,
            focusedOutputId: Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.id) : '',
            activeTitle: Hyprland.activeToplevel ? String(Hyprland.activeToplevel.title || '') : '',
            activeClass: Hyprland.activeToplevel
                ? String((Hyprland.activeToplevel.lastIpcObject || ({ })).class || '') : '' };
    }

    function nativeClientRows() {
        var rows = [];
        var objects = [];
        var addresses = [];
        var toplevels = Hyprland.toplevels.values;
        for (var i = 0; i < toplevels.length; i++) {
            var toplevel = toplevels[i];
            if (!toplevel) continue;
            var address = canonicalAddress(toplevel.address);
            if (!address) continue;
            var details = toplevel.lastIpcObject || ({ });
            var workspace = toplevel.workspace;
            if (!workspace) continue;
            var workspaceId = workspaceIdForNative(workspace);
            rows.push({ address: address, workspace: { id: workspaceId },
                monitor: toplevel.monitor ? String(toplevel.monitor.name || '') : '',
                appId: details.appId || '', class: details.class || '', initialClass: details.initialClass || '',
                title: String(toplevel.title || details.title || ''),
                at: nativeSequence(details.at), size: nativeSequence(details.size),
                mapped: details.mapped, hidden: details.hidden, pinned: details.pinned,
                floating: details.floating, fullscreen: details.fullscreen,
                fullscreenClient: details.fullscreenClient,
                grouped: details.grouped !== undefined && details.grouped !== null
                    ? nativeSequence(details.grouped) : undefined,
                group: nativeSequence(details.group) });
            objects.push(toplevel);
            addresses.push(address);
        }
        return { rows: rows, objects: objects, addresses: addresses };
    }

    function buildNativeOverviewSnapshot() {
        var desktop = nativeDesktopSnapshot();
        var native = nativeClientRows();
        var identityState = nativeIdentityState;
        var clients = Overview.normalizeOverviewClients(native.rows, desktop.outputs);
        for (var j = 0; j < clients.length; j++)
            clients[j].instanceId = identityState.byAddress[clients[j].address] || '';
        var active = Hyprland.activeToplevel;
        var activeAddress = active ? canonicalAddress(active.address) : null;
        return { revision: snapshotRevision, desktop: desktop, clients: clients,
            activeAddress: activeAddress, mru: identityState.mru.slice() };
    }

    function refreshNativeIdentities() {
        var native = nativeClientRows();
        if (!Hyprland.monitors.values.length) {
            identityTracker.clear();
            lastActiveInstanceId = '';
            nativeIdentityState = ({ byAddress: ({}), mru: [] });
            snapshotRevision++;
            return;
        }
        var tracked = identityTracker.sync(native.objects, native.addresses);
        var activeAddress = Hyprland.activeToplevel
            ? canonicalAddress(Hyprland.activeToplevel.address) : '';
        var activeInstanceId = '';
        for (var i = 0; i < native.addresses.length; i++) {
            if (native.addresses[i] === activeAddress) {
                activeInstanceId = tracked.instanceIds[i];
                break;
            }
        }
        if (activeInstanceId && activeInstanceId !== lastActiveInstanceId) {
            identityTracker.activate(activeAddress);
            lastActiveInstanceId = activeInstanceId;
            tracked = identityTracker.sync(native.objects, native.addresses);
        } else if (!activeInstanceId) {
            lastActiveInstanceId = '';
        }
        var byAddress = ({ });
        for (var j = 0; j < native.addresses.length; j++)
            byAddress[native.addresses[j]] = tracked.instanceIds[j];
        nativeIdentityState = ({ byAddress: byAddress, mru: tracked.mru.slice() });
        snapshotRevision++;
    }

    function unavailableOverviewSnapshot() {
        return { kind: 'unavailable', reason: 'disconnected' };
    }

    function findClient(ref, currentSnapshot) {
        if (!ref || typeof ref !== 'object') return null;
        var address = canonicalAddress(ref.address);
        if (!address || typeof ref.instanceId !== 'string' || !ref.instanceId) return null;
        var clients = currentSnapshot && Array.isArray(currentSnapshot.clients) ? currentSnapshot.clients : [];
        for (var i = 0; i < clients.length; i++) {
            if (clients[i].address === address && clients[i].instanceId === ref.instanceId) return clients[i];
        }
        return null;
    }

    function workspaceSelector(workspace) {
        if (!workspace) return null;
        var id = String(workspace.id);
        var name = String(workspace.name || id);
        if (workspace.special) {
            var specialName = name.replace(/^special:/, '');
            return specialName && !/[\0\r\n,]/.test(specialName) ? 'special:' + specialName : null;
        }
        if (/^[1-9]\d{0,9}$/.test(id) && Number(id) <= 2147483647) return id;
        var trimmed = name.trim();
        return trimmed && !/[\0\r\n,]/.test(trimmed) ? 'name:' + trimmed : null;
    }

    function newRequestId(prefix) { return prefix + '-' + (++serial); }
    function finish(requestId, result) {
        Qt.callLater(function() { root.commandFinished(requestId, result); });
    }

    function completePending(requestId, result) {
        var found = false;
        var remaining = [];
        for (var i = 0; i < pendingCommands.length; i++) {
            if (pendingCommands[i].requestId === requestId) found = true;
            else remaining.push(pendingCommands[i]);
        }
        if (!found) return;
        pendingCommands = remaining;
        finish(requestId, result);
    }

    function confirmPendingCommands() {
        var now = Date.now();
        var current = overviewSnapshot;
        for (var i = pendingCommands.length - 1; i >= 0; i--) {
            var pending = pendingCommands[i];
            if (current.kind !== 'ready' && current.reason === 'disconnected') {
                completePending(pending.requestId, { ok: false, reason: 'unavailable' });
                continue;
            }
            var focusedWorkspaceId = Hyprland.focusedWorkspace
                ? workspaceIdForNative(Hyprland.focusedWorkspace) : '';
            var result = Overview.confirmOverviewCommand(pending,
                current.kind === 'ready' ? current.value : null, focusedWorkspaceId, now);
            if (result) completePending(pending.requestId, result);
        }
    }

    function addPending(requestId, kind, data) {
        pendingCommands = pendingCommands.concat([Object.assign({ requestId: requestId, kind: kind,
            deadline: Date.now() + 1000 }, data)]);
    }

    function dispatch(luaCommand, legacyCommand) {
        Hyprland.dispatch(Hyprland.usingLua ? luaCommand : legacyCommand);
    }

    function focusWindow(ref, forceDispatch) {
        var requestId = newRequestId('focus');
        if (preview) { finish(requestId, { ok: false, reason: 'preview' }); return requestId; }
        if (safeMode) { finish(requestId, { ok: false, reason: 'safe-mode' }); return requestId; }
        var current = overviewSnapshot;
        if (current.kind !== 'ready') { finish(requestId, { ok: false, reason: 'unavailable' }); return requestId; }
        var client = findClient(ref, current.value);
        if (!client) { finish(requestId, { ok: false, reason: 'device-removed' }); return requestId; }
        if (current.value.activeAddress === client.address && !forceDispatch) {
            finish(requestId, { ok: true }); return requestId;
        }
        var selector = 'address:' + client.address;
        try {
            dispatch('hl.dsp.focus({ window = ' + JSON.stringify(selector) + ' })',
                'focuswindow ' + selector);
            addPending(requestId, 'focus', { address: client.address,
                ref: { address: client.address, instanceId: client.instanceId } });
        } catch (error) {
            finish(requestId, { ok: false, reason: 'unavailable', detail: String(error) });
        }
        return requestId;
    }

    function dispatchFocusWorkspace(id) {
        dispatch('hl.dsp.focus({ workspace = ' + JSON.stringify(String(id)) + ' })', 'workspace ' + id);
    }

    function dispatchMove(window, workspace) {
        dispatch('hl.dsp.window.move({ window = ' + JSON.stringify(window)
                + ', workspace = ' + JSON.stringify(workspace) + ', follow = false })',
            'movetoworkspacesilent ' + workspace + ',' + window);
    }

    // focus target -> preselect side -> silent move -> give back the destination monitor's
    // workspace -> restore focus. A step that never confirms times out instead of stalling.
    function advancePlacement() {
        var run = placementRun;
        if (!run) return;
        var now = Date.now();
        if (run.phase === 'focus') {
            var active = Hyprland.activeToplevel ? canonicalAddress(Hyprland.activeToplevel.address) : '';
            if (active !== run.plan.target && now - run.since < 400) return;
            dispatch('hl.dsp.layout(' + JSON.stringify('preselect ' + run.plan.direction) + ')',
                'layoutmsg preselect ' + run.plan.direction);
            run.phase = 'preselect'; run.since = now;
        } else if (run.phase === 'preselect') {
            if (now - run.since < 40) return;
            dispatchMove(run.window, run.workspace);
            refreshNavigationCatalog();
            run.phase = 'moved'; run.since = now;
        } else if (run.phase === 'moved') {
            var current = overviewSnapshot.kind === 'ready' ? overviewSnapshot.value : null;
            var moved = current ? current.clients.find(function(item) { return item.address === run.address; }) : null;
            if ((!moved || moved.workspaceId !== run.destinationId) && now - run.since < 600) return;
            if (run.plan.restoreWorkspaceId) dispatchFocusWorkspace(run.plan.restoreWorkspaceId);
            run.phase = 'restore'; run.since = now;
        } else {
            if (now - run.since < 40) return;
            if (run.plan.restoreFocusAddress)
                dispatch('hl.dsp.focus({ window = ' + JSON.stringify('address:' + run.plan.restoreFocusAddress) + ' })',
                    'focuswindow address:' + run.plan.restoreFocusAddress);
            else if (run.plan.restoreFocusWorkspaceId) dispatchFocusWorkspace(run.plan.restoreFocusWorkspaceId);
            placementRun = null;
        }
    }

    function moveWindow(ref, destinationId, point) {
        var requestId = newRequestId('move');
        if (preview) { finish(requestId, { ok: false, reason: 'preview' }); return requestId; }
        if (safeMode) { finish(requestId, { ok: false, reason: 'safe-mode' }); return requestId; }
        var current = overviewSnapshot;
        if (current.kind !== 'ready') { finish(requestId, { ok: false, reason: 'unavailable' }); return requestId; }
        var client = findClient(ref, current.value);
        if (!client) { finish(requestId, { ok: false, reason: 'device-removed' }); return requestId; }
        if (client.pinned || client.grouped.length > 0) {
            finish(requestId, { ok: false, reason: 'unsupported' }); return requestId;
        }
        var destination = current.value.desktop.workspaces.find(function(item) {
            return item.id === String(destinationId);
        });
        var destinationKey = String(destinationId);
        var virtualNumeric = !destination && /^[1-9]\d{0,9}$/.test(destinationKey)
            && Number(destinationKey) <= 2147483647;
        if (!destination && !virtualNumeric) {
            finish(requestId, { ok: false, reason: 'unsupported' }); return requestId;
        }
        if (client.workspaceId === destinationKey) {
            finish(requestId, { ok: true }); return requestId;
        }
        var workspace = destination ? workspaceSelector(destination) : destinationKey;
        if (!workspace) { finish(requestId, { ok: false, reason: 'unsupported' }); return requestId; }
        var window = 'address:' + client.address;
        var placement = point && destination && !placementRun
            ? OverviewLayout.dropPlacement(current.value.clients, client.address, destination.id, point) : null;
        var plan = placement ? Overview.placementPlan(current.value, client, destination.id, placement) : null;
        try {
            if (plan) {
                dispatch('hl.dsp.focus({ window = ' + JSON.stringify('address:' + plan.target) + ' })',
                    'focuswindow address:' + plan.target);
                placementRun = { phase: 'focus', since: Date.now(), plan: plan, window: window,
                    workspace: workspace, address: client.address, destinationId: destination.id };
            } else {
                dispatchMove(window, workspace);
                refreshNavigationCatalog();
            }
            addPending(requestId, 'move', { ref: { address: client.address,
                instanceId: client.instanceId }, destinationId: destination ? destination.id : destinationKey,
                deadline: Date.now() + (plan ? 2000 : 1000) });
        } catch (error) {
            finish(requestId, { ok: false, reason: 'unavailable', detail: String(error) });
        }
        return requestId;
    }

    function activateOverviewWorkspace(id) {
        var requestId = newRequestId('workspace');
        if (preview) { finish(requestId, { ok: false, reason: 'preview' }); return requestId; }
        if (safeMode) { finish(requestId, { ok: false, reason: 'safe-mode' }); return requestId; }
        var current = overviewSnapshot;
        if (current.kind !== 'ready') { finish(requestId, { ok: false, reason: 'unavailable' }); return requestId; }
        var workspace = current.value.desktop.workspaces.find(function(item) {
            return item.id === String(id);
        });
        var workspaceKey = String(id);
        var virtualNumeric = !workspace && /^[1-9]\d{0,9}$/.test(workspaceKey)
            && Number(workspaceKey) <= 2147483647;
        if (!workspace && !virtualNumeric) { finish(requestId, { ok: false, reason: 'unsupported' }); return requestId; }
        var selector = workspace ? workspaceSelector(workspace) : workspaceKey;
        if (!selector) { finish(requestId, { ok: false, reason: 'unsupported' }); return requestId; }
        if (workspace && Hyprland.focusedWorkspace
                && workspaceIdForNative(Hyprland.focusedWorkspace) === workspace.id) {
            finish(requestId, { ok: true }); return requestId;
        }
        try {
            dispatch('hl.dsp.focus({ workspace = ' + JSON.stringify(selector) + ' })',
                'workspace ' + selector);
            addPending(requestId, 'workspace', { destinationId: workspace ? workspace.id : workspaceKey });
        } catch (error) {
            finish(requestId, { ok: false, reason: 'unavailable', detail: String(error) });
        }
        return requestId;
    }

    function captureSourceFor(ref) {
        if (preview || safeMode) return null;
        var current = overviewSnapshot;
        var client = current.kind === 'ready' ? findClient(ref, current.value) : null;
        if (!client) return null;
        var toplevels = Hyprland.toplevels.values;
        for (var i = 0; i < toplevels.length; i++) {
            var toplevel = toplevels[i];
            if (toplevel && canonicalAddress(toplevel.address) === client.address
                    && client.instanceId === current.value.clients.find(function(row) {
                        return row.address === client.address;
                    }).instanceId) return toplevel.wayland || null;
        }
        return null;
    }

    function focusWorkspace(id) {
        var requestId = newRequestId('workspace-legacy');
        if (preview) {
            finish(requestId, { ok: false, reason: 'preview' });
            return requestId;
        }
        if (safeMode) {
            finish(requestId, { ok: false, reason: 'safe-mode' });
            return requestId;
        }
        var key = String(id);
        var numeric = /^-?\d+$/.test(key);
        numeric = numeric && Number.isSafeInteger(Number(key));
        var values = Hyprland.workspaces.values;
        var workspace = null;
        for (var i = 0; i < values.length; i++) {
            var special = Number(values[i].id) < 0 || String(values[i].name).indexOf('special:') === 0;
            if ((special && String(values[i].name) === key)
                    || (!special && numeric && String(values[i].id) === key)) {
                workspace = values[i];
                break;
            }
        }
        if (!numeric && !workspace) {
            finish(requestId, { ok: false, reason: 'unsupported' });
            return requestId;
        }
        if (workspace) workspace.activate();
        else Hyprland.dispatch(Hyprland.usingLua
            ? 'hl.dsp.focus({ workspace = "' + key + '" })'
            : 'workspace ' + key);
        finish(requestId, { ok: true });
        return requestId;
    }
}
