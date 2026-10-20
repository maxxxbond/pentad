import QtQuick
import QtQml
import Quickshell
import qs.theme
import "../services"
import "../features/bar"

ShellRoot {
    id: root
    property Desktop desktop: Desktop { telemetryEnabled: true }
    property QtObject fixtureServices: QtObject {
        readonly property Desktop desktop: root.desktop
    }
    property string scenario: Quickshell.env("PENTAD_DESKTOP_SCENARIO") || "capture-stop"
    property string expectedRequest: ""
    property var busyActions: ({})
    property int phase: 0
    property var checks: []
    property int gpuPublishedSamples: 0
    property int gpuMissingSamples: 0
    property int partialSamples: 0

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }

    function finish() {
        const passed = checks.length > 0 && checks.every(function(item) { return item.passed; });
        console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }

    function rejectDuplicate(action) {
        const requestId = desktop.command(action);
        busyActions = Object.assign({}, busyActions, { [requestId]: action });
    }

    Component.onCompleted: {
        Theme.resolve({ appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: true });
        if (["gpu", "gpu-slow", "gpu-cancel"].includes(root.scenario)) desktop.sampler.interval = 250;
    }

    ToolsWidget {
        id: tools
        services: root.fixtureServices
    }

    Connections {
        target: root.desktop
        function onTelemetryValueChanged() {
            if (root.scenario !== "gpu" && root.scenario !== "gpu-slow") return;
            const telemetry = root.desktop.telemetryValue;
            if (telemetry.gpus.length === 2) root.gpuPublishedSamples++;
            else if (root.gpuPublishedSamples > 0) root.gpuMissingSamples++;
            if (root.gpuPublishedSamples > 0 && (root.desktop.samplingPending || root.desktop.gpuDeadline.running
                || root.desktop.loadedFiles !== 7)) root.partialSamples++;
        }
        function onCommandFinished(requestId, result) {
            if (Object.prototype.hasOwnProperty.call(root.busyActions, requestId)) {
                const action = root.busyActions[requestId];
                const pending = action === "record" ? root.desktop.state.value.recordPending
                    : root.desktop.state.value.inhibitPending;
                root.check(action + "-duplicate-rejected-while-pending", !result.ok
                    && result.reason === "busy" && pending, JSON.stringify({ result: result, pending: pending }));
                const remaining = Object.assign({}, root.busyActions);
                delete remaining[requestId];
                root.busyActions = remaining;
                return;
            }
            if (requestId !== root.expectedRequest) {
                root.check("original-request-id", false, requestId + " != " + root.expectedRequest);
                root.finish();
                return;
            }
            if (root.scenario === "capture-stop") {
                if (root.phase === 1) {
                    root.check("screenshot-request-settled", result.ok && result.reason === "ok", JSON.stringify(result));
                    root.check("screenshot-result-path", typeof result.path === "string" && result.path.endsWith(".png"), result.path);
                    root.expectedRequest = root.desktop.command("record");
                    root.phase = 2;
                } else if (root.phase === 2) {
                    root.check("record-start-request-settled", result.ok && result.reason === "ok", JSON.stringify(result));
                    root.desktop.telemetryEnabled = false;
                    root.check("recording-state-independent-of-telemetry", root.desktop.state.kind === "ready"
                        && root.desktop.state.value.telemetryStatus.kind === "disabled"
                        && root.desktop.state.value.telemetry === null && root.desktop.state.value.recording === true,
                        JSON.stringify(root.desktop.state));
                    root.check("record-start-result-path", typeof result.path === "string" && result.path.endsWith(".mp4"), result.path);
                    root.phase = 3;
                    stopOwnedTimer.start();
                } else if (root.phase === 4) {
                    root.check("owned-record-stop-request-settled", result.ok && result.reason === "ok", JSON.stringify(result));
                    root.check("recording-state-cleared", root.desktop.state.kind === "ready" && !root.desktop.state.value.recording);
                    root.desktop.telemetryEnabled = true;
                    root.desktop.telemetryEnabled = false;
                    root.desktop.telemetryEnabled = true;
                    root.phase = 5;
                    telemetryWaiter.start();
                }
                return;
            }
            if (root.scenario === "xdg-fallback") {
                root.check("missing-xdg-dir-keeps-original-request-and-falls-back", result.ok
                    && result.reason === "ok" && typeof result.path === "string" && result.path.endsWith(".png"), JSON.stringify(result));
                root.finish();
                return;
            }
            if (root.scenario === "inhibit") {
                if (root.phase === 1) {
                    root.check("inhibit-start-request-settled", result.ok && root.desktop.state.value.inhibited, JSON.stringify(result));
                    root.phase = 2;
                    stopOwnedTimer.start();
                } else {
                    root.check("owned-inhibit-stop-request-settled", result.ok, JSON.stringify(result));
                    root.phase = 5;
                    verifyInhibitTimer.start();
                }
                return;
            }
            if (root.scenario === "guards") {
                if (root.phase === 1) {
                    root.check("record-pending-clears-after-start", result.ok && root.desktop.state.value.recording
                        && !root.desktop.state.value.recordPending, JSON.stringify({ result: result, state: root.desktop.state.value }));
                    root.phase = 2;
                    root.expectedRequest = root.desktop.command("record");
                    root.check("record-stop-becomes-pending", root.desktop.state.value.recordPending);
                    root.rejectDuplicate("record");
                } else if (root.phase === 2) {
                    root.check("record-pending-clears-after-stop", result.ok && !root.desktop.state.value.recording
                        && !root.desktop.state.value.recordPending, JSON.stringify({ result: result, state: root.desktop.state.value }));
                    root.phase = 3;
                    root.expectedRequest = root.desktop.command("inhibit");
                    root.check("inhibit-start-becomes-pending", root.desktop.state.value.inhibitPending);
                    root.rejectDuplicate("inhibit");
                } else if (root.phase === 3) {
                    root.check("inhibit-pending-clears-after-start", result.ok && root.desktop.state.value.inhibited
                        && !root.desktop.state.value.inhibitPending, JSON.stringify({ result: result, state: root.desktop.state.value }));
                    root.phase = 4;
                    root.expectedRequest = root.desktop.command("inhibit");
                    root.check("inhibit-stop-becomes-pending", root.desktop.state.value.inhibitPending);
                    root.rejectDuplicate("inhibit");
                } else if (root.phase === 4) {
                    root.check("inhibit-pending-clears-after-stop", result.ok && !root.desktop.state.value.inhibited
                        && !root.desktop.state.value.inhibitPending, JSON.stringify({ result: result, state: root.desktop.state.value }));
                    root.finish();
                }
                return;
            }
            root.check("failed-action-settled-with-original-id", !result.ok && result.reason === "unavailable", JSON.stringify(result));
            if (root.scenario === "dnd") root.check("dnd-stays-explicitly-unavailable", root.desktop.state.value.dndAvailable === false);
            if (root.scenario === "missing-recorder") root.check("failed-recorder-clears-start-state", !root.desktop.state.value.recording && !root.desktop.recordStarting);
            root.finish();
        }
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: {
            root.check("desktop-ready-independent-of-telemetry-loading", root.desktop.state.kind === "ready"
                && ["ready", "unavailable"].includes(root.desktop.state.value.telemetryStatus.kind));
            root.check("source-default-tools-order", tools.actions.map(function(item) { return item.action; }).join(",")
                === "dnd,inhibit,screenshot,record", tools.actions.map(function(item) { return item.action; }).join(","));
            const dndControl = tools.buttonRepeater.itemAt(0);
            const screenshotControl = tools.buttonRepeater.itemAt(2);
            const recordControl = tools.buttonRepeater.itemAt(3);
            root.check("dnd-action-blocked-context-remains-enabled", tools.actions[0].action === "dnd"
                && root.desktop.state.value.dndAvailable === false && !dndControl.actionAvailable && dndControl.enabled);
            root.check("capture-and-record-actions-enabled", screenshotControl.actionAvailable && recordControl.actionAvailable);
            if (["gpu", "gpu-slow", "gpu-cancel"].includes(root.scenario)) {
                gpuWaiter.start();
            } else if (root.scenario === "capture-stop") {
                root.expectedRequest = root.desktop.command("screenshot");
                root.phase = 1;
            } else if (root.scenario === "inhibit") {
                root.expectedRequest = root.desktop.command("inhibit");
                root.phase = 1;
            } else if (root.scenario === "guards") {
                root.expectedRequest = root.desktop.command("record");
                root.phase = 1;
                root.check("record-selection-is-pending", root.desktop.state.value.recordPending);
                root.rejectDuplicate("record");
            } else {
                const action = root.scenario === "missing-recorder" ? "record"
                    : root.scenario === "missing-picker" ? "color-picker"
                    : root.scenario === "dnd" ? "dnd"
                        : root.scenario === "missing-inhibit" ? "inhibit" : "screenshot";
                root.expectedRequest = root.desktop.command(action);
                root.phase = 1;
            }
        }
    }

    Timer {
        id: stopOwnedTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (root.scenario === "inhibit" && root.phase === 2) {
                root.expectedRequest = root.desktop.command("inhibit");
                root.phase = 4;
            } else if (root.scenario === "capture-stop" && root.phase === 3) {
                root.expectedRequest = root.desktop.command("record");
                root.phase = 4;
            }
        }
    }

    Timer {
        id: verifyInhibitTimer
        interval: 100
        repeat: false
        onTriggered: {
            root.check("owned-inhibitor-state-cleared", !root.desktop.state.value.inhibited);
            root.finish();
        }
    }

    Timer {
        id: telemetryWaiter
        interval: 30
        repeat: true
        onTriggered: {
            if (root.desktop.state.value.telemetryStatus.kind === "ready") {
                stop();
                root.check("procfs-reenabled-with-fresh-three-file-sample", root.desktop.telemetryReady
                    && root.desktop.state.value.telemetry && root.desktop.state.value.telemetry.memory !== null);
                root.finish();
            } else if (telemetryWaiter.telemetryAttempts++ >= 100) {
                stop();
                root.check("procfs-reenabled-with-fresh-three-file-sample", false, JSON.stringify(root.desktop.state.value.telemetryStatus));
                root.finish();
            }
        }
        property int telemetryAttempts: 0
    }

    Timer {
        id: gpuWaiter
        interval: 30
        repeat: true
        property int attempts: 0
        onTriggered: {
            const telemetry = root.desktop.state.value.telemetry;
            if (root.scenario === "gpu-cancel" && root.desktop.gpuExpected >= 3 && root.desktop.gpuDeadline.running) {
                stop();
                root.desktop.telemetryEnabled = false;
                root.check("disabling-telemetry-cancels-active-gpu-workers", root.desktop.gpuWorkers.length === 0
                    && root.desktop.state.value.telemetry === null
                    && root.desktop.state.value.telemetryStatus.kind === "disabled");
                gpuCancelVerifier.start();
            } else if (["gpu", "gpu-slow"].includes(root.scenario) && telemetry && telemetry.gpus.length === 2 && root.gpuPublishedSamples >= 5) {
                stop();
                root.check("five-atomic-gpu-samples-without-transient-unavailability", root.gpuMissingSamples === 0 && root.partialSamples === 0);
                root.check("drm-cards-and-legacy-sample-values", telemetry.gpuPercent === 0.64
                    && telemetry.gpus[0].memory.used === 100 && telemetry.gpus[1].memory.total === 2000,
                    JSON.stringify(telemetry));
                root.finish();
            } else if (gpuWaiter.attempts++ > 160) {
                stop();
                root.check(["gpu", "gpu-slow"].includes(root.scenario) ? "drm-cards-and-legacy-sample-values" : "gpu-sample-started-for-cancellation", false, JSON.stringify(telemetry));
                root.finish();
            }
        }
    }

    Timer {
        id: gpuCancelVerifier
        interval: 700
        repeat: false
        onTriggered: {
            root.check("cancelled-gpu-result-does-not-publish-after-disable", root.desktop.state.value.telemetry === null
                && root.desktop.state.value.telemetryStatus.kind === "disabled" && root.desktop.gpuWorkers.length === 0);
            root.finish();
        }
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: {
            root.check("desktop-command-completed-before-fixture-deadline", false, "Timed out in phase " + root.phase);
            root.finish();
        }
    }
}
