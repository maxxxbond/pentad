import QtQuick
import Quickshell
import "services" as Services

ShellRoot {
    id: root
    property string mode: Quickshell.env("PENTAD_VISUALIZER_MODE") || "fake"
    property bool reducedMotion: mode === "reduced-motion"
    property Services.Visualizer visualizer: Services.Visualizer {
        preview: root.mode === "preview"
        safeMode: root.mode === "safe-mode"
        reducedMotion: root.reducedMotion
    }
    property var checks: []
    property int phase: 0
    property double phaseAt: 0

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        var passed = checks.every(function(item) { return item.passed; });
        console.log("PENTAD_VISUALIZER_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            if (root.mode === "reduced-motion") {
                root.visualizer.acquire("reduced-motion-client");
                root.phase = 1;
                root.phaseAt = Date.now();
                stop();
                root.gatedCheck.start();
            } else if (root.mode === "preview" || root.mode === "safe-mode") {
                root.visualizer.acquire("gated-client");
                root.phase = 1;
                root.phaseAt = Date.now();
                stop();
                root.gatedCheck.start();
            } else if (root.mode === "missing") {
                root.visualizer.acquire("missing-client");
                root.phase = 1;
                root.phaseAt = Date.now();
                stop();
                root.missingCheck.start();
            } else if (root.mode === "actual") {
                root.visualizer.acquire("actual-client");
                root.phase = 1;
                root.phaseAt = Date.now();
                stop();
                root.actualCheck.start();
            } else {
                root.visualizer.acquire("first");
                root.visualizer.acquire("second");
                root.phase = 1;
                root.phaseAt = Date.now();
                stop();
                root.fakeCheck.start();
            }
        }
    }
    property Timer fakeCheck: Timer {
        interval: 20
        repeat: true
        running: false
        onTriggered: {
            if (root.phase === 1 && root.visualizer.state.kind === "ready") {
                root.check("fake CAVA stdin receives one complete config",
                    root.visualizer.frame.values.length === 50
                    && root.visualizer.frame.values[0] === 0.5,
                    JSON.stringify(root.visualizer.frame));
                root.check("two consumers share one analyzer", root.visualizer.consumers.length === 2);
                root.visualizer.release("first");
                root.check("releasing one consumer keeps analyzer alive", root.visualizer.analyzer.running);
                root.visualizer.release("second");
                root.phase = 2;
                root.phaseAt = Date.now();
            } else if (root.phase === 2 && !root.visualizer.analyzer.running) {
                root.check("last release stops analyzer and clears frame",
                    !root.visualizer.frame.available && root.visualizer.frame.values.length === 0);
                root.visualizer.acquire("again");
                root.phase = 3;
            } else if (root.phase === 3 && root.visualizer.state.kind === "ready") {
                root.check("reacquire restarts analyzer with stdin enabled", root.visualizer.frame.values.length === 50);
                root.visualizer.release("again");
                root.phase = 4;
                root.phaseAt = Date.now();
            } else if (root.phase === 4 && !root.visualizer.analyzer.running) {
                root.check("second release stops restarted analyzer", !root.visualizer.frame.available);
                root.finish();
                stop();
            } else if (Date.now() - root.phaseAt > 5000) {
                root.check("fake analyzer lifecycle reached expected states", false,
                    JSON.stringify({ phase: root.phase, state: root.visualizer.state, running: root.visualizer.analyzer.running }));
                root.finish();
                stop();
            }
        }
    }
    property Timer gatedCheck: Timer {
        interval: 30
        repeat: true
        running: false
        onTriggered: {
            if (root.phase === 1 && Date.now() - root.phaseAt > 180) {
                var expected = root.mode === "preview" ? "preview"
                    : root.mode === "safe-mode" ? "safe-mode" : "reduced-motion";
                root.check(expected + " prevents analyzer start", !root.visualizer.analyzer.running
                    && root.visualizer.state.reason === expected, root.visualizer.state.reason);
                root.finish();
                stop();
            }
        }
    }
    property Timer missingCheck: Timer {
        interval: 30
        repeat: true
        running: false
        onTriggered: {
            if (root.phase === 1 && root.visualizer.state.kind === "unavailable"
                    && root.visualizer.state.reason !== "starting") {
                root.check("missing CAVA settles unavailable without restart loop",
                    !root.visualizer.analyzer.running && root.visualizer.consumers.length === 1,
                    root.visualizer.state.reason);
                root.finish();
                stop();
            } else if (Date.now() - root.phaseAt > 4000) {
                root.check("missing CAVA reports bounded failure", false, JSON.stringify(root.visualizer.state));
                root.finish();
                stop();
            }
        }
    }
    property Timer actualCheck: Timer {
        interval: 30
        repeat: true
        running: false
        onTriggered: {
            if (root.visualizer.state.kind === "ready") {
                root.check("installed CAVA produces a native 50-band frame",
                    root.visualizer.frame.values.length === 50, JSON.stringify(root.visualizer.frame));
                root.visualizer.release("actual-client");
                root.finish();
                stop();
            } else if (root.visualizer.state.kind === "unavailable"
                    && root.visualizer.state.reason !== "starting" && root.phaseAt + 3200 < Date.now()) {
                root.check("installed CAVA reached ready state", false, root.visualizer.state.reason);
                root.finish();
                stop();
            } else if (Date.now() - root.phaseAt > 5000) {
                root.check("installed CAVA frame arrived before timeout", false, JSON.stringify(root.visualizer.state));
                root.finish();
                stop();
            }
        }
    }
}
