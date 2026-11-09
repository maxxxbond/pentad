pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components
import qs.theme
import "../../logic/notifications.mjs" as Policy

FocusScope {
    id: root
    objectName: root.popup ? "notification-popup-card" : "notification-center-card"
    required property var services
    required property var record
    property bool expanded: false
    property bool popup: false
    property string outputId: ""
    property real now: Date.now()
    property bool replyOpen: false
    readonly property bool hidden: !!services.notifications && services.notifications.privacy === true && !!record.body
    readonly property bool live: record && record.wireId !== null
    readonly property bool critical: record.urgency === "critical"
    readonly property var buttons: Policy.notificationButtons(record)
    readonly property bool canReply: live && !!record.reply
    readonly property bool engaged: hover.hovered || root.activeFocus
    // Clickable only when a click can reach the source; checked while hovered to keep idle cards cheap.
    readonly property bool clickable: hover.hovered && root.canActivate()
    readonly property int pad: 12
    // The app icon column; the header, headline and detail start after it.
    readonly property int iconSize: 32
    readonly property int indent: iconSize + 12
    // Header line height: app name and time at rest, the hover buttons when engaged.
    readonly property int band: Metrics.statusIcon
    readonly property int thumbSize: 40
    readonly property string appName: record.app || services.text("Невідома програма", "Unknown app")
    readonly property var message: hidden
        ? ({ headline: record.title || appName, detail: services.text("Вміст приховано", "Content hidden") })
        : Policy.notificationText(record)
    // A popup offers an explicit Open when the app gave no buttons of its own; resolved once per record
    // because finding the source window reads the compositor snapshot.
    property bool openable: false
    readonly property string appIconSource: {
        const icon = String(record.icon || "");
        if (!icon) return "";
        if (Quickshell.hasThemeIcon(icon)) return Quickshell.iconPath(icon, true);
        if (icon.startsWith("file://")) return icon;
        if (icon.startsWith("/")) return "file://" + icon;
        return "";
    }
    readonly property string imageSource: {
        const image = String(record.image || "");
        return image.startsWith("/") ? "file://" + image : image;
    }
    readonly property bool hasImage: imageSource !== "" && thumbImage.status !== Image.Error
    readonly property var timeLabels: ({
        now: services.text("щойно", "now"), minutes: services.text("хв", "min"),
        hours: services.text("год", "h"), yesterday: services.text("Вчора", "Yesterday"),
        clock: function(date) { return Qt.formatTime(date, "HH:mm"); },
        date: function(date) { return Qt.formatDate(date, "d MMM"); }
    })
    readonly property bool replyRequested: !popup && canReply && services.notifications.replyRequest === record.key
    signal expandedChangedByUser(bool expanded)
    signal activated()
    width: parent ? parent.width : 320
    implicitHeight: card.height
    height: implicitHeight
    activeFocusOnTab: !popup
    Accessible.role: Accessible.Button
    Accessible.name: appName + ": " + message.headline + (message.detail ? ". " + message.detail : "")
    Keys.onReturnPressed: root.activate()
    Keys.onEnterPressed: root.activate()
    Keys.onDeletePressed: root.dismiss()

    function dismiss() { services.notifications.dismiss(record.key); }
    function toggleExpanded() {
        if (popup) expanded = !expanded;
        else expandedChangedByUser(!expanded);
    }
    function sourceWindow() {
        const hyprland = services.hyprland;
        const snapshot = hyprland && typeof hyprland.currentOverviewSnapshot === "function"
            ? hyprland.currentOverviewSnapshot() : null;
        if (!snapshot || snapshot.kind !== "ready") return null;
        return Policy.findNotificationWindow(record, snapshot.value.clients, snapshot.value.mru);
    }
    function sourceEntry() {
        if (services.preview || services.safeMode) return null;
        const name = record.desktopEntry || record.app;
        return name ? DesktopEntries.heuristicLookup(name) : null;
    }
    function canActivate() { return Policy.hasDefaultAction(record) || !!sourceWindow() || !!sourceEntry(); }
    // The app's own default action may only navigate internally, and Hyprland ignores most
    // activation requests, so the matching window is focused as well; launching is the last resort.
    function activate() {
        const key = record.key;
        const window = sourceWindow();
        let handled = Policy.hasDefaultAction(record) && services.notifications.invoke(key, "default");
        if (window) {
            services.hyprland.focusWindow({ address: window.address, instanceId: window.instanceId });
            handled = true;
        } else if (!handled) {
            const entry = sourceEntry();
            if (entry) { entry.execute(); handled = true; }
        }
        if (!handled) return;
        services.notifications.dismiss(key);
        root.activated();
    }
    function openReply() {
        if (popup) {
            services.notifications.requestReply(record.key);
            if (services.popups) services.popups.open("right", outputId);
            return;
        }
        replyOpen = true;
        replyField.forceActiveFocus();
    }
    function sendReply() {
        if (!services.notifications.reply(record.key, replyField.text)) return;
        replyField.text = "";
        replyOpen = false;
    }
    function consumeReplyRequest() {
        if (!replyRequested || !services.notifications.takeReplyRequest(record.key)) return;
        Qt.callLater(function() { root.openReply(); });
    }
    function refreshOpenable() { openable = popup && buttons.length === 0 && canActivate(); }
    onReplyRequestedChanged: consumeReplyRequest()
    onCanReplyChanged: if (!canReply) replyOpen = false
    onRecordChanged: refreshOpenable()
    Component.onCompleted: { consumeReplyRequest(); refreshOpenable(); }

    component HeaderButton: PentadButton {
        id: headerButton
        width: Metrics.controlSmall - 6
        controlHeight: Metrics.controlSmall - 6
        iconSize: Metrics.panelIcon
        background: Rectangle {
            radius: Math.min(width, height) / 2
            color: headerButton.down || headerButton.hovered ? Qt.alpha(Theme.tokens.text, 0.12) : "transparent"
            border.width: headerButton.visualFocus ? 1 : 0
            border.color: Theme.tokens.accent
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.state } }
        }
    }
    component ActionPill: PentadButton {
        id: pill
        property bool primary: false
        property url glyph: ""
        controlHeight: Metrics.controlSmall
        leftPadding: 10
        rightPadding: 10
        contentItem: Item {
            implicitWidth: pillRow.implicitWidth
            implicitHeight: Metrics.controlSmall
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 6
                PentadIcon {
                    id: pillIcon
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pill.glyph.toString() !== ""
                    source: pill.glyph
                    pixelSize: Metrics.panelIcon
                    color: pillLabel.color
                }
                Text {
                    id: pillLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, pill.availableWidth - (pillIcon.visible ? pillIcon.width + pillRow.spacing : 0)))
                    text: pill.text
                    textFormat: Text.PlainText
                    color: pill.enabled ? Theme.tokens.text : Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: Metrics.textCaption
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }
        }
        // The primary action is one tonal step higher; accent never fills the capsule.
        background: Rectangle {
            radius: Math.min(width, height) / 2
            color: Qt.alpha(Theme.tokens.text, (pill.primary ? 0.06 : 0) + (pill.down ? 0.16 : pill.hovered ? 0.11 : 0.06))
            border.width: pill.visualFocus ? 1 : 0
            border.color: Theme.tokens.accent
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.state } }
        }
    }

    ContinuousSurface {
        id: card
        objectName: "notification-card-surface"
        readonly property real swipeX: swipe.active ? Math.max(0, swipe.activeTranslation.x) : 0
        // Set once a swipe is released past the threshold: the card keeps flying out, then dismisses.
        property bool leaving: false
        x: card.leaving ? card.width + 24 : card.swipeX
        width: root.width
        height: content.height + root.pad * 2
        opacity: 1 - Math.min(card.leaving ? 1 : 0.8, Math.max(0, card.x) / Math.max(1, card.width))
        extent: Metrics.radiusCard
        castsShadow: root.popup
        fill: root.clickable || swipe.active ? Theme.tokens.surfaceOverlay
            : root.critical ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.error, 0.07))
            : Theme.tokens.surfaceRaised
        edge: root.critical ? Qt.alpha(Theme.tokens.error, 0.5)
            : root.activeFocus && !replyField.activeFocus ? Theme.tokens.accent
            : "transparent"
        Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.state } }
        onXChanged: if (card.leaving && card.x >= card.width + 24) root.dismiss()
        Behavior on x { enabled: !swipe.active && !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

        HoverHandler {
            id: hover
            cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        // Below the content, so buttons keep their own clicks.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.MiddleButton) root.dismiss();
                else root.activate();
            }
        }
        // Popups swipe away to the right, toward the screen edge they arrived from.
        // activeTranslation is already reset when active turns false, so the release reads the last
        // offset seen during the drag. A fast flick dismisses before the distance threshold; its speed
        // (px/s, smoothed) is measured on the wall clock because centroid.velocity is unreliable.
        DragHandler {
            id: swipe
            property real lastX: 0
            property real lastVelocity: 0
            property real lastTime: 0
            enabled: root.popup && !card.leaving
            target: null
            yAxis.enabled: false
            onActiveTranslationChanged: {
                if (!active) return;
                const now = Date.now(), dt = Math.max(1, now - lastTime);
                lastVelocity = 0.5 * lastVelocity + 0.5 * (activeTranslation.x - lastX) * 1000 / dt;
                lastX = activeTranslation.x;
                lastTime = now;
            }
            onActiveChanged: {
                if (active) { lastX = 0; lastVelocity = 0; lastTime = Date.now(); return; }
                if (lastX >= card.width * 0.35 || (lastX > 24 && lastVelocity > 900)) card.leaving = true;
            }
        }

        Column {
            id: content
            x: root.pad
            y: root.pad
            width: card.width - root.pad * 2
            spacing: 8

            // The app icon holds the left column; the app name, headline and detail stack beside it.
            Item {
                id: lead
                width: content.width
                height: Math.max(root.iconSize, bodyRow.y + bodyRow.height)

                // A symbolic fallback sits in a tonal circle, so every card keeps a face.
                Item {
                    id: appIconBox
                    width: root.iconSize
                    height: root.iconSize
                    Rectangle {
                        anchors.fill: parent
                        radius: Math.min(width, height) / 2
                        visible: root.appIconSource === ""
                        color: root.critical ? Qt.alpha(Theme.tokens.error, 0.14) : Qt.alpha(Theme.tokens.text, 0.08)
                    }
                    PentadIcon {
                        id: appIcon
                        anchors.centerIn: parent
                        pixelSize: root.appIconSource !== "" ? root.iconSize : Metrics.exposedIcon
                        symbolic: root.appIconSource === ""
                        color: root.critical ? Theme.tokens.error : Theme.tokens.textMuted
                        source: root.appIconSource !== "" ? root.appIconSource
                            : Qt.resolvedUrl("../../assets/icons/material/notifications/notifications-symbolic.svg")
                        accessibleName: root.appName
                    }
                }

                // One header line: app name, then time, repeat count and unread dot. The meta gives
                // way to the hover buttons.
                Item {
                    id: header
                    x: root.indent
                    width: content.width - root.indent
                    height: root.band

                    PentadText {
                        id: appLabel
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, header.width - Math.max(meta.width, controls.width) - 8)
                        text: root.appName
                        textFormat: Text.PlainText
                        role: "caption"
                        color: root.critical ? Theme.tokens.error : Theme.tokens.textMuted
                        font.weight: Font.Medium
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                    Row {
                        id: meta
                        anchors.right: parent.right
                        height: root.band
                        spacing: 6
                        opacity: root.engaged ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state } }
                        PentadText {
                            id: timeLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: Policy.formatNotificationTime(root.record.receivedAt, root.now, root.timeLabels)
                            textFormat: Text.PlainText
                            role: "caption"
                            color: Theme.tokens.textMuted
                            wrapMode: Text.NoWrap
                            Accessible.name: new Date(root.record.receivedAt).toLocaleString(Qt.locale(), Locale.ShortFormat)
                        }
                        // The same notification sent again folds into this card and counts here.
                        Rectangle {
                            id: repeatChip
                            objectName: "notification-repeat-chip"
                            anchors.verticalCenter: parent.verticalCenter
                            width: repeatLabel.implicitWidth + 12
                            height: 18
                            radius: Math.min(width, height) / 2
                            visible: root.record.repeat > 1
                            color: Qt.alpha(Theme.tokens.text, 0.08)
                            Accessible.role: Accessible.StaticText
                            Accessible.name: root.services.text("Повторів: ", "Repeats: ") + root.record.repeat
                            PentadText {
                                id: repeatLabel
                                anchors.centerIn: parent
                                text: root.record.repeat
                                textFormat: Text.PlainText
                                role: "caption"
                                color: Theme.tokens.text
                                font.weight: Font.Medium
                                wrapMode: Text.NoWrap
                            }
                        }
                        // Every popup is unread, so only the center marks it.
                        Rectangle {
                            id: unreadDot
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: Math.min(width, height) / 2
                            visible: !root.popup && !root.record.read
                            color: root.critical ? Theme.tokens.error : Theme.tokens.accent
                        }
                    }
                    Row {
                        id: controls
                        anchors.right: parent.right
                        height: root.band
                        spacing: 2
                        opacity: root.engaged ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state } }
                        HeaderButton {
                            id: expandButton
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.expanded || headlineLabel.truncated || detailLabel.truncated
                            chevron: root.expanded ? "up" : "down"
                            accessibleName: root.expanded ? root.services.text("Згорнути", "Collapse")
                                : root.services.text("Розгорнути", "Expand")
                            onClicked: root.toggleExpanded()
                        }
                        HeaderButton {
                            id: clearButton
                            anchors.verticalCenter: parent.verticalCenter
                            iconSource: Qt.resolvedUrl("../../assets/icons/material/notifications/close-symbolic.svg")
                            accessibleName: root.services.text("Відхилити сповіщення", "Dismiss notification")
                            onClicked: root.dismiss()
                        }
                    }
                }

                // The headline leads in full text colour; a picture the app sent becomes a thumbnail beside it.
                Item {
                    id: bodyRow
                    x: root.indent
                    y: header.height
                    width: content.width - root.indent
                    height: Math.max(textStack.height, thumbnail.visible ? thumbnail.height : 0)
                    Column {
                        id: textStack
                        width: Math.max(0, bodyRow.width - (thumbnail.visible ? thumbnail.width + 8 : 0))
                        spacing: 2
                        PentadText {
                            id: headlineLabel
                            width: textStack.width
                            text: root.message.headline
                            textFormat: Text.PlainText
                            color: Theme.tokens.text
                            font.weight: Font.DemiBold
                            lineHeight: 1.2
                            wrapMode: Text.Wrap
                            maximumLineCount: root.expanded ? 4 : 2
                            elide: Text.ElideRight
                        }
                        PentadText {
                            id: detailLabel
                            width: textStack.width
                            visible: text !== ""
                            text: root.message.detail
                            textFormat: Text.PlainText
                            color: Qt.alpha(Theme.tokens.text, 0.78)
                            lineHeight: 1.2
                            wrapMode: Text.Wrap
                            maximumLineCount: root.expanded ? 12 : root.popup ? 3 : 2
                            elide: Text.ElideRight
                        }
                    }
                    ContinuousSurface {
                        id: thumbnail
                        anchors.right: parent.right
                        width: root.thumbSize
                        height: root.thumbSize
                        visible: root.hasImage
                        extent: Metrics.radiusSmall
                        fill: Qt.alpha(Theme.tokens.text, 0.06)
                        Image {
                            id: thumbImage
                            anchors.fill: parent
                            source: root.imageSource
                            sourceSize.width: root.thumbSize * 2
                            sourceSize.height: root.thumbSize * 2
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            Accessible.ignored: true
                        }
                    }
                }
            }

            Flow {
                id: actions
                objectName: "notification-actions-flow"
                readonly property int count: root.buttons.length + (root.openable ? 1 : 0)
                    + (root.canReply && !root.replyOpen ? 1 : 0)
                readonly property int perRow: Math.max(1, Math.min(3, count))
                readonly property real cell: Math.max(0, (width - (perRow - 1) * spacing) / perRow)
                width: content.width
                spacing: 8
                visible: count > 0
                Repeater {
                    model: root.buttons
                    delegate: ActionPill {
                        required property var modelData
                        required property int index
                        width: actions.cell
                        text: modelData.label
                        primary: index === 0
                        accessibleName: modelData.label
                        onClicked: root.services.notifications.invoke(root.record.key, modelData.key)
                    }
                }
                ActionPill {
                    objectName: "notification-open-action"
                    width: actions.cell
                    visible: root.openable
                    primary: true
                    glyph: Qt.resolvedUrl("../../assets/icons/material/stash/open-in-new-symbolic.svg")
                    text: root.services.text("Відкрити", "Open")
                    onClicked: root.activate()
                }
                ActionPill {
                    width: actions.cell
                    visible: root.canReply && !root.replyOpen
                    primary: root.buttons.length === 0 && !root.openable
                    glyph: Qt.resolvedUrl("../../assets/icons/material/notifications/reply-symbolic.svg")
                    text: root.services.text("Відповісти", "Reply")
                    onClicked: root.openReply()
                }
            }

            Item {
                width: content.width
                height: Metrics.controlMedium
                visible: root.replyOpen && root.canReply
                PentadTextField {
                    id: replyField
                    anchors.left: parent.left
                    anchors.right: sendButton.left
                    anchors.rightMargin: 8
                    height: parent.height
                    placeholderText: root.record.reply && root.record.reply.placeholder
                        ? root.record.reply.placeholder : root.services.text("Відповідь…", "Reply…")
                    accessibleName: root.services.text("Відповідь", "Reply")
                    maximumLength: 4096
                    onAccepted: root.sendReply()
                    Keys.onEscapePressed: { root.replyOpen = false; root.forceActiveFocus(); }
                }
                PentadButton {
                    id: sendButton
                    anchors.right: parent.right
                    width: Metrics.controlMedium
                    controlHeight: Metrics.controlMedium
                    iconSource: Qt.resolvedUrl("../../assets/icons/material/notifications/send-symbolic.svg")
                    iconSize: Metrics.panelIcon
                    ink: Theme.tokens.accent
                    requestedEnabled: replyField.text.trim() !== ""
                    accessibleName: root.services.text("Надіслати", "Send")
                    background: Rectangle {
                        radius: Math.min(width, height) / 2
                            color: Qt.alpha(Theme.tokens.text, sendButton.enabled ? (sendButton.hovered ? 0.16 : 0.11) : 0.06)
                        border.width: sendButton.visualFocus ? 1 : 0
                        border.color: Theme.tokens.accent
                    }
                    onClicked: root.sendReply()
                }
            }
        }
    }
}
