import QtQuick
import qs.features.bar

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var controller
    required property var services
    signal actionRequested(string action)
    implicitWidth: island.implicitWidth
    implicitHeight: island.implicitHeight
    readonly property real renderedHeight: island.renderedHeight
    readonly property var inputRegion: island.inputRegion
    visible: !!controller
    LiveIsland {
        id: island
        anchors.fill: parent
        services: root.controller ? root.controller.serviceFacade : root.services
        outputId: root.context.outputId
        consumerId: 'island:' + root.context.outputId + ':' + root.instanceId
        onActivated: root.actionRequested('activity')
    }
}
