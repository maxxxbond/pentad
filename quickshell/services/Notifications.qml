import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../logic/notifications.mjs" as Policy

QtObject {
    id: root
    required property var config
    property bool preview: false
    property bool safeMode: false
    // Hides notification bodies in popups and the center; not persisted across sessions.
    property bool privacy: false
    property var state: ({ status: preview ? "unavailable" : "starting", dnd: false, history: [], popups: [], unread: 0 })
    property var controller: null
    property var nativeById: ({})
    property var policyToNative: ({})
    property var nativeIdToArchiveKey: ({})
    property var archiveKeyToNativeId: ({})
    property var programmaticClose: ({})
    property var actionClose: ({})
    property bool restoreComplete: false
    property bool persistenceDisabled: false
    property bool saveQueued: false
    property bool saving: false
    property int saveRevision: 0
    property int localRevision: 0
    property int serial: 0
    property int ownerProbeGeneration: 0
    property var ownerProbeProcess: null
    property var pendingRefresh: ({})
    property int monotonicElapsed: 0
    readonly property bool nativeEnabled: !preview && !safeMode
    property var pendingNotifications: []
    signal commandFinished(string requestId, var result)

    function wallNow() { return Date.now(); }
    function schedule(delayMs, callback) {
        const timer = timerFactory.createObject(root, { interval: Math.max(0, Math.ceil(delayMs)), callback: callback });
        timer.start();
        return function() { if (timer) { timer.stop(); timer.destroy(); } };
    }
    function setState(next) {
        state = next;
        localRevision++;
        queueSave();
    }
    function closeNative(policyId, reason) {
        const nativeId = policyToNative[String(policyId)];
        if (nativeId === undefined) return;
        const item = nativeById[String(nativeId)];
        if (!item || !item.object) return;
        programmaticClose = Object.assign({}, programmaticClose, { [String(nativeId)]: true });
        if (reason === 1) item.object.expire();
        else item.object.dismiss();
    }
    function invokeNative(policyId, actionKey) {
        const nativeId = policyToNative[String(policyId)];
        const item = nativeId === undefined ? null : nativeById[String(nativeId)];
        if (!item || !item.object) return;
        const actions = item.object.actions || [];
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].identifier === actionKey) {
                actionClose = Object.assign({}, actionClose, { [String(nativeId)]: true });
                actions[i].invoke();
                const nextAction = Object.assign({}, actionClose); delete nextAction[String(nativeId)]; actionClose = nextAction;
                return;
            }
        }
    }
    function replyNative(policyId, text) {
        const nativeId = policyToNative[String(policyId)];
        const item = nativeId === undefined ? null : nativeById[String(nativeId)];
        if (!item || !item.object || !item.object.hasInlineReply) return;
        actionClose = Object.assign({}, actionClose, { [String(nativeId)]: true });
        item.object.sendInlineReply(text);
        const nextAction = Object.assign({}, actionClose); delete nextAction[String(nativeId)]; actionClose = nextAction;
    }
    function clearMappings(nativeId) {
        const key = String(nativeId);
        const item = nativeById[key];
        if (!item) return;
        const nextNative = Object.assign({}, nativeById); delete nextNative[key]; nativeById = nextNative;
        const nextPolicy = Object.assign({}, policyToNative); delete nextPolicy[String(item.policyId)]; policyToNative = nextPolicy;
        const nextKeys = Object.assign({}, nativeIdToArchiveKey); delete nextKeys[key]; nativeIdToArchiveKey = nextKeys;
        const nextReverse = Object.assign({}, archiveKeyToNativeId); delete nextReverse[item.archiveKey]; archiveKeyToNativeId = nextReverse;
    }
    function capture(notification) {
        if (!notification) return;
        if (!controller || !restoreComplete) {
            if (!pendingNotifications.some(function(item) { return item.id === notification.id; }))
                pendingNotifications = pendingNotifications.concat([notification]);
            return;
        }
        controller.setStatus("available");
        const nativeId = String(notification.id);
        const previous = nativeById[nativeId];
        const actions = [];
        const nativeActions = notification.actions || [];
        for (let i = 0; i < nativeActions.length; ++i)
            actions.push(nativeActions[i].identifier, nativeActions[i].text);
        const hints = Object.assign({}, notification.hints || {}, {
            urgency: notification.urgency === NotificationUrgency.Critical ? 2
                : notification.urgency === NotificationUrgency.Low ? 0 : 1,
            transient: notification.transient === true,
            resident: notification.resident === true,
            "desktop-entry": notification.desktopEntry || "",
        });
        const nativeTimeout = Number(notification.expireTimeout);
        const expireTimeout = nativeTimeout < 0 ? -1 : nativeTimeout === 0 ? 0
            : Math.min(nativeTimeout, 0x7fffffff);
        const policyId = controller.notify({ app: notification.appName || "Unknown app",
            replacesId: previous ? previous.policyId : 0, icon: notification.appIcon || "",
            image: notification.image || "",
            reply: notification.hasInlineReply ? { placeholder: notification.inlineReplyPlaceholder || "" } : null,
            title: notification.summary || "", body: notification.body || "", actions: actions,
            hints: hints, expireTimeout: expireTimeout, sender: null });
        let record = stateRecord(policyId);
        if (!record) record = controller.read().popups.find(function(item) { return item.wireId === policyId; });
        if (!record) { clearMappings(notification.id); notification.dismiss(); return; }
        if (record.wireId !== policyId) {
            clearMappings(notification.id);
            notification.dismiss();
            return;
        }
        const item = { object: notification, policyId: policyId, archiveKey: record.key };
        const nextNative = Object.assign({}, nativeById, { [nativeId]: item }); nativeById = nextNative;
        policyToNative = Object.assign({}, policyToNative, { [String(policyId)]: notification.id });
        nativeIdToArchiveKey = Object.assign({}, nativeIdToArchiveKey, { [nativeId]: record.key });
        archiveKeyToNativeId = Object.assign({}, archiveKeyToNativeId, { [record.key]: notification.id });
    }
    function stateRecord(policyId) {
        const current = controller.read();
        return current.history.find(function(item) { return item.wireId === policyId; }) || null;
    }
    function nativeClosed(notification, reason) {
        const nativeId = String(notification.id), entry = nativeById[nativeId];
        if (!entry) return;
        clearMappings(notification.id);
        if (programmaticClose[nativeId] || actionClose[nativeId]) {
            const nextProgrammatic = Object.assign({}, programmaticClose); delete nextProgrammatic[nativeId]; programmaticClose = nextProgrammatic;
            const nextAction = Object.assign({}, actionClose); delete nextAction[nativeId]; actionClose = nextAction;
            return;
        }
        if (reason === NotificationCloseReason.CloseRequested) controller.closeFromSender(entry.policyId);
        else if (controller.read().history.some(function(item) { return item.wireId === entry.policyId; }))
            controller.closeFromSender(entry.policyId);
    }
    function refreshNative(notification) {
        if (!notification) return;
        const id = String(notification.id);
        if (!nativeById[id] || pendingRefresh[id]) return;
        const scheduled = Object.assign({}, pendingRefresh, { [id]: notification }); pendingRefresh = scheduled;
        Qt.callLater(function() {
            const current = root.pendingRefresh[id];
            if (!current) return;
            const next = Object.assign({}, root.pendingRefresh); delete next[id]; root.pendingRefresh = next;
            if (root.nativeById[id]) root.capture(current);
        });
    }
    function dismiss(key) { if (controller) controller.dismiss(key); }
    function clearGroup(groupKey) { if (controller) controller.clearGroup(groupKey); }
    function clearAll() { if (controller) controller.clearAll(); }
    function invoke(key, actionKey) { return controller ? controller.invoke(key, actionKey) : false; }
    function reply(key, text) { return controller ? controller.reply(key, text) : false; }
    // Popups never take keyboard focus, so a popup's reply opens the center, which consumes this request.
    property string replyRequest: ""
    function requestReply(key) { replyRequest = String(key || ""); }
    function takeReplyRequest(key) {
        if (!key || replyRequest !== key) return false;
        replyRequest = "";
        return true;
    }
    function setDnd(enabled) { if (controller) controller.setDnd(enabled); }
    function setCenterOpen(outputId, open) {
        if (!controller) return;
        controller.setCenterOpen(outputId, open);
        // The center shows who serves notifications; refresh that if this shell is not the owner.
        if (open && state.status !== "available") startOwnerProbe();
    }
    function setCenterPresented(outputId, shown) { if (controller) controller.setCenterPresented(outputId, shown); }
    function setPresented(key, shown) { if (controller) controller.setPresented(key, shown); }
    function setHovered(key, hovered) { if (controller) controller.setHovered(key, hovered); }
    function recoverInvalidStorage() {
        if (config.documentStates.notifications.kind !== "invalid" && config.documentStates.notifications.kind !== "error") return false;
        persistenceDisabled = false;
        localRevision++;
        queueSave();
        return true;
    }
    function queueSave() {
        if (!restoreComplete || persistenceDisabled || preview || safeMode) return;
        saveQueued = true;
        saveDebounce.restart();
    }
    function saveArchive() {
        if (!saveQueued || saving || persistenceDisabled || !controller) return;
        saveQueued = false; saving = true; saveRevision = localRevision;
        const requestId = config.save("notifications", controller.archive());
        expectedSaveId = requestId;
    }
    function handleConfigResult(requestId, result) {
        if (requestId !== expectedSaveId) return;
        expectedSaveId = ""; saving = false;
        if (!result.ok) {
            if (result.reason === "invalid" || result.reason === "conflict") persistenceDisabled = true;
            else saveQueued = true;
        }
        if (saveQueued && !persistenceDisabled) saveDebounce.restart();
    }
    function loadArchive() {
        if (preview || safeMode) {
            controller.setStatus("unavailable");
            controller.restore({ schemaVersion: 1, dnd: false, records: [] });
            restoreComplete = true;
            drainPending();
            return;
        }
        const documentState = config.documentStates.notifications;
        if (!documentState || documentState.kind === "loading") return;
        if (documentState.kind === "invalid" || documentState.kind === "error") {
            persistenceDisabled = true;
            controller.setStatus("unavailable");
            restoreComplete = true;
            state = controller.read();
            drainPending();
            // Storage trouble is not an ownership verdict; restore the probed status once the server exists.
            if (serverLoader.item) startOwnerProbe();
            return;
        }
        controller.restore(config.documents.notifications);
        restoreComplete = true;
        state = controller.read();
        drainPending();
    }
    function drainPending() {
        const pending = pendingNotifications;
        pendingNotifications = [];
        pending.forEach(function(notification) { capture(notification); });
    }

    property string expectedSaveId: ""
    property Component timerFactory: Component {
        Timer { required property var callback; repeat: false; onTriggered: { callback(); destroy(); } }
    }
    property Connections configConnections: Connections {
        target: root.config
        function onDocumentChanged(name) { if (name === "notifications" && !root.restoreComplete) root.loadArchive(); }
        function onDocumentStatesChanged() { if (!root.restoreComplete) root.loadArchive(); }
        function onCommandFinished(requestId, result) { root.handleConfigResult(requestId, result); }
    }
    property Timer saveDebounce: Timer { interval: 250; repeat: false; onTriggered: root.saveArchive() }
    property Component ownerProbeWorker: Component {
        Process {
            id: process
            required property int generation
            property bool startedOnce: false
            property bool outputOverflow: false
            property string output: ""
            command: ["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", "org.freedesktop.Notifications"]
            stdout: SplitParser {
                splitMarker: ""
                onRead: function(chunk) { process.captureChunk(chunk); }
            }
            stderr: SplitParser { splitMarker: "" }
            property Timer deadline: Timer {
                interval: 1200
                running: false
                onTriggered: {
                    if (process.running) process.signal(9);
                    root.finishOwnerProbe(process, null);
                }
            }
            onStarted: { startedOnce = true; output = ""; outputOverflow = false; deadline.restart(); }
            onRunningChanged: if (!running && !startedOnce) root.finishOwnerProbe(process, null)
            onExited: function(code, exitStatus) {
                deadline.stop();
                if (code !== 0 || exitStatus !== 0 || outputOverflow) { root.finishOwnerProbe(process, null); return; }
                const match = /^\s*u\s+(\d+)\s*$/.exec(output);
                root.finishOwnerProbe(process, match ? Number(match[1]) : null);
            }
            function captureChunk(chunk) {
                if (output.length + String(chunk).length > 512) {
                    outputOverflow = true;
                    if (running) signal(9);
                    return;
                }
                output += String(chunk);
            }
        }
    }
    function finishOwnerProbe(worker, pid) {
        if (!worker) return;
        const current = ownerProbeProcess === worker && worker.generation === ownerProbeGeneration;
        if (ownerProbeProcess === worker) ownerProbeProcess = null;
        worker.deadline.stop();
        if (current && nativeEnabled && controller)
            controller.setStatus(pid === null ? "unavailable" : pid === Quickshell.processId ? "available" : "another-server");
        worker.destroy();
    }
    function startOwnerProbe() {
        if (!nativeEnabled || ownerProbeProcess || !controller) return;
        const worker = ownerProbeWorker.createObject(root, { generation: ++ownerProbeGeneration });
        if (!worker) { controller.setStatus("unavailable"); return; }
        ownerProbeProcess = worker;
        worker.running = true;
    }
    // Probed once when the server loads, then only while this shell does not own the name. Once it does,
    // nothing can take it: the native server registers without allowing replacement. Until then the name
    // can change hands with no native signal (the other daemon exits, the native server may take over), so
    // the slow re-check keeps the status honest; a delivered notification also proves ownership at once.
    property Timer ownerProbeTimer: Timer {
        interval: 60000
        repeat: true
        running: root.nativeEnabled && root.state.status !== "available"
        onTriggered: root.startOwnerProbe()
    }
    property Loader serverLoader: Loader {
        active: root.nativeEnabled
        sourceComponent: Component {
            NotificationServer {
                actionsSupported: true
                inlineReplySupported: true
                imageSupported: true
                bodyMarkupSupported: false
                bodyImagesSupported: false
                onNotification: function(notification) {
                    notification.tracked = true;
                    root.capture(notification);
                }
            }
        }
        onLoaded: Qt.callLater(function() { root.startOwnerProbe(); });
    }
    property Instantiator nativeWatches: Instantiator {
        model: root.serverLoader.item ? root.serverLoader.item.trackedNotifications : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onSummaryChanged() { root.refreshNative(modelData); }
            function onBodyChanged() { root.refreshNative(modelData); }
            function onAppNameChanged() { root.refreshNative(modelData); }
            function onAppIconChanged() { root.refreshNative(modelData); }
            function onUrgencyChanged() { root.refreshNative(modelData); }
            function onActionsChanged() { root.refreshNative(modelData); }
            function onHintsChanged() { root.refreshNative(modelData); }
            function onExpireTimeoutChanged() { root.refreshNative(modelData); }
            function onResidentChanged() { root.refreshNative(modelData); }
            function onTransientChanged() { root.refreshNative(modelData); }
            function onDesktopEntryChanged() { root.refreshNative(modelData); }
            function onImageChanged() { root.refreshNative(modelData); }
            function onHasInlineReplyChanged() { root.refreshNative(modelData); }
            function onInlineReplyPlaceholderChanged() { root.refreshNative(modelData); }
            function onClosed(reason) { root.nativeClosed(modelData, reason); }
        }
    }
    property var scheduler: ({ wallNow: function() { return root.wallNow(); },
        monotonicNow: function() { return root.monotonicElapsed; },
        schedule: function(delay, callback) { return root.schedule(delay, callback); } })
    property var effects: ({ changed: function(next) { root.setState(next); },
        closed: function(id, reason) { root.closeNative(id, reason); },
        action: function(id, key) { root.invokeNative(id, key); },
        reply: function(id, text) { root.replyNative(id, text); } })
    readonly property var popupPolicy: Policy.popupPolicy(config.documents.interface)
    onPopupPolicyChanged: if (controller) controller.setPopupPolicy(popupPolicy)
    // The card look; cards read it live, so a change in Settings restyles open popups and the center.
    readonly property string cardStyle: popupPolicy.style
    Component.onCompleted: {
        controller = Policy.createNotificationController(Quickshell.processId.toString(), scheduler, effects);
        controller.setPopupPolicy(popupPolicy);
        if (!restoreComplete) loadArchive();
    }
    property FrameAnimation monotonicClock: FrameAnimation {
        running: root.nativeEnabled && root.state.popups.length > 0
        onTriggered: root.monotonicElapsed += Math.max(0, Math.round(frameTime * 1000))
    }
    Component.onDestruction: if (controller) controller.dispose()
}
