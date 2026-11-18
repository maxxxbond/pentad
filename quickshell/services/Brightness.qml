pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../logic/brightness.mjs" as BrightnessLogic

QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property bool initialized: false
    property string outputId: ""
    property int nextRequestId: 1
    property var operation: null
    property var activeWorker: null
    property var brightnessValue: null
    // Where the wheel wants the level to be, ahead of the hardware; null when nothing is pending.
    property var desiredValue: null
    // The resolved backlight device or DDC bus (with its VCP max), so follow-up writes skip detection.
    property var resolvedTarget: null
    property string failureReason: "output-unavailable"
    readonly property bool active: !preview
    readonly property var state: preview || brightnessValue === null
        ? ({ kind: "unavailable", reason: failureReason, value: null })
        : ({ kind: "ready", value: brightnessValue })
    signal commandFinished(string requestId, var result)

    Component.onCompleted: {
        initialized = true;
        if (active && outputId) read();
    }
    onOutputIdChanged: {
        if (!initialized) return;
        cancelOperation("output-changed");
        desiredValue = null;
        resolvedTarget = null;
        brightnessValue = null;
        failureReason = "output-unavailable";
        if (active && outputId) read();
    }
    onPreviewChanged: {
        if (initialized && !preview && outputId && brightnessValue === null) read();
    }

    property Component commandWorker: Component {
        Process {
            id: worker
            required property string requestId
            required property string stage
            required property var argv
            property bool startedOnce: false
            property bool settled: false
            command: argv
            stdout: StdioCollector { }
            stderr: StdioCollector { }
            property Timer deadline: Timer {
                interval: 5000
                running: true
                onTriggered: {
                    if (worker.running) worker.signal(9);
                    root.finishWorker(worker, false, "timeout");
                }
            }
            onStarted: startedOnce = true
            onRunningChanged: {
                if (!running && !startedOnce && !settled)
                    root.finishWorker(worker, false, "start-failed");
            }
            onExited: function(code, exitStatus) {
                root.finishWorker(worker, code === 0 && exitStatus === 0, "command-failed");
            }
        }
    }

    function request(steps, goal) {
        const requestId = `brightness-${nextRequestId++}`;
        if (operation) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: "busy" }); });
            return requestId;
        }
        if (!active || !outputId || !/^[A-Za-z0-9_.:-]+$/.test(outputId)) {
            failureReason = preview ? "preview" : "output-unavailable";
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: failureReason }); });
            return requestId;
        }
        if (steps !== null && (!Number.isFinite(steps) || !Number.isInteger(steps))) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: "unsupported" }); });
            return requestId;
        }
        if (steps !== null && safeMode) {
            Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: "safe-mode" }); });
            return requestId;
        }
        const cached = resolvedTarget && resolvedTarget.outputId === outputId ? resolvedTarget : null;
        operation = { requestId: requestId, outputId: outputId, steps: steps, goal: goal === undefined ? null : goal, target: cached };
        if (cached && operation.goal !== null) writeGoal();
        else if (cached && cached.kind === "backlight")
            start("backlight-read", ["brightnessctl", "--device", cached.id, "--machine-readable", "info"]);
        else if (cached)
            start("ddc-read", ["ddcutil", "--bus", cached.bus, "getvcp", "10", "--terse"]);
        else if (BrightnessLogic.isInternalOutput(outputId))
            start("brightnessctl-list", ["brightnessctl", "--list", "--machine-readable"]);
        else
            start("ddc-detect", ["ddcutil", "detect", "--brief"]);
        return requestId;
    }

    function read() { return request(null); }
    function adjust(steps) { return request(steps); }
    // Wheel steps: the desired level moves at once and writes coalesce into one absolute target.
    function nudge(steps) {
        if (!Number.isInteger(steps) || !steps) return "";
        const base = desiredValue !== null ? desiredValue : brightnessValue;
        if (base === null || safeMode || !active) return adjust(steps);
        desiredValue = Math.round(BrightnessLogic.clampBrightness(base + steps * 0.05) * 100) / 100;
        return operation ? "" : request(steps, desiredValue);
    }
    function writeGoal() {
        const target = operation.target, goal = operation.goal;
        if (target.kind === "backlight") {
            start("backlight-set", ["brightnessctl", "--device", target.id, "--machine-readable", "set", `${Math.round(goal * 100)}%`]);
        } else {
            operation.written = Math.max(1, Math.round(goal * target.max));
            start("ddc-set", ["ddcutil", "--bus", target.bus, "setvcp", "10", String(operation.written)]);
        }
    }

    function start(stage, argv) {
        const worker = commandWorker.createObject(root, {
            requestId: operation.requestId, stage: stage, argv: argv
        });
        if (!worker) {
            finishOperation(false, "start-failed");
            return;
        }
        activeWorker = worker;
        worker.running = true;
    }

    function cancelOperation(reason) {
        if (!operation) return;
        const requestId = operation.requestId;
        operation = null;
        if (activeWorker) {
            const worker = activeWorker;
            activeWorker = null;
            worker.settled = true;
            worker.deadline.stop();
            if (worker.running) worker.signal(9);
            worker.destroy();
        }
        commandFinished(requestId, { ok: false, reason: reason });
    }

    function finishWorker(worker, ok, reason) {
        if (worker.settled) return;
        worker.settled = true;
        worker.deadline.stop();
        const stage = worker.stage;
        const output = worker.stdout.text.trim();
        const requestId = worker.requestId;
        worker.destroy();
        if (activeWorker === worker) activeWorker = null;
        if (!operation || operation.requestId !== requestId) return;
        if (operation.outputId !== outputId) return;
        if (!ok) { finishOperation(false, reason); return; }
        try {
            if (stage === "brightnessctl-list") {
                const devices = BrightnessLogic.parseBacklightList(output);
                if (devices.length !== 1) throw new Error("output-unavailable");
                operation.target = { kind: "backlight", id: devices[0].id, outputId: operation.outputId };
                resolvedTarget = operation.target;
                start("backlight-read", ["brightnessctl", "--device", devices[0].id, "--machine-readable", "info"]);
            } else if (stage === "ddc-detect") {
                const bus = BrightnessLogic.parseDdcBus(output, operation.outputId);
                if (bus === null) throw new Error("output-unavailable");
                operation.target = { kind: "ddc", bus: bus, max: 0, outputId: operation.outputId };
                start("ddc-read", ["ddcutil", "--bus", bus, "getvcp", "10", "--terse"]);
            } else if (stage === "backlight-read") {
                const value = BrightnessLogic.parseBacklightBrightness(output);
                if (operation.steps === null) finishOperation(true, "ok", value);
                else {
                    const next = Math.round(BrightnessLogic.clampBrightness(operation.goal !== null
                        ? operation.goal : value + operation.steps * 0.05) * 100);
                    start("backlight-set", ["brightnessctl", "--device", operation.target.id, "--machine-readable", "set", `${next}%`]);
                }
            } else if (stage === "backlight-set") {
                start("backlight-read-after-set", ["brightnessctl", "--device", operation.target.id, "--machine-readable", "info"]);
            } else if (stage === "backlight-read-after-set") {
                finishOperation(true, "ok", BrightnessLogic.parseBacklightBrightness(output));
            } else if (stage === "ddc-read") {
                const current = BrightnessLogic.parseDdcBrightness(output);
                operation.target.max = current.max;
                resolvedTarget = operation.target;
                if (operation.steps === null) finishOperation(true, "ok", Math.round(current.value * 100) / 100);
                else {
                    const next = Math.max(1, Math.round(BrightnessLogic.clampBrightness(operation.goal !== null
                        ? operation.goal : current.value + operation.steps * 0.05) * current.max));
                    operation.written = next;
                    start("ddc-set", ["ddcutil", "--bus", operation.target.bus, "setvcp", "10", String(next)]);
                }
            } else if (stage === "ddc-set") {
                // `setvcp` verifies the written value itself (ddcutil's default) and fails when the monitor
                // disagrees, so a second DDC read would only halve the rate of coalesced wheel writes.
                finishOperation(true, "ok", Math.round(operation.written / operation.target.max * 100) / 100);
            }
        } catch (error) {
            finishOperation(false, error.message || "invalid-output");
        }
    }

    function finishOperation(ok, reason, value) {
        if (!operation) return;
        const requestId = operation.requestId, goal = operation.goal;
        operation = null;
        if (ok) {
            brightnessValue = Math.round(value * 100) / 100;
            failureReason = "";
            // Steps that arrived while this write ran go out as one follow-up; an unchanged goal settles.
            const followUp = desiredValue !== null && desiredValue !== goal
                && Math.abs(desiredValue - brightnessValue) > 0.005;
            if (!followUp) desiredValue = null;
            commandFinished(requestId, { ok: true, value: brightnessValue });
            if (followUp) Qt.callLater(function() {
                if (!root.operation && root.desiredValue !== null) root.request(0, root.desiredValue);
            });
        } else {
            desiredValue = null;
            resolvedTarget = null;
            brightnessValue = null;
            failureReason = reason;
            commandFinished(requestId, { ok: false, reason: reason });
        }
    }
}
