import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.components
import qs.theme

// Visual choice cards (radio semantics). options: [{ value, label, art }].
// `artDelegate` may draw the preview; it sees `option` (the entry) and fills its parent.
FocusScope {
    id: root
    property var options: []
    property var value: undefined
    property string accessibleName: ""
    property int columns: Math.max(1, options.length)
    property Component artDelegate: null
    readonly property int cardArtHeight: 64
    readonly property int currentIndex: indexOf(value)
    readonly property alias repeater: cards
    signal activated(var value)

    implicitWidth: 320
    implicitHeight: grid.implicitHeight
    Accessible.name: accessibleName
    Accessible.role: Accessible.RadioButton

    function indexOf(v) {
        for (let i = 0; i < options.length; i++) if (options[i].value === v) return i;
        return -1;
    }
    function step(from, delta) {
        if (options.length === 0) return;
        const next = (from + delta + options.length) % options.length;
        activated(options[next].value);
        Qt.callLater(function() {
            const card = cards.itemAt(next);
            if (card) card.forceActiveFocus(Qt.TabFocusReason);
        });
    }

    GridLayout {
        id: grid
        width: parent.width
        columns: root.columns
        columnSpacing: 8
        rowSpacing: 8

        Repeater {
            id: cards
            model: root.options
            delegate: Control {
                id: card
                required property int index
                required property var modelData
                readonly property bool selected: root.currentIndex === index
                // Roving tabindex: one stop per group, on the selected card (or the first).
                activeFocusOnTab: root.currentIndex < 0 ? index === 0 : selected
                objectName: "optionCard_" + modelData.value
                Layout.fillWidth: true
                Layout.preferredHeight: root.cardArtHeight + label.implicitHeight + 24
                Accessible.name: modelData.label
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                Accessible.onPressAction: root.activated(modelData.value)

                Keys.onPressed: function(event) {
                    const forward = event.key === Qt.Key_Right || event.key === Qt.Key_Down;
                    const backward = event.key === Qt.Key_Left || event.key === Qt.Key_Up;
                    if (forward || backward) { root.step(index, forward ? 1 : -1); event.accepted = true; }
                    else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activated(modelData.value);
                        event.accepted = true;
                    }
                }

                ContinuousSurface {
                    anchors.fill: parent
                    // Selection is tonal elevation plus the check mark; only keyboard focus draws an edge.
                    fill: card.selected || area.containsMouse ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                    edge: card.visualFocus ? Theme.tokens.accent : "transparent"
                    extent: Metrics.radiusMedium
                }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8
                    Item {
                        id: art
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.cardArtHeight
                        clip: true
                        Loader {
                            anchors.fill: parent
                            property var option: card.modelData
                            sourceComponent: root.artDelegate ? root.artDelegate : placeholder
                        }
                        PentadIcon {
                            objectName: "optionCardCheck"
                            visible: card.selected
                            anchors.top: parent.top
                            anchors.right: parent.right
                            source: Qt.resolvedUrl("../../assets/icons/material/radio-button-checked-symbolic.svg")
                            pixelSize: Metrics.panelIcon
                            color: Theme.tokens.accent
                        }
                    }
                    PentadText {
                        id: label
                        Layout.fillWidth: true
                        text: card.modelData.label
                        textFormat: Text.PlainText
                        role: "caption"
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        color: card.selected ? Theme.tokens.text : Theme.tokens.textMuted
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { card.forceActiveFocus(); root.activated(card.modelData.value); }
                }
            }
        }
    }

    Component {
        id: placeholder
        Rectangle {
            radius: Metrics.radiusSmall
            color: Theme.tokens.surfaceOverlay
        }
    }
}
