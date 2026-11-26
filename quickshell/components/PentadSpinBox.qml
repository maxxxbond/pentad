import QtQuick
import QtQuick.Controls.Basic
import qs.theme

SpinBox {
    id: control

    property string accessibleName: ""
    // Fractional values: the SpinBox itself stays integer, so values are scaled by 10^decimals.
    // `from`, `to`, `stepSize` and `value` are then in scaled units; use `realValue` for the number.
    property int decimals: 0
    // The box is an 8 px rectangle; `capsule` draws it as a capsule where its host's controls are capsules.
    property bool capsule: false
    readonly property real factor: Math.pow(10, decimals)
    readonly property real realValue: value / factor
    textFromValue: function(scaled, locale) { return Number(scaled / control.factor).toLocaleString(locale, "f", control.decimals); }
    valueFromText: function(text, locale) { return Math.round(Number.fromLocaleString(locale, text) * control.factor); }
    validator: DoubleValidator {
        bottom: Math.min(control.from, control.to) / control.factor
        top: Math.max(control.from, control.to) / control.factor
        decimals: control.decimals
        notation: DoubleValidator.StandardNotation
        locale: control.locale.name
    }
    implicitHeight: Metrics.controlMedium
    implicitWidth: 120
    Accessible.name: accessibleName
    Accessible.role: Accessible.SpinBox
    font.family: Theme.tokens.fontFamily
    font.pixelSize: Metrics.textBody
    editable: true
    leftPadding: 10
    topPadding: 4
    bottomPadding: 4
    rightPadding: 40 + endInset

    contentItem: TextInput {
        z: 2
        text: control.displayText
        font: control.font
        color: Theme.tokens.text
        selectionColor: Theme.tokens.accent
        selectedTextColor: Theme.tokens.surface
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: control.inputMethodHints
        selectByMouse: true
    }

    // A capsule has no room in its round end for the stacked pair, so the arrows stand side by
    // side at full height, clear of the end.
    readonly property real endInset: capsule ? Metrics.space2 : 0
    up.indicator: Item {
        x: control.width - width - control.down.indicator.width - control.endInset
        y: 0
        width: 20
        height: control.capsule ? control.height : control.height / 2
        PentadChevron {
            anchors.centerIn: parent
            direction: "up"
            pixelSize: Metrics.panelIcon
            engaged: control.up.pressed || control.up.hovered || control.activeFocus
        }
        Accessible.ignored: true
    }

    down.indicator: Item {
        x: control.width - width - control.endInset
        y: control.capsule ? 0 : control.height / 2
        width: 20
        height: control.capsule ? control.height : control.height / 2
        PentadChevron {
            anchors.centerIn: parent
            direction: "down"
            pixelSize: Metrics.panelIcon
            engaged: control.down.pressed || control.down.hovered || control.activeFocus
        }
        Accessible.ignored: true
    }

    background: ContinuousSurface {
        fill: Theme.tokens.surfaceOverlay
        edge: control.visualFocus ? Theme.tokens.accent : "transparent"
        extent: Metrics.radiusMedium
        capsule: control.capsule
    }
}
