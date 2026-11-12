import QtQuick
import qs.theme

Item {
    id: root
    property string text: ''
    property real progress: 0
    property color accent: Theme.tokens.accent
    // The surface behind the line; the edge fades blend into it.
    property color fadeColor: Theme.tokens.surface
    readonly property int maxPixelSize: 19
    readonly property int minPixelSize: 15
    readonly property int fadeWidth: 24
    implicitHeight: 26
    clip: true
    // Shrink long lines towards minPixelSize before they have to scroll.
    readonly property int pixelSize: measure.advanceWidth > 0 && width > 0
        ? Math.max(minPixelSize, Math.min(maxPixelSize, Math.floor(maxPixelSize * width / measure.advanceWidth)))
        : maxPixelSize
    readonly property real textWidth: fitted.advanceWidth
    readonly property bool overflows: textWidth > width
    readonly property real lineWidth: Math.max(width, textWidth)
    readonly property real textStart: Math.max(0, (lineWidth - textWidth) / 2)
    readonly property real scrollOffset: Math.max(0, Math.min(lineWidth - width,
        textStart + textWidth * progress - width * 0.65))
    readonly property bool hiddenLeft: overflows && scrollOffset > 0.5
    readonly property bool hiddenRight: overflows && scrollOffset < lineWidth - width - 0.5
    TextMetrics {
        id: measure
        text: root.text
        font.family: Theme.tokens.fontFamily
        font.pixelSize: root.maxPixelSize
        font.weight: Font.Bold
    }
    TextMetrics { id: fitted; text: root.text; font: base.font }
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
            font.pixelSize: root.pixelSize
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        Item {
            width: root.textStart + root.textWidth * Math.max(0, Math.min(1, root.progress))
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
    // Soft edges only on the side where the line continues out of view.
    Rectangle {
        width: root.fadeWidth
        height: parent.height
        visible: root.hiddenLeft
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.fadeColor }
            GradientStop { position: 1; color: Qt.alpha(root.fadeColor, 0) }
        }
    }
    Rectangle {
        x: parent.width - width
        width: root.fadeWidth
        height: parent.height
        visible: root.hiddenRight
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(root.fadeColor, 0) }
            GradientStop { position: 1; color: root.fadeColor }
        }
    }
    Accessible.name: text
    Accessible.role: Accessible.StaticText
}
