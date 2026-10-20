pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import "../logic/session-actions.mjs" as Rules

QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    readonly property bool writable: !preview && !safeMode
    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID")
    readonly property string userName: Rules.cleanIdentity(Quickshell.env("USER") || Quickshell.env("LOGNAME"))
    property string displayName: userName
    property string hostName: ""
    property var capabilities: ({ lock: "unavailable", logout: "unavailable", reboot: "unavailable", poweroff: "unavailable" })
    property var state: ({ action: "", confirmation: "", pending: "", error: "" })
    readonly property string confirmation: state.confirmation
    readonly property string pending: state.pending
    property var controller: null
    property var workers: []
    property bool started: false
    property bool refreshing: false
    property int readsRemaining: 0
    signal actionFinished(string action, bool ok)

    property FileView hostnameFile: FileView {
        path: root.preview ? "" : "/proc/sys/kernel/hostname"
        printErrors: false
        watchChanges: true
        onLoaded: root.hostName = Rules.cleanIdentity(text(), 253)
        onLoadFailed: root.hostName = ""
    }
    property Timer capabilityPoller: Timer {
        interval: 30000
        repeat: true
        running: !root.preview
        onTriggered: root.refreshCapabilities()
    }
    property Component workerComponent: Component {
        Process {
            id: worker
            required property var argv
            required property var callback
            property bool settled: false
            property bool startedOnce: false
            property string output: ""
            command: argv
            stdout: SplitParser {
                splitMarker: ""
                onRead: function(chunk) {
                    if (worker.output.length + String(chunk).length > 4096) {
                        root.finishWorker(worker, false, "invalid-response");
                        return;
                    }
                    worker.output += String(chunk);
                }
            }
            stderr: SplitParser { splitMarker: "" }
            property Timer startGuard: Timer {
                interval: 1500
                running: true
                onTriggered: if (!worker.startedOnce) root.finishWorker(worker, false, "unavailable")
            }
            property Timer deadline: Timer {
                interval: 10000
                onTriggered: root.finishWorker(worker, false, "timeout")
            }
            onStarted: { startedOnce = true; startGuard.stop(); deadline.restart(); }
            onExited: function(code, status) { root.finishWorker(worker, code === 0 && status === 0, "failed"); }
        }
    }

    function launch(argv, callback) {
        const worker = workerComponent.createObject(root, { argv: argv, callback: callback });
        if (!worker) { callback(false, "", "unavailable"); return; }
        workers = workers.concat([worker]);
        worker.running = true;
    }
    function finishWorker(worker, ok, reason) {
        if (!worker || worker.settled) return;
        worker.settled = true;
        worker.startGuard.stop();
        worker.deadline.stop();
        const callback = worker.callback;
        const output = worker.output;
        workers = workers.filter(function(item) { return item !== worker; });
        if (worker.running) worker.signal(9);
        worker.destroy();
        callback(ok, output, ok ? "" : reason);
    }
    function setCapability(action, value) {
        capabilities = Object.assign({}, capabilities, { [action]: value });
    }
    function finishRead() {
        readsRemaining = Math.max(0, readsRemaining - 1);
        if (!readsRemaining) refreshing = false;
    }
    function refreshCapabilities() {
        if (preview || refreshing) return;
        refreshing = true;
        readsRemaining = Rules.validSessionId(sessionId) ? 3 : 2;
        const base = ["busctl", "--system", "--timeout=5", "call", "org.freedesktop.login1",
            "/org/freedesktop/login1", "org.freedesktop.login1.Manager"];
        if (Rules.validSessionId(sessionId)) {
            launch(base.concat(["GetSession", "s", sessionId]), function(ok, output) {
                if (!root.preview) {
                    const valid = ok && /^o "\/org\/freedesktop\/login1\/session\/[A-Za-z0-9_]+"$/.test(output.trim());
                    root.setCapability("lock", valid ? "yes" : "unavailable");
                    root.setCapability("logout", valid ? "yes" : "unavailable");
                }
                root.finishRead();
            });
        } else {
            setCapability("lock", "unavailable");
            setCapability("logout", "unavailable");
        }
        for (const action of ["reboot", "poweroff"]) {
            launch(base.concat([action === "reboot" ? "CanReboot" : "CanPowerOff"]), function(ok, output) {
                if (!root.preview) root.setCapability(action, ok ? Rules.parseCapability(output) : "unavailable");
                root.finishRead();
            });
        }
    }
    function initialize() {
        if (!controller) controller = Rules.createSessionController({
            writable: function() { return root.writable; },
            capabilities: function() { return root.capabilities; },
            sessionId: function() { return root.sessionId; },
            changed: function(next) { root.state = next; },
            finished: function(action, ok) { root.actionFinished(action, ok); },
            execute: function(argv, done) {
                root.launch(argv, function(ok, output, reason) { done(ok, reason); });
            }
        });
        if (preview || started) return;
        started = true;
        if (/^[A-Za-z0-9_.][A-Za-z0-9_.-]{0,127}$/.test(userName))
            launch(["getent", "passwd", userName], function(ok, output) {
                if (!root.preview && ok) root.displayName = Rules.parseAccount(output, root.userName);
            });
        refreshCapabilities();
    }
    function canRequest(action) {
        return writable && !pending && ["yes", "challenge"].indexOf(capabilities[action]) >= 0;
    }
    function request(action) { initialize(); return controller.request(action); }
    function confirm() { return controller ? controller.confirm() : false; }
    function cancel() { if (controller) controller.cancel(); }
    function stopWorkers(reason) {
        for (const worker of workers.slice()) finishWorker(worker, false, reason);
        refreshing = false;
        readsRemaining = 0;
    }
    Component.onCompleted: initialize()
    onPreviewChanged: {
        if (preview) { started = false; cancel(); stopWorkers("read-only"); }
        else Qt.callLater(initialize);
    }
    onSafeModeChanged: if (safeMode) cancel()
    Component.onDestruction: {
        if (controller) controller.dispose();
        stopWorkers("service-stopped");
    }
}
