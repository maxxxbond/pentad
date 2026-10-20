import QtQuick
import qs.theme

// Six-dot grip. The parent decides the hit area; this only draws the glyph.
Item {
    id: root
    property bool engaged: false
    property color color: engaged ? Theme.tokens.text : Theme.tokens.textMuted
    implicitWidth: Metrics.panelIcon
    implicitHeight: Metrics.panelIcon
    Accessible.ignored: true
    PentadIcon {
        anchors.centerIn: parent
        source: Qt.resolvedUrl("../assets/icons/pentad/drag-indicator-symbolic.svg")
        pixelSize: Metrics.panelIcon
        color: root.color
        Accessible.ignored: true
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
}
