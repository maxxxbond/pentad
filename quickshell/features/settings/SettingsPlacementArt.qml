import QtQuick
import qs.theme
import "../../logic/pentads.mjs" as Pentads

// A thumbnail of the desktop: the bar's three sections on top, the two side menus below.
// Sections the widget lives in are filled with the accent; the rest stay as faint outlines.
Item {
    id: root
    property var zones: []
    property string accessibleName: ""
    // Switched-off widgets keep their footprint but lose the accent.
    property bool dimmed: false
    readonly property color litColor: dimmed ? Qt.alpha(Theme.tokens.accent, 0.4) : Theme.tokens.accent
    readonly property color dimColor: Qt.alpha(Theme.tokens.text, 0.12)
    readonly property real inset: 5
    readonly property real barHeight: 7
    readonly property real menuWidth: 14
    readonly property real sideWidth: 18
    readonly property real centerWidth: 14
    function active(id) { return Array.isArray(zones) && zones.indexOf(id) >= 0; }

    implicitWidth: 72
    implicitHeight: 44
    Accessible.name: accessibleName
    Accessible.role: Accessible.Graphic
    Accessible.description: Pentads.zones.filter(function(zone) { return root.active(zone.id); })
        .map(function(zone) { return zone.labelEn; }).join(", ")

    // A tonal plaque, no frame: the sections are told apart by fill alone.
    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusTag
        color: Qt.alpha(Theme.tokens.text, 0.05)
    }
    Rectangle {
        x: root.inset; y: root.inset
        width: root.sideWidth; height: root.barHeight
        radius: Metrics.radiusTag / 2
        color: root.active("left") ? root.litColor : root.dimColor
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
    Rectangle {
        x: (root.width - root.centerWidth) / 2; y: root.inset
        width: root.centerWidth; height: root.barHeight
        radius: Metrics.radiusTag / 2
        color: root.active("center") ? root.litColor : root.dimColor
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
    Rectangle {
        x: root.width - root.inset - root.sideWidth; y: root.inset
        width: root.sideWidth; height: root.barHeight
        radius: Metrics.radiusTag / 2
        color: root.active("right") ? root.litColor : root.dimColor
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
    Rectangle {
        x: root.inset; y: root.inset + root.barHeight + 4
        width: root.menuWidth; height: root.height - y - root.inset
        radius: Metrics.radiusTag / 2
        color: root.active("left-menu") ? root.litColor : root.dimColor
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
    Rectangle {
        x: root.width - root.inset - root.menuWidth; y: root.inset + root.barHeight + 4
        width: root.menuWidth; height: root.height - y - root.inset
        radius: Metrics.radiusTag / 2
        color: root.active("right-menu") ? root.litColor : root.dimColor
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
}
