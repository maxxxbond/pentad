import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.components
import qs.theme
import "../../logic/settings-color.mjs" as ColorLogic

// Preset swatches (the chosen one wears a ring) and a compact hex field for any other color.
// Commits a valid #RRGGBB on Enter/blur, Esc reverts.
ColumnLayout {
    id: root
    property string value: ""
    property var presets: ColorLogic.defaultSwatches
    property string accessibleName: ""
    property string invalidText: "Use a 6-digit hex color, like #869677."
    property string customLabel: "Custom"
    readonly property alias input: input
    readonly property string normalized: ColorLogic.normalizeColor(input.text)
    readonly property bool valid: normalized !== ""
    readonly property bool invalid: input.text !== "" && !valid
    readonly property bool preset: presets.some(function(swatch) { return ColorLogic.sameColor(swatch, root.value); })
    signal committed(string color)
    spacing: 8

    function revert() { input.text = root.value.toUpperCase(); }
    function commit() {
        if (!valid) return false;
        if (!ColorLogic.sameColor(normalized, root.value)) root.committed(normalized);
        return true;
    }
    // Check-mark color with the better contrast against a swatch.
    function inkFor(hex) {
        const color = Qt.color(hex);
        const channel = function(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
        const luminance = 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
        return luminance > 0.45 ? "#111311" : "#F2F4F1";
    }
    onValueChanged: if (!input.activeFocus) revert()
    Component.onCompleted: revert()

    Flow {
        id: swatches
        Layout.fillWidth: true
        spacing: 8
        Accessible.role: Accessible.RadioButton
        Accessible.name: root.accessibleName
        Repeater {
            model: root.presets
            delegate: Control {
                id: sw
                required property string modelData
                readonly property bool on: ColorLogic.sameColor(modelData, root.value)
                width: Metrics.controlSmall
                height: Metrics.controlSmall
                activeFocusOnTab: true
                objectName: "colorSwatch_" + modelData
                Accessible.name: modelData
                Accessible.role: Accessible.RadioButton
                Accessible.checked: on
                Accessible.onPressAction: root.committed(modelData.toUpperCase())
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.committed(modelData.toUpperCase());
                        event.accepted = true;
                    }
                }
                // Keyboard focus is the only ring; the chosen swatch is marked by its check.
                Rectangle {
                    id: ring
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: sw.visualFocus ? 2 : 0
                    border.color: Theme.tokens.accent
                }
                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    width: sw.visualFocus ? parent.width - 8 : parent.width - 4
                    height: width
                    radius: width / 2
                    color: sw.modelData
                    scale: swHover.hovered && !sw.on ? 1.1 : 1
                    Behavior on width { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
                    Behavior on scale { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
                    PentadIcon {
                        anchors.centerIn: parent
                        visible: sw.on
                        source: Qt.resolvedUrl("../../assets/icons/material/controls/check-symbolic.svg")
                        pixelSize: 12
                        color: root.inkFor(sw.modelData)
                        Accessible.ignored: true
                    }
                }
                HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { sw.forceActiveFocus(); root.committed(sw.modelData.toUpperCase()); } }
            }
        }
    }

    RowLayout {
        spacing: 8
        PentadTextField {
            id: input
            Layout.preferredWidth: 132
            implicitHeight: Metrics.controlSmall
            fill: Theme.tokens.surfaceOverlay
            leftPadding: 32
            rightPadding: 8
            maximumLength: 7
            placeholderText: "#RRGGBB"
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            accessibleName: root.accessibleName
            error: root.invalid
            onEditingFinished: {
                if (!root.commit()) root.revert();
            }
            Keys.onEscapePressed: function(event) { root.revert(); event.accepted = true; }
            Rectangle {
                id: chip
                objectName: "colorChip"
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: Metrics.radiusTag
                color: root.valid ? root.normalized : Qt.alpha(Theme.tokens.text, 0.08)
            }
        }
        PentadText {
            objectName: "colorCustomLabel"
            visible: !root.preset && root.valid && !root.invalid
            text: root.customLabel
            textFormat: Text.PlainText
            role: "caption"
            color: Theme.tokens.textMuted
            wrapMode: Text.NoWrap
        }
    }
    PentadText {
        objectName: "colorError"
        visible: root.invalid
        text: root.invalidText
        textFormat: Text.PlainText
        role: "caption"
        color: Theme.tokens.error
        Layout.fillWidth: true
    }
}
