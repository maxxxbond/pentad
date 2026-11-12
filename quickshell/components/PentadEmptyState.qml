import QtQuick
import qs.theme

// The one empty state: a centred muted icon, one muted line and, when `actionText` is set, one
// capsule action that emits actionRequested(). The line wraps inside the component when the
// space is narrow; it never widens its parent.
Item {
    id: root
    property url iconSource: ""
    property string text: ""
    property string actionText: ""
    signal actionRequested()
    // For tests and focus chains; the button is hidden while actionText is empty.
    readonly property alias actionButton: button

    readonly property bool hasIcon: iconSource.toString() !== ""
    readonly property real naturalTextWidth: Math.ceil(labelMetrics.advanceWidth(text))

    implicitWidth: 2 * Metrics.space4 + Math.max(hasIcon ? Metrics.space6 : 0, naturalTextWidth,
        button.visible ? button.implicitWidth : 0)
    implicitHeight: 2 * Metrics.space5 + content.implicitHeight
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.Grouping
    Accessible.name: text

    FontMetrics {
        id: labelMetrics
        font: label.font
    }

    Column {
        id: content
        anchors.centerIn: parent
        width: Math.max(0, root.width - 2 * Metrics.space4)
        spacing: Metrics.space3
        PentadIcon {
            visible: root.hasIcon
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.iconSource
            pixelSize: Metrics.space6
            color: Theme.tokens.textMuted
            Accessible.ignored: true
        }
        PentadText {
            id: label
            visible: root.text !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.naturalTextWidth, parent.width)
            text: root.text
            textFormat: Text.PlainText
            color: Theme.tokens.textMuted
            horizontalAlignment: Text.AlignHCenter
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        PentadButton {
            id: button
            visible: root.actionText !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.actionText
            // An empty state usually fills a raised panel; one elevation step keeps the capsule visible there.
            restFill: Theme.tokens.surfaceOverlay
            onClicked: root.actionRequested()
        }
    }
}
