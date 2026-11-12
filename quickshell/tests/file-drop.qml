import QtQuick
import QtTest
import Quickshell
import qs.theme
import qs.components
import "../logic/spring.mjs" as SpringLogic
import "../logic/stash-view.mjs" as StashView

// PentadFileDrop in every state, in the dark and the light theme, plus one zone driven through a
// whole drop (hover, drop, progress, done, back to rest) with frames grabbed while it moves.
ShellRoot {
    id: root
    property TestEvent keys: TestEvent {}
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property bool reduced: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    readonly property string capture: Quickshell.env("PENTAD_ARTIFACT_PATH")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property int activations: 0
    property var results: ({})
    readonly property real fileBytes: 2.4e6
    readonly property string fileName: "brief.pdf"

    function applyTheme(appearance, reducedMotion) {
        Theme.resolve({ appearance: appearance, accent: "#869677", fontFamily: "Geist", reducedMotion: reducedMotion });
    }
    function size(bytes) {
        return StashView.formatSize(bytes, "en");
    }
    Component.onCompleted: applyTheme(appearance, reduced)

    FloatingWindow {
        id: window
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: true
        implicitWidth: 984
        implicitHeight: 776
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
            Grid {
                id: stateGrid
                x: 24
                y: 24
                columns: 3
                spacing: 24
                PentadFileDrop {
                    id: idleZone
                    width: 296
                    height: 216
                    title: "Drop into Stash"
                    hint: "Files, links, images or text"
                }
                PentadFileDrop {
                    id: hoverZone
                    width: 296
                    height: 216
                    active: true
                    title: "Release to keep it"
                    hint: "Files, links, images or text"
                }
                PentadFileDrop {
                    id: workingZone
                    width: 296
                    height: 216
                    phase: "working"
                    progress: 0.58
                    title: "Saving " + root.fileName
                    hint: root.size(root.fileBytes * 0.58) + " of " + root.size(root.fileBytes)
                }
                PentadFileDrop {
                    id: doneZone
                    width: 296
                    height: 216
                    phase: "done"
                    title: "Saved to Stash"
                    hint: root.fileName + " · " + root.size(root.fileBytes)
                }
                PentadFileDrop {
                    id: unmeasuredZone
                    width: 296
                    height: 216
                    phase: "working"
                    title: "Copying 3 files"
                    hint: "holiday.jpg and 2 more"
                }
                Column {
                    spacing: 24
                    PentadFileDrop {
                        id: compactZone
                        width: 296
                        height: 92
                        title: "Drop here"
                        hint: "Files, links, images or text"
                    }
                    PentadFileDrop {
                        id: pickerZone
                        width: 296
                        height: 100
                        activatable: true
                        iconSource: Qt.resolvedUrl("../assets/icons/material/media/cloud-upload-symbolic.svg")
                        title: "Choose a file to send"
                        hint: "Your phone picks it up in LocalSend"
                        onActivated: root.activations++
                    }
                }
            }
            Item {
                id: liveFrame
                x: 24
                y: stateGrid.y + stateGrid.height + 24
                width: 344
                height: 264
                PentadFileDrop {
                    id: live
                    x: 24
                    y: 24
                    width: 296
                    height: 216
                    title: phase === "done" ? "Saved to Stash" : phase === "working" ? "Saving " + root.fileName
                        : active ? "Release to keep it" : "Drop into Stash"
                    hint: phase === "done" ? root.fileName + " · " + root.size(root.fileBytes)
                        : phase === "working" ? root.size(root.fileBytes * Math.max(0, progress)) + " of " + root.size(root.fileBytes)
                        : "Files, links, images or text"
                }
            }
            Row {
                x: liveFrame.x + liveFrame.width + 24
                y: liveFrame.y
                spacing: 8
                Repeater {
                    id: strip
                    model: 4
                    Image {
                        required property int index
                        width: 140
                        height: 108
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }
            }
        }
    }

    // A real-time timeline: the live zone runs the same springs as in use.
    Timer {
        id: timeline
        interval: 16
        repeat: true
        running: true
        property real elapsed: 0
        property real uploadStart: -1
        property int frame: 0
        property var marks: [700, 1350, 2700, 3250]
        function grab() {
            const index = frame++;
            liveFrame.grabToImage(result => {
                strip.itemAt(index).source = result.url;
                if (root.capture)
                    result.saveToFile(root.capture + ".live-" + index + ".png");
            });
        }
        onTriggered: {
            elapsed += interval;
            if (elapsed >= 300 && !live.active && live.phase === "idle" && uploadStart < 0)
                live.active = true;
            if (elapsed >= 700 && root.results.lift === undefined)
                root.results.lift = !root.reduced ? live.lift > 0.5 && live.lift < 1.2 : live.lift === 1;
            if (elapsed >= 1000 && uploadStart < 0) {
                live.active = false;
                live.progress = 0;
                live.phase = "working";
                uploadStart = elapsed;
            }
            if (uploadStart >= 0 && live.phase === "working") {
                live.progress = SpringLogic.uploadPace((elapsed - uploadStart) / 2100);
                if (live.progress >= 1)
                    live.phase = "done";
            }
            if (frame < marks.length && elapsed >= marks[frame])
                grab();
            if (elapsed >= 2000 && root.results.ring === undefined)
                root.results.ring = live.phase === "working" && live.ringLevel > 0.9 && live.successLevel < 0.01;
            if (elapsed >= 4400 && root.results.settled === undefined)
                root.results.settled = live.phase === "done" && !live.moving && Math.abs(live.successLevel - 1) < 0.01
                    && live.ringLevel < 0.01;
            if (elapsed >= 4500) {
                running = false;
                finish();
            }
        }
    }

    function finish() {
        const restZonesStill = !idleZone.moving && !workingZone.moving && !doneZone.moving && !compactZone.moving;
        const compactHidesCircle = compactZone.coreSize === 0 && idleZone.coreSize === 72;
        const springsFromSource = SpringLogic.fileDropSprings.circle[0] === 420 && SpringLogic.fileDropSprings.circle[1] === 14;
        // Keyboard: Tab focus draws the ring, Enter and Space activate once each.
        pickerZone.forceActiveFocus(Qt.TabFocusReason);
        const ring = pickerZone.visualFocus;
        keys.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
        keys.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
        const keyboardWorks = ring && root.activations === 2;
        const restingZoneTakesNoFocus = idleZone.focusPolicy === Qt.NoFocus;
        // Reduced motion: a phase change lands at once.
        applyTheme(root.appearance, true);
        live.phase = "idle";
        const reducedLands = !live.moving && live.coreSize > 0 && live.successLevel === 0 && live.ringLevel === 0;
        applyTheme(root.appearance, root.reduced);
        const checks = [
            { name: "file-drop-springs-match-source", passed: springsFromSource },
            { name: "file-drop-hover-lifts-zone", passed: root.results.lift === true },
            { name: "file-drop-ring-shows-while-working", passed: root.results.ring === true },
            { name: "file-drop-drop-runs-to-done-and-settles", passed: root.results.settled === true },
            { name: "file-drop-static-states-do-no-work", passed: restZonesStill },
            { name: "file-drop-short-zone-keeps-only-text", passed: compactHidesCircle },
            { name: "file-drop-keyboard-activates-with-ring", passed: keyboardWorks },
            { name: "file-drop-passive-zone-takes-no-focus", passed: restingZoneTakesNoFocus },
            { name: "file-drop-reduced-motion-lands-at-once", passed: reducedLands }
        ];
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(check => check.passed) ? "pass" : "fail",
            checks: checks
        }));
        Qt.callLater(saveThemes);
    }
    // The main capture in the requested theme, then the same grid in the other theme.
    function saveThemes() {
        if (!root.capture) {
            Qt.quit();
            return;
        }
        content.grabToImage(result => {
            result.saveToFile(root.capture);
            applyTheme(root.appearance === "dark" ? "light" : "dark", root.reduced);
            otherTheme.start();
        });
    }
    Timer {
        id: otherTheme
        interval: 400
        onTriggered: content.grabToImage(result => {
            result.saveToFile(root.capture + ".other-theme.png");
            Qt.quit();
        })
    }
}
