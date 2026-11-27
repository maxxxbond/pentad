import QtQuick
import QtQuick.Controls.Basic
import QtTest
import Quickshell
import qs.theme
import qs.components

// PentadComboBox's spring motion in real time: the list drops out and overshoots, rows fall in,
// the highlight stretches between rows, a pick rolls the value and draws the check before the
// list folds away, and a press outside, Escape and a reopen mid-fold all keep the motion.
ShellRoot {
    id: root
    property TestEvent input: TestEvent {}
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property bool reduced: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    readonly property string capture: Quickshell.env("PENTAD_ARTIFACT_PATH")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property int activations: 0
    property int confirmedActivations: 0
    property int confirmedIndex: 1
    property var results: ({})
    property real peak: 0
    readonly property var idle: [
        { label: "5 min", value: 300 },
        { label: "10 min", value: 600 },
        { label: "15 min", value: 900 },
        { label: "30 min", value: 1800 },
        { label: "Never", value: 0 }
    ]
    readonly property var zones: {
        const list = [];
        for (let i = -11; i <= 14; i++)
            list.push({ label: "UTC" + (i >= 0 ? "+" : "") + i, value: i });
        return list;
    }

    function applyTheme(appearance, reducedMotion) {
        Theme.resolve({ appearance: appearance, accent: "#869677", fontFamily: "Geist", reducedMotion: reducedMotion });
    }
    function near(a, b, epsilon) {
        return Math.abs(a - b) < (epsilon === undefined ? 0.01 : epsilon);
    }
    function rowItem(box, index) {
        return box.popup.contentItem.itemAtIndex(index);
    }
    Component.onCompleted: applyTheme(appearance, reduced)

    FloatingWindow {
        id: window
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: true
        implicitWidth: 560
        implicitHeight: 520
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: minimumSize
        color: Theme.tokens.surface

        // The window and its popup layer composited: a grab of the content alone misses the list.
        Item {
            id: stage
            width: window.implicitWidth
            height: window.implicitHeight
            Rectangle {
                anchors.fill: parent
                color: Theme.tokens.surface
            }
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: content
                live: true
            }
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: content.Overlay.overlay
                live: true
            }
        }

        Item {
            id: content
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                color: Theme.tokens.surface
            }
            PentadComboBox {
                id: timer
                x: 32
                y: 32
                width: 220
                model: root.idle
                textRole: "label"
                valueRole: "value"
                currentIndex: 1
                accessibleName: "Turn off the display"
                onActivated: root.activations++
            }
            PentadComboBox {
                id: confirmed
                x: 32
                y: 280
                width: 220
                model: root.idle
                textRole: "label"
                valueRole: "value"
                currentIndex: root.confirmedIndex
                accessibleName: "Put the computer to sleep"
                onActivated: {
                    root.confirmedActivations++;
                    currentIndex = Qt.binding(() => root.confirmedIndex);
                }
            }
            PentadComboBox {
                id: zone
                x: 300
                y: 32
                width: 220
                model: root.zones
                textRole: "label"
                valueRole: "value"
                currentIndex: 20
                displayText: currentIndex >= 0 ? currentText : "Unknown"
                accessibleName: "Time zone"
            }
        }
    }

    Timer {
        id: timeline
        interval: 16
        repeat: true
        running: true
        property real elapsed: 0
        property int next: 0
        readonly property var steps: [
            { at: 300, run: () => {
                root.input.mouseClick(timer, 30, timer.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.results.opens = timer.popup.visible;
            } },
            { at: 400, run: () => {
                root.results.drops = timer.listLevel > 0.1 && timer.listLevel < 1.2;
                root.results.stagger = timer.rowLevel(0) > timer.rowLevel(4) + 0.1 || (timer.rowLevel(0) > 0.01 && timer.rowLevel(4) === 0);
            } },
            { at: 470, run: () => {
                root.results.stagger = root.results.stagger && timer.rowLevel(0) > timer.rowLevel(4);
            } },
            { at: 1100, run: () => {
                const current = root.rowItem(timer, 1);
                root.results.settled = root.near(timer.listLevel, 1) && current !== null
                    && root.near(timer.highlightSpan.top, current.y, 0.5) && root.near(timer.highlightSpan.height, current.height, 0.5);
                root.results.overshoot = root.peak > 1.01 && root.peak < 1.15;
                root.input.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
                root.input.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
            } },
            { at: 1170, run: () => {
                const rowHeight = root.rowItem(timer, 3).height;
                root.results.stretch = timer.highlightedIndex === 3 && timer.highlightSpan.height > rowHeight * 1.3;
            } },
            { at: 1900, run: () => {
                const target = root.rowItem(timer, 3);
                root.results.lands = root.near(timer.highlightSpan.top, target.y, 0.5) && root.near(timer.highlightSpan.height, target.height, 0.5);
                root.input.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                root.results.pickClosesAtOnce = timer.currentIndex === 3 && root.activations === 1 && !timer.popup.opened && !timer.listOpen;
            } },
            { at: 1960, run: () => {
                root.results.pickWaitsForCheck = timer.listLevel > 0.9 && timer.rollLevel < 0.9 && timer.checkLevel(3) > 0.05
                    && timer.checkLevel(3) < 1 && timer.displayText === "30 min";
            } },
            { at: 2900, run: () => {
                root.results.foldsAway = timer.listLevel < 0.01 && !timer.popup.opened && root.near(timer.rollLevel, 1)
                    && root.near(timer.checkLevel(3), 1) && timer.checkLevel(1) < 0.01;
                root.input.mouseClick(timer, 30, timer.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } },
            { at: 3700, run: () => root.input.mouseClick(content, 280, 470, Qt.LeftButton, Qt.NoModifier, 0) },
            { at: 3730, run: () => {
                root.results.outsideFolds = !timer.popup.opened && !timer.listOpen && timer.listLevel > 0.5 && timer.currentIndex === 3;
            } },
            { at: 4500, run: () => {
                root.results.outsideGone = timer.listLevel < 0.01 && root.activations === 1;
                timer.forceActiveFocus(Qt.TabFocusReason);
                root.input.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            } },
            { at: 5300, run: () => root.input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0) },
            { at: 5330, run: () => {
                root.results.escapeFolds = !timer.popup.opened && !timer.listOpen && timer.listLevel > 0.5;
                // Reopen before the fold ends: the list grows back from where it is.
                timer.popup.open();
            } },
            { at: 6100, run: () => {
                root.results.reopens = timer.popup.visible && root.near(timer.listLevel, 1) && timer.rowLevel(0) > 0.99;
                root.input.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
                root.input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.input.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
                root.results.spaceDuringFold = timer.listOpen && timer.currentIndex === 3 && root.activations === 1;
                root.input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
            } },
            { at: 6900, run: () => {
                // A host's change at rest lands at once.
                timer.currentIndex = 0;
                root.results.hostChangeLands = root.near(timer.rollLevel, 1, 1e-9) && timer.checkLevel(0) === 1
                    && timer.displayText === "5 min";
                root.input.mouseClick(zone, 30, zone.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } },
            { at: 7700, run: () => {
                const view = root.rowItem(zone, 20);
                const list = zone.popup.contentItem.children[0];
                root.results.longListShowsCurrent = view !== null && view.y >= list.contentY - 1
                    && view.y + view.height <= list.contentY + list.height + 1 && zone.firstRow > 0
                    && root.near(zone.listLevel, 1) && zone.rowLevel(20) > 0.99;
                zone.popup.close();
            } },
            { at: 8500, run: () => {
                root.applyTheme(root.appearance, true);
                timer.popup.open();
            } },
            { at: 8540, run: () => {
                root.results.reducedOpens = timer.popup.visible && root.near(timer.listLevel, 1, 1e-6) && timer.rowLevel(4) === 1;
                timer.popup.close();
            } },
            { at: 8640, run: () => {
                root.results.reducedCloses = !timer.popup.visible && !timer.popup.opened && timer.listLevel === 0;
                root.applyTheme(root.appearance, root.reduced);
                confirmed.popup.open();
            } },
            { at: 9500, run: () => {
                const row = root.rowItem(confirmed, 3);
                root.input.mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } },
            { at: 9560, run: () => {
                // The host set the index back to its confirmed value: nothing rolls there and back.
                root.results.hostRevertStill = root.confirmedActivations === 1 && confirmed.currentIndex === 1
                    && confirmed.displayText === "10 min" && root.near(confirmed.rollLevel, 1) && confirmed.checkLevel(3) < 0.01
                    && root.near(confirmed.checkLevel(1), 1);
                zone.forceActiveFocus(Qt.TabFocusReason);
                root.input.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
            } },
            { at: 10400, run: () => root.input.keyClick(Qt.Key_End, Qt.NoModifier, 0) },
            { at: 11200, run: () => {
                const last = root.zones.length - 1;
                const view = root.rowItem(zone, last);
                const list = zone.popup.contentItem.children[0];
                root.results.endKeepsHighlight = zone.highlightedIndex === last && view !== null
                    && view.y + view.height <= list.contentY + list.height + 1
                    && root.near(zone.highlightSpan.top, view.y, 0.5);
                root.input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.results.endPicksNothing = zone.currentIndex === 20;
            } },
            { at: 12000, run: () => timer.popup.open() }
        ]
        onTriggered: {
            elapsed += interval;
            if (timer.popup.visible)
                root.peak = Math.max(root.peak, timer.listLevel);
            while (next < steps.length && elapsed >= steps[next].at)
                steps[next++].run();
            if (elapsed >= 13100) {
                running = false;
                root.finish();
            }
        }
    }

    function finish() {
        const checks = [
            { name: "combo-motion-opens-on-click", passed: root.results.opens === true },
            { name: "combo-motion-list-drops-out", passed: root.results.drops === true },
            { name: "combo-motion-rows-fall-in-one-after-another", passed: root.results.stagger === true },
            { name: "combo-motion-list-overshoots-once", passed: root.results.overshoot === true },
            { name: "combo-motion-highlight-starts-on-current", passed: root.results.settled === true },
            { name: "combo-motion-highlight-stretches-between-rows", passed: root.results.stretch === true },
            { name: "combo-motion-highlight-lands-on-row", passed: root.results.lands === true },
            { name: "combo-motion-pick-closes-popup-at-once", passed: root.results.pickClosesAtOnce === true },
            { name: "combo-motion-pick-rolls-value-and-draws-check", passed: root.results.pickWaitsForCheck === true },
            { name: "combo-motion-list-folds-away", passed: root.results.foldsAway === true },
            { name: "combo-motion-press-outside-folds", passed: root.results.outsideFolds === true },
            { name: "combo-motion-press-outside-picks-nothing", passed: root.results.outsideGone === true },
            { name: "combo-motion-escape-folds", passed: root.results.escapeFolds === true },
            { name: "combo-motion-reopen-mid-fold-grows-back", passed: root.results.reopens === true },
            { name: "combo-motion-host-change-at-rest-lands", passed: root.results.hostChangeLands === true },
            { name: "combo-motion-long-list-shows-current", passed: root.results.longListShowsCurrent === true },
            { name: "combo-motion-reduced-motion-opens-at-once", passed: root.results.reducedOpens === true },
            { name: "combo-motion-reduced-motion-closes-at-once", passed: root.results.reducedCloses === true },
            { name: "combo-motion-space-during-fold-reopens-without-pick", passed: root.results.spaceDuringFold === true },
            { name: "combo-motion-host-revert-in-activated-shows-no-roll", passed: root.results.hostRevertStill === true },
            { name: "combo-motion-end-keeps-highlight-in-view", passed: root.results.endKeepsHighlight === true
                && root.results.endPicksNothing === true },
            { name: "combo-motion-at-rest-does-no-work", passed: !zone.animating && !confirmed.animating }
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
        stage.grabToImage(result => {
            result.saveToFile(root.capture);
            Qt.quit();
        });
    }
}
