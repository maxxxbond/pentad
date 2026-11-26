import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// Slider editor for a SettingsField: slider, number input and optional unit.
// `owner` is the owning SettingsField. The slider and its number box together are one field wide
// and one control tall, so the editor ends on the row's trailing line like every other control.
RowLayout {
    required property var owner
    spacing: Metrics.space2
    property alias slider: slider
    // The number box fits the longest value the slider can show, and is never under 48 px.
    readonly property string widestNumber: {
        const shown = function(value) { return String(Math.round(value * 1000) / 1000); };
        const from = owner.item.min !== undefined ? owner.item.min : 0;
        const to = owner.item.max !== undefined ? owner.item.max : 1;
        const step = owner.item.step !== undefined ? owner.item.step : 0;
        return [shown(from), shown(to), shown(to - step)]
            .reduce(function(longest, text) { return text.length > longest.length ? text : longest; }, "");
    }
    readonly property real numberWidth: Math.max(Metrics.space6 + Metrics.space4,
        Math.ceil(numberMetrics.advanceWidth(widestNumber)) + 2 * Metrics.space2 + Metrics.space1)
    FontMetrics {
        id: numberMetrics
        font: numberInput.font
    }
    PentadSlider {
        id: slider
        Layout.fillWidth: true
        implicitWidth: Metrics.settingsFieldWidth - parent.spacing - parent.numberWidth
        implicitHeight: Metrics.controlSmall
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
        Layout.preferredWidth: parent.numberWidth
        implicitHeight: Metrics.controlSmall
        capsule: Metrics.settingsFieldCapsule
        leftPadding: Metrics.space2
        rightPadding: Metrics.space2
        fill: Theme.tokens.surfaceOverlay
        accessibleName: owner.labelText
        horizontalAlignment: TextInput.AlignHCenter
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
