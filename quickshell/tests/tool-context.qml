import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.theme
import qs.services
import "../features/bar"

ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    property var checks: []
    property var actions: []
    property bool finishing: false
    property var desktopValue: ({ recording: false, recordPending: true, inhibited: false, inhibitPending: true })
    property Services nativeServices: Services { preview: true; safeMode: true }

    QtObject {
        id: fakeDesktop
        property bool preview: false
        property bool safeMode: false
        property var state: ({ kind: "ready", value: root.desktopValue })
        function command(action) {
            root.actions = root.actions.concat([action]);
            return "fixture-command-" + root.actions.length;
        }
    }
    QtObject {
        id: fakeNotifications
        property var state: ({ status: "available", dnd: false })
    }
    QtObject {
        id: fakeServices
        readonly property bool preview: false
        readonly property bool safeMode: false
        readonly property var config: root.nativeServices.config
        readonly property var plugins: root.nativeServices.plugins
        readonly property var hyprland: root.nativeServices.hyprland
        readonly property var audio: root.nativeServices.audio
        readonly property var power: root.nativeServices.power
        readonly property var network: root.nativeServices.network
        readonly property var tray: root.nativeServices.tray
        readonly property var media: root.nativeServices.media
        readonly property var artwork: root.nativeServices.artwork
        readonly property var lyrics: root.nativeServices.lyrics
        readonly property var visualizer: root.nativeServices.visualizer
        readonly property var shelf: root.nativeServices.shelf
        readonly property var activity: root.nativeServices.activity
        readonly property var navigation: root.nativeServices.navigation
        readonly property var desktop: fakeDesktop
        readonly property var notifications: fakeNotifications
        readonly property var popups: null
        function brightnessFor(outputId) { return root.nativeServices.brightnessFor(outputId); }
        function releaseBrightness(outputId) { root.nativeServices.releaseBrightness(outputId); }
        function text(ukrainian, english) { return english; }
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }

    function findText(item, value) {
        if (!item) return null;
        if (item.text === value) return item;
        for (const child of item.children || []) {
            const found = findText(child, value);
            if (found) return found;
        }
        return null;
    }

    function findPointer(item) {
        if (!item) return null;
        if (item.acceptedButtons !== undefined && typeof item.forceActiveFocus === "function")
            return item;
        for (const child of item.children || []) {
            const found = findPointer(child);
            if (found) return found;
        }
        return null;
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

    function findButton(item, value) {
        if (!item) return null;
        if (item.text === value && item.requestedEnabled !== undefined)
            return item;
        for (const child of item.children || []) {
            const found = findButton(child, value);
            if (found) return found;
        }
        return null;
    }

    function finish() {
        if (finishing) return;
        finishing = true;
        const artifact = Quickshell.env("PENTAD_ARTIFACT_PATH");
        function complete() {
            const finalPassed = root.checks.length > 0 && root.checks.every(function(item) { return item.passed; });
            console.log("PENTAD_TEST " + JSON.stringify({ status: finalPassed ? "pass" : "fail", checks: root.checks }));
            Qt.quit();
        }
        function saveGallery() {
            if (!artifact) { complete(); return; }
            captureSurface.grabToImage(function(result) {
                root.check("tool-context-capture-saved", result.saveToFile(artifact));
                complete();
            });
        }
        if (artifact && toolWidget.contextPopup.opened) {
            popupCaptureDeadline.start();
            toolWidget.contextPopup.surface.grabToImage(function(result) {
                popupCaptureDeadline.stop();
                const saved = result.saveToFile(artifact + ".popover.png");
                root.check("optional-popover-surface-capture", saved,
                    saved ? "captured" : "surface grab returned no image; geometry was checked");
                saveGallery();
            });
        } else saveGallery();
    }

    Component.onCompleted: {
        Theme.resolve({
            appearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE") || "dark",
            accent: Quickshell.env("PENTAD_GALLERY_ACCENT") || "#869677",
            fontFamily: "Geist",
            reducedMotion: true,
        });
        toolWidget.contextPopup.grabFocus = false;
    }

    FloatingWindow {
        id: fixtureWindow
        visible: true
        implicitWidth: 1280
        implicitHeight: 220
        color: "#101210"
        Rectangle {
            id: captureSurface
            anchors.fill: parent
            color: "#1b1e1b"
            BarFace {
                id: barFace
                x: 0; y: 0; width: 1280; height: 40
                services: nativeServices
                outputId: "tool-context-fixture"
                ToolsWidget {
                    id: toolWidget
                    x: (parent.width - width) / 2
                    y: 6
                    services: fakeServices
                    onActivated: function(action) { root.actions = root.actions.concat([action]); }
                }
            }
        }
    }

    TestCase {
        id: testCase
        name: "ToolContext"
        when: false

        function test_contextAndPendingGuards() {
            wait(40);
            const record = toolWidget.buttonRepeater.itemAt(3);
            const inhibit = toolWidget.buttonRepeater.itemAt(1);
            const screenshot = toolWidget.buttonRepeater.itemAt(2);
            const popup = toolWidget.contextPopup;

            root.check("pending-actions-block-primary-record", record.pending
                && pointer.mouseClick(record, record.width / 2, record.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0) && root.actions.length === 0);
            root.check("pending-actions-block-primary-inhibit", inhibit.pending
                && pointer.mouseClick(inhibit, inhibit.width / 2, inhibit.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0) && root.actions.length === 0);

            root.check("record-context-right-press-dispatched", pointer.mousePress(record,
                record.width / 2, record.height / 2, Qt.RightButton, Qt.NoModifier, 0));
            wait(40);
            root.check("record-context-opens-before-release", popup.opened && popup.anchorItem === record);
            root.check("record-context-right-release-dispatched", pointer.mouseRelease(record,
                record.width / 2, record.height / 2, Qt.RightButton, Qt.NoModifier, 0));
            wait(40);
            root.check("record-context-release-keeps-menu-open", popup.opened && popup.anchorItem === record);
            const recordStatus = root.findText(popup.contentItem, "In progress…");
            const recordAction = root.findButton(popup.contentItem, "Record area");
            root.check("record-context-open-and-compact", popup.opened && popup.anchorItem === record
                && popup.window.width > 0 && popup.window.width >= 240 && popup.window.width < 360 && popup.window.height > 0,
                JSON.stringify({ opened: popup.opened, width: popup.window.width, height: popup.window.height }));
            root.check("pending-record-context-is-readable-without-primary-action", !!recordStatus && !recordAction
                && recordStatus.lineCount === 1, JSON.stringify({ status: !!recordStatus, action: !!recordAction }));
            root.check("inhibit-context-right-click-dispatched", pointer.mouseClick(inhibit,
                inhibit.width / 2, inhibit.height / 2, Qt.RightButton, Qt.NoModifier, 0));
            wait(40);
            const inhibitStatus = root.findText(popup.contentItem, "In progress…");
            const inhibitAction = root.findButton(popup.contentItem, "Turn on");
            root.check("open-context-retargets-in-place", popup.opened && popup.anchorItem === inhibit
                && toolWidget.contextControl === inhibit, JSON.stringify({ opened: popup.opened, anchor: popup.anchorItem === inhibit }));
            root.check("pending-inhibit-context-remains-readable", !!inhibitStatus
                && !inhibitAction && inhibitStatus.lineCount === 1
                && root.findText(popup.contentItem, "Prevent sleep").lineCount === 1);
            popup.close();
            root.desktopValue = { recording: false, recordPending: false, inhibited: false, inhibitPending: false };
            pointer.mouseClick(inhibit, inhibit.width / 2, inhibit.height / 2, Qt.RightButton, Qt.NoModifier, 0);
            wait(40);
            root.check("inactive-inhibit-context-omits-redundant-status", !root.findText(popup.contentItem, "Off")
                && !root.findButton(popup.contentItem, "Turn on"));
            popup.close();
            pointer.mouseClick(inhibit, inhibit.width / 2, inhibit.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            root.check("inhibit-primary-click-still-dispatches", root.actions.length === 1 && root.actions[0] === "inhibit");
            root.actions = [];
            root.desktopValue = { recording: true, recordPending: false, inhibited: true, inhibitPending: false };
            pointer.mouseClick(record, record.width / 2, record.height / 2, Qt.RightButton, Qt.NoModifier, 0);
            wait(40);
            root.check("active-record-context-does-not-duplicate-stop", !!root.findText(popup.contentItem, "Area · no audio")
                && !root.findButton(popup.contentItem, "Stop recording"));
            popup.close();
            pointer.mouseClick(inhibit, inhibit.width / 2, inhibit.height / 2, Qt.RightButton, Qt.NoModifier, 0);
            wait(40);
            root.check("active-inhibit-context-omits-redundant-status", !root.findText(popup.contentItem, "On")
                && !root.findButton(popup.contentItem, "Turn off"));
            popup.close();
            const dnd = toolWidget.buttonRepeater.itemAt(0);
            pointer.mouseClick(dnd, dnd.width / 2, dnd.height / 2, Qt.RightButton, Qt.NoModifier, 0);
            wait(40);
            root.check("dnd-context-label-is-single-line-without-toggle", root.findText(popup.contentItem, "Do not disturb").lineCount === 1
                && !root.findButton(popup.contentItem, "Turn on"));
            popup.close();

            root.check("screenshot-context-right-click-dispatched", pointer.mouseClick(screenshot,
                screenshot.width / 2, screenshot.height / 2, Qt.RightButton, Qt.NoModifier, 0));
            wait(40);
            const pickColor = root.findText(popup.contentItem, "Pick color");
            root.check("screenshot-context-uses-real-bar-and-offers-color-picker", popup.opened
                && toolWidget.barItem === barFace && barFace.objectName === "pentad-bar-face"
                && !!pickColor && pickColor.enabled);
            if (pickColor) pointer.mouseClick(pickColor, pickColor.width / 2, pickColor.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("secondary-color-picker-action-forwarded", root.actions.length === 1
                && root.actions[0] === "color-picker", JSON.stringify(root.actions));

            popup.close();
            wait(120);
            const recordPointer = root.findNamed(record, "tools-input-record") || root.findPointer(record);
            if (recordPointer) {
                recordPointer.focus = true;
                recordPointer.forceActiveFocus(Qt.OtherFocusReason);
            }
            wait(40);
            const activeFocusItem = fixtureWindow.contentItem.Window.window.activeFocusItem;
            root.check("record-context-input-focused-for-keyboard", !!recordPointer && recordPointer.activeFocus,
                JSON.stringify({ objectName: recordPointer ? recordPointer.objectName : "", activeFocusItem:
                    activeFocusItem ? activeFocusItem.objectName : "" }));
            const keyboardOpened = pointer.keyClick(Qt.Key_Menu, Qt.NoModifier, 0);
            wait(40);
            root.check("menu-key-opens-record-context", keyboardOpened && popup.opened
                && toolWidget.contextControl === record, JSON.stringify({ opened: popup.opened,
                    anchor: popup.anchorItem === record, context: toolWidget.contextControl === record }));
            root.check("context-popover-does-not-grab-focus", popup.grabFocus === false);
            popup.close();
            root.check("screenshot-context-reopens-for-native-capture", pointer.mouseClick(screenshot,
                screenshot.width / 2, screenshot.height / 2, Qt.RightButton, Qt.NoModifier, 0));
            wait(40);
            const screenshotAction = root.findButton(popup.contentItem, "Capture area");
            const screenshotHeader = root.findText(popup.contentItem, "Area screenshot");
            root.check("bar-screenshot-menu-has-contract-continuous-corners", popup.opened
                && popup.anchorItem === screenshot && popup.window.geometry.bodyTop === 0
                && popup.window.geometry.radius === Metrics.attachedRadius
                && popup.window.geometry.contentLeft >= 0
                && popup.window.geometry.contentRight <= popup.window.width
                && popup.window.surfaceHeight <= 160,
                JSON.stringify({ opened: popup.opened, width: popup.window.width, height: popup.window.surfaceHeight,
                    bodyTop: popup.window.geometry.bodyTop, contentLeft: popup.window.geometry.contentLeft,
                    contentRight: popup.window.geometry.contentRight, captureButton: !!screenshotAction,
                    header: !!screenshotHeader }));
            root.check("bar-screenshot-menu-only-offers-secondary-action", !!screenshotHeader
                && screenshotHeader.lineCount === 1 && !screenshotAction
                && !!root.findButton(popup.contentItem, "Pick color"));
            finish();
        }
    }

    Timer {
        id: popupCaptureDeadline
        interval: 400
        repeat: false
        onTriggered: {
            const artifact = Quickshell.env("PENTAD_ARTIFACT_PATH");
            if (!artifact) { Qt.quit(); return; }
            captureSurface.grabToImage(function(result) {
                root.check("tool-context-capture-saved", result.saveToFile(artifact));
                const passed = root.checks.length > 0 && root.checks.every(function(item) { return item.passed; });
                console.log("PENTAD_TEST " + JSON.stringify({ status: passed ? "pass" : "fail", checks: root.checks }));
                Qt.quit();
            });
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: testCase.test_contextAndPendingGuards()
    }
}
