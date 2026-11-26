pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/settings-chips.mjs" as Chips

// Multi-select chips. The first chip is the sentinel ("Auto"); picking any language
// chip leaves it, clearing the last language returns to it. Chips are capsules told apart
// by tonal fill and a check mark, never by an outline.
FocusScope {
    id: root
    property var choices: []
    property var value: undefined
    property string sentinel: "auto"
    property string sentinelLabel: "Auto"
    property bool sentinelAllowed: true
    property string accessibleName: ""
    signal activated(var value)

    readonly property var selected: Chips.selectedChoices(value)
    readonly property bool auto: Chips.isSentinel(value, sentinel)
    readonly property alias repeater: chips

    implicitWidth: 320
    implicitHeight: flow.implicitHeight
    Accessible.name: accessibleName
    Accessible.role: Accessible.List

    // A Control, so the focus edge follows visualFocus (keyboard only).
    component Chip: Control {
        id: chip
        property string label: ""
        property bool checked: false
        property bool sentinelChip: false
        signal toggled()
        width: content.implicitWidth + 24
        height: Metrics.controlSmall
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.checked: checked
        Accessible.onPressAction: toggled()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                chip.toggled();
                event.accepted = true;
            }
        }
        ContinuousSurface {
            anchors.fill: parent
            fill: chip.checked ? Theme.tokens.surfaceOverlay
                : chipHover.hovered ? Qt.alpha(Theme.tokens.text, 0.08) : Qt.alpha(Theme.tokens.text, 0.04)
            edge: chip.visualFocus ? Theme.tokens.accent : "transparent"
            // Chips are capsules (user decision, 2026-10-19).
            capsule: true
            Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        }
        Row {
            id: content
            anchors.centerIn: parent
            spacing: 4
            PentadIcon {
                visible: chip.checked
                anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl("../../assets/icons/material/controls/check-symbolic.svg")
                pixelSize: Metrics.panelIcon
                color: Theme.tokens.accent
                Accessible.ignored: true
            }
            PentadText {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                textFormat: Text.PlainText
                role: "caption"
                font.weight: chip.checked || chip.sentinelChip ? Font.Medium : Font.Normal
                color: chip.checked || chipHover.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                wrapMode: Text.NoWrap
                Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
            }
        }
        HoverHandler { id: chipHover; enabled: chip.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: chip.enabled; onTapped: { chip.forceActiveFocus(); chip.toggled(); } }
    }

    Flow {
        id: flow
        width: parent.width
        spacing: 4
        layoutDirection: LayoutMirroring.enabled ? Qt.RightToLeft : Qt.LeftToRight
        Chip {
            objectName: "chip_" + root.sentinel
            visible: root.sentinelAllowed
            label: root.sentinelLabel
            checked: root.auto
            sentinelChip: true
            onToggled: if (!root.auto) root.activated(root.sentinel)
        }
        Repeater {
            id: chips
            model: root.choices
            delegate: Chip {
                required property var modelData
                objectName: "chip_" + modelData.value
                label: modelData.label
                checked: root.selected.indexOf(modelData.value) >= 0
                onToggled: root.activated(Chips.toggleChoice(root.value, modelData.value, root.sentinel))
            }
        }
    }
}
