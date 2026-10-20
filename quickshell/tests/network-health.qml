import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: root
    property string scenario: Quickshell.env("PENTAD_NETWORK_HEALTH_SCENARIO") || "ready"
    property var checks: []
    property var results: []
    property string requestId: ""
    property bool requested: false
    property bool finished: false
    property bool ownerLossObserved: false
    property int staleGeneration: -1
    property int ticks: 0

    QtObject { id: fakeNetworks; property var values: [] }
    QtObject {
        id: fakeWifi
        property string name: "fixture-wifi"
        property int type: 1
        property bool connected: false
        property bool scannerEnabled: false
        property var networks: fakeNetworks
    }
    QtObject { id: fakeDevices; property var values: [fakeWifi] }
    QtObject {
        id: fakeBackend
        property int backend: 1
        property bool ready: true
        property bool wifiEnabled: true
        property bool wifiHardwareEnabled: true
        property int connectivity: 4
        property var devices: fakeDevices
    }

    Network {
        id: adapter
        backendOverride: fakeBackend
        healthProbeOverride: true
        healthProbeInterval: 150
        wifiReadbackOverride: root.scenario.startsWith("wifi-")
        wifiReadbackInterval: 150
        safeMode: !root.scenario.startsWith("wifi-")
    }
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
        if (finished) return;
        finished = true;
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.ticks++;
            if (root.scenario === "loss-recovery") {
                if (!root.requested && adapter.state.kind === "ready") {
                    root.requested = true;
                    root.requestId = adapter.begin("wifi", false);
                }
                const result = root.results.find(function(item) { return item.id === root.requestId; });
                if (result && !root.ownerLossObserved) {
                    root.check("owner-loss-cancels-pending-request-once",
                        !result.result.ok && result.result.reason === "service-missing"
                        && root.results.filter(function(item) { return item.id === root.requestId; }).length === 1);
                    root.check("owner-loss-is-unavailable-not-stale-ready",
                        adapter.state.kind === "unavailable" && adapter.state.reason === "service-missing");
                    root.ownerLossObserved = true;
                    root.waitingForRecovery = true;
                }
                if (root.waitingForRecovery && adapter.state.kind === "ready") {
                    root.waitingForRecovery = false;
                    root.check("owner-recovery-restores-backend-readiness", adapter.state.kind === "ready");
                    root.finish();
                    return;
                }
            } else if (root.scenario.startsWith("wifi-")) {
                if (!root.requested && adapter.state.kind === "ready" && adapter.wifiReadbackReady) {
                    root.requested = true;
                    root.requestId = adapter.setWifiEnabled(false);
                    root.check("native-property-setter-is-optimistic-not-confirmed",
                        fakeBackend.wifiEnabled === false && adapter.state.value.wifiEnabled === true
                        && adapter.operation && adapter.operation.target === false && root.results.length === 0,
                        JSON.stringify({ fake: fakeBackend.wifiEnabled, actual: adapter.state.value.wifiEnabled,
                            operation: adapter.operation, resultCount: root.results.length,
                            readbackReady: adapter.wifiReadbackReady, readbackReason: adapter.wifiReadbackReason }));
                }
                const result = root.results.find(function(item) { return item.id === root.requestId; });
                if (result) {
                    const count = root.results.filter(function(item) { return item.id === root.requestId; }).length;
                    if (root.scenario === "wifi-delayed") {
                        root.check("wifi-toggle-completes-after-delayed-daemon-readback", result.result.ok
                            && adapter.state.kind === "ready" && adapter.state.value.wifiEnabled === false && count === 1,
                            JSON.stringify({ result: result.result, state: adapter.state.kind,
                                actual: adapter.state.value ? adapter.state.value.wifiEnabled : null, count: count }));
                    } else if (root.scenario === "wifi-mismatch") {
                        root.check("permanent-mismatch-times-out-and-keeps-last-actual", !result.result.ok
                            && result.result.reason === "timeout" && adapter.state.value.wifiEnabled === true && count === 1);
                    } else if (root.scenario === "wifi-getfailure") {
                        root.check("property-read-failure-does-not-claim-write", !result.result.ok
                            && result.result.reason === "read-only-unavailable"
                            && adapter.state.value.wifiEnabled === null && count === 1);
                    } else if (root.scenario === "wifi-timeout") {
                        root.check("property-read-timeout-settles-request-once", !result.result.ok
                            && result.result.reason === "timeout" && adapter.state.value.wifiEnabled === null && count === 1);
                    } else if (root.scenario === "wifi-owner-loss") {
                        root.check("owner-loss-cancels-optimistic-toggle-once", !result.result.ok
                            && result.result.reason === "service-missing" && adapter.state.kind === "unavailable" && count === 1);
                    }
                    root.finish();
                    return;
                }
            } else if (root.scenario === "late-generation") {
                if (root.staleGeneration < 0 && adapter.ownerProbeGeneration > 0)
                    root.staleGeneration = adapter.ownerProbeGeneration;
                if (adapter.state.kind === "ready" && root.staleGeneration >= 0
                    && adapter.ownerProbeGeneration > root.staleGeneration) {
                    adapter.applyOwnerProbeResult(root.staleGeneration, false, "service-missing");
                    root.check("late-owner-result-cannot-overwrite-newer-generation",
                        adapter.state.kind === "ready" && adapter.ownerPresent);
                    root.finish();
                    return;
                }
            } else if (!root.requested) {
                if (root.scenario !== "ready" && adapter.state.kind === "unavailable"
                    && adapter.state.reason === (root.scenario === "owner-missing" ? "service-missing" : "read-only-unavailable")) {
                    root.requested = true;
                    root.check(root.scenario === "owner-missing"
                        ? "dbus-owner-false-is-reported-service-missing"
                        : "probe-failure-is-explicitly-unavailable", true, adapter.state.reason);
                    root.finish();
                    return;
                }
                if (root.scenario === "ready" && adapter.state.kind === "ready") {
                    root.requested = true;
                    root.check("owner-true-enables-backend", adapter.state.value.devices.length === 1);
                    root.finish();
                    return;
                }
            }
            if (root.ticks > 400) {
                root.check("health-fixture-timed-out", false, `${root.scenario}:${adapter.state.kind}/${adapter.state.reason}`);
                root.finish();
            }
        }
    }
    property bool waitingForRecovery: false
}
