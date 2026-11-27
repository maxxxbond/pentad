import QtQuick
import QtTest
import Quickshell
import qs.theme
import qs.components

// PentadScrubber at rest, hovered, mid-drag and with keyboard focus, with the real pointer and
// keyboard driving it and frames grabbed while the capsule springs.
ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    property TestEvent keys: TestEvent {}
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property bool reduced: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    readonly property string capture: Quickshell.env("PENTAD_ARTIFACT_PATH")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property var results: ({})
    property int movedCount: 0

    function applyTheme(appearance, reducedMotion) {
        Theme.resolve({ appearance: appearance, accent: "#869677", fontFamily: "Geist", reducedMotion: reducedMotion });
    }
    Component.onCompleted: applyTheme(appearance, reduced)

    FloatingWindow {
        id: window
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: true
        implicitWidth: 360
        implicitHeight: 394
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
                spacing: 16
                PentadScrubber {
                    id: live
                    width: 312
                    label: "Opacity"
                    value: 0.25
                    onMoved: function(next) {
                        value = next;
                        root.movedCount++;
                    }
                }
                PentadScrubber {
                    id: loud
                    width: 312
                    label: "Volume"
                    from: 0
                    to: 100
                    stepSize: 1
                    decimals: 0
                    ticks: 4
                    value: 64
                    valueText: Math.round(value) + "%"
                    onMoved: function(next) { value = next }
                }
                PentadScrubber {
                    id: held
                    width: 312
                    label: "Brightness"
                    value: 0.5
                }
                // The shape of the control-center volume row without its icon (a fixture cannot resolve
                // the asset path): separator slot, 48 px, press that grabs instead of jumping.
                PentadScrubber {
                    id: audioLike
                    width: 312
                    height: 48
                    label: "Volume"
                    trailingSlot: 44
                    relativeDrag: true
                    value: 0.64
                    valueText: Math.round(value * 100) + "%"
                    onMoved: function(next) { value = next }
                }
                // Asked 70 % while the device still reports 40 %: full fill to 40 %, a fainter band on to 70 %.
                PentadScrubber {
                    id: pending
                    width: 312
                    height: 48
                    label: "Pending"
                    relativeDrag: true
                    value: 0.7
                    confirmedValue: 0.4
                    valueText: Math.round(value * 100) + "%"
                }
                PentadScrubber {
                    id: smallest
                    width: 312
                    label: "Minimum"
                    value: 0.01
                }
                PentadScrubber {
                    id: off
                    width: 312
                    label: "Disabled"
                    value: 0.7
                    enabled: false
                }
            }
        }
    }

    Timer {
        id: timeline
        interval: 16
        repeat: true
        running: true
        property real elapsed: 0
        property bool pressed: false
        property bool nudged: false
        onTriggered: {
            elapsed += interval;
            // Rest: the capsule is faint and small.
            if (elapsed >= 100 && root.results.rest === undefined)
                root.results.rest = live.thumbLevel < 0.01 && Math.abs(live.shown - 0.25) < 0.001;
            // The pointer arrives: the capsule springs up.
            if (elapsed >= 200 && !pressed && root.results.hover === undefined) {
                root.pointer.mouseMove(live, live.width * 0.25, live.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                pressed = true;
            }
            if (elapsed >= 700 && root.results.hover === undefined)
                root.results.hover = live.active && live.thumbLevel > 0.95;
            // A press puts the value under the pointer; a drag follows it with no lag.
            if (elapsed >= 800 && root.results.press === undefined) {
                root.pointer.mousePress(live, live.width * 0.5, live.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.results.press = Math.abs(live.value - 0.5) < 0.0101 && live.held;
                root.pointer.mouseMove(live, live.width * 0.75, live.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.results.drag = Math.abs(live.value - 0.75) < 0.0101 && Math.abs(live.shown - live.position) < 0.0001;
                root.pointer.mouseMove(live, live.width * 5, live.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.results.dragClamps = live.value === 1;
                root.pointer.mouseMove(live, live.width * -3, live.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.results.dragClampsLow = live.value === 0;
                root.pointer.mouseMove(live, live.width * 0.6, live.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.pointer.mouseRelease(live, live.width * 0.6, live.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            }
            if (elapsed >= 820 && root.results.glide === undefined) {
                // Keyboard, not pointer: the fill glides, so right after a key it is still behind.
                live.forceActiveFocus(Qt.TabFocusReason);
                root.results.ring = live.visualFocus;
                root.keys.keyClick(Qt.Key_End, Qt.NoModifier, 0);
                root.results.glide = live.value === 1 && live.shown < 0.99;
            }
            if (elapsed >= 1200 && root.results.landed === undefined)
                root.results.landed = Math.abs(live.shown - 1) < 0.001;
            // Near 90 % the capsule would sit on the value, so it steps aside; mid-bar it stays.
            if (elapsed >= 1300 && !nudged) {
                live.value = 0.9;
                held.value = 0.1;
                nudged = true;
            }
            if (elapsed >= 1600 && root.results.labelCleared === undefined)
                root.results.labelCleared = held.thumbOverText && held.thumbClear < 0.01;
            if (elapsed >= 1600 && root.results.cleared === undefined)
                root.results.cleared = live.thumbOverText && live.thumbClear < 0.01 && !loud.thumbOverText
                    && loud.thumbClear === 1;
            if (elapsed >= 1700)
                finish();
        }
    }

    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; i++) {
            const found = findNamed(children[i], name);
            if (found) return found;
        }
        return null;
    }
    function finish() {
        timeline.running = false;
        // Keyboard: arrows step, Home and End jump, the value stays in range.
        live.value = 0.5;
        live.forceActiveFocus(Qt.TabFocusReason);
        keys.keyClick(Qt.Key_Right, Qt.NoModifier, 0);
        const right = Math.abs(live.value - 0.51) < 1e-9;
        keys.keyClick(Qt.Key_Left, Qt.NoModifier, 0);
        keys.keyClick(Qt.Key_Left, Qt.NoModifier, 0);
        const left = Math.abs(live.value - 0.49) < 1e-9;
        keys.keyClick(Qt.Key_Home, Qt.NoModifier, 0);
        const home = live.value === 0;
        keys.keyClick(Qt.Key_Left, Qt.NoModifier, 0);
        const floor = live.value === 0;
        keys.keyClick(Qt.Key_End, Qt.NoModifier, 0);
        keys.keyClick(Qt.Key_Right, Qt.NoModifier, 0);
        const ceiling = live.value === 1;
        // A scrubber that never took the pointer or focus keeps no ring and stays faint.
        const quiet = !loud.visualFocus && loud.thumbLevel === 0 && !loud.active;
        // Custom text replaces the number; the default shows the value to its decimals.
        const texts = loud.shownValue === "64%" && held.shownValue === "0.10";
        // A disabled scrubber is dimmed and ignores keys.
        off.forceActiveFocus(Qt.TabFocusReason);
        keys.keyClick(Qt.Key_End, Qt.NoModifier, 0);
        const disabled = off.opacity < 0.5 && off.value === 0.7;
        // Asked and real level: the fill stops at the device's level and the band runs on to the asked one;
        // a confirmed level shows no band.
        const band = root.findNamed(pending, "scrubberAskedBand");
        const askedBand = !!band && band.visible
            && Math.abs(pending.solidExtent - 0.4 * pending.trackLength) < 0.5
            && Math.abs(pending.bandExtent - 0.7 * pending.trackLength) < 0.5
            && Math.abs(band.x - pending.solidExtent) < 0.5;
        const confirmedNoBand = Math.abs(loud.bandExtent - loud.solidExtent) < 0.5;
        // Reduced motion: the capsule and the fill land at once.
        applyTheme(root.appearance, true);
        held.value = 0.3;
        const reducedLands = held.shown === 0.3;
        applyTheme(root.appearance, root.reduced);
        const checks = [
            { name: "scrubber-rests-faint-and-small", passed: root.results.rest === true },
            { name: "scrubber-hover-springs-capsule-up", passed: root.results.hover === true },
            { name: "scrubber-press-sets-value-under-pointer", passed: root.results.press === true },
            { name: "scrubber-drag-follows-pointer-exactly", passed: root.results.drag === true },
            { name: "scrubber-drag-stays-in-range", passed: root.results.dragClamps === true && root.results.dragClampsLow === true },
            { name: "scrubber-keyboard-focus-shows-ring", passed: root.results.ring === true },
            { name: "scrubber-key-jump-glides-then-lands", passed: root.results.glide === true && root.results.landed === true },
            { name: "scrubber-capsule-steps-aside-from-the-value", passed: root.results.cleared === true },
            { name: "scrubber-capsule-steps-aside-from-the-label", passed: root.results.labelCleared === true },
            { name: "scrubber-arrows-step-and-ends-clamp", passed: right && left && home && floor && ceiling },
            { name: "scrubber-untouched-one-stays-quiet", passed: quiet },
            { name: "scrubber-value-text-and-decimals", passed: texts },
            { name: "scrubber-disabled-ignores-input", passed: disabled },
            { name: "scrubber-moved-signal-fires", passed: root.movedCount > 0 },
            { name: "scrubber-reduced-motion-lands-at-once", passed: reducedLands },
            { name: "scrubber-shows-real-level-and-asked-band", passed: askedBand },
            { name: "scrubber-confirmed-level-has-no-band", passed: confirmedNoBand }
        ];
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(check => check.passed) ? "pass" : "fail",
            checks: checks
        }));
        Qt.callLater(saveThemes);
    }
    function saveThemes() {
        if (!root.capture) {
            Qt.quit();
            return;
        }
        // Where the capsule used to sit on the text: over the value, over the label, and one mid-bar.
        live.value = 0.9;
        loud.value = 40;
        held.value = 0.1;
        settle.start();
    }
    Timer {
        id: settle
        interval: 500
        onTriggered: content.grabToImage(result => {
            result.saveToFile(root.capture);
            Qt.quit();
        })
    }
}
