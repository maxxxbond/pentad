import QtQuick
import qs.components

// The bar button for the Stash: it opens the Stash window, or focuses it when it is open as a window.
Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property var controller
    signal actionRequested(string action)
    implicitWidth: trigger.implicitWidth
    implicitHeight: trigger.implicitHeight

    PentadButton {
        id: trigger
        objectName: 'shelf-widget-button'
        text: root.services.text('Сховок', 'Stash')
        onClicked: root.services.stash.toggle()
    }
}
