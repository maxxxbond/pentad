import QtQuick
import qs.theme
import "../../logic/pentads.mjs" as Pentads

// Five-segment glyph of the sections a widget is active in: menus are 6x16 bars,
// bar sections are 12x6 segments. Active segments use the accent color.
Item {
    id: root
    property var zones: []
    property string accessibleName: ""
    readonly property real gap: 2
    readonly property real menuWidth: 6
    readonly property real menuHeight: 16
    readonly property real segmentWidth: 12
    readonly property real segmentHeight: 6

    implicitWidth: 2 * menuWidth + 3 * segmentWidth + 4 * gap
    implicitHeight: menuHeight
    Accessible.name: accessibleName
    Accessible.role: Accessible.Graphic
    Accessible.description: Pentads.zones.filter(function(zone) { return root.zones.indexOf(zone.id) >= 0; })
        .map(function(zone) { return zone.labelEn; }).join(", ")

    Row {
        spacing: root.gap
        Repeater {
            model: Pentads.zones
            delegate: Rectangle {
                required property var modelData
                readonly property bool menu: modelData.kind === "menu"
                readonly property bool active: root.zones.indexOf(modelData.id) >= 0
                width: menu ? root.menuWidth : root.segmentWidth
                height: menu ? root.menuHeight : root.segmentHeight
                anchors.verticalCenter: parent.verticalCenter
                radius: Metrics.radiusMicro / 2
                color: active ? Theme.tokens.accent : Qt.alpha(Theme.tokens.text, 0.12)
            }
        }
    }
}
