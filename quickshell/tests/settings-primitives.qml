import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.components
import qs.features.settings
import qs.theme

ShellRoot {
    id: root

    property TestEvent pointer: TestEvent {}
    property var checks: []
    property var activations: []
    property var tabActivations: []
    property int navClicks: 0

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }

    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }

    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks,
        }));
        Qt.quit();
    }

    FloatingWindow {
        id: fixtureWindow
        visible: true
        implicitWidth: 720
        implicitHeight: 520
        color: Theme.tokens.surface

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            SettingsSection {
                id: plainSection
                width: 680
                title: "Plain"
                SettingsRow {
                    id: plainRow
                    width: parent.width
                    label: "Plain row"
                }
                SettingsRow {
                    id: secondRow
                    width: parent.width
                    label: "Second row"
                }
            }
            SettingsSection {
                id: helpSection
                width: 680
                title: "Helped"
                helpText: "Explanation"
            }
            SettingsSection {
                id: narrowSection
                width: 400
                title: "Narrow"
                SettingsRow { width: parent.width; label: "Narrow row" }
            }
            SettingsRow {
                id: okRow
                width: 400
                label: "No error"
                error: false
                errorText: "Should stay hidden"
            }
            SettingsRow {
                id: failedRow
                width: 400
                label: "Failed"
                error: true
                errorText: "Save failed"
                helpText: "Row help"
            }
            PentadSegmented {
                id: segmented
                width: 240
                accessibleName: "Mode"
                options: [
                    { value: "a", label: "Alpha" },
                    { value: "b", label: "Beta" },
                    { value: "c", label: "Gamma" },
                ]
                value: "a"
                onActivated: function(value) { root.activations = root.activations.concat([value]); }
            }
            PentadSegmented {
                id: tabsControl
                width: 240
                accessibleName: "Tabs"
                tabList: true
                activateOnPress: true
                segmentObjectName: "seg-tab-"
                options: [
                    { value: 0, label: "One" },
                    { value: 1, label: "Two" },
                ]
                value: 0
                onActivated: function(value) { root.tabActivations = root.tabActivations.concat([value]); }
            }
            PentadSegmented {
                id: longLabels
                accessibleName: "Long labels"
                options: [{ value: 0, label: "Розташування" }, { value: 1, label: "Інструменти" }]
                value: 0
            }
            FontMetrics {
                id: longMetrics
                font.family: Theme.tokens.fontFamily
                font.pixelSize: Metrics.textBody
            }
            SettingsNavItem {
                id: navItem
                width: 200
                label: "Appearance"
                active: true
                onClicked: root.navClicks += 1
            }
            SettingsNavItem {
                id: collapsedNav
                label: "Bar"
                collapsed: true
            }
        }

        TestCase {
            id: testCase
            name: "SettingsPrimitives"
            when: false

            function test_primitives() {
                wait(0);
                root.check("section-without-help-has-no-info-button",
                    !root.findNamed(plainSection, "settings-section-info").visible);
                root.check("section-with-help-shows-info-button",
                    root.findNamed(helpSection, "settings-section-info").visible);
                // Section: rows lie flat on one card, separated by inset lines.
                root.check("embedded-row-has-no-own-card", !root.findNamed(plainRow, "settings-row-card").visible);
                root.check("first-row-has-no-separator", !root.findNamed(plainRow, "settings-row-separator").visible);
                root.check("second-row-draws-separator", root.findNamed(secondRow, "settings-row-separator").visible);
                root.check("standalone-row-draws-its-card", root.findNamed(okRow, "settings-row-card").visible);
                root.check("section-narrow-keeps-card-below-caption",
                    root.findNamed(narrowSection, "settings-section-card").y > 0);
                root.check("row-without-help-has-no-info-button", !root.findNamed(plainRow, "settings-row-info").visible);
                root.check("row-with-help-shows-info-button", root.findNamed(failedRow, "settings-row-info").visible);
                // A standalone row in error wears the softened status edge on its card.
                const failedCard = root.findNamed(failedRow, "settings-row-card");
                root.check("error-row-outlines-in-soft-status-red", failedCard !== null && failedCard.visible
                    && String(failedCard.edge) !== "#00000000" && failedCard.edge.a < 1, failedCard ? String(failedCard.edge) : "no card");
                root.check("row-hides-error-text-when-not-error", !root.findNamed(okRow, "settings-row-error").visible);
                root.check("row-shows-error-text-when-error", root.findNamed(failedRow, "settings-row-error").visible
                    && root.findNamed(failedRow, "settings-row-error").text === "Save failed");
                failedRow.error = false;
                root.check("row-error-text-hides-after-error-clears", !root.findNamed(failedRow, "settings-row-error").visible);
                failedRow.pending = true;
                root.check("row-pending-shows-indicator", root.findNamed(failedRow, "settings-row-pending").visible);
                failedRow.pending = false;

                const segmentWidth = segmented.segmentWidth;
                root.pointer.mouseClick(segmented, segmented.inset + segmentWidth * 1.5, segmented.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0);
                root.check("segmented-click-emits-activated", root.activations.length === 1 && root.activations[0] === "b",
                    JSON.stringify(root.activations));
                root.check("segmented-click-does-not-change-value", segmented.value === "a" && segmented.selectedIndex === 0);
                const clickX = segmented.inset + segmentWidth * 1.5;
                root.pointer.mousePress(segmented, clickX, segmented.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("segmented-default-waits-for-release", root.activations.length === 1);
                root.pointer.mouseRelease(segmented, clickX, segmented.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("segmented-default-activates-on-release", root.activations.length === 2 && root.activations[1] === "b");
                // Pointer focus never draws the ring; a key press does.
                root.check("pointer-focus-draws-no-ring", segmented.activeFocus && !root.findNamed(segmented, "segmentedFocusRing").visible);

                segmented.forceActiveFocus();
                wait(0);
                const before = root.activations.length;
                root.pointer.keyClick(Qt.Key_Right, Qt.NoModifier, 0);
                root.check("segmented-arrow-does-not-activate", root.activations.length === before && segmented.value === "a");
                root.check("keyboard-draws-ring", root.findNamed(segmented, "segmentedFocusRing").visible);
                root.pointer.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                // The earlier click left keyboard focus on "b", so Right moves it to "c".
                root.check("segmented-arrow-enter-emits-activated", root.activations.length === before + 1
                    && root.activations[root.activations.length - 1] === "c",
                    JSON.stringify(root.activations));
                root.check("segmented-keyboard-does-not-change-value", segmented.value === "a");
                root.pointer.keyClick(Qt.Key_End, Qt.NoModifier, 0);
                root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
                root.check("segmented-end-space-emits-last", root.activations[root.activations.length - 1] === "c");
                segmented.value = "b";
                root.check("segmented-follows-parent-value", segmented.selectedIndex === 1);

                root.check("tabs-segment-object-names", !!root.findNamed(tabsControl, "seg-tab-0") && !!root.findNamed(tabsControl, "seg-tab-1")
                    && tabsControl.segments.itemAt(1) === root.findNamed(tabsControl, "seg-tab-1"));
                longLabels.width = longLabels.implicitWidth;
                const longAdvance = longMetrics.advanceWidth("Розташування");
                root.check("segmented-implicit-width-fits-long-labels", longLabels.implicitWidth > 2 * 96 + 2 * longLabels.inset
                    && longLabels.segmentWidth >= longAdvance + 16, longLabels.implicitWidth + "/" + longLabels.segmentWidth + "/" + longAdvance);
                root.pointer.mousePress(tabsControl, tabsControl.inset + tabsControl.segmentWidth * 1.5, tabsControl.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0);
                root.check("tabs-activate-on-press", root.tabActivations.length === 1 && root.tabActivations[0] === 1,
                    JSON.stringify(root.tabActivations));
                root.pointer.mouseRelease(tabsControl, tabsControl.inset + tabsControl.segmentWidth * 1.5, tabsControl.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0);
                root.check("tabs-release-does-not-repeat", root.tabActivations.length === 1);

                root.pointer.mouseClick(navItem, navItem.width / 2, navItem.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("nav-item-click-emits-clicked", root.navClicks === 1);
                root.finish();
            }
        }

        Timer {
            interval: 300
            running: true
            repeat: false
            onTriggered: testCase.test_primitives()
        }
    }
}
