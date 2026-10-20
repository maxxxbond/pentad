pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme

TabBar {
    id: control
    property string accessibleName: "Tabs"
    implicitHeight: Metrics.controlMedium
    Accessible.name: accessibleName
    Accessible.role: Accessible.PageTabList
    background: ContinuousSurface { fill: Theme.tokens.surface; extent: Metrics.radiusSmall }
    contentItem: Row {
        spacing: 4
        Repeater {
            model: control.count
            delegate: Button {
                id: tabButton
                required property int index
                property var sourceTab: control.itemAt(index)
                text: sourceTab ? sourceTab.text : ""
                checked: index === control.currentIndex
                implicitWidth: contentItem.implicitWidth + 24
                implicitHeight: Metrics.controlMedium
                Accessible.role: Accessible.PageTab
                Accessible.name: text
                onPressed: control.setCurrentIndex(index)
                background: ContinuousSurface {
                    fill: tabButton.checked ? Theme.tokens.surfaceOverlay : "transparent"
                    extent: Metrics.radiusSmall
                }
                contentItem: Text {
                    text: tabButton.sourceTab ? tabButton.sourceTab.text : ""
                    color: tabButton.checked ? Theme.tokens.text : Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: Metrics.textBody
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
