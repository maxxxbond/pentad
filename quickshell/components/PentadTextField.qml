import QtQuick
import QtQuick.Controls.Basic
import qs.theme

TextField {
    id: control
    property bool error: false
    property string accessibleName: placeholderText
    // Resting fill; a field that sits on a raised card passes the next elevation step.
    property color fill: Theme.tokens.surfaceRaised
    // A field is a 6 px rectangle; `capsule` draws it as a capsule where its host's controls are capsules.
    property bool capsule: false
    implicitHeight: Metrics.controlLarge
    implicitWidth: 220
    Accessible.name: accessibleName
    Accessible.role: Accessible.EditableText
    color: Theme.tokens.text
    placeholderTextColor: Theme.tokens.textMuted
    font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
    leftPadding: 12; rightPadding: 12
    // The line is centred in the whole height. The style's 6 px above and below would leave a
    // short field (28 px) less room than a line of text needs, and the text would sit off-centre.
    topPadding: 0; bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    selectionColor: Theme.tokens.accent
    selectedTextColor: Theme.tokens.surface
    // Borderless: tonal fill with hover and focus state layers. The edge is drawn only for
    // keyboard focus (visualFocus) and for an error, in the palette's softened status red.
    background: ContinuousSurface {
        fill: control.activeFocus ? Qt.tint(control.fill, Qt.alpha(Theme.tokens.text, 0.06))
            : control.hovered ? Qt.tint(control.fill, Qt.alpha(Theme.tokens.text, 0.05)) : control.fill
        edge: control.error ? Qt.alpha(Theme.tokens.error, 0.7) : control.visualFocus ? Theme.tokens.accent : "transparent"
        extent: Metrics.radiusSmall
        capsule: control.capsule
        Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }
}
