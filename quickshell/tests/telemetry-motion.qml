import QtQuick
import Quickshell
import qs.theme
import "../features/bar"

ShellRoot {
    id: root
    property var sample: snapshot(0.2)
    property var checks: []
    property var savedGpu: null
    property var savedCpu: null
    property var savedDisc: null
    property int intermediateFrames: 0
    property int resetFrames: 0
    property int replacedFrames: 0
    property QtObject services: QtObject {
        readonly property QtObject desktop: QtObject {
            readonly property var state: ({ kind: "ready", value: { telemetry: root.sample } })
        }
    }
    function snapshot(ratio) {
        return { cpuPercent: ratio, gpuPercent: ratio, memory: { used: ratio * 1073741824, total: 1073741824 },
            gpus: [{ id: "card0", load: ratio, memory: { used: ratio * 1073741824, total: 1073741824 } }],
            rxBytesPerSecond: 1024, txBytesPerSecond: 2048 };
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const result = find(child, name);
            if (result) return result;
        }
        return null;
    }
    function check(name, passed) { checks.push({ name: name, passed: !!passed }); }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({ status: checks.every(c => c.passed) ? "pass" : "fail", checks: checks }));
        Qt.quit();
    }
    Component.onCompleted: Theme.resolve({ appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: false })

    FloatingWindow {
        visible: true
        implicitWidth: 360
        implicitHeight: 300
        color: Theme.tokens.surface
        TelemetryWidget { id: bar; x: 24; y: 12; services: root.services }
        TelemetryDetails { id: details; x: 24; y: 56; width: implicitWidth; height: implicitHeight; services: root.services; value: root.sample }
    }
    FrameAnimation {
        running: steps.step >= 2 && steps.step <= 6
        onTriggered: {
            const cpu = root.find(details, "telemetry-resource-gauge");
            const gpu = details.gpuDelegates.itemAt(0);
            const disc = bar.metricRepeater.itemAt(0).children[0];
            if (cpu !== root.savedCpu || gpu !== root.savedGpu || disc !== root.savedDisc) root.replacedFrames++;
            const gpuRing = root.find(gpu, "telemetry-resource-gauge");
            if (cpu.displayedFraction < 0.19 || gpuRing.displayedFraction < 0.19 || disc.displayedRatio < 0.19) root.resetFrames++;
            if (Math.abs(cpu.displayedFraction - cpu.fraction) > 0.001
                && Math.abs(gpuRing.displayedFraction - gpuRing.fraction) > 0.001
                && Math.abs(disc.displayedRatio - disc.ratio) > 0.001) root.intermediateFrames++;
        }
    }
    Timer {
        id: steps
        interval: 250
        repeat: true
        running: true
        property int step: 0
        onTriggered: {
            step++;
            if (step === 1) {
                root.savedCpu = root.find(details, "telemetry-resource-gauge");
                root.savedGpu = details.gpuDelegates.itemAt(0);
                root.savedDisc = bar.metricRepeater.itemAt(0).children[0];
            } else if (step <= 6) {
                root.sample = root.snapshot(step % 2 ? 0.4 : 0.8);
            } else if (step === 7) {
                root.check("quarter-second-updates-retain-gpu-gauges-and-bar-discs", root.replacedFrames === 0);
                root.check("arcs-interpolate-together-on-rendered-frames", root.intermediateFrames >= 5);
                root.check("updates-never-reset-arcs-to-empty", root.resetFrames === 0);
                Theme.resolve({ appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: true });
                root.sample = root.snapshot(0.6);
            } else if (step === 8) {
                const gpu = root.find(details.gpuDelegates.itemAt(0), "telemetry-resource-gauge");
                root.check("reduced-motion-updates-directly", Math.abs(gpu.displayedFraction - 0.6) < 0.000001
                    && Math.abs(root.savedDisc.displayedRatio - 0.6) < 0.000001);
                root.sample = null;
            } else if (step === 9) {
                const gpu = root.find(details.gpuDelegates.itemAt(0), "telemetry-resource-gauge");
                root.check("real-unavailability-clears-the-arc", gpu.fraction === 0 && gpu.displayedFraction === 0);
                root.sample = root.snapshot(0.7);
            } else if (step === 10) {
                root.check("sensor-recovery-reuses-existing-gpu-slot", root.savedGpu === details.gpuDelegates.itemAt(0));
                root.finish();
            }
        }
    }
    Timer { interval: 7000; running: true; onTriggered: { root.check("motion-test-completes", false); root.finish(); } }
}
