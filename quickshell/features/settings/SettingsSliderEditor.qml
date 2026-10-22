import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// Slider editor for a SettingsField: slider, number input and optional unit.
// `owner` is the owning SettingsField.
RowLayout {
    required property var owner
    spacing: 12
    property alias slider: slider
    PentadSlider {
        id: slider
        Layout.fillWidth: true
        property bool dirty: false
        accessibleName: owner.labelText
        from: owner.item.min !== undefined ? owner.item.min : 0
        to: owner.item.max !== undefined ? owner.item.max : 1
        stepSize: owner.item.step !== undefined ? owner.item.step : 0
        snapMode: Slider.SnapAlways
        value: Number(owner.displayed)
        confirmedValue: Number(owner.confirmed)
        valueText: String(value)
        enabled: !owner.blocked
        function flush() {
            dirty = false;
            owner.change(owner.item.kind === "integer" ? Math.round(value) : value);
            value = Qt.binding(function() { return Number(owner.displayed); });
        }
        onMoved: { dirty = true; if (!pressed) flush(); }
        onPressedChanged: if (!pressed && dirty) flush()
    }
    PentadTextField {
        id: numberInput
        objectName: "sliderNumber"
        Layout.preferredWidth: 72
        implicitHeight: Metrics.controlMedium
        fill: Theme.tokens.surfaceOverlay
        accessibleName: owner.labelText
        horizontalAlignment: TextInput.AlignRight
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        text: String(Math.round(slider.value * 1000) / 1000)
        enabled: !owner.blocked
        onEditingFinished: {
            const n = Number(text.replace(",", "."));
            if (text.trim() === "" || !Number.isFinite(n)) {
                text = Qt.binding(function() { return String(Math.round(slider.value * 1000) / 1000); });
                return;
            }
            const v = owner.clampNumber(n);
            if (v !== Number(owner.displayed)) owner.change(v);
            text = Qt.binding(function() { return String(Math.round(slider.value * 1000) / 1000); });
        }
    }
    PentadText {
        visible: owner.item.unit !== undefined
        text: owner.item.unit || ""
        textFormat: Text.PlainText
        role: "caption"
        color: Theme.tokens.textMuted
        wrapMode: Text.NoWrap
    }
}
