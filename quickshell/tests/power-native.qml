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
    property bool serviceLossChecked: false
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
            if (root.scenario === "missing-utility" && state.kind === "unavailable"
                    && state.reason === "unavailable") {
                root.check("missing-utility-is-unavailable", true);
                root.finish();
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
            if (root.scenario === "set-fail" && root.results.length) {
                root.check("failed-set-does-not-claim-applied-profile", !root.results[0].result.ok
                    && adapter.profileState.kind === "unavailable");
                root.finish();
                return;
            }
            if (["success", "set-fail", "readback-timeout", "service-reconnect"].includes(root.scenario)
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
            if (root.scenario === "service-reconnect" && root.results.length) {
                if (!root.serviceLossChecked) {
                    root.serviceLossChecked = true;
                    root.check("lost-profile-service-invalidates-pending-readiness", !root.results[0].result.ok
                        && root.results[0].result.reason === "unavailable"
                        && adapter.profileState.kind === "unavailable");
                }
                if (adapter.profileState.kind === "ready"
                        && adapter.profileState.value.actual === "performance") {
                    root.check("profile-service-reconnect-restores-readback", true);
                    root.finish();
                }
            }
            if (root.ticks > 700) {
                root.check("fixture-completed-before-deadline", false, root.scenario + ":" + JSON.stringify(state));
                root.finish();
            }
        }
    }
}
