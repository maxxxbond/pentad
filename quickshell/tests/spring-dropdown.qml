import QtQuick
import QtQuick.Controls.Basic
import QtTest
import Quickshell
import qs.theme
import qs.components

// PentadSpringDropdown at rest, open, and one dropdown driven through a whole session in real time:
// open from the keyboard, the highlight stretching between rows, a pick that rolls the value and
// folds the menu, a pointer pick, a press outside and Escape.
ShellRoot {
    id: root
    property TestEvent input: TestEvent {}
    readonly property string requestedAppearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE")
    readonly property bool reduced: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    readonly property string capture: Quickshell.env("PENTAD_ARTIFACT_PATH")
    property string appearance: requestedAppearance === "light" ? "light" : "dark"
    property int activations: 0
    property var results: ({})
    property real peak: 0
    // Notification modes, the way the shell would offer them.
    readonly property var modes: [
        { text: "All notifications", color: Theme.tokens.success },
        { text: "Important only", color: Theme.tokens.warning },
        { text: "Silent, history only", color: Theme.tokens.textMuted },
        { text: "Do not disturb", color: Theme.tokens.error }
    ]

    function applyTheme(appearance, reducedMotion) {
        Theme.resolve({ appearance: appearance, accent: "#869677", fontFamily: "Geist", reducedMotion: reducedMotion });
    }
    function near(a, b, epsilon) {
        return Math.abs(a - b) < (epsilon === undefined ? 0.01 : epsilon);
    }
    Component.onCompleted: applyTheme(appearance, reduced)

    FloatingWindow {
        id: window
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: true
        implicitWidth: 640
        implicitHeight: 560
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: minimumSize
        color: Theme.tokens.surface

        // The window and its popup layer composited, because a grab of the content alone misses
        // the menu, which lives in the overlay. Hidden under the content.
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
            PentadSpringDropdown {
                id: rest
                x: 40
                y: 40
                model: root.modes
                currentIndex: 0
                accessibleName: "Notifications"
            }
            PentadSpringDropdown {
                id: empty
                x: 40
                y: 112
                model: []
                accessibleName: "Notifications"
            }
            PentadSpringDropdown {
                id: shown
                x: 340
                y: 40
                model: root.modes
                currentIndex: 2
                accessibleName: "Notifications"
            }
            PentadSpringDropdown {
                id: live
                x: 40
                y: 380
                keepCentred: true
                model: root.modes
                currentIndex: 1
                accessibleName: "Notifications"
                onActivated: root.activations++
            }
        }
    }

    // A real-time timeline; every step is at an absolute time in milliseconds.
    Timer {
        id: timeline
        interval: 16
        repeat: true
        running: true
        property real elapsed: 0
        property int next: 0
        readonly property var steps: [
            { at: 300, run: () => {
                live.forceActiveFocus(Qt.TabFocusReason);
                root.results.ring = live.visualFocus;
                root.input.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
            } },
            { at: 440, run: () => {
                const first = live.rowAt(0).fall.value;
                const last = live.rowAt(3).fall.value;
                root.results.stagger = live.menuLevel > 0.1 && first > last + 0.1;
            } },
            { at: 1300, run: () => {
                root.results.openSettled = live.expanded && root.near(live.menuLevel, 1)
                    && root.near(live.liftOffset, -(live.gap + live.menuHeight) / 2, 0.1)
                    && live.hoveredIndex === 1 && root.near(live.highlight.top, live.menuPadding + live.rowHeight, 0.1);
                root.results.overshoot = root.peak > 1.01 && root.peak < 1.15;
                root.input.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
                root.input.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
            } },
            { at: 1370, run: () => {
                root.results.stretch = live.hoveredIndex === 3 && live.highlight.height > live.rowHeight * 1.3;
            } },
            { at: 2100, run: () => {
                root.results.highlightLands = root.near(live.highlight.top, live.menuPadding + 3 * live.rowHeight, 0.5)
                    && root.near(live.highlight.height, live.rowHeight, 0.5);
                root.input.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
            } },
            { at: 2150, run: () => {
                root.results.rolling = live.currentIndex === 3 && root.activations === 1 && live.rollLevel < 0.9
                    && live.expanded;
            } },
            { at: 3000, run: () => {
                root.results.foldsAway = !live.expanded && !live.menuShown && root.near(live.liftOffset, 0, 0.1)
                    && root.near(live.rollLevel, 1) && root.near(live.rowAt(3).check.value, 1)
                    && live.rowAt(1).check.value < 0.01 && live.activeFocus && live.visualFocus;
                root.input.mouseClick(live, live.width / 2, live.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } },
            { at: 3800, run: () => {
                const row = live.rowAt(0);
                root.results.pointerOpens = live.expanded && root.near(live.menuLevel, 1);
                root.input.mouseMove(row, row.width / 2, row.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                root.input.mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } },
            { at: 3850, run: () => {
                root.results.pointerPick = live.currentIndex === 0 && root.activations === 2;
            } },
            { at: 4700, run: () => {
                root.results.pointerCloses = !live.menuShown && !live.visualFocus;
                root.input.mouseClick(live, live.width / 2, live.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } },
            { at: 5500, run: () => root.input.mouseClick(content, 600, 520, Qt.LeftButton, Qt.NoModifier, 0) },
            { at: 6300, run: () => {
                root.results.outsideCloses = !live.expanded && !live.menuShown && live.currentIndex === 0
                    && root.activations === 2;
                live.forceActiveFocus(Qt.TabFocusReason);
                root.input.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
            } },
            { at: 7000, run: () => root.input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0) },
            { at: 7700, run: () => {
                root.results.escape = !live.expanded && !live.menuShown && live.currentIndex === 0 && live.visualFocus;
                // Reduced motion: opening and closing land at once.
                root.applyTheme(root.appearance, true);
                live.open();
                root.results.reducedOpen = root.near(live.menuLevel, 1, 1e-9) && live.rowAt(3).fall.value === 1
                    && root.near(live.liftOffset, -(live.gap + live.menuHeight) / 2, 1e-9);
                live.close();
                root.results.reducedClose = !live.expanded && live.menuLevel === 0;
            } },
            { at: 7800, run: () => {
                root.results.reducedClose = root.results.reducedClose && !live.menuShown;
                root.applyTheme(root.appearance, root.reduced);
                shown.open();
            } }
        ]
        onTriggered: {
            elapsed += interval;
            if (live.expanded)
                root.peak = Math.max(root.peak, live.menuLevel);
            while (next < steps.length && elapsed >= steps[next].at)
                steps[next++].run();
            if (elapsed >= 8900) {
                running = false;
                root.finish();
            }
        }
    }

    function finish() {
        empty.open();
        const checks = [
            { name: "spring-dropdown-keyboard-focus-draws-ring", passed: root.results.ring === true },
            { name: "spring-dropdown-rows-fall-in-one-after-another", passed: root.results.stagger === true },
            { name: "spring-dropdown-menu-overshoots-once", passed: root.results.overshoot === true },
            { name: "spring-dropdown-opens-lifts-and-settles", passed: root.results.openSettled === true },
            { name: "spring-dropdown-highlight-stretches-between-rows", passed: root.results.stretch === true },
            { name: "spring-dropdown-highlight-lands-on-row", passed: root.results.highlightLands === true },
            { name: "spring-dropdown-pick-rolls-value-and-waits-for-check", passed: root.results.rolling === true },
            { name: "spring-dropdown-folds-away-and-returns-focus", passed: root.results.foldsAway === true },
            { name: "spring-dropdown-pointer-opens", passed: root.results.pointerOpens === true },
            { name: "spring-dropdown-pointer-picks", passed: root.results.pointerPick === true },
            { name: "spring-dropdown-pointer-close-draws-no-ring", passed: root.results.pointerCloses === true },
            { name: "spring-dropdown-press-outside-closes-without-pick", passed: root.results.outsideCloses === true },
            { name: "spring-dropdown-escape-closes", passed: root.results.escape === true },
            { name: "spring-dropdown-reduced-motion-opens-at-once", passed: root.results.reducedOpen === true },
            { name: "spring-dropdown-reduced-motion-closes-at-once", passed: root.results.reducedClose === true },
            { name: "spring-dropdown-at-rest-does-no-work", passed: !rest.animating && !rest.menuShown },
            { name: "spring-dropdown-empty-model-stays-closed", passed: !empty.expanded && !empty.menuShown },
            { name: "spring-dropdown-shown-opens-without-lift", passed: shown.expanded && root.near(shown.menuLevel, 1)
                && shown.liftOffset === 0 }
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
        stage.grabToImage(result => {
            result.saveToFile(root.capture);
            Qt.quit();
        });
    }
}
