pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme

// The tray under the grid while editing: hidden controls that can be put back.
// The parent sets y, width and height.
Item {
    id: trayArea
    required property var services
    required property bool editing
    required property var hiddenTiles
    readonly property real trayImplicitHeight: tray.implicitHeight
    signal addRequested(string key)

    objectName: "control-center-edit-tray"
    visible: opacity > 0
    opacity: trayArea.editing ? 1 : 0
    enabled: trayArea.editing
    clip: true
    Behavior on opacity { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic } }
    Flow {
        id: tray
        width: parent.width
        spacing: 6
        PentadText {
            width: parent.width
            text: trayArea.hiddenTiles.length
                ? trayArea.services.text("Сховані — натисніть, щоб додати", "Hidden — tap to add")
                : trayArea.services.text("Усі елементи на місці. Перетягуйте, тягніть за куточок, щоб змінити розмір.",
                    "Everything is placed. Drag to move, pull the corner to resize.")
            role: "caption"
            color: Theme.tokens.textMuted
            wrapMode: Text.Wrap
        }
        Repeater {
            model: trayArea.hiddenTiles
            delegate: QuickSettingsEditChip {
                required property var modelData
                objectName: "control-center-edit-add-" + modelData.key
                text: modelData.title
                iconSource: Qt.resolvedUrl("../../assets/icons/material/controls/add-symbolic.svg")
                onClicked: trayArea.addRequested(modelData.key)
            }
        }
    }
}
