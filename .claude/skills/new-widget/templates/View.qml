import QtQuick
import qs.components
import qs.theme

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property var controller
    readonly property bool controllerReady: controller !== null

    function tr(uk, en) { return typeof services.text === 'function' ? services.text(uk, en) : en; }

    visible: controllerReady
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    PentadText {
        id: label
        anchors.centerIn: parent
        text: root.controllerReady ? controller.summary : ''
        font.pixelSize: Metrics.textBody
    }
}
