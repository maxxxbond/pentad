pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "../logic/power-profiles.mjs" as Profiles

// Power profiles come from power-profiles-daemon. The native PowerProfiles singleton reports
// changes without polling; one bounded busctl probe checks that the daemon exists and lists its
// profiles, and a write goes through busctl so its result and the readback are observed.
QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property bool initialized: false
    property int nextRequestId: 1
    property var profiles: []
    property string actualProfile: ""
    property string desiredProfile: ""
    property string failureReason: "service-missing"
    property var operation: null
    property var worker: null
    readonly property bool active: !preview
    readonly property var batteryState: preview || !UPower.displayDevice.ready
        ? ({ kind: "unavailable", reason: preview ? "preview" : "service-missing" })
        : ({ kind: "ready", value: { battery: battery } })
    readonly property var state: batteryState
    readonly property var profileState: preview || profiles.length === 0 || !actualProfile
        ? ({ kind: "unavailable", reason: preview ? "preview" : failureReason })
        : ({ kind: "ready", value: { profiles: profiles.slice(), actual: actualProfile,
            desired: desiredProfile, pending: !!operation } })
    readonly property var battery: {
        if (preview) return null;
        const device = UPower.displayDevice;
        if (!device.isPresent || !device.isLaptopBattery) return null;
        const charge = Number.isFinite(device.percentage)
            ? Math.max(0, Math.min(100, device.percentage * 100)) : null;
        const chargeState = device.state === UPowerDeviceState.Charging ? "charging"
            : device.state === UPowerDeviceState.Discharging ? "discharging"
            : device.state === UPowerDeviceState.FullyCharged ? "full" : "unknown";
        return { percent: charge, state: chargeState };
    }
    signal commandFinished(string requestId, var result)

    property Component commandWorker: Component {
        Process {
            id: process
            required property var argv
            required property string stage
            property bool startedOnce: false
            property bool settled: false
            property bool outputOverflow: false
            command: argv
            property string output: ""
            stdout: SplitParser {
                splitMarker: ""
                onRead: function(chunk) { process.captureChunk(chunk); }
            }
            stderr: SplitParser { splitMarker: "" }
            property Timer deadline: Timer {
                interval: 3000
                running: true
                onTriggered: {
                    if (process.running) process.signal(9);
                    root.finishWorker(process, false, "timeout");
                }
            }
            onStarted: startedOnce = true
            onRunningChanged: if (!running && !startedOnce && !settled)
                root.finishWorker(process, false, "unavailable");
            onExited: function(code, exitStatus) {
                root.finishWorker(process, code === 0 && exitStatus === 0 && !outputOverflow,
                    outputOverflow ? "invalid-response" : "exit");
            }
            function captureChunk(chunk) {
                const text = String(chunk);
                const next = output.length + text.length;
                if (next > 16384) {
                    outputOverflow = true;
                    if (running) signal(9);
                    return;
                }
                output += text;
            }
        }
    }

    // The daemon announces profile changes over D-Bus; nothing here polls.
    property Connections nativeProfiles: Connections {
        target: root.active ? PowerProfiles : null
        function onProfileChanged() { root.nativeProfileChanged(); }
        function onHasPerformanceProfileChanged() {
            if (root.profiles.length === 0
                    || PowerProfiles.hasPerformanceProfile !== root.profiles.includes("performance"))
                root.requestProbe();
        }
    }
    property Timer probeLater: Timer {
        interval: 250
        repeat: false
        onTriggered: if (root.worker || root.operation) restart(); else root.probe();
    }
    property Timer confirmationDeadline: Timer {
        interval: 5000
        repeat: false
        onTriggered: root.finishOperation(false, "timeout");
    }
    property Timer readbackTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: {
            if (!root.operation) return;
            if (root.worker) restart();
            else root.start("get", Array.from(Profiles.readbackCommand));
        }
    }

    Component.onCompleted: {
        initialized = true;
        if (active) probe();
    }
    onPreviewChanged: {
        if (preview) {
            cancelOperation("preview");
            probeLater.stop();
            profiles = [];
            actualProfile = "";
            failureReason = "preview";
        } else if (initialized) probe();
    }

    function probe() { start("probe", Array.from(Profiles.probeCommand)); }
    function requestProbe() {
        if (!active || (worker && worker.stage === "probe")) return;
        probeLater.restart();
    }
    function nativeProfileName() {
        const value = PowerProfiles.profile;
        return value === PowerProfile.Performance ? "performance"
            : value === PowerProfile.PowerSaver ? "power-saver" : "balanced";
    }
    function nativeProfileChanged() {
        if (!active) return;
        const name = nativeProfileName();
        if (Profiles.validProfile(name, profiles)) observe(name);
        else requestProbe();
    }
    function observe(actual) {
        actualProfile = actual;
        failureReason = "";
        if (!operation) desiredProfile = actual;
        else if (actual === operation.profile) finishOperation(true, "ok");
    }
    function start(stage, argv) {
        if (!active || worker) return;
        const instance = commandWorker.createObject(root, { stage: stage, argv: argv });
        if (!instance) {
            if (stage === "probe") failProbe("unavailable");
            else finishOperation(false, "unavailable");
            return;
        }
        worker = instance;
        instance.running = true;
    }
    function finishWorker(instance, ok, reason) {
        if (instance.settled) return;
        instance.settled = true;
        instance.deadline.stop();
        const stage = instance.stage;
        const output = instance.output.trim();
        instance.destroy();
        if (worker === instance) worker = null;
        if (!active) return;
        // A started command that exits with an error means the daemon did not answer.
        const why = reason === "exit" ? (stage === "probe" ? "service-missing" : "unavailable") : reason;
        if (stage === "probe") {
            try {
                if (!ok) throw new Error(why);
                const result = Profiles.parseProbe(output);
                profiles = result.profiles;
                observe(result.actual);
            } catch (error) {
                failProbe(error.message || "invalid-response");
                if (operation) finishOperation(false, failureReason);
            }
            return;
        }
        if (!operation) return;
        if (!ok) {
            finishOperation(false, why);
            requestProbe();
            return;
        }
        if (stage === "set") {
            // The daemon's change notification or the readback confirms the new profile.
            readbackTimer.restart();
            return;
        }
        try {
            observe(Profiles.parseReadback(output, profiles));
            if (operation) readbackTimer.restart();
        } catch (error) {
            finishOperation(false, error.message || "invalid-response");
            requestProbe();
        }
    }
    function failProbe(reason) {
        profiles = [];
        actualProfile = "";
        failureReason = reason || "unavailable";
    }
    function setProfile(profile) {
        const requestId = `power-${nextRequestId++}`;
        if (operation || worker) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: "busy" }); });
            return requestId;
        }
        if (!active || safeMode) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: preview ? "preview" : "safe-mode" }); });
            return requestId;
        }
        if (profileState.kind !== "ready" || !Profiles.validProfile(profile, profiles)) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: "unavailable" }); });
            return requestId;
        }
        desiredProfile = profile;
        operation = { requestId: requestId, profile: profile };
        confirmationDeadline.restart();
        start("set", Profiles.setCommand(profile, profiles));
        return requestId;
    }
    function finishOperation(ok, reason) {
        if (!operation) return;
        const current = operation;
        operation = null;
        confirmationDeadline.stop();
        readbackTimer.stop();
        if (!ok) desiredProfile = actualProfile;
        Qt.callLater(function() {
            commandFinished(current.requestId, ok ? { ok: true, value: actualProfile }
                : { ok: false, reason: reason, actual: actualProfile });
        });
    }
    function cancelOperation(reason) {
        if (worker) {
            const instance = worker;
            worker = null;
            instance.settled = true;
            instance.deadline.stop();
            if (instance.running) instance.signal(9);
            instance.destroy();
        }
        if (operation) finishOperation(false, reason);
    }
    Component.onDestruction: {
        probeLater.stop();
        cancelOperation("service-stopped");
    }
}
