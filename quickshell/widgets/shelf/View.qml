import QtQuick
import qs.components
import qs.features.shelf

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property var controller
    readonly property bool readOnly: !!context.preview || !!services.preview || !!services.safeMode
    readonly property alias shelfGrid: shelfContent
    signal actionRequested(string action)
    implicitWidth: trigger.implicitWidth
    implicitHeight: trigger.implicitHeight

    PentadButton {
        id: trigger
        text: 'Shelf'
        accessibleName: 'Open shelf'
        onPressed: shelfPopup.openFor(trigger)
    }
    PentadPopup {
        id: shelfPopup
        implicitWidth: 408
        implicitHeight: Math.min(560, shelfContent.implicitHeight + 8)
        contentItem: PentadScrollView {
            id: shelfScroll
            implicitWidth: 392
            contentWidth: availableWidth
            contentHeight: shelfContent.implicitHeight
            ShelfGrid {
                id: shelfContent
                objectName: 'shelf-widget-grid'
                width: shelfScroll.availableWidth
                shelf: root.services.shelf
                readOnly: root.readOnly
                language: root.services?.config?.documents?.interface?.language || 'en'
            }
        }
    }
}
