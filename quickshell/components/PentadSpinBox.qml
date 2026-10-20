import QtQuick
import QtQuick.Controls.Basic
import qs.theme

SpinBox {
    id: control

    property string accessibleName: ""
    // Fractional values: the SpinBox itself stays integer, so values are scaled by 10^decimals.
    // `from`, `to`, `stepSize` and `value` are then in scaled units; use `realValue` for the number.
    property int decimals: 0
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
    rightPadding: 40

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

    up.indicator: Item {
        x: control.width - width - control.down.indicator.width
        y: 0
        width: 20
        height: control.height / 2
        PentadChevron {
            anchors.centerIn: parent
            direction: "up"
            pixelSize: Metrics.panelIcon
            engaged: control.up.pressed || control.up.hovered || control.activeFocus
        }
        Accessible.ignored: true
    }

    down.indicator: Item {
        x: control.width - width
        y: control.height / 2
        width: 20
        height: control.height / 2
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
    }
}
