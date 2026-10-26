import QtQuick
import QtQuick.Controls.Basic
import qs.theme

// A capsule like PentadSegmented, with the chevron in a round well concentric with the right end.
ComboBox {
    id: control
    property string accessibleName: ""
    // Resting fill; on a raised card pass the next elevation step.
    property color fill: Theme.tokens.surfaceRaised
    readonly property bool mirroredLayout: LayoutMirroring.enabled
    readonly property bool engaged: control.hovered || control.visualFocus || control.popup.visible
    // The well sits `wellInset` inside the capsule, so its circle shares the capsule end's centre.
    readonly property real wellInset: 4
    readonly property real wellSize: height - 2 * wellInset

    implicitHeight: Metrics.controlMedium
    implicitWidth: 160
    leftPadding: mirroredLayout ? wellSize + wellInset + 8 : 16
    rightPadding: mirroredLayout ? 16 : wellSize + wellInset + 8
    font.family: Theme.tokens.fontFamily
    font.pixelSize: Metrics.textBody
    Accessible.name: accessibleName !== "" ? accessibleName : displayText
    Accessible.role: Accessible.ComboBox

    MenuPointerIntent {
        active: control.popup.visible
        anchorItem: control
        surfaceItem: control.popup.contentItem
        onDismissRequested: control.popup.close()
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            control.forceActiveFocus(Qt.MouseFocusReason);
            if (control.popup.visible) control.popup.close();
            else control.popup.open();
        }
    }

    contentItem: Text {
        text: control.displayText
        textFormat: Text.PlainText
        color: control.enabled ? Theme.tokens.text : Theme.tokens.textMuted
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Rectangle {
        x: control.mirroredLayout ? control.wellInset : control.width - width - control.wellInset
        y: control.wellInset
        width: control.wellSize
        height: control.wellSize
        radius: width / 2
        color: Qt.alpha(Theme.tokens.text, control.engaged ? 0.12 : 0.06)
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        PentadChevron {
            anchors.centerIn: parent
            // The glyph's ink sits half a unit past the centre along its point; pull it back so the
            // turned chevron is optically centred in the well.
            anchors.verticalCenterOffset: (control.popup.visible ? 0.5 : -0.5) * pixelSize / 24
            direction: control.popup.visible ? "up" : "down"
            pixelSize: Metrics.chevronIcon
            color: control.engaged ? Theme.tokens.text : Theme.tokens.textMuted
            engaged: control.engaged
        }
    }
    background: ContinuousSurface {
        fill: control.popup.visible || control.down || control.hovered ? Qt.tint(control.fill, Qt.alpha(Theme.tokens.text, 0.05)) : control.fill
        edge: control.visualFocus ? Theme.tokens.accent : "transparent"
        extent: height / 2
        opacity: control.enabled ? 1 : 0.55
        Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }

    popup: Popup {
        id: list
        y: control.height + 6
        width: Math.max(control.width, 180)
        x: control.mirroredLayout ? control.width - width : 0
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 320)
        padding: 6
        focus: true
        transformOrigin: Item.Top
        // A press on the box itself is left to its toggle; with CloseOnPressOutside it would close
        // the list and the same press would open it again.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        // Opens with a short fade and settle from the box; closes at once so a chosen value never
        // waits on an animation.
        enter: Transition {
            enabled: !Theme.tokens.reducedMotion
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.short }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Motion.short; easing.type: Easing.OutCubic }
        }
        background: ContinuousSurface {
            fill: Theme.tokens.surfaceOverlay
            extent: Metrics.radiusPopover
            castsShadow: true
        }
        contentItem: ListView {
            id: options
            clip: true
            implicitHeight: contentHeight
            spacing: 2
            model: list.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            // The custom handle has no idle fade of its own, so the bar only exists when the list scrolls.
            ScrollBar.vertical: ScrollBar {
                policy: options.contentHeight > options.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                implicitWidth: 6
                contentItem: Rectangle { radius: Metrics.radiusTag; color: Qt.alpha(Theme.tokens.text, 0.24) }
            }
        }
    }

    delegate: ItemDelegate {
        id: row
        required property int index
        required property var modelData
        readonly property bool current: control.currentIndex === index
        width: ListView.view ? ListView.view.width : control.width
        height: Metrics.controlMedium
        leftPadding: 12
        rightPadding: 10
        text: {
            const entry = modelData;
            const role = control.textRole;
            return role ? String(entry[role]) : String(entry);
        }
        highlighted: control.highlightedIndex === index
        Accessible.name: text
        // Concentric with the list: the popover radius less its padding.
        background: ContinuousSurface {
            fill: row.highlighted || row.hovered ? Qt.alpha(Theme.tokens.text, row.current ? 0.12 : 0.07)
                : row.current ? Qt.alpha(Theme.tokens.text, 0.08) : "transparent"
            extent: Metrics.radiusPopover - 6
        }
        contentItem: Item {
            Text {
                anchors.left: parent.left
                anchors.right: check.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.text
                textFormat: Text.PlainText
                color: row.current || row.highlighted || row.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                font.family: Theme.tokens.fontFamily
                font.pixelSize: Metrics.textBody
                font.weight: row.current ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }
            PentadIcon {
                id: check
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: row.current
                source: Qt.resolvedUrl("../assets/icons/material/controls/check-symbolic.svg")
                pixelSize: Metrics.panelIcon + 2
                color: Theme.tokens.accent
                Accessible.ignored: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                control.currentIndex = row.index;
                control.activated(row.index);
                control.popup.close();
            }
        }
    }
}
