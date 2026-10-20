import QtQuick
import qs.components
import qs.theme
import '../../logic/workspaces.mjs' as Workspaces

Column {
    id: root
    required property var services
    required property string outputId
    readonly property var state: services.hyprland.state
    readonly property var choices: state.kind === 'ready' ? Workspaces.workspaceChoicesForOutput(state.value, outputId) : []
    width: 420
    spacing: 8
    PentadText { text: 'Workspaces'; role: 'title' }
    Repeater {
        model: root.choices
        PentadButton {
            required property var modelData
            text: Workspaces.workspaceLabel(modelData)
            accessibleName: text
            onClicked: root.services.hyprland.focusWorkspace(modelData.id)
        }
    }
}
