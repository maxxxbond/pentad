pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// A capsule action used by the editing bar and the add tray: icon and label side by side.
Button {
    id: chip
    property url iconSource: ""
    property bool prominent: false
    implicitHeight: Metrics.controlSmall
    implicitWidth: chipRow.implicitWidth + 24
    hoverEnabled: true
    Accessible.name: text
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Motion.press; easing.type: Easing.OutCubic } }
    background: Rectangle {
        radius: height / 2
        color: chip.prominent ? (chip.hovered ? Qt.lighter(Theme.tokens.accent, 1.08) : Theme.tokens.accent)
            : chip.down || chip.hovered ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
        border.width: chip.visualFocus ? 1 : 0
        border.color: chip.prominent ? Theme.tokens.onAccent : Theme.tokens.accent
        opacity: chip.enabled ? 1 : 0.55
        Behavior on color { ColorAnimation { duration: Motion.state } }
    }
    contentItem: Item {
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            PentadIcon {
                visible: chip.iconSource.toString() !== ""
                anchors.verticalCenter: parent.verticalCenter
                source: chip.iconSource
                pixelSize: Metrics.panelIcon
                color: chip.prominent ? Theme.tokens.onAccent : Theme.tokens.text
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                color: chip.prominent ? Theme.tokens.onAccent : Theme.tokens.text
                font.family: Theme.tokens.fontFamily
                font.pixelSize: Metrics.textCaption
                font.weight: chip.prominent ? Font.DemiBold : Font.Normal
            }
        }
    }
}
