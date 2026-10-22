pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// Accent candidates as round swatches; the one matching the accent carries a check.
// candidates: [{ hex, share }]
Item {
    id: root
    property var candidates: []
    property string value: ""
    property string emptyText: ""
    property string accessibleName: ""
    signal activated(string hex)
    readonly property alias repeater: swatches
    implicitWidth: candidates.length ? row.implicitWidth : hint.implicitWidth
    implicitHeight: Metrics.controlSmall

    function readableOn(hex) {
        const c = Qt.color(hex);
        const luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return luminance > 0.5 ? "#111311" : "#F2F4F1";
    }

    Row {
        id: row
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        visible: root.candidates.length > 0
        Repeater {
            id: swatches
            model: root.candidates
            delegate: Control {
                id: swatch
                required property var modelData
                readonly property bool selected: String(root.value).toUpperCase() === String(modelData.hex).toUpperCase()
                objectName: "accentSwatch_" + modelData.hex
                width: Metrics.controlSmall
                height: Metrics.controlSmall
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: root.accessibleName + " " + modelData.hex
                Accessible.checkable: true
                Accessible.checked: selected
                Accessible.onPressAction: root.activated(modelData.hex)
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activated(swatch.modelData.hex);
                        event.accepted = true;
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: swatchHover.hovered ? parent.width : parent.width - 4
                    height: width
                    radius: width / 2
                    color: swatch.modelData.hex
                    border.width: swatch.visualFocus ? 2 : 0
                    border.color: Theme.tokens.text
                    Behavior on width { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
                }
                PentadIcon {
                    anchors.centerIn: parent
                    visible: swatch.selected
                    source: Qt.resolvedUrl("../../assets/icons/material/controls/check-symbolic.svg")
                    pixelSize: 16
                    color: root.readableOn(swatch.modelData.hex)
                    Accessible.ignored: true
                }
                HoverHandler { id: swatchHover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: root.enabled; onTapped: root.activated(swatch.modelData.hex) }
            }
        }
    }
    PentadText {
        id: hint
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.candidates.length === 0
        text: root.emptyText
        textFormat: Text.PlainText
        color: Theme.tokens.textMuted
        wrapMode: Text.NoWrap
    }
}
