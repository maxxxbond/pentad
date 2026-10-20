import QtQuick
import QtQuick.Controls.Basic
import qs.theme

ComboBox {
    id: control
    property string accessibleName: ""
    // Resting fill; on a raised card pass the next elevation step.
    property color fill: Theme.tokens.surfaceRaised
    readonly property bool mirroredLayout: LayoutMirroring.enabled

    implicitHeight: Metrics.controlMedium
    implicitWidth: 160
    leftPadding: 12
    rightPadding: 12 + Metrics.panelIcon + 8
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
    indicator: PentadChevron {
        x: control.mirroredLayout ? 12 : control.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        direction: control.popup.visible ? "up" : "down"
        pixelSize: Metrics.panelIcon
        engaged: control.hovered || control.activeFocus || control.popup.visible
    }
    background: ContinuousSurface {
        fill: control.popup.visible || control.down || control.hovered ? Qt.tint(control.fill, Qt.alpha(Theme.tokens.text, 0.05)) : control.fill
        edge: control.visualFocus ? Theme.tokens.accent : "transparent"
        extent: Metrics.radiusSmall
        opacity: control.enabled ? 1 : 0.55
        Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }

    popup: Popup {
        id: list
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 320)
        padding: 4
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        // Opens with a short fade; closes at once so a chosen value never waits on an animation.
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.short } }
        background: ContinuousSurface {
            fill: Theme.tokens.surfaceOverlay
            extent: Metrics.radiusMedium
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: list.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
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
        rightPadding: 12
        text: {
            const entry = modelData;
            const role = control.textRole;
            return role ? String(entry[role]) : String(entry);
        }
        highlighted: control.highlightedIndex === index
        Accessible.name: text
        background: ContinuousSurface {
            fill: row.highlighted || row.hovered ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
            extent: Metrics.radiusSmall
        }
        contentItem: Item {
            Text {
                anchors.left: parent.left
                anchors.right: check.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.text
                textFormat: Text.PlainText
                color: Theme.tokens.text
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
                pixelSize: Metrics.panelIcon
                color: Theme.tokens.accent
                Accessible.ignored: true
            }
        }

        MouseArea {
            anchors.fill: parent
            onPressed: {
                control.currentIndex = row.index;
                control.activated(row.index);
                control.popup.close();
            }
        }
    }
}
