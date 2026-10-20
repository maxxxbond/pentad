pragma ComponentBehavior: Bound
import QtQuick
import qs.theme
import qs.components

Item {
    id: root
    property var rect: null
    property string kind: 'none'
    property bool animate: false
    property bool handles: false
    property string sizeText: ''
    readonly property bool hasHole: !!rect && rect.width > 0 && rect.height > 0
    readonly property color glass: kind === 'selection' ? Qt.rgba(0.12, 0.13, 0.15, 0.56) : Qt.rgba(0.14, 0.15, 0.17, 0.40)
    readonly property color frameColor: Qt.rgba(1, 1, 1, 0.92)
    property real holeX: hasHole ? rect.x : width / 2
    property real holeY: hasHole ? rect.y : height / 2
    property real holeWidth: hasHole ? rect.width : 0
    property real holeHeight: hasHole ? rect.height : 0
    readonly property bool glide: animate && kind === 'window' && !Theme.tokens.reducedMotion
    Behavior on holeX { enabled: root.glide; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
    Behavior on holeY { enabled: root.glide; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
    Behavior on holeWidth { enabled: root.glide; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
    Behavior on holeHeight { enabled: root.glide; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }

    Rectangle { x: 0; y: 0; width: root.width; height: Math.max(0, root.holeY); color: root.glass }
    Rectangle { x: 0; y: root.holeY; width: Math.max(0, root.holeX); height: root.holeHeight; color: root.glass }
    Rectangle {
        x: root.holeX + root.holeWidth; y: root.holeY
        width: Math.max(0, root.width - x); height: root.holeHeight
        color: root.glass
    }
    Rectangle {
        x: 0; y: root.holeY + root.holeHeight
        width: root.width; height: Math.max(0, root.height - y)
        color: root.glass
    }

    Rectangle {
        visible: root.hasHole && root.kind === 'window'
        x: root.holeX; y: root.holeY; width: root.holeWidth; height: root.holeHeight
        color: Qt.alpha(Theme.tokens.accent, 0.12)
    }
    Rectangle {
        visible: root.hasHole
        x: root.holeX - 1; y: root.holeY - 1
        width: root.holeWidth + 2; height: root.holeHeight + 2
        color: 'transparent'
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.38)
    }
    Rectangle {
        visible: root.hasHole
        x: root.holeX; y: root.holeY; width: root.holeWidth; height: root.holeHeight
        color: 'transparent'
        border.width: root.kind === 'window' ? 2 : 1
        border.color: root.frameColor
    }

    Repeater {
        model: root.handles && root.hasHole ? [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]] : []
        Rectangle {
            id: handle
            required property var modelData
            readonly property bool corner: modelData[0] !== 0.5 && modelData[1] !== 0.5
            readonly property bool vertical: modelData[0] !== 0.5 && !corner
            width: corner ? 10 : vertical ? 5 : 16
            height: corner ? 10 : vertical ? 16 : 5
            radius: Math.min(width, height) / 2
            x: Math.round(root.holeX + modelData[0] * root.holeWidth - width / 2)
            y: Math.round(root.holeY + modelData[1] * root.holeHeight - height / 2)
            color: 'white'
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.45)
        }
    }

    Rectangle {
        id: sizeBadge
        visible: root.hasHole && !!root.sizeText
        x: Math.max(4, Math.min(root.width - width - 4, root.holeX))
        y: root.holeY - height - 8 >= 4 ? root.holeY - height - 8 : root.holeY + 8
        width: sizeLabel.implicitWidth + 16
        height: 22
        radius: height / 2
        color: Qt.rgba(0.07, 0.08, 0.09, 0.82)
        PentadText {
            id: sizeLabel
            anchors.centerIn: parent
            role: 'caption'
            color: 'white'
            wrapMode: Text.NoWrap
            text: root.sizeText
            font.features: ({ 'tnum': 1 })
        }
    }
}
