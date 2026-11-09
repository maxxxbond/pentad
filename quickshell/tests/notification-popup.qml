import QtQuick
import Quickshell
import QtTest
import qs.services
import qs.features.notifications
import qs.theme

ShellRoot {
    id: root
    property TestEvent pointer: TestEvent {}
    property var swipeCard: null
    property string swipeKey: ""
    property real swipePeak: 0
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
        property var dismissed: []
        function dismiss(key) {
            dismissed = dismissed.concat([key]);
            root.services.notifications.dismiss(key);
        }
        function invoke(key, action) { return root.services.notifications.invoke(key, action); }
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
            // Sent twice: the copy folds into one card with a repeat count.
            { title: "Review requested", body: "Please review the changes before the next release.",
                urgency: 2, image: "/usr/share/pixmaps/archlinux-logo.png", copies: 2 },
            // Without a title the body leads; with only a default action the popup offers Open.
            { title: "", body: "The background worker is healthy again.", actions: ["default", "Open"] }
        ].forEach(function(item, index) {
            for (let copy = 0; copy < (item.copies || 1); ++copy) controller.notify({
                app: "Fixture monitor", title: item.title, body: item.body, icon: "", image: item.image || "",
                actions: item.actions || ["open", longAction, "rollback", "Rollback the deployment and restore the previous release"],
                hints: { urgency: item.urgency || 1, transient: false, resident: true }, expireTimeout: 0,
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
                const repeated = cards.filter(function(card) { return card.record.repeat === 2; });
                const chip = repeated.length === 1 ? root.findNamed(repeated[0], "notification-repeat-chip") : null;
                root.check("repeat-folds-into-one-card", repeated.length === 1 && !!chip && chip.visible,
                    "repeats=" + JSON.stringify(cards.map(function(card) { return card.record.repeat; })));
                const opens = cards.map(function(card) {
                    const action = root.findNamed(card, "notification-open-action");
                    return !!action && action.visible;
                });
                root.check("open-offered-only-without-app-buttons", JSON.stringify(opens) === "[true,false,false]",
                    JSON.stringify(opens));
                root.stablePresentedCount = root.fakeNotifications.presentedCalls;
            } else if (root.step === 5) {
                root.check("sticky-popups-remain-after-multiple-frames", secondHost.localRecords.length === 3
                    && root.fakeNotifications.state.popups.length === 3);
                root.check("no-repeated-presentation-acknowledgements", root.fakeNotifications.presentedCalls === root.stablePresentedCount);
                const capture = Quickshell.env("PENTAD_ARTIFACT_PATH");
                if (capture) secondHost.cardColumn.grabToImage(function(result) { result.saveToFile(capture); });
            } else if (root.step === 6) {
                const cards = [];
                root.collectNamed(secondHost.cardColumn, "notification-popup-card", cards);
                root.hoverCard = cards.length ? cards[0] : null;
                if (root.hoverCard) root.pointer.mouseMove(root.hoverCard, root.hoverCard.width / 2, root.hoverCard.height / 2,
                    0, Qt.NoButton, Qt.NoModifier);
            } else if (root.step === 7) {
                root.check("hover-swaps-meta-for-controls", !!root.hoverCard && root.hoverCard.engaged && root.hoverCard.clickable);
                const capture = Quickshell.env("PENTAD_ARTIFACT_PATH");
                if (capture) secondHost.cardColumn.grabToImage(function(result) { result.saveToFile(capture + ".hover.png"); });
                root.startSwipe();
            } else if (root.step <= 7 + 5 * root.swipes.length) {
                // Each swipe: press, four slow moves (the last one releases), then the checks.
                const phase = (root.step - 8) % 5, swipe = root.swipes[Math.floor((root.step - 8) / 5)];
                if (phase < 4) {
                    root.moveSwipe(phase + 1, swipe.distance);
                    return;
                }
                const key = root.swipeKey, gone = root.fakeNotifications.dismissed.indexOf(key) >= 0
                    && secondHost.localRecords.every(function(record) { return record.key !== key; });
                const detail = "peak=" + root.swipePeak + " dismissed=" + JSON.stringify(root.fakeNotifications.dismissed);
                root.check(swipe.name + "-follows-pointer", root.swipePeak > 20, detail);
                if (swipe.dismisses) root.check(swipe.name + "-dismisses", key !== "" && gone, detail);
                else {
                    const surface = root.findNamed(root.swipeCard, "notification-card-surface");
                    root.check(swipe.name + "-springs-back", key !== "" && !gone && !!surface && surface.x === 0, detail);
                }
                if (root.step === 7 + 5 * root.swipes.length) { stop(); root.report(); return; }
                const next = root.swipes[Math.floor((root.step - 8) / 5) + 1];
                Theme.resolve({ appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: next.reducedMotion });
                root.startSwipe();
            }
        }
    }
    property int stablePresentedCount: 0
    property var hoverCard: null
    readonly property var swipes: [
        { name: "swipe-reduced-motion", distance: 0.72, reducedMotion: true, dismisses: true },
        { name: "swipe-animated", distance: 0.72, reducedMotion: false, dismisses: true },
        { name: "swipe-short", distance: 0.2, reducedMotion: false, dismisses: false }
    ]
    function startSwipe() {
        const cards = [];
        collectNamed(secondHost.cardColumn, "notification-popup-card", cards);
        swipeCard = cards.length ? cards[0] : null;
        swipeKey = swipeCard ? swipeCard.record.key : "";
        swipePeak = 0;
        if (swipeCard) pointer.mousePress(swipeCard, 40, swipeCard.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
    }
    function moveSwipe(move, distance) {
        const card = swipeCard;
        if (!card) return;
        const x = 40 + move * card.width * distance / 4;
        pointer.mouseMove(card, x, card.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
        const surface = findNamed(card, "notification-card-surface");
        if (surface) swipePeak = Math.max(swipePeak, surface.x);
        if (move === 4) pointer.mouseRelease(card, x, card.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
    }
}
