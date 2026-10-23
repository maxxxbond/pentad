import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

Button {
    id: root
    property bool selected: false
    property string subtitle: ""
    property url iconSource: ""
    // 1..4 draws signal bars at the trailing edge; -1 hides them.
    property int signalLevel: -1
    property string tooltipText: text
    property string accessibleName: text + (selected ? " · selected" : "")
    implicitHeight: subtitle || iconSource.toString() !== "" ? 64 : 52
    leftPadding: 14
    rightPadding: 14
    topPadding: 10
    bottomPadding: 10
    Accessible.name: accessibleName
    Accessible.role: Accessible.Button
    Accessible.description: selected ? "Selected" : ""
    ToolTip.visible: (hovered || activeFocus) && (truncatedLabel.truncated || tooltipText !== text)
    ToolTip.delay: 700
    ToolTip.text: tooltipText

    background: Rectangle {
        radius: 14
        color: root.down || root.hovered ? Theme.tokens.surfaceOverlay
            : root.selected ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.accent, 0.10)) : "transparent"
        opacity: root.enabled ? 1 : 0.58
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.tokens.accent
        Rectangle {
            visible: root.selected
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 24
            radius: 1.5
            color: Theme.tokens.accent
        }
    }
    contentItem: Item {
        PentadIcon {
            id: deviceIcon
            visible: root.iconSource.toString() !== ""
            anchors.verticalCenter: parent.verticalCenter
            source: root.iconSource
            pixelSize: Metrics.menuIcon
            color: root.selected ? Theme.tokens.accent : Theme.tokens.textMuted
            Accessible.ignored: true
        }
        Column {
            x: deviceIcon.visible ? 36 : 0
            width: Math.max(0, parent.width - x - 28 - (bars.visible ? bars.width + 8 : 0))
            anchors.verticalCenter: parent.verticalCenter
            PentadText {
                id: truncatedLabel
                width: parent.width
                text: root.text
                role: "body"
                solid: true
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                maximumLineCount: 2
            }
            PentadText {
                visible: root.subtitle !== ""
                width: parent.width
                text: root.subtitle
                role: "caption"
                solid: true
                color: Theme.tokens.textMuted
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }
        SignalBars {
            id: bars
            visible: root.signalLevel >= 0
            level: Math.max(0, root.signalLevel)
            activeColor: root.selected ? Theme.tokens.accent : Theme.tokens.text
            anchors.right: parent.right
            anchors.rightMargin: root.selected ? 28 : 0
            anchors.verticalCenter: parent.verticalCenter
        }
        PentadIcon {
            visible: root.selected
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl("../../assets/icons/material/screenshot/check-symbolic.svg")
            pixelSize: Metrics.textBody
            color: Theme.tokens.accent
            Accessible.ignored: true
        }
    }
}
