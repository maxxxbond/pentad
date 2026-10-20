pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/workspaces.mjs' as Workspaces

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property var controller
    readonly property var hyprState: services.hyprland.state
    readonly property var choices: hyprState.kind === 'ready'
        ? Workspaces.workspaceChoicesForOutput(hyprState.value, context.outputId) : []
    readonly property bool focused: hyprState.kind === 'ready'
        && hyprState.value.outputs.some(function(output) {
            return (output.id === String(context.outputId) || output.name === String(context.outputId))
                && String(output.id) === String(hyprState.value.focusedOutputId);
        })
    width: 350
    implicitWidth: width
    implicitHeight: content.implicitHeight

    Column {
        id: content
        width: root.width
        spacing: 12
        Row {
            id: heading
            width: parent.width
            spacing: 8
            PentadText { text: 'Workspaces'; role: 'section'; width: parent.width - focusLabel.implicitWidth - 8 }
            PentadText {
                id: focusLabel
                text: root.focused ? 'Active monitor' : ''
                role: 'caption'
                color: Theme.tokens.textMuted
            }
        }

        Flow {
            id: workspaceGrid
            width: parent.width
            spacing: 8
            Repeater {
                model: root.choices
                delegate: PentadButton {
                    required property var modelData
                    text: Workspaces.workspaceLabel(modelData)
                    accessibleName: text
                    checked: modelData.active
                    requestedEnabled: !root.context.preview
                    onClicked: root.services.hyprland.focusWorkspace(modelData.id)
                }
            }
        }

        PentadCard {
            id: activeWindow
            width: parent.width
            implicitHeight: activeTitle.implicitHeight + 24
            PentadText {
                id: activeTitle
                x: 12
                y: 12
                width: parent.width - 24
                text: root.hyprState.kind !== 'ready' ? 'Workspace service unavailable'
                    : root.focused && root.hyprState.value.activeTitle
                        ? root.hyprState.value.activeTitle : 'No active window on this monitor'
                role: 'body'
                wrapMode: Text.Wrap
            }
        }
    }
}
