import QtQuick
import QtQuick.Controls.Basic
import qs.theme

TextField {
    id: control
    property bool error: false
    property string accessibleName: placeholderText
    // Resting fill; a field that sits on a raised card passes the next elevation step.
    property color fill: Theme.tokens.surfaceRaised
    implicitHeight: Metrics.controlLarge
    implicitWidth: 220
    Accessible.name: accessibleName
    Accessible.role: Accessible.EditableText
    color: Theme.tokens.text
    placeholderTextColor: Theme.tokens.textMuted
    font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
    leftPadding: 12; rightPadding: 12
    selectionColor: Theme.tokens.accent
    selectedTextColor: Theme.tokens.surface
    // Borderless: tonal fill with hover and focus state layers. The edge is drawn only for
    // keyboard focus (visualFocus) and for an error, in the palette's softened status red.
    background: ContinuousSurface {
        fill: control.activeFocus ? Qt.tint(control.fill, Qt.alpha(Theme.tokens.text, 0.06))
            : control.hovered ? Qt.tint(control.fill, Qt.alpha(Theme.tokens.text, 0.05)) : control.fill
        edge: control.error ? Qt.alpha(Theme.tokens.error, 0.7) : control.visualFocus ? Theme.tokens.accent : "transparent"
        extent: Metrics.radiusSmall
        Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
}
