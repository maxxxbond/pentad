import QtQuick
import QtTest
import Quickshell
import qs.theme
import qs.components

// PentadHoldButton driven with a real pointer: an early release springs the fill back and shows the
// hint, a full hold confirms exactly once, and reduced motion drops the spring. The buttons are
// captured once in the requested theme.
ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property bool reduced: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    readonly property string capture: Quickshell.env("PENTAD_ARTIFACT_PATH")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property int restartConfirms: 0
    property int shutdownConfirms: 0
    property var results: ({})

    function applyTheme(appearance, reducedMotion) {
        Theme.resolve({ appearance: appearance, accent: "#869677", fontFamily: "Geist", reducedMotion: reducedMotion });
    }
    Component.onCompleted: applyTheme(appearance, reduced)

    FloatingWindow {
        id: window
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: true
        implicitWidth: 520
        implicitHeight: 360
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: minimumSize
        color: Theme.tokens.surface

        Item {
            id: content
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                color: Theme.tokens.surface
            }
            Column {
                x: 24
                y: 24
                spacing: 12
                PentadHoldButton {
                    id: idle
                    width: 208
                    text: "Restart"
                    hintText: "Press and hold"
                    iconSource: Qt.resolvedUrl("assets/icons/material/media/cloud-upload-symbolic.svg")
                    onConfirmed: root.restartConfirms++
                }
                PentadHoldButton {
                    id: danger
                    width: 208
                    destructive: true
                    text: "Shut down"
                    hintText: "Press and hold"
                    iconSource: Qt.resolvedUrl("assets/icons/material/media/cloud-upload-symbolic.svg")
                    onConfirmed: root.shutdownConfirms++
                }
                PentadHoldButton {
                    id: plain
                    width: 208
                    text: "Publish"
                    hintText: "Press and hold"
                }
                PentadHoldButton {
                    id: off
                    width: 208
                    enabled: false
                    text: "Unavailable"
                }
            }
        }
    }

    function press(item) {
        pointer.mousePress(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
    }
    function release(item) {
        pointer.mouseRelease(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
    }

    // A real-time timeline: press, let go early, wait, press again and hold to the end.
    Timer {
        id: timeline
        interval: 16
        repeat: true
        running: true
        property real elapsed: 0
        property bool mid: false
        property bool early: false
        property bool hinted: false
        property bool rested: false
        property bool full: false
        onTriggered: {
            elapsed += interval;
            if (elapsed >= 200 && !mid && idle.progress === 0 && !idle.pressed)
                root.press(idle);
            if (elapsed >= 700 && root.results.mid === undefined) {
                root.results.mid = idle.pressed && idle.progress > 0.3 && idle.progress < 0.9 && root.restartConfirms === 0;
                mid = true;
            }
            if (elapsed >= 800 && !early) {
                root.release(idle);
                early = true;
                root.results.early = idle.progress > 0 && idle.holdHint && root.restartConfirms === 0;
            }
            if (elapsed >= 1000 && root.results.hint === undefined) {
                root.results.hint = idle.holdHint && idle.text === "Restart";
            }
            if (elapsed >= 2800 && root.results.rested === undefined)
                root.results.rested = idle.progress === 0 && !idle.holdHint && !idle.draining && !idle.pressed;
            if (elapsed >= 2900 && !full) {
                full = true;
                root.press(danger);
            }
            if (elapsed >= 3500 && root.results.fullMid === undefined) {
                root.results.fullMid = danger.progress > 0.4 && danger.progress < 1 && root.shutdownConfirms === 0;
            }
            if (elapsed >= 4200 && root.results.confirmed === undefined) {
                root.results.confirmed = root.shutdownConfirms === 1 && danger.progress === 1;
                root.release(danger);
            }
            if (elapsed >= 4400 && root.results.stays === undefined)
                root.results.stays = root.shutdownConfirms === 1 && danger.progress === 1 && !danger.draining;
            if (elapsed >= 4500) {
                running = false;
                finish();
            }
        }
    }

    function finish() {
        // Reset returns a landed button to empty.
        danger.reset();
        const resetWorks = danger.progress === 0 && !danger.holdHint;
        // Reduced motion: the fill drops at once on an early release, no spring swing.
        applyTheme(root.appearance, true);
        press(plain);
        const startedReduced = plain.pressed;
        release(plain);
        const reducedLands = startedReduced && plain.progress === 0;
        applyTheme(root.appearance, root.reduced);
        // A disabled button takes no press and its fill stays empty.
        press(off);
        release(off);
        const disabledIdle = off.progress === 0 && !off.pressed;
        const checks = [
            { name: "hold-button-fill-grows-while-pressed", passed: root.results.mid === true },
            { name: "hold-button-early-release-does-not-confirm", passed: root.results.early === true },
            { name: "hold-button-early-release-shows-hint", passed: root.results.hint === true },
            { name: "hold-button-fill-springs-back-to-empty", passed: root.results.rested === true },
            { name: "hold-button-full-hold-is-not-instant", passed: root.results.fullMid === true },
            { name: "hold-button-full-hold-confirms-once", passed: root.results.confirmed === true },
            { name: "hold-button-fill-stays-full-after-confirm", passed: root.results.stays === true },
            { name: "hold-button-reset-empties-a-landed-button", passed: resetWorks },
            { name: "hold-button-reduced-motion-drops-the-spring", passed: reducedLands },
            { name: "hold-button-disabled-takes-no-press", passed: disabledIdle },
            { name: "hold-button-at-rest-does-no-work", passed: !idle.draining && idle.progress === 0 }
        ];
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(check => check.passed) ? "pass" : "fail",
            checks: checks
        }));
        Qt.callLater(saveThemes);
    }
    // The main capture in the requested theme.
    function saveThemes() {
        if (!root.capture) {
            Qt.quit();
            return;
        }
        content.grabToImage(result => {
            result.saveToFile(root.capture);
            Qt.quit();
        });
    }
}
