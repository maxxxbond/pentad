import QtQuick
import QtTest
import Quickshell
import qs.theme
import qs.components
import "../logic/wheel-picker.mjs" as Wheel

// PentadWheelPicker in use: a time picker (looping hours and minutes, an AM/PM column that stops
// at its ends) driven by real pointer and key events: a change from outside, arrows, Home/End,
// a tap on a row, a slow drag, a flick, a pull past the end of a column that does not loop, and
// reduced motion. A second picker is held half a row between two options to show the drum mid-turn.
ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property bool reduced: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    readonly property string capture: Quickshell.env("PENTAD_ARTIFACT_PATH")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property var current: ({ hour: "8", minute: "41", period: "am" })
    property var edits: []
    property var results: ({})
    readonly property var hours: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"]
    readonly property var minutes: Array.from({ length: 60 }, (_, i) => (i < 10 ? "0" : "") + i)
    readonly property var columns: [
        { id: "hour", label: "Hour", options: hours, loop: true },
        { id: "minute", label: "Minute", options: minutes, loop: true },
        { id: "period", label: "AM or PM", options: ["am", "pm"], loop: false }
    ]

    function applyTheme(appearance, reducedMotion) {
        Theme.resolve({ appearance: appearance, accent: "#869677", fontFamily: "Geist", reducedMotion: reducedMotion });
    }
    function near(a, b, eps) {
        return Math.abs(a - b) < (eps ?? 0.01);
    }
    function lastEdit() {
        return edits.length > 0 ? edits[edits.length - 1] : "";
    }
    Component.onCompleted: applyTheme(appearance, reduced)

    FloatingWindow {
        id: window
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: true
        implicitWidth: 560
        implicitHeight: 280
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
            PentadWheelPicker {
                id: picker
                x: 24
                y: 24
                accessibleName: "Alarm time"
                columns: root.columns
                value: root.current
                onEdited: (column, option) => {
                    root.edits = root.edits.concat([column + "=" + option]);
                    const next = Object.assign({}, root.current);
                    next[column] = option;
                    root.current = next;
                }
            }
            PentadWheelPicker {
                id: midTurn
                x: 300
                y: 24
                accessibleName: "Alarm time, held mid-turn"
                columns: root.columns
                value: ({ hour: "3", minute: "20", period: "am" })
            }
        }
    }

    // The columns by id, and the screen point of a row `rows` below the band.
    function col(id) {
        return picker.column(id);
    }
    function rowY(rows) {
        return Wheel.drumHeight / 2 + Wheel.rowGeometry(rows).y;
    }
    function snapshot(name) {
        results[name] = { hour: col("hour").position, minute: col("minute").position, period: col("period").position, edits: edits.join(",") };
    }

    // The scenario, one action per mark (ms). Waits are generous: a settle takes about a second.
    Timer {
        id: timeline
        interval: 16
        repeat: true
        running: true
        property real elapsed: 0
        property int stage: 0
        readonly property var marks: [400, 600, 1500, 1700, 2500, 2800, 3700, 5000, 6600, 6900, 8100, 8600, 9200, 9800]
        function run(index) {
            const hour = root.col("hour");
            const minute = root.col("minute");
            const period = root.col("period");
            switch (index) {
            case 0:
                // Rest: the drums sit on the options of `value`, nothing moves, nothing was edited.
                root.snapshot("at400");
                root.results.rest = hour.position === 7 && minute.position === 41 && period.position === 0
                    && !hour.moving && !minute.moving && !period.moving && root.edits.length === 0
                    && !hour.userDriven;
                // A change from outside turns the drum (the short way round) and sends no edit.
                root.current = { hour: "11", minute: "41", period: "am" };
                break;
            case 1:
                root.results.turning = hour.moving && hour.position > 7 && hour.position < 10.2;
                break;
            case 2:
                root.snapshot("at1500");
                root.results.outside = hour.position === 10 && !hour.moving && root.edits.length === 0
                    && hour.nearest === 10;
                // Looping the other way: 11 -> 2 is three rows forward through 12, 1.
                root.current = { hour: "2", minute: "41", period: "am" };
                break;
            case 3:
                // Keyboard: Tab focus shows the ring; Down is one row, instantly.
                hour.forceActiveFocus(Qt.TabFocusReason);
                root.results.ring = hour.ringVisible && hour.visualFocus;
                break;
            case 4:
                root.snapshot("at2500");
                root.results.shortWay = hour.position === 13 && hour.nearest === 1;
                root.edits = [];
                root.pointer.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
                root.results.down = hour.position === 14 && root.lastEdit() === "hour=3" && !hour.moving;
                root.pointer.keyClick(Qt.Key_PageDown, Qt.NoModifier, 0);
                root.results.page = hour.position === 19 && root.lastEdit() === "hour=8";
                root.pointer.keyClick(Qt.Key_Home, Qt.NoModifier, 0);
                root.results.home = hour.position === 12 && root.lastEdit() === "hour=1";
                root.pointer.keyClick(Qt.Key_End, Qt.NoModifier, 0);
                root.results.end = hour.position === 23 && root.lastEdit() === "hour=12";
                root.pointer.keyClick(Qt.Key_Up, Qt.NoModifier, 0);
                root.results.up = hour.position === 22 && root.lastEdit() === "hour=11";
                break;
            case 5:
                // A tap on the row one below the band moves the minute forward by one, springing.
                root.edits = [];
                root.pointer.mouseClick(minute, minute.width / 2, root.rowY(1), Qt.LeftButton, Qt.NoModifier, 0);
                root.results.tapStarted = minute.moving && !minute.keyboardEngaged;
                break;
            case 6:
                root.results.tap = minute.position === 42 && root.lastEdit() === "minute=42" && !minute.moving;
                // A slow drag up by two rows, then a pause so the release has no speed: it settles
                // on the nearest row, without coasting.
                root.edits = [];
                root.pointer.mousePress(minute, minute.width / 2, Wheel.drumHeight / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(minute, minute.width / 2, Wheel.drumHeight / 2 - 24, 40, Qt.NoButton, Qt.NoModifier);
                root.pointer.mouseMove(minute, minute.width / 2, Wheel.drumHeight / 2 - 48, 40, Qt.NoButton, Qt.NoModifier);
                root.pointer.mouseMove(minute, minute.width / 2, Wheel.drumHeight / 2 - 72, 40, Qt.NoButton, Qt.NoModifier);
                root.results.dragHeld = minute.dragging && root.near(minute.position, 44, 0.01);
                root.pointer.mouseRelease(minute, minute.width / 2, Wheel.drumHeight / 2 - 72, Qt.LeftButton, Qt.NoModifier, 150);
                break;
            case 7:
                root.results.drag = minute.position === 44 && !minute.dragging && !minute.moving
                    && root.lastEdit() === "minute=44";
                // A flick: fast moves, released at speed. It coasts several rows, then lands on a row.
                root.edits = [];
                root.pointer.mousePress(minute, minute.width / 2, Wheel.drumHeight - 30, Qt.LeftButton, Qt.NoModifier, 0);
                for (let y = Wheel.drumHeight - 60; y >= 30; y -= 30)
                    root.pointer.mouseMove(minute, minute.width / 2, y, 8, Qt.NoButton, Qt.NoModifier);
                root.pointer.mouseRelease(minute, minute.width / 2, 30, Qt.LeftButton, Qt.NoModifier, 0);
                root.results.flickMoving = minute.moving && !minute.dragging;
                break;
            case 8:
                root.snapshot("flick");
                root.results.flick = !minute.moving && Number.isInteger(minute.position)
                    && Math.abs(minute.position - 44) >= 5 && root.edits.length >= 3;
                break;
            case 9:
                // The AM/PM column does not loop: pulled far past its end, the drum only gives a
                // little, then springs back to the last option on release.
                root.edits = [];
                root.pointer.mousePress(period, period.width / 2, Wheel.drumHeight - 30, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(period, period.width / 2, Wheel.drumHeight - 130, 40, Qt.NoButton, Qt.NoModifier);
                root.pointer.mouseMove(period, period.width / 2, Wheel.drumHeight - 230, 40, Qt.NoButton, Qt.NoModifier);
                root.pointer.mouseMove(period, period.width / 2, 8, 40, Qt.NoButton, Qt.NoModifier);
                root.results.overscroll = period.position > 1 && period.position < 2.2;
                root.pointer.mouseRelease(period, period.width / 2, 8, Qt.LeftButton, Qt.NoModifier, 150);
                break;
            case 10:
                root.results.stops = period.position === 1 && period.nearest === 1 && !period.moving
                    && root.lastEdit() === "period=pm";
                // Reduced motion: a change from outside lands at once.
                root.applyTheme(root.appearance, true);
                root.current = { hour: "5", minute: "15", period: "am" };
                root.results.reducedLands = hour.nearest === 4 && minute.nearest === 15 && period.nearest === 0
                    && !hour.moving && !minute.moving && !period.moving;
                root.applyTheme(root.appearance, root.reduced);
                break;
            case 11:
                // Held half a row between two options: the drum mid-turn, for the screenshot.
                const turning = midTurn.column("minute");
                turning.hold(20.5);
                midTurn.column("hour").hold(2.5);
                root.results.midTurn = root.near(turning.position, 20.5, 0.001) && !turning.userDriven;
                break;
            case 12:
                // A hidden picker does no work: nothing runs for a column that is not visible.
                root.results.static = !midTurn.column("hour").moving && !hour.moving;
                break;
            case 13:
                finish();
                break;
            }
        }
        onTriggered: {
            elapsed += interval;
            while (stage < marks.length && elapsed >= marks[stage])
                run(stage++);
        }
    }

    function finish() {
        timeline.running = false;
        const hour = col("hour");
        const checks = [
            { name: "wheel-picker-rests-on-its-value-and-does-no-work", passed: results.rest === true },
            { name: "wheel-picker-outside-change-turns-the-drum-without-edits", passed: results.turning === true && results.outside === true },
            { name: "wheel-picker-outside-change-loops-the-short-way", passed: results.shortWay === true },
            { name: "wheel-picker-keyboard-focus-draws-ring", passed: results.ring === true },
            { name: "wheel-picker-arrows-page-home-end", passed: results.down === true && results.page === true
                && results.home === true && results.end === true && results.up === true },
            { name: "wheel-picker-tap-on-row-springs-to-it", passed: results.tapStarted === true && results.tap === true },
            { name: "wheel-picker-slow-drag-follows-pointer-and-settles-on-row", passed: results.dragHeld === true && results.drag === true },
            { name: "wheel-picker-fast-release-flicks-several-rows", passed: results.flickMoving === true && results.flick === true },
            { name: "wheel-picker-non-loop-column-gives-a-little-then-stops", passed: results.overscroll === true && results.stops === true },
            { name: "wheel-picker-reduced-motion-lands-at-once", passed: results.reducedLands === true },
            { name: "wheel-picker-mid-turn-and-idle-do-no-work", passed: results.midTurn === true && results.static === true },
            { name: "wheel-picker-column-has-spinbox-name", passed: hour.Accessible.role === Accessible.SpinBox
                && hour.Accessible.name.indexOf("Hour") === 0 },
            { name: "wheel-picker-column-takes-keyboard-focus", passed: hour.focusPolicy === Qt.StrongFocus }
        ];
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(check => check.passed) ? "pass" : "fail",
            checks: checks,
            details: results
        }));
        Qt.callLater(saveThemes);
    }
    // The capture in the requested theme.
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
