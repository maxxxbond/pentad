import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import qs.components

Button {
    id: control
    property string glyph: ""
    property color accent: Theme.tokens.accent
    property bool prominent: false
    property int diameter: prominent ? 42 : 30
    property real cornerRadius: diameter / 2
    property int glyphPixelSize: prominent ? 26 : 18
    property bool pausedProminent: false
    property bool selected: false
    readonly property url iconSource: glyph ? Qt.resolvedUrl('../../assets/icons/material/media/'
        + glyph.replace(/_/g, '-') + '-symbolic.svg') : ''
    readonly property bool iconReady: symbol.imageStatus === Image.Ready
    implicitWidth: diameter
    implicitHeight: diameter
    property color foreground: !enabled ? Theme.tokens.textMuted
        : prominent && (!pausedProminent || down || hovered) ? Theme.tokens.surface
        : prominent || selected ? accent : Theme.tokens.text
    hoverEnabled: true
    HoverHandler {
        enabled: control.enabled
        blocking: false
        cursorShape: Qt.PointingHandCursor
    }
    padding: 0
    Accessible.name: text
    Accessible.role: Accessible.Button
    contentItem: Item {
        PentadIcon {
            id: symbol
            anchors.centerIn: parent
            pixelSize: control.glyphPixelSize
            source: control.iconSource
            color: control.foreground
            Accessible.ignored: true
        }
    }
    background: Rectangle {
        radius: control.cornerRadius
        color: control.prominent ? (control.pausedProminent
                ? control.down ? Qt.alpha(control.accent, 0.42)
                : control.hovered ? Qt.alpha(control.accent, 0.88)
                : Qt.alpha(control.accent, 0.72) : control.accent)
            : control.selected ? Qt.alpha(control.accent, 0.22)
            : control.down ? Qt.alpha(control.accent, 0.22)
            : control.hovered ? Theme.tokens.surfaceOverlay : "transparent"
        opacity: control.enabled ? 1 : 0.45
    }
}
