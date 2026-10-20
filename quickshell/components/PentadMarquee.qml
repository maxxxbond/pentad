import QtQuick
import qs.theme

Item {
    id: root

    property string text: ""
    property bool marqueeEnabled: true
    property real xAlign: 0.5
    property real offset: 0
    property real fontSize: Metrics.panelFont
    property color color: Theme.tokens.text

    implicitHeight: 22
    clip: true

    readonly property real overflow: Math.max(0, textMetrics.width - width)

    onTextChanged: {
        offset = 0
        if (marquee.running) marquee.restart()
    }

    TextMetrics {
        id: textMetrics
        font: label.font
        text: root.text
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
        x: root.overflow > 0 ? root.offset : Math.max(0, (root.width - textMetrics.width) * root.xAlign)
        width: textMetrics.width
        text: root.text
        color: root.color
        font.family: Theme.tokens.fontFamily
        font.pixelSize: root.fontSize
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideNone
    }

    SequentialAnimation {
        id: marquee
        running: root.visible && root.marqueeEnabled && !Motion.reducedMotion && root.overflow > 0
        loops: Animation.Infinite

        PauseAnimation { duration: 1200 }
        NumberAnimation {
            target: root
            property: "offset"
            to: -root.overflow
            duration: Math.max(1, root.overflow / 0.028)
            easing.type: Easing.Linear
        }
        PauseAnimation { duration: 1200 }
        NumberAnimation {
            target: root
            property: "offset"
            to: 0
            duration: Math.max(1, root.overflow / 0.028)
            easing.type: Easing.Linear
        }

        onRunningChanged: if (!running) root.offset = 0
    }
}
