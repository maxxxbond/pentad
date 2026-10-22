pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/control-model.mjs" as Controls

// The editing bar above the grid: column count on the left, reset and done on the right.
// The parent sets width and height.
Item {
    id: bar
    required property var services
    required property bool editing
    required property int chosenColumns
    signal columnsRequested(int columns)
    signal resetRequested()
    signal doneRequested()

    objectName: "control-center-edit-bar"
    visible: opacity > 0
    opacity: bar.editing ? 1 : 0
    enabled: bar.editing
    clip: true
    Behavior on opacity { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic } }

    Rectangle {
        id: columnTrack
        objectName: "control-center-grid-columns"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: columnRow.width + 8
        height: Metrics.controlSmall + 4
        radius: height / 2
        color: Theme.tokens.surfaceRaised
        Accessible.role: Accessible.Grouping
        Accessible.name: bar.services.text("Колонок у сітці", "Grid columns")
        Rectangle {
            id: columnThumb
            readonly property int selectedIndex: Math.max(0, Controls.gridColumnChoices.indexOf(bar.chosenColumns))
            x: 4 + selectedIndex * (Metrics.controlSmall + 12)
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.controlSmall + 12
            height: Metrics.controlSmall
            radius: height / 2
            color: Theme.tokens.accent
            Behavior on x { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
        }
        Row {
            id: columnRow
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: Controls.gridColumnChoices
                delegate: Button {
                    id: columnButton
                    required property int modelData
                    objectName: "control-center-grid-columns-" + modelData
                    readonly property bool selected: bar.chosenColumns === modelData
                    width: Metrics.controlSmall + 12
                    height: Metrics.controlSmall
                    hoverEnabled: true
                    checkable: false
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: selected
                    Accessible.name: bar.services.text(modelData + " колонки", modelData + " columns")
                    onClicked: bar.columnsRequested(modelData)
                    background: Rectangle {
                        radius: height / 2
                        color: !columnButton.selected && columnButton.hovered ? Theme.tokens.surfaceOverlay : "transparent"
                        border.width: columnButton.visualFocus ? 1 : 0
                        border.color: Theme.tokens.accent
                        Behavior on color { ColorAnimation { duration: Motion.state } }
                    }
                    contentItem: Text {
                        text: String(columnButton.modelData)
                        color: columnButton.selected ? Theme.tokens.onAccent : Theme.tokens.text
                        font.family: Theme.tokens.fontFamily
                        font.pixelSize: Metrics.textCaption
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        Behavior on color { ColorAnimation { duration: Motion.state } }
                    }
                }
            }
        }
    }
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        QuickSettingsEditChip {
            objectName: "control-center-edit-reset"
            text: bar.services.text("Скинути", "Reset")
            onClicked: bar.resetRequested()
        }
        QuickSettingsEditChip {
            objectName: "control-center-edit-done"
            text: bar.services.text("Готово", "Done")
            iconSource: Qt.resolvedUrl("../../assets/icons/material/controls/check-symbolic.svg")
            prominent: true
            onClicked: bar.doneRequested()
        }
    }
}
