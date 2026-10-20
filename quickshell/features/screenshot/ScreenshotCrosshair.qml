pragma ComponentBehavior: Bound
import QtQuick
import qs.components

Item {
    id: root
    property real pointX: 0
    property real pointY: 0
    property string label: ''
    property bool camera: false
    readonly property int px: Math.floor(pointX)
    readonly property int py: Math.floor(pointY)
    readonly property int arm: 10
    readonly property int gap: 3

    Item {
        anchors.fill: parent
        visible: !root.camera
        Repeater {
            model: [
                [-root.gap - root.arm, 0, root.arm, 1],
                [root.gap + 1, 0, root.arm, 1],
                [0, -root.gap - root.arm, 1, root.arm],
                [0, root.gap + 1, 1, root.arm]
            ]
            Item {
                id: arm
                required property var modelData
                x: root.px + modelData[0]
                y: root.py + modelData[1]
                width: modelData[2]
                height: modelData[3]
                Rectangle {
                    x: -1; y: -1
                    width: arm.width + 2; height: arm.height + 2
                    color: Qt.rgba(0, 0, 0, 0.55)
                }
                Rectangle {
                    anchors.fill: parent
                    color: 'white'
                }
            }
        }
    }
    Rectangle {
        visible: !root.camera
        x: root.px - 1; y: root.py - 1
        width: 3; height: 3
        color: Qt.rgba(0, 0, 0, 0.55)
        Rectangle { x: 1; y: 1; width: 1; height: 1; color: 'white' }
    }

    Rectangle {
        id: cameraPointer
        visible: root.camera
        x: root.px - width / 2
        y: root.py - height / 2
        width: 34
        height: 34
        radius: height / 2
        color: Qt.rgba(0.07, 0.08, 0.09, 0.78)
        border.width: 1.5
        border.color: Qt.rgba(1, 1, 1, 0.85)
        PentadIcon {
            anchors.centerIn: parent
            source: Qt.resolvedUrl('../../assets/icons/material/media/photo-camera-symbolic.svg')
            pixelSize: 18
            color: 'white'
        }
    }

    Rectangle {
        id: badge
        visible: !!root.label
        readonly property bool flipX: root.px + 18 + width > root.width - 4
        readonly property bool flipY: root.py + 18 + height > root.height - 4
        x: flipX ? root.px - 18 - width : root.px + 18
        y: flipY ? root.py - 18 - height : root.py + 18
        width: readout.implicitWidth + 14
        height: 20
        radius: 6
        color: Qt.rgba(0.07, 0.08, 0.09, 0.78)
        PentadText {
            id: readout
            anchors.centerIn: parent
            role: 'caption'
            color: 'white'
            wrapMode: Text.NoWrap
            font.features: ({ 'tnum': 1 })
            text: root.label
        }
    }
}
