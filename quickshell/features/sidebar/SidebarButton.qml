import QtQuick
import qs.components
import qs.theme

PentadButton {
    id: control
    property bool opened: false
    focusPolicy: Qt.StrongFocus
    opacity: enabled || pending ? 1 : 0.35
    scale: down ? 0.97 : 1
    Behavior on scale { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.press } }
    contentItem: Text {
        text: control.text
        textFormat: Text.PlainText
        color: control.visualFocus ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.8)
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: ContinuousSurface {
        fill: control.opened ? Theme.tokens.surface
            : control.down ? Qt.alpha(Theme.tokens.text, 0.12)
            : control.visualFocus || control.checked ? Theme.tokens.surfaceOverlay
            : control.hovered ? Qt.alpha(Theme.tokens.text, 0.05) : Theme.tokens.surfaceRaised
        extent: Metrics.radiusSmall
    }
}
