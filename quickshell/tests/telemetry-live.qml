import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: root
    property Desktop desktop: Desktop { preview: false; safeMode: true }
    property bool watching: false
    property int missingSamples: 0
    property int updates: 0
    property double lastSample: 0
    property var checks: []
    property double watchingSince: 0
    function check(name, passed) { checks.push({ name: name, passed: !!passed }); }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.every(function(c) { return c.passed; }) ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
    Connections {
        target: root.desktop
        function onStateChanged() {
            if (root.watching && !root.desktop.state.value.telemetry) root.missingSamples++;
        }
    }
    Timer {
        interval: 40
        repeat: true
        running: true
        onTriggered: {
            if (!root.desktop.telemetryReady) return;
            if (!root.watching) {
                root.watching = true;
                root.watchingSince = Date.now();
                root.lastSample = root.desktop.sampleTime;
                root.desktop.sample();
                root.check('refresh-retains-completed-telemetry-while-reading-procfs', root.desktop.telemetryReady
                    && root.desktop.state.value.telemetry !== null);
            } else if (root.desktop.sampleTime !== root.lastSample) {
                root.lastSample = root.desktop.sampleTime;
                root.updates++;
                if (root.updates < 3) return;
                root.check('three-real-samples-arrive-within-three-seconds', Date.now() - root.watchingSince < 3000);
                root.check('three-real-procfs-updates-without-missing-frame', root.missingSamples === 0);
                root.check('real-cpu-memory-and-network-values-available',
                    Number.isFinite(root.desktop.telemetryValue.cpuPercent)
                    && !!root.desktop.telemetryValue.memory
                    && Number.isFinite(root.desktop.telemetryValue.rxBytesPerSecond));
                root.watching = false;
                root.desktop.telemetryEnabled = false;
                root.check('disable-still-clears-sample-and-stops-readiness',
                    !root.desktop.telemetryReady && root.desktop.state.value.telemetry === null);
                root.finish();
            }
        }
    }
    Timer {
        interval: 10000
        running: true
        onTriggered: { root.check('live-telemetry-completes-before-deadline', false); root.finish(); }
    }
}
