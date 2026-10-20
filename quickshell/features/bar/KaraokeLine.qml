import QtQuick
import qs.theme

Item {
    id: root
    property string text: ''
    property real progress: 0
    property color accent: Theme.tokens.accent
    implicitHeight: 26
    clip: true
    readonly property real lineWidth: Math.max(width, measure.width)
    readonly property real textStart: Math.max(0, (lineWidth - measure.width) / 2)
    readonly property real scrollOffset: Math.max(0, Math.min(lineWidth - width,
        textStart + measure.width * progress - width * 0.65))
    TextMetrics { id: measure; text: root.text; font: base.font }
    Item {
        x: -root.scrollOffset
        width: root.lineWidth
        height: root.height
        Text {
            id: base
            renderType: Text.NativeRendering
            anchors.fill: parent
            text: root.text
            color: Qt.alpha(Theme.tokens.text, 0.4)
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 19
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        Item {
            width: root.textStart + measure.width * Math.max(0, Math.min(1, root.progress))
            height: parent.height
            clip: true
            Text {
                renderType: Text.NativeRendering
                width: root.lineWidth
                height: parent.height
                text: root.text
                font: base.font
                color: root.accent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    Accessible.name: text
    Accessible.role: Accessible.StaticText
}
