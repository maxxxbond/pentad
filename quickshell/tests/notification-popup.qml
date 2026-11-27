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
        property string cardStyle: "toast"
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
            // Without a title the body leads; a default action makes the card itself the button.
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
        Item { id: lateHost; visible: false; width: 360; height: 400 }
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
    // Every look side by side in a window of fixed size. The private compositor stops presenting a
    // popup whose size changes while it is shown, so restyling and the one-line hover are checked here.
    PanelWindow {
        id: gallery
        screen: root.firstScreen
        visible: root.galleryRecords.length > 0
        color: Theme.tokens.surface
        implicitWidth: 1280
        implicitHeight: 720
        exclusionMode: ExclusionMode.Ignore
        Row {
            id: galleryRow
            x: 16
            y: 16
            spacing: 16
            Repeater {
                model: ["toast", "bold", "line", "source"]
                delegate: Column {
                    id: galleryColumn
                    required property string modelData
                    property QtObject styleNotifications: QtObject {
                        property string cardStyle: galleryColumn.modelData
                        readonly property var state: root.fakeNotifications.state
                        property string replyRequest: ""
                        function dismiss(key) {}
                        function invoke(key, action) { return false; }
                    }
                    property QtObject styleServices: QtObject {
                        readonly property var config: root.services.config
                        readonly property var notifications: galleryColumn.styleNotifications
                        readonly property var hyprland: root.fakeHyprland
                        function text(uk, en) { return uk; }
                    }
                    objectName: "gallery-" + modelData
                    width: 296
                    spacing: 8
                    Repeater {
                        model: root.galleryRecords
                        delegate: NotificationCard {
                            required property var modelData
                            services: galleryColumn.styleServices
                            record: modelData
                            popup: true
                        }
                    }
                }
            }
        }
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
                // Only cards with app buttons carry an actions row; the default action is the card click.
                const withButtons = cards.filter(function(card) { return card.buttons.length > 0; });
                const actionsFit = cards.length === 3 && withButtons.length === 2 && withButtons.every(function(card) {
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
                root.stablePresentedCount = root.fakeNotifications.presentedCalls;
                // A popup card is often created before its window shows; the detail must appear once it does.
                const build = root.fakeNotifications.state.popups.find(function(record) { return record.title === "Build completed"; });
                root.lateCard = lateCardComponent.createObject(lateHost, { services: root.fakeUiServices, record: build, popup: true });
                lateHost.visible = true;
            } else if (root.step === 5) {
                root.check("sticky-popups-remain-after-multiple-frames", secondHost.localRecords.length === 3
                    && root.fakeNotifications.state.popups.length === 3);
                root.check("no-repeated-presentation-acknowledgements", root.fakeNotifications.presentedCalls === root.stablePresentedCount);
                const lateDetail = root.lateCard ? root.findNamed(root.lateCard, "notification-detail") : null;
                root.check("detail-shows-when-created-hidden", !!lateDetail && lateDetail.visible && lateDetail.height > 0,
                    lateDetail ? "visible=" + lateDetail.visible + " height=" + lateDetail.height : "no card");
                if (root.lateCard) root.lateCard.destroy();
                root.capture(secondHost.cardColumn, "");
                const restHeadline = root.findNamed(root.popupCards()[0], "notification-headline");
                root.restHeadlineWidth = restHeadline ? restHeadline.width : -1;
                root.galleryRecords = root.fakeNotifications.state.popups.slice();
            } else if (root.step === 6) {
                const shape = root.galleryCards("source").map(function(card) {
                    const line = root.findNamed(card, "notification-source-line");
                    const split = root.findNamed(card, "notification-split-actions");
                    const flow = root.findNamed(card, "notification-actions-flow");
                    return (line && line.visible ? "L" : "-") + (split && split.visible ? "S" : "-") + (flow && flow.visible ? "F" : "-");
                });
                // Every card names its source; the two with app buttons end in the action row, never the flow.
                root.check("source-style-header-and-action-row", JSON.stringify(shape) === '["L--","LS-","LS-"]', JSON.stringify(shape));
                const line = root.galleryCards("line");
                const heights = line.map(function(card) { return card.compact ? card.height : -1; });
                root.check("line-style-rests-on-one-line", heights.length === 3 && heights.every(function(height) { return height === 56; }),
                    JSON.stringify(heights));
                const inline = line.length === 3 ? root.findNamed(line[2], "notification-inline-detail") : null;
                root.check("line-style-keeps-detail-inline", !!inline && inline.visible && inline.width > 0);
            } else if (root.step === 7) {
                const line = root.galleryCards("line");
                if (line.length === 3) root.pointer.mouseMove(line[2], line[2].width / 2, 20, 0, Qt.NoButton, Qt.NoModifier);
            } else if (root.step === 8) {
                const card = root.galleryCards("line")[2];
                const flow = card ? root.findNamed(card, "notification-actions-flow") : null;
                root.check("line-style-opens-under-pointer", !!card && !card.compact && card.height > 56 && !!flow && flow.visible,
                    card ? "height=" + card.height : "no card");
            } else if (root.step === 9) {
                // A change in Settings restyles cards that are already open.
                root.galleryColumn("toast").styleNotifications.cardStyle = "line";
            } else if (root.step === 10) {
                const restyled = root.galleryCards("toast");
                root.check("open-cards-follow-a-style-change", restyled.length === 3 && restyled.every(function(card) {
                    return card.variant === "line" && card.compact && card.height === 56;
                }), JSON.stringify(restyled.map(function(card) { return card.variant + ":" + card.height; })));
                root.galleryColumn("toast").styleNotifications.cardStyle = "toast";
            } else if (root.step === 11) {
                const cards = root.popupCards();
                root.hoverCard = cards.length ? cards[0] : null;
                if (root.hoverCard) root.pointer.mouseMove(root.hoverCard, root.hoverCard.width / 2, root.hoverCard.height / 2,
                    0, Qt.NoButton, Qt.NoModifier);
            } else if (root.step === 12) {
                root.check("hover-marks-card-clickable", !!root.hoverCard && root.hoverCard.engaged && root.hoverCard.clickable);
                const headline = root.hoverCard ? root.findNamed(root.hoverCard, "notification-headline") : null;
                root.check("hover-keeps-title-wrap", !!headline && root.restHeadlineWidth > 0 && headline.width === root.restHeadlineWidth,
                    "rest=" + root.restHeadlineWidth + " hover=" + (headline ? headline.width : -1));
                root.startSwipe();
            } else if (root.step <= 12 + 5 * root.swipes.length) {
                // Each swipe: press, four slow moves (the last one releases), then the checks.
                const phase = (root.step - 13) % 5, swipe = root.swipes[Math.floor((root.step - 13) / 5)];
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
                if (root.step === 12 + 5 * root.swipes.length) { stop(); root.report(); return; }
                const next = root.swipes[Math.floor((root.step - 13) / 5) + 1];
                Theme.resolve({ appearance: "dark", accent: "#869677", fontFamily: "Geist", reducedMotion: next.reducedMotion });
                root.startSwipe();
            }
        }
    }
    property int stablePresentedCount: 0
    property var hoverCard: null
    property var lateCard: null
    property Component lateCardComponent: Component { NotificationCard {} }
    property real restHeadlineWidth: -1
    property var galleryRecords: []
    function popupCards() {
        const cards = [];
        collectNamed(secondHost.cardColumn, "notification-popup-card", cards);
        return cards;
    }
    function galleryColumn(style) { return findNamed(galleryRow, "gallery-" + style); }
    function galleryCards(style) {
        const cards = [];
        collectNamed(galleryColumn(style), "notification-popup-card", cards);
        return cards;
    }
    // Saves an item next to the report; the suffix names the look or state.
    function capture(item, suffix) {
        const path = Quickshell.env("PENTAD_ARTIFACT_PATH");
        if (path && item) item.grabToImage(function(result) { result.saveToFile(path + suffix); });
    }
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
