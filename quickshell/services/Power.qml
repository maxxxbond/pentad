pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "../logic/power-profiles.mjs" as Profiles

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
                    outputOverflow ? "invalid-response" : "unavailable");
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

    property Timer poller: Timer {
        interval: 2500
        repeat: true
        running: root.initialized && root.active
        onTriggered: if (!root.operation && !root.worker) root.start("list", ["powerprofilesctl", "list"]);
    }
    property Timer confirmationDeadline: Timer {
        interval: 5000
        repeat: false
        onTriggered: root.finishOperation(false, "timeout");
    }
    property Timer readbackTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: if (root.operation && !root.worker)
            root.start("get", ["powerprofilesctl", "get"]);
    }

    Component.onCompleted: {
        initialized = true;
        if (active) start("list", ["powerprofilesctl", "list"]);
    }
    onPreviewChanged: {
        if (preview) {
            cancelOperation("preview");
            profiles = [];
            actualProfile = "";
            failureReason = "preview";
        } else if (initialized) start("list", ["powerprofilesctl", "list"]);
    }

    function start(stage, argv) {
        if (!active || worker) return;
        const instance = commandWorker.createObject(root, { stage: stage, argv: argv });
        if (!instance) { failProbe("unavailable"); return; }
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
        if (!ok) {
            if (operation) {
                if (["unavailable", "timeout", "io"].includes(reason)) failProbe(reason);
                finishOperation(false, reason);
            }
            else failProbe(reason);
            return;
        }
        try {
            if (stage === "list") {
                profiles = Profiles.parseProfiles(output);
                if (operation) start("set", ["powerprofilesctl", "set", operation.profile]);
                else start("get", ["powerprofilesctl", "get"]);
            } else if (stage === "set") {
                start("get", ["powerprofilesctl", "get"]);
            } else if (stage === "get") {
                const actual = Profiles.parseActiveProfile(output, profiles);
                actualProfile = actual;
                if (!operation) desiredProfile = actual;
                failureReason = "";
                if (operation && actual === operation.profile) finishOperation(true, "ok");
                else if (operation) readbackTimer.restart();
            }
        } catch (error) {
            if (operation) finishOperation(false, error.message || "invalid-response");
            else failProbe(error.message || "invalid-response");
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
        if (state.kind !== "ready" || !Profiles.validProfile(profile, profiles)) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: "unavailable" }); });
            return requestId;
        }
        desiredProfile = profile;
        operation = { requestId: requestId, profile: profile };
        confirmationDeadline.restart();
        start("set", ["powerprofilesctl", "set", profile]);
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
    Component.onDestruction: cancelOperation("service-stopped")
}
