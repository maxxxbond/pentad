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
    // The look chosen in Settings → Notifications; every look keeps the same behaviour.
    readonly property string variant: {
        const style = services.notifications ? String(services.notifications.cardStyle || "") : "";
        return Policy.notificationStyles.indexOf(style) >= 0 ? style : "toast";
    }
    readonly property bool bold: variant === "bold"
    readonly property bool source: variant === "source"
    // The one-line look opens to the full card while the pointer or focus is on it.
    readonly property bool compact: variant === "line" && !engaged && !expanded && !replyOpen
    // Popups and the source look keep the close button in view; other center cards show it on hover or focus.
    readonly property bool showControls: popup || source || engaged
    readonly property int pad: bold ? 20 : 12
    // The app icon column; the source look has none and puts a small icon in its header line instead.
    readonly property int iconSize: bold ? 44 : variant === "line" ? 32 : source ? 0 : 36
    readonly property int indent: iconSize > 0 ? iconSize + (bold ? 16 : 12) : 0
    // Height of the first line (title or source header), matched to the buttons beside it.
    readonly property int band: variant === "line" ? iconSize : bold ? Metrics.controlSmall - 4 : Metrics.controlSmall - 6
    readonly property int thumbSize: 40
    readonly property string appName: record.app || services.text("Невідома програма", "Unknown app")
    readonly property var message: hidden
        ? ({ headline: record.title || appName, detail: services.text("Вміст приховано", "Content hidden") })
        : Policy.notificationText(record)
    readonly property string appIconSource: {
        const icon = String(record.icon || "");
        if (!icon) return "";
        if (Quickshell.hasThemeIcon(icon)) return Quickshell.iconPath(icon, true);
        if (icon.startsWith("file://")) return icon;
        if (icon.startsWith("/")) return "file://" + icon;
        return "";
    }
    readonly property url glyphSource: Qt.resolvedUrl("../../assets/icons/material/notifications/notifications-symbolic.svg")
    readonly property string imageSource: {
        const image = String(record.image || "");
        return image.startsWith("/") ? "file://" + image : image;
    }
    readonly property bool hasImage: imageSource !== "" && thumbImage.status !== Image.Error
    // From the data, never from child visibility: a card built inside a hidden popup window would
    // otherwise read its children as invisible and keep the body hidden after the window shows.
    readonly property bool hasBody: message.detail !== "" || hasImage
    readonly property bool hasActions: buttons.length > 0 || (canReply && !replyOpen)
    readonly property var timeLabels: ({
        now: services.text("щойно", "now"), minutes: services.text("хв", "min"),
        hours: services.text("год", "h"), yesterday: services.text("Вчора", "Yesterday"),
        clock: function(date) { return Qt.formatTime(date, "HH:mm"); },
        date: function(date) { return Qt.formatDate(date, "d MMM"); }
    })
    readonly property string timeText: Policy.formatNotificationTime(record.receivedAt, now, timeLabels)
    // The source look lists app buttons and Reply as one row of equal actions.
    readonly property var splitEntries: buttons.map(function(button, index) {
        return { key: button.key, label: button.label, primary: index === 0, reply: false };
    }).concat(canReply && !replyOpen
        ? [{ key: "", label: services.text("Відповісти", "Reply"), primary: buttons.length === 0, reply: true }] : [])
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
    onReplyRequestedChanged: consumeReplyRequest()
    onCanReplyChanged: if (!canReply) replyOpen = false
    Component.onCompleted: consumeReplyRequest()

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
        // Quiet actions are text until hovered: the large look and the source look's action row.
        property bool quiet: false
        property url glyph: ""
        controlHeight: Metrics.controlSmall
        leftPadding: 10
        rightPadding: 10
        contentItem: Item {
            // From the label's natural width, so a pill sized to its content never loops through availableWidth.
            implicitWidth: (pill.glyph.toString() !== "" ? pillIcon.width + pillRow.spacing : 0) + pillLabel.implicitWidth
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
                    width: Math.min(implicitWidth, Math.max(0, pill.availableWidth - (pill.glyph.toString() !== "" ? pillIcon.width + pillRow.spacing : 0)))
                    text: pill.text
                    textFormat: Text.PlainText
                    color: pill.enabled && (pill.primary || pill.hovered) ? Theme.tokens.text : Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: pill.quiet ? Metrics.textBody : Metrics.textCaption
                    font.weight: pill.quiet ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                }
            }
        }
        // The primary action is a tonal capsule, the rest are quiet text until hovered; accent never fills.
        background: Rectangle {
            radius: Math.min(width, height) / 2
            color: Qt.alpha(Theme.tokens.text, pill.primary && !pill.quiet ? (pill.down ? 0.2 : pill.hovered ? 0.16 : 0.11)
                : (pill.down ? 0.12 : pill.hovered ? 0.07 : 0))
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
        height: content.height + root.pad * 2 + (splitActions.visible ? splitActions.height : 0)
        opacity: 1 - Math.min(card.leaving ? 1 : 0.8, Math.max(0, card.x) / Math.max(1, card.width))
        extent: root.compact ? card.height / 2 : root.bold || root.source ? Metrics.radiusLarge : Metrics.radiusCard
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
            spacing: root.bold ? 14 : 12

            // The app icon holds the left column; the title, detail and actions line up beside it.
            Item {
                id: lead
                // Room for the title on its first line, left of the repeat count and the buttons.
                readonly property real titleRoom: Math.max(0, lead.width - root.indent
                    - (root.source ? 0 : trailing.width + (root.record.repeat > 1 ? repeatChip.width + 6 : 0) + 8))
                width: content.width
                height: Math.max(root.iconSize, root.compact ? root.band
                    : root.hasBody ? bodyRow.y + bodyRow.height : headlineLabel.y + headlineLabel.height)

                // A symbolic fallback sits in a tonal shape, so every card keeps a face.
                Item {
                    id: appIconBox
                    width: root.iconSize
                    height: root.iconSize
                    visible: root.iconSize > 0
                    Rectangle {
                        anchors.fill: parent
                        radius: root.variant === "toast" ? Metrics.radiusMedium : Math.min(width, height) / 2
                        visible: root.appIconSource === ""
                        color: root.critical ? Qt.alpha(Theme.tokens.error, 0.14) : Qt.alpha(Theme.tokens.text, 0.08)
                    }
                    PentadIcon {
                        anchors.centerIn: parent
                        pixelSize: root.appIconSource !== "" ? root.iconSize
                            : root.variant === "line" ? Metrics.exposedIcon : Metrics.statusIcon
                        symbolic: root.appIconSource === ""
                        color: root.critical ? Theme.tokens.error : Theme.tokens.text
                        source: root.appIconSource !== "" ? root.appIconSource : root.glyphSource
                        accessibleName: root.appName
                    }
                }

                // The source look names the app and the time above the title.
                Row {
                    id: sourceLine
                    objectName: "notification-source-line"
                    height: root.band
                    spacing: 6
                    visible: root.source
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Metrics.panelIcon
                        height: Metrics.panelIcon
                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusTag
                            visible: root.appIconSource === ""
                            color: root.critical ? Qt.alpha(Theme.tokens.error, 0.2) : Qt.alpha(Theme.tokens.text, 0.1)
                        }
                        PentadIcon {
                            anchors.centerIn: parent
                            pixelSize: root.appIconSource !== "" ? Metrics.panelIcon : 12
                            symbolic: root.appIconSource === ""
                            color: root.critical ? Theme.tokens.error : Theme.tokens.text
                            source: root.appIconSource !== "" ? root.appIconSource : root.glyphSource
                            accessibleName: root.appName
                        }
                    }
                    PentadText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, Math.max(0, lead.width - Metrics.panelIcon - trailing.width
                            - (root.record.repeat > 1 ? repeatChip.width + 6 : 0) - (root.popup || root.record.read ? 0 : 12) - 20))
                        text: root.appName + " · " + root.timeText
                        textFormat: Text.PlainText
                        role: "caption"
                        color: Theme.tokens.textMuted
                        font.weight: Font.Medium
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: Math.min(width, height) / 2
                        visible: !root.popup && !root.record.read
                        color: root.critical ? Theme.tokens.error : Theme.tokens.accent
                    }
                }

                FontMetrics {
                    id: headlineMetrics
                    font: headlineLabel.font
                }
                // The title's natural width, measured apart from the label so sizing it never loops through wrapping.
                TextMetrics {
                    id: headlineNatural
                    font: headlineLabel.font
                    text: root.message.headline
                }
                // The title's first line centres on the buttons beside it; the source look puts it under its header.
                PentadText {
                    id: headlineLabel
                    objectName: "notification-headline"
                    x: root.indent
                    y: root.source ? root.band + 4 : Math.round((root.band - headlineMetrics.height) / 2)
                    // On one line the title keeps its natural width while the detail still gets a readable share.
                    width: root.compact && root.message.detail !== ""
                        ? Math.min(Math.ceil(headlineNatural.advanceWidth), Math.max(lead.titleRoom * 0.5, lead.titleRoom - 96))
                        : root.source ? lead.width : lead.titleRoom
                    text: root.message.headline
                    textFormat: Text.PlainText
                    role: root.bold ? "section" : "body"
                    color: root.critical ? Theme.tokens.error : Theme.tokens.text
                    font.weight: Font.DemiBold
                    lineHeight: 1.2
                    wrapMode: root.compact ? Text.NoWrap : Text.Wrap
                    maximumLineCount: root.compact ? 1 : root.expanded ? 4 : 2
                    elide: Text.ElideRight
                }
                // The one-line look continues the title with the detail on the same line.
                PentadText {
                    id: inlineDetail
                    objectName: "notification-inline-detail"
                    x: headlineLabel.x + headlineLabel.width + 8
                    y: headlineLabel.y
                    width: Math.max(0, lead.titleRoom - headlineLabel.width - 8)
                    visible: root.compact && root.message.detail !== ""
                    text: root.message.detail
                    textFormat: Text.PlainText
                    color: Theme.tokens.textMuted
                    lineHeight: 1.2
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
                // The same notification sent again folds into this card and counts here.
                Rectangle {
                    id: repeatChip
                    objectName: "notification-repeat-chip"
                    anchors.right: trailing.left
                    anchors.rightMargin: 6
                    y: Math.round((root.band - height) / 2)
                    width: Math.max(height, repeatLabel.implicitWidth + 12)
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
                        color: Theme.tokens.textMuted
                        font.weight: Font.Medium
                        wrapMode: Text.NoWrap
                    }
                }
                // The center shows time and the unread dot at rest; popups and the source look keep the close
                // button in view and reserve the expand slot, so the title never rewraps on hover.
                Item {
                    id: trailing
                    anchors.right: parent.right
                    width: root.popup || root.source ? (root.compact ? clearButton.width : clearButton.width * 2 + controls.spacing)
                        : Math.max(meta.width, controls.width)
                    height: root.band
                    Row {
                        id: meta
                        anchors.right: parent.right
                        height: root.band
                        spacing: 6
                        opacity: root.showControls ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state } }
                        PentadText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.timeText
                            textFormat: Text.PlainText
                            role: "caption"
                            color: Theme.tokens.textMuted
                            wrapMode: Text.NoWrap
                            Accessible.name: new Date(root.record.receivedAt).toLocaleString(Qt.locale(), Locale.ShortFormat)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: Math.min(width, height) / 2
                            visible: !root.record.read
                            color: root.critical ? Theme.tokens.error : Theme.tokens.accent
                        }
                    }
                    Row {
                        id: controls
                        anchors.right: parent.right
                        height: root.band
                        spacing: 2
                        opacity: root.showControls ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state } }
                        HeaderButton {
                            id: expandButton
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.engaged && (root.expanded || headlineLabel.truncated || detailLabel.truncated)
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

                // The detail sits under the title; a picture the app sent becomes a thumbnail beside it.
                Item {
                    id: bodyRow
                    x: root.indent
                    y: headlineLabel.y + headlineLabel.height + (root.bold ? 4 : 2)
                    width: lead.width - root.indent
                    height: Math.max(root.message.detail !== "" ? detailLabel.height : 0, root.hasImage ? thumbnail.height : 0)
                    visible: root.hasBody && !root.compact
                    PentadText {
                        id: detailLabel
                        objectName: "notification-detail"
                        width: Math.max(0, bodyRow.width - (root.hasImage ? thumbnail.width + 8 : 0))
                        visible: text !== ""
                        text: root.message.detail
                        textFormat: Text.PlainText
                        role: root.variant === "toast" ? "caption" : "body"
                        color: root.source ? Qt.alpha(Theme.tokens.text, 0.72) : Theme.tokens.textMuted
                        lineHeight: 1.2
                        wrapMode: Text.Wrap
                        maximumLineCount: root.expanded ? 12 : 2
                        elide: Text.ElideRight
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

            // Actions keep their own width and line up with the text; the large look's quiet ones line up
            // their labels, not their hover capsules.
            Flow {
                id: actions
                objectName: "notification-actions-flow"
                x: root.indent - (root.bold ? 10 : 0)
                width: content.width - x
                spacing: root.bold ? 4 : 8
                visible: root.hasActions && !root.compact && !root.source
                Repeater {
                    model: root.buttons
                    delegate: ActionPill {
                        required property var modelData
                        required property int index
                        width: Math.min(implicitWidth, actions.width)
                        text: modelData.label
                        primary: index === 0
                        quiet: root.bold
                        accessibleName: modelData.label
                        onClicked: root.services.notifications.invoke(root.record.key, modelData.key)
                    }
                }
                ActionPill {
                    width: Math.min(implicitWidth, actions.width)
                    visible: root.canReply && !root.replyOpen
                    primary: root.buttons.length === 0
                    quiet: root.bold
                    glyph: Qt.resolvedUrl("../../assets/icons/material/notifications/reply-symbolic.svg")
                    text: root.services.text("Відповісти", "Reply")
                    onClicked: root.openReply()
                }
            }

            Item {
                x: root.indent
                width: content.width - root.indent
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

        // The source look ends in a row of equal actions under a separator, edge to edge.
        Item {
            id: splitActions
            objectName: "notification-split-actions"
            y: content.y + content.height + root.pad
            width: card.width
            height: Metrics.controlMedium + 5
            visible: root.source && root.hasActions
            Rectangle {
                width: parent.width
                height: 1
                color: Qt.alpha(Theme.tokens.text, 0.08)
            }
            Row {
                id: splitRow
                y: 1
                width: parent.width
                height: parent.height - 1
                Repeater {
                    model: root.splitEntries
                    delegate: Item {
                        id: splitCell
                        required property var modelData
                        required property int index
                        width: splitRow.width / Math.max(1, root.splitEntries.length)
                        height: splitRow.height
                        Rectangle {
                            width: 1
                            height: parent.height
                            visible: splitCell.index > 0
                            color: Qt.alpha(Theme.tokens.text, 0.08)
                        }
                        ActionPill {
                            anchors.fill: parent
                            anchors.margins: 4
                            text: splitCell.modelData.label
                            primary: splitCell.modelData.primary
                            quiet: true
                            accessibleName: splitCell.modelData.label
                            onClicked: splitCell.modelData.reply ? root.openReply()
                                : root.services.notifications.invoke(root.record.key, splitCell.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
