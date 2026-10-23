import QtQuick
import Quickshell
import "../services"
import "../features/system"

ShellRoot {
    id: root
    property string scenario: Quickshell.env("PENTAD_POWER_SCENARIO") || "success"
    property var checks: []
    property var results: []
    property string requestId: ""
    property bool requested: false
    property bool sawDesiredActualSplit: false
    property bool batteryContractChecked: false
    property int readyTick: -1
    property int ticks: 0

    Power { id: adapter; preview: false; safeMode: root.scenario === "safe-mode" }
    PowerControls { width: 360; visible: false; power: adapter }
    Connections {
        target: adapter
        function onCommandFinished(id, result) {
            root.results = root.results.concat([{ id: id, result: result }]);
        }
    }
    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length && checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }
    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            root.ticks++;
            if (!root.batteryContractChecked) {
                root.batteryContractChecked = true;
                root.check("public-power-state-keeps-battery-shape", adapter.state.kind === adapter.batteryState.kind
                    && (adapter.state.kind !== "ready" || Object.prototype.hasOwnProperty.call(adapter.state.value, "battery")));
            }
            const state = adapter.profileState;
            if (root.scenario === "missing-utility" && !adapter.worker && state.kind === "unavailable"
                    && state.reason === "unavailable") {
                root.check("missing-utility-is-unavailable", true);
                root.finish();
                return;
            }
            if (root.scenario === "service-missing" && !adapter.worker && root.ticks > 8) {
                root.check("missing-daemon-is-service-missing", state.kind === "unavailable"
                    && state.reason === "service-missing", JSON.stringify(state));
                root.finish();
                return;
            }
            if (root.scenario === "idle" && state.kind === "ready") {
                if (root.readyTick < 0) root.readyTick = root.ticks;
                // About three seconds idle: the runner checks that only the first probe ran.
                if (root.ticks - root.readyTick > 120) {
                    root.check("idle-profile-stays-ready", state.value.actual === "balanced" && !adapter.worker);
                    root.finish();
                }
                return;
            }
            if (root.scenario === "safe-mode" && state.kind === "ready" && !root.requested) {
                root.requested = true;
                root.requestId = adapter.setProfile("performance");
            }
            if (state.kind === "ready" && state.value.pending && state.value.actual !== state.value.desired)
                root.sawDesiredActualSplit = true;
            if (root.scenario === "safe-mode" && root.results.length) {
                root.check("safe-mode-denies-profile-write", root.results[0].id === root.requestId
                    && !root.results[0].result.ok && root.results[0].result.reason === "safe-mode");
                root.check("safe-mode-state-remains-readable", adapter.profileState.kind === "ready"
                    && adapter.profileState.value.actual === "balanced");
                root.finish();
                return;
            }
            if (root.scenario === "set-fail" && root.results.length && state.kind === "ready"
                    && !adapter.worker && !adapter.probeLater.running) {
                root.check("failed-set-keeps-last-confirmed-profile", !root.results[0].result.ok
                    && root.results[0].result.reason === "unavailable"
                    && state.value.actual === "balanced" && state.value.desired === "balanced"
                    && !state.value.pending, JSON.stringify(state));
                root.finish();
                return;
            }
            if (["success", "set-fail", "readback-timeout", "service-lost"].includes(root.scenario)
                    && state.kind === "ready" && !root.requested) {
                root.check("initial-profile-is-read-from-service", state.value.actual === "balanced"
                    && state.value.profiles.indexOf("performance") >= 0);
                root.requested = true;
                root.requestId = adapter.setProfile("performance");
            }
            if (root.scenario === "success" && root.results.length) {
                root.check("request-finishes-only-after-actual-readback", root.results[0].id === root.requestId
                    && root.results[0].result.ok && root.results[0].result.value === "performance"
                    && adapter.profileState.value.actual === "performance");
                root.check("pending-exposed-desired-separately-from-actual", root.sawDesiredActualSplit);
                root.finish();
            }
            if (root.scenario === "readback-timeout" && root.results.length) {
                root.check("delayed-readback-times-out-with-last-actual", !root.results[0].result.ok
                    && root.results[0].result.reason === "timeout"
                    && adapter.profileState.kind === "ready"
                    && adapter.profileState.value.actual === "balanced"
                    && adapter.profileState.value.desired === "balanced"
                    && !adapter.profileState.value.pending);
                root.finish();
            }
            if (root.scenario === "service-lost" && root.results.length && state.kind === "unavailable"
                    && !adapter.worker && !adapter.probeLater.running) {
                root.check("lost-profile-service-becomes-unavailable", !root.results[0].result.ok
                    && state.reason === "service-missing", JSON.stringify(state));
                root.finish();
                return;
            }
            if (root.ticks > 700) {
                root.check("fixture-completed-before-deadline", false, root.scenario + ":" + JSON.stringify(state));
                root.finish();
            }
        }
    }
}
