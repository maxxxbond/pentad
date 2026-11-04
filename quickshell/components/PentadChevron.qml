import QtQuick
import qs.theme

Item {
    id: root
    property string direction: "right"
    property bool engaged: false
    property bool shown: true
    property color color: Theme.tokens.textMuted
    property int pixelSize: Metrics.chevronIcon
    readonly property real restOpacity: 0.72
    readonly property var angles: ({ right: 0, down: 90, left: 180, up: 270 })
    implicitWidth: pixelSize
    implicitHeight: pixelSize
    rotation: angles[direction] !== undefined ? angles[direction] : 0
    opacity: !shown ? 0 : engaged ? 1 : restOpacity
    visible: opacity > 0
    Accessible.ignored: true
    Behavior on rotation {
        enabled: !Theme.tokens.reducedMotion
        NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        enabled: !Theme.tokens.reducedMotion
        NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic }
    }
    PentadIcon {
        anchors.fill: parent
        // The 24-unit artwork spans x=9..16: centre its ink before the parent
        // rotates, so every direction and every animation frame share a centre.
        transform: Translate { x: -0.5 * root.pixelSize / 24 }
        source: Qt.resolvedUrl("../assets/icons/material/chevron-right-symbolic.svg")
        pixelSize: root.pixelSize
        color: root.color
        Accessible.ignored: true
    }
}
