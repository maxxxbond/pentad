import QtQuick
import QtQuick.Controls.Basic
import qs.theme

MenuSeparator {
    id: root

    property int lineThickness: 1
    property int horizontalInset: 4

    padding: 0
    topPadding: 3
    bottomPadding: 3
    implicitHeight: topPadding + lineThickness + bottomPadding

    contentItem: Item {
        implicitHeight: root.lineThickness

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.horizontalInset
            anchors.rightMargin: root.horizontalInset
            color: Theme.tokens.text
            opacity: 0.07
        }
    }
}
