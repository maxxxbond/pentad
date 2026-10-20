import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: root
    property string scenario: Quickshell.env("PENTAD_BRIGHTNESS_SCENARIO") || "internal-success"
    property string outputId: scenario.indexOf("external-") === 0 ? "HDMI-A-1" : "eDP-1"
    property var results: []
    property string adjustRequestId: ""
    property bool actionStarted: false
    property bool outputChanged: false
    property int ticks: 0
    property var checks: []

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        const ids = results.map(function(item) { return item.id; });
        check("request-ids-are-stable-and-unique", ids.length > 0
            && ids.every(function(id) { return /^brightness-\d+$/.test(id); })
            && new Set(ids).size === ids.length, JSON.stringify(ids));
        const ok = checks.length > 0 && checks.every(function(item) { return item.passed; });
        console.log("PENTAD_TEST " + JSON.stringify({ status: ok ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }

    Brightness {
        id: adapter
        preview: false
        safeMode: root.scenario === "safe-mode"
        outputId: root.outputId
    }
    Connections {
        target: adapter
        function onCommandFinished(requestId, result) {
            root.results = root.results.concat([{ id: requestId, result: result }]);
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            root.ticks++;
            if (root.scenario === "output-changed" && root.ticks === 2) {
                root.outputId = "HDMI-A-1";
                root.outputChanged = true;
            }
            if (root.scenario === "output-changed" && root.results.length >= 2) {
                staleReplyWait.start();
                stop();
                return;
            }
            if (["internal-coalesce", "external-coalesce"].includes(root.scenario)
                    && root.results.length === 1 && !root.actionStarted) {
                root.actionStarted = true;
                adapter.nudge(1); adapter.nudge(1); adapter.nudge(1);
                root.check("wheel-desired-moves-before-hardware", adapter.desiredValue === 0.55
                    && adapter.state.value === 0.4, JSON.stringify({ desired: adapter.desiredValue, state: adapter.state }));
            }
            if (["internal-coalesce", "external-coalesce"].includes(root.scenario)
                    && root.actionStarted && !adapter.operation && adapter.desiredValue === null && root.results.length >= 3) {
                root.check("burst-settles-on-desired-level", adapter.state.kind === "ready" && adapter.state.value === 0.55
                    && root.results.every(function(item) { return item.result.ok; }), JSON.stringify(root.results));
                root.finish();
                return;
            }
            if (["internal-success", "external-success", "safe-mode"].includes(root.scenario)
                    && root.results.length === 1 && !root.actionStarted) {
                root.actionStarted = true;
                root.adjustRequestId = adapter.adjust(1);
            }
            if (["internal-success", "external-success"].includes(root.scenario)
                    && root.results.length >= 2) {
                const expected = 0.45;
                root.check("initial-read-confirmed", root.results[0].result.ok && root.results[0].result.value === 0.4,
                    JSON.stringify(root.results[0]));
                root.check("adjust-result-matches-request-and-readback", root.results[1].id === root.adjustRequestId
                    && root.results[1].result.ok && root.results[1].result.value === expected
                    && adapter.state.kind === "ready" && adapter.state.value === expected,
                    JSON.stringify(root.results[1]));
                root.finish();
            } else if (root.scenario === "safe-mode" && root.results.length >= 2) {
                root.check("safe-mode-read-allowed", root.results[0].result.ok && root.results[0].result.value === 0.4);
                root.check("safe-mode-write-denied", root.results[1].id === root.adjustRequestId
                    && !root.results[1].result.ok && root.results[1].result.reason === "safe-mode",
                    JSON.stringify(root.results[1]));
                root.finish();
            } else if (["missing-utility", "invalid-device", "start-fail", "timeout"].includes(root.scenario)
                    && root.results.length > 0) {
                const expected = root.scenario === "invalid-device" ? "output-unavailable"
                    : root.scenario === "timeout" ? "timeout" : "start-failed";
                root.check("expected-native-failure", !root.results[0].result.ok
                    && root.results[0].result.reason === expected, JSON.stringify(root.results[0]));
                root.finish();
            }
        }
    }
    Timer {
        id: staleReplyWait
        interval: 2300
        repeat: false
        onTriggered: {
            root.check("output-change-cancels-old-request", root.outputChanged
                && root.results.length === 2 && root.results[0].result.reason === "output-changed",
                JSON.stringify(root.results));
            root.check("new-output-read-wins-without-stale-result", root.results[1].result.ok
                && root.results[1].result.value === 0.4 && adapter.state.kind === "ready"
                && adapter.state.value === 0.4, JSON.stringify({ results: root.results, state: adapter.state }));
            root.finish();
        }
    }
    Timer {
        interval: 16000
        running: true
        onTriggered: {
            root.check("fixture-completed-before-deadline", false, root.scenario + ":" + JSON.stringify(root.results));
            root.finish();
        }
    }
}
