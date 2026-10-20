pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/notifications.mjs" as Policy

Item {
    id: root
    required property var services
    required property string outputId
    property bool presented: false
    readonly property var notificationState: services.notifications.state
    readonly property var history: notificationState.history || []
    readonly property var groups: Policy.groupNotifications(history)
    property var renderedGroups: groups
    property var expandedGroups: ({})
    property var expandedCards: ({})
    property string scrollAnchorKey: ""
    property real scrollAnchorOffset: 0
    property int scrollAnchorIndex: 0
    property bool scrollAnchorAtTop: true
    property real now: Date.now()
    readonly property string replyRequest: services.notifications.replyRequest || ""
    implicitHeight: 280
    // Header, optional service line and the list's own content; the panel uses it to avoid empty space.
    readonly property real preferredHeight: 28 + 8 + (statusLine.visible ? statusLine.height + 8 : 0)
        + Math.max(Metrics.controlLarge * 2, list.contentHeight)
    clip: true

    // A popup's reply lands here: unfold its group so the card can open the field.
    function revealReplyTarget() {
        if (!replyRequest) return;
        const index = groups.findIndex(function(group) {
            return group.records.some(function(record) { return record.key === root.replyRequest; });
        });
        if (index < 0) return;
        if (groups[index].records.length > 1) setGroupExpanded(groups[index].key, true);
        Qt.callLater(function() { list.positionViewAtIndex(index, ListView.Contain); });
    }
    onReplyRequestChanged: revealReplyTarget()
    Timer {
        interval: 30000
        repeat: true
        triggeredOnStart: true
        running: root.presented
        onTriggered: root.now = Date.now()
    }

    function setGroupExpanded(key, expanded) {
        const next = Object.assign({}, expandedGroups);
        next[key] = expanded;
        expandedGroups = next;
    }
    function setCardExpanded(key, expanded) {
        const next = Object.assign({}, expandedCards);
        next[key] = expanded;
        expandedCards = next;
    }
    function updateRenderedGroups() {
        const previous = renderedGroups || [];
        if (previous.length > 0 && list.count > 0) {
            scrollAnchorAtTop = list.contentY <= list.originY + 1;
            let index = scrollAnchorAtTop ? 0 : list.indexAt(1, list.contentY + 1);
            if (index < 0) {
                for (let candidate = 0; candidate < list.count; ++candidate) {
                    const item = list.itemAtIndex(candidate);
                    if (item && item.y + item.height > list.contentY) { index = candidate; break; }
                }
            }
            if (index < 0) index = 0;
            scrollAnchorIndex = index;
            const item = list.itemAtIndex(index);
            scrollAnchorKey = previous[index] ? previous[index].key : "";
            scrollAnchorOffset = item ? list.contentY - item.y : 0;
        } else {
            scrollAnchorAtTop = true;
            scrollAnchorIndex = 0;
            scrollAnchorKey = "";
            scrollAnchorOffset = 0;
        }
        renderedGroups = groups;
        restoreScroll.restart();
    }
    onGroupsChanged: updateRenderedGroups()
    onPresentedChanged: {
        services.notifications.setCenterOpen(outputId, presented);
        services.notifications.setCenterPresented(outputId, presented);
    }
    onOutputIdChanged: {
        services.notifications.setCenterOpen(outputId, presented);
        services.notifications.setCenterPresented(outputId, presented);
    }
    Component.onCompleted: {
        services.notifications.setCenterOpen(outputId, presented);
        services.notifications.setCenterPresented(outputId, presented);
        revealReplyTarget();
    }
    Component.onDestruction: {
        services.notifications.setCenterOpen(outputId, false);
        services.notifications.setCenterPresented(outputId, false);
    }

    Timer {
        id: restoreScroll
        interval: 50
        repeat: false
        onTriggered: {
            if (root.renderedGroups.length === 0) return;
            let index = root.scrollAnchorKey
                ? root.renderedGroups.findIndex(function(group) { return group.key === root.scrollAnchorKey; })
                : -1;
            if (index < 0) index = Math.min(root.scrollAnchorIndex, root.renderedGroups.length - 1);
            if (root.scrollAnchorAtTop) index = 0;
            list.positionViewAtIndex(index, ListView.Beginning);
            Qt.callLater(function() {
                const item = list.itemAtIndex(index);
                if (!item) return;
                const offset = root.scrollAnchorAtTop ? 0 : root.scrollAnchorOffset;
                const targetY = item.y + offset;
                list.contentY = Math.max(list.originY,
                    Math.min(targetY, list.originY + list.contentHeight - list.height));
            });
        }
    }

    Column {
        anchors.fill: parent
        spacing: 8
        Item {
            width: parent.width
            height: 28
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                PentadText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.services.text("Сповіщення", "Notifications")
                    role: "section"
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                }
                Rectangle {
                    id: unreadBadge
                    // Only unread items earn a badge; a resting zero beside visible history reads as a contradiction.
                    readonly property bool shown: root.notificationState.unread > 0
                    width: shown ? Math.max(height, count.implicitWidth + 12) : 0
                    height: 20
                    radius: Math.min(width, height) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: width > 0
                    opacity: shown ? 1 : 0
                    clip: true
                    color: Qt.alpha(Theme.tokens.accent, 0.22)
                    Behavior on width { NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: Motion.state } }
                    PentadText {
                        id: count
                        anchors.centerIn: parent
                        text: root.notificationState.unread
                        role: "caption"
                        font.weight: Font.DemiBold
                        color: Theme.tokens.text
                        Accessible.name: root.services.text("Непрочитані: ", "Unread: ") + text
                    }
                }
            }
            PentadButton {
                id: clearAll
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.notificationState.history.length > 0
                text: root.services.text("Очистити все", "Clear all")
                controlHeight: 26
                leftPadding: 10
                rightPadding: 10
                requestedEnabled: root.notificationState.history.length > 0
                contentItem: Row {
                    spacing: 6
                    PentadIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl("../../assets/icons/material/notifications/clear-all-symbolic.svg")
                        pixelSize: Metrics.panelIcon
                        color: clearAllLabel.color
                        Accessible.ignored: true
                    }
                    Text {
                        id: clearAllLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: clearAll.text
                        textFormat: Text.PlainText
                        color: clearAll.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                        font.family: Theme.tokens.fontFamily
                        font.pixelSize: Metrics.textCaption
                        font.weight: Font.Medium
                    }
                }
                background: Rectangle {
                    radius: Math.min(width, height) / 2
                    color: clearAll.down || clearAll.hovered ? Qt.alpha(Theme.tokens.text, 0.10) : Qt.alpha(Theme.tokens.text, 0.05)
                    border.width: clearAll.activeFocus ? 1 : 0
                    border.color: Theme.tokens.accent
                }
                onClicked: root.services.notifications.clearAll()
            }
        }

        PentadText {
            id: statusLine
            width: parent.width
            visible: root.notificationState.status !== "available"
            text: root.notificationState.status === "another-server"
                ? root.services.text("Працює інша служба сповіщень · показано збережену історію", "Another notification service is active · showing saved history")
                : root.services.text("Служба сповіщень недоступна · показано збережену історію", "Notification service unavailable · showing saved history")
            color: Theme.tokens.textMuted
            role: "caption"
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "notification-center-list"
            width: parent.width
            height: Math.max(0, parent.height - y)
            clip: true
            spacing: 8
            model: root.renderedGroups
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: group
                required property var modelData
                readonly property bool expanded: root.expandedGroups[modelData.key] === true
                readonly property bool stacked: modelData.records.length > 1
                readonly property int peeks: stacked && !expanded ? Math.min(2, modelData.records.length - 1) : 0
                readonly property Item leadCard: cards.count > 0 ? cards.itemAt(0) : null
                width: list.width
                height: groupColumn.height + peeks * 5
                Accessible.role: Accessible.Grouping
                Accessible.name: modelData.app

                // Collapsed stacks peek out under the newest card, like sheets in a pile.
                Repeater {
                    model: group.peeks
                    delegate: ContinuousSurface {
                        required property int index
                        readonly property int depth: index + 1
                        x: depth * 8
                        y: (group.leadCard ? group.leadCard.y + groupColumn.y : 0) + depth * 5
                        z: -depth
                        width: Math.max(0, group.width - depth * 16)
                        height: group.leadCard ? group.leadCard.height : 0
                        extent: Metrics.radiusCard
                        fill: Theme.tokens.surfaceRaised
                        opacity: depth === 1 ? 0.7 : 0.4
                    }
                }
                MouseArea {
                    // The visible sheet edges unfold the stack.
                    x: 0
                    y: group.height - group.peeks * 5
                    width: group.width
                    height: group.peeks * 5
                    enabled: group.peeks > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setGroupExpanded(group.modelData.key, true)
                }

                Column {
                    id: groupColumn
                    width: parent.width
                    spacing: 6
                    Item {
                        width: parent.width
                        height: group.stacked ? 26 : 0
                        visible: group.stacked
                        PentadButton {
                            id: groupHeading
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, Math.max(0, parent.width - clearGroup.width - 6))
                            controlHeight: 26
                            leftPadding: 8
                            rightPadding: 8
                            text: group.modelData.app
                            accessibleName: group.modelData.app + " · " + group.modelData.records.length
                                + root.services.text(" сповіщень", " notifications")
                                + (group.expanded ? root.services.text(", згорнути", ", collapse") : root.services.text(", розгорнути", ", expand"))
                            contentItem: Row {
                                spacing: 6
                                Text {
                                    id: groupLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, Math.max(0, groupHeading.availableWidth - groupCount.width - groupChevron.width - 12))
                                    text: groupHeading.text
                                    textFormat: Text.PlainText
                                    color: Theme.tokens.text
                                    font.family: Theme.tokens.fontFamily
                                    font.pixelSize: Metrics.textCaption
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    id: groupCount
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(height, groupCountLabel.implicitWidth + 10)
                                    height: 18
                                    radius: Math.min(width, height) / 2
                                    color: group.modelData.unread ? Qt.alpha(Theme.tokens.accent, 0.22) : Qt.alpha(Theme.tokens.text, 0.08)
                                    PentadText {
                                        id: groupCountLabel
                                        anchors.centerIn: parent
                                        text: group.modelData.records.length
                                        role: "caption"
                                        font.weight: Font.Medium
                                        color: Theme.tokens.text
                                        Accessible.ignored: true
                                    }
                                }
                                PentadChevron {
                                    id: groupChevron
                                    anchors.verticalCenter: parent.verticalCenter
                                    direction: group.expanded ? "up" : "down"
                                    engaged: groupHeading.hovered || groupHeading.activeFocus
                                    pixelSize: Metrics.panelIcon
                                }
                            }
                            background: Rectangle {
                                radius: Math.min(width, height) / 2
                                color: groupHeading.down || groupHeading.hovered ? Qt.alpha(Theme.tokens.text, 0.08) : "transparent"
                                border.width: groupHeading.activeFocus ? 1 : 0
                                border.color: Theme.tokens.accent
                            }
                            onClicked: root.setGroupExpanded(group.modelData.key, !group.expanded)
                        }
                        PentadButton {
                            id: clearGroup
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            controlHeight: 26
                            iconSource: Qt.resolvedUrl("../../assets/icons/material/notifications/close-symbolic.svg")
                            iconSize: Metrics.panelIcon
                            accessibleName: root.services.text("Очистити сповіщення: ", "Clear ") + group.modelData.app
                            background: Rectangle {
                                radius: Math.min(width, height) / 2
                                color: clearGroup.down || clearGroup.hovered ? Qt.alpha(Theme.tokens.text, 0.10) : "transparent"
                                border.width: clearGroup.activeFocus ? 1 : 0
                                border.color: Theme.tokens.accent
                            }
                            onClicked: root.services.notifications.clearGroup(group.modelData.key)
                        }
                    }
                    Repeater {
                        id: cards
                        model: group.expanded ? group.modelData.records : group.modelData.records.slice(0, 1)
                        delegate: NotificationCard {
                            required property var modelData
                            services: root.services
                            record: modelData
                            outputId: root.outputId
                            now: root.now
                            expanded: root.expandedCards[modelData.key] === true
                            objectName: "notification-card-" + modelData.key
                            onExpandedChangedByUser: function(value) { root.setCardExpanded(modelData.key, value); }
                            onActivated: if (root.services.popups) root.services.popups.closeSurface("right", root.outputId)
                        }
                    }
                }
            }
            Column {
                // Centred in the reserved empty-state band, which the organizer never covers.
                x: (parent.width - width) / 2
                y: (Metrics.controlLarge * 2 - height) / 2
                width: Math.max(0, parent.width - 20)
                spacing: 6
                visible: root.groups.length === 0
                PentadIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: Qt.resolvedUrl("../../assets/icons/material/notifications/notifications-symbolic.svg")
                    pixelSize: Metrics.statusIcon
                    color: Qt.alpha(Theme.tokens.textMuted, 0.7)
                    Accessible.ignored: true
                }
                PentadText {
                    width: parent.width
                    text: root.notificationState.status === "available"
                        ? root.services.text("Немає сповіщень", "No notifications")
                        : root.services.text("Немає збережених сповіщень", "No saved notifications")
                    role: "caption"
                    color: Theme.tokens.textMuted
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
