import QtQuick
import QtQuick.Window
import Quickshell
import qs.services
import qs.shell
import qs.components

ShellRoot {
    id: root
    property Services services: Services { preview: true; safeMode: true }
    property int step: 0
    property string side: ""
    property string direction: ""
    property double requestedAt: 0
    property double lastFrameAt: 0
    property var samples: []
    property var measurements: []
    property var positions: []
    property var popupChecks: []
    property real firstPopupX: 0
    property Item probeAnchor: Item {
        parent: bar.rightPopup.rightContent
        x: 20; y: 20; width: 24; height: 24
    }
    property AttachedPopover probe: AttachedPopover {
        anchorItem: root.probeAnchor
        manager: root.services.popups
        Text { width: 140; height: 40; text: "Isolated menu probe" }
    }
    readonly property var host: side === "left" ? bar.leftPopup : side === "right" ? bar.rightPopup : null
    property bool collecting: false
    property real sampledProgress: -1

    function frame() {
        if (!collecting || !host || !host.visible) return;
        if (host.slideProgress === sampledProgress) return;
        sampledProgress = host.slideProgress;
        const now = Date.now();
        samples.push(now - lastFrameAt);
        positions.push(sampledProgress);
        lastFrameAt = now;
    }
    function finishSample() {
        if (!collecting) return;
        collecting = false;
        const gaps = samples.slice(1).sort(function(a, b) { return a - b; });
        measurements.push({ side: side, direction: direction,
            cycle: Math.floor((step - 1) / 4), frames: samples.length,
            frameGapsMs: samples.slice(), positions: positions.slice(),
            firstFrameMs: samples.length ? samples[0] : null,
            p95GapMs: gaps.length ? gaps[Math.ceil(gaps.length * 0.95) - 1] : null,
            maxGapMs: gaps.length ? gaps[gaps.length - 1] : null });
    }
    function beginSample(nextSide, nextDirection) {
        side = nextSide;
        direction = nextDirection;
        samples = [];
        positions = [];
        sampledProgress = -1;
        requestedAt = Date.now();
        lastFrameAt = requestedAt;
        collecting = true;
    }
    function report() {
        const checks = [
            { name: "left-and-right-open-close-samples-collected", passed: measurements.length === 20 },
            { name: "every-opening-delivered-a-frame", passed: measurements.filter(function(m) {
                return m.direction === "open";
            }).every(function(m) { return m.frames > 0; }) },
            { name: "motion-measurements", passed: true, detail: JSON.stringify(measurements) }
        ].concat(popupChecks);
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(function(check) { return check.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }

    BarWindow {
        id: bar
        services: root.services
        screen: Quickshell.screens[0]
        // Hovering the bar prepares a drawer; the profile measures prepared drawers.
        Component.onCompleted: {
            bar.leftPopup.prepareSide('left');
            bar.rightPopup.prepareSide('right');
        }
    }
    Connections {
        target: root.host ? root.host.attachedSurface.Window.window : null
        function onFrameSwapped() { root.frame(); }
    }
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            if (bar.leftPopup.leftContentStatus !== Loader.Ready
                    || bar.rightPopup.rightContentStatus !== Loader.Ready) {
                console.log("PENTAD_TEST " + JSON.stringify({ status: "fail", checks: [
                    { name: "menus-prepared", passed: false, detail: JSON.stringify({
                        left: [bar.leftPopup.leftPrepared, bar.leftPopup.leftContentStatus],
                        right: [bar.rightPopup.rightPrepared, bar.rightPopup.rightContentStatus] }) }
                ] }));
                Qt.quit();
                return;
            }
            cycleTimer.start();
        }
    }
    Timer {
        id: cycleTimer
        interval: 400
        repeat: true
        onTriggered: {
            root.finishSample();
            if (root.step >= 20) {
                if (root.step === 20) root.services.popups.open("right", bar.outputId);
                if (root.step === 21) root.probe.open();
                if (root.step === 22) {
                    root.firstPopupX = root.probe.window.margins.left;
                    root.popupChecks.push({ name: "child-popup-opens-with-input-mask-and-focus", passed:
                        root.probe.opened && root.probe.window.mask.rows.length > 0
                        && !!root.probe.window.contentItem.Window.window.activeFocusItem });
                    root.probe.close();
                    root.probeAnchor.x += 40;
                }
                if (root.step === 23) {
                    root.popupChecks.push({ name: "child-popup-closes", passed: !root.probe.opened });
                    root.probe.open();
                }
                if (root.step === 24) {
                    root.popupChecks.push({ name: "child-popup-reopens-at-current-anchor", passed:
                        root.probe.opened && Math.abs(root.probe.window.margins.left - root.firstPopupX - 40) <= 1
                        && root.probe.window.mask.rows.length > 0 });
                    root.probe.close();
                    root.services.popups.closeSurface("right", bar.outputId);
                }
                if (root.step === 25) { stop(); root.report(); return; }
                root.step++;
                return;
            }
            const position = root.step % 4;
            const side = position < 2 ? "left" : "right";
            const opening = position % 2 === 0;
            root.beginSample(side, opening ? "open" : "close");
            if (opening) root.services.popups.open(side, bar.outputId);
            else root.services.popups.closeSurface(side, bar.outputId);
            root.step++;
        }
    }
}
