import QtQuick
import Quickshell
import QtTest
import qs.services
import qs.features.notifications
import qs.theme

ShellRoot {
    id: root
    property Services services: Services { preview: true; safeMode: true }
    property int step: 0
    property int presentedCalls: 0
    property var firstScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    property var secondScreen: Quickshell.screens.length > 1 ? Quickshell.screens[1] : null

    property QtObject fakeHyprland: QtObject {
        property var state: ({ kind: "ready", value: {
            focusedOutputId: 1,
            outputs: root.firstScreen && root.secondScreen ? [
                { id: 1, name: root.firstScreen.name }, { id: 2, name: root.secondScreen.name }
            ] : []
        } })
    }
    property QtObject fakeNotifications: QtObject {
        property var state: root.services.notifications.state
        property int presentedCalls: 0
        property Connections serviceChanges: Connections {
            target: root.services.notifications
            function onStateChanged() { root.fakeNotifications.state = root.services.notifications.state; }
        }
        function setPresented(key, shown) {
            presentedCalls++;
            root.services.notifications.setPresented(key, shown);
        }
        function setHovered(key, hovered) { root.services.notifications.setHovered(key, hovered); }
    }
    property QtObject fakeUiServices: QtObject {
        readonly property var config: root.services.config
        readonly property var notifications: root.fakeNotifications
        readonly property var hyprland: root.fakeHyprland
        function text(uk, en) { return uk; }
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    property var checks: []
    function report() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const items = item.children || [];
        for (let index = 0; index < items.length; ++index) {
            const found = findNamed(items[index], name);
            if (found) return found;
        }
        return null;
    }
    function collectNamed(item, name, found) {
        if (!item) return;
        if (item.objectName === name) found.push(item);
        const items = item.children || [];
        for (let index = 0; index < items.length; ++index) collectNamed(items[index], name, found);
    }
    function addFixtures() {
        const controller = services.notifications.controller;
        controller.setStatus("available");
        const longAction = "Open the complete deployment summary and review all affected services";
        [
            { title: "Build completed", body: "The deployment finished successfully across every production region. This long message checks that the popup body wraps inside its card and remains clipped to the card mask when the display is short." },
            { title: "Review requested", body: "Please review the changes before the next release." },
            { title: "Service restarted", body: "The background worker is healthy again." }
        ].forEach(function(item, index) {
            controller.notify({
                app: "Fixture monitor", title: item.title, body: item.body, icon: "",
                actions: ["open", longAction, "rollback", "Rollback the deployment and restore the previous release"],
                hints: { urgency: 1, transient: false, resident: true }, expireTimeout: 0,
                sender: "notification-popup-fixture-" + index
            });
        });
    }

    Component.onCompleted: {
        Theme.resolve({ appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: true });
        if (!firstScreen || !secondScreen) {
            check("two-virtual-screens", false, "The private KWin fixture requires two virtual screens.");
            report();
        }
    }

    PanelWindow {
        id: firstBar
        screen: root.firstScreen
        visible: true
        color: "transparent"
        implicitWidth: 1280
        implicitHeight: 36
        exclusionMode: ExclusionMode.Ignore
        NotificationPopupHost { id: firstHost; services: root.fakeUiServices; barWindow: firstBar; outputId: root.firstScreen ? root.firstScreen.name : "" }
    }
    PanelWindow {
        id: secondBar
        screen: root.secondScreen
        visible: true
        color: "transparent"
        implicitWidth: 1280
        implicitHeight: 36
        exclusionMode: ExclusionMode.Ignore
        NotificationPopupHost { id: secondHost; services: root.fakeUiServices; barWindow: secondBar; outputId: root.secondScreen ? root.secondScreen.name : "" }
    }

    Timer {
        interval: 450
        repeat: true
        running: true
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                root.check("preview-restored-without-native-server", root.services.notifications.restoreComplete
                    && !!root.services.notifications.controller && !root.services.notifications.nativeEnabled);
                root.addFixtures();
            } else if (root.step === 2) {
                const records = root.fakeNotifications.state.popups;
                root.check("initial-focused-output-routes-three", records.length === 3
                    && firstHost.localRecords.length === 3 && secondHost.localRecords.length === 0);
                root.check("initial-popup-window-visible", firstHost.popupWindow.visible && !secondHost.popupWindow.visible);
                root.fakeHyprland.state = ({ kind: "ready", value: {
                    focusedOutputId: 2,
                    outputs: [ { id: 1, name: root.firstScreen.name }, { id: 2, name: root.secondScreen.name } ]
                } });
            } else if (root.step === 3) {
                root.check("focus-change-retains-existing-routes", firstHost.localRecords.length === 3
                    && secondHost.localRecords.length === 0);
                root.fakeHyprland.state = ({ kind: "ready", value: {
                    focusedOutputId: 2, outputs: [ { id: 2, name: root.secondScreen.name } ]
                } });
            } else if (root.step === 4) {
                const cards = [];
                root.collectNamed(secondHost.cardColumn, "notification-popup-card", cards);
                root.check("removed-output-reroutes-once", firstHost.localRecords.length === 0
                    && secondHost.localRecords.length === 3 && secondHost.popupWindow.visible
                    && root.fakeNotifications.state.popups.length === 3);
                root.check("popup-sizes-match-card-stack", secondHost.popupWindow.height <= root.secondScreen.height
                    && Math.abs(secondHost.popupWindow.height - secondHost.cardColumn.implicitHeight - 2 * Metrics.overlayShadowRoom) < 2);
                const actionsFit = cards.length === 3 && cards.every(function(card) {
                    const flow = root.findNamed(card, "notification-actions-flow");
                    return card.height === card.implicitHeight && !!flow && flow.width > 0
                        && flow.height > 0 && flow.y + flow.height <= card.height;
                });
                root.check("long-card-actions-fit", actionsFit,
                    "cards=" + cards.length + (cards.length ? ", first=" + cards[0].height + "/" + cards[0].implicitHeight : ""));
                root.stablePresentedCount = root.fakeNotifications.presentedCalls;
            } else if (root.step === 5) {
                root.check("sticky-popups-remain-after-multiple-frames", secondHost.localRecords.length === 3
                    && root.fakeNotifications.state.popups.length === 3);
                root.check("no-repeated-presentation-acknowledgements", root.fakeNotifications.presentedCalls === root.stablePresentedCount);
                stop();
                root.report();
            }
        }
    }
    property int stablePresentedCount: 0
}
