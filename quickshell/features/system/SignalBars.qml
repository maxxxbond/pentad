import QtQuick
import qs.theme

// Four rounded bars of rising height; the first `level` are lit.
Row {
    id: root
    property int level: 0
    property color activeColor: Theme.tokens.text
    property color idleColor: Theme.tokens.textMuted
    readonly property int barWidth: 3
    readonly property int maxHeight: 16
    spacing: 2
    width: 4 * barWidth + 3 * spacing
    height: maxHeight
    Accessible.ignored: true

    Repeater {
        model: 4
        delegate: Rectangle {
            required property int index
            width: root.barWidth
            height: 6 + index * 3
            y: root.maxHeight - height
            radius: width / 2
            color: index < root.level ? root.activeColor : root.idleColor
            opacity: index < root.level ? 1 : 0.35
        }
    }
}
