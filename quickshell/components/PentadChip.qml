import QtQuick
import QtQuick.Controls.Basic
import qs.theme

// The one chip: a capsule Metrics.controlSmall tall with a label and an optional count. Selected is
// tonal elevation, a brighter label and a check mark, never an accent fill. The host owns `checked`:
// click, Space and Enter only emit toggled(), and the host decides whether `checked` changes.
AbstractButton {
    id: root
    // A count shown after the label; -1 hides it.
    property int count: -1

    readonly property bool hasCount: count >= 0
    readonly property real stateLayer: down ? Metrics.statePressed : hovered ? Metrics.stateHover : 0
    readonly property color foreground: checked || hovered ? Theme.tokens.text : Theme.tokens.textMuted
    readonly property real markSpace: checked ? Metrics.panelIcon + Metrics.space1 : 0
    readonly property real countSpace: hasCount ? Metrics.space1 + Math.ceil(countLabel.implicitWidth) : 0

    // Never checkable: AbstractButton would flip `checked` itself and break the host's binding.
    checkable: false
    implicitHeight: Metrics.controlSmall
    implicitWidth: leftPadding + rightPadding + markSpace + Math.ceil(label.implicitWidth) + countSpace
    leftPadding: Metrics.space3
    rightPadding: Metrics.space3
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    LayoutMirroring.childrenInherit: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.description: hasCount ? String(count) : ""
    Accessible.checkable: true
    Accessible.checked: checked

    onClicked: toggled()
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.toggled();
            event.accepted = true;
        }
    }

    contentItem: Item {
        opacity: root.enabled ? 1 : Metrics.stateDisabled
        Row {
            anchors.centerIn: parent
            spacing: Metrics.space1
            PentadIcon {
                visible: root.checked
                anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl("../assets/icons/material/controls/check-symbolic.svg")
                pixelSize: Metrics.panelIcon
                color: Theme.tokens.accent
                Accessible.ignored: true
            }
            PentadText {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, root.availableWidth - root.markSpace - root.countSpace))
                text: root.text
                textFormat: Text.PlainText
                role: "caption"
                color: root.foreground
                font.weight: root.checked ? Font.Medium : Font.Normal
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                maximumLineCount: 1
                Accessible.ignored: true
                Behavior on color {
                    enabled: !Theme.tokens.reducedMotion
                    ColorAnimation {
                        duration: Motion.short
                        easing.type: Motion.easeStandard
                    }
                }
            }
            PentadText {
                id: countLabel
                visible: root.hasCount
                anchors.verticalCenter: parent.verticalCenter
                text: String(root.count)
                textFormat: Text.PlainText
                role: "caption"
                color: Theme.tokens.textMuted
                font.features: ({ tnum: 1 })
                wrapMode: Text.NoWrap
                Accessible.ignored: true
            }
        }
    }

    // A capsule; the state layer lies over the resting fill, and the focus edge appears only
    // when focus came from the keyboard.
    // A plain Rectangle: the continuous-corner surface reads as a rounded rectangle at pill radius.
    background: Rectangle {
        color: root.checked ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, root.stateLayer))
            : Qt.alpha(Theme.tokens.text, Metrics.stateHover + root.stateLayer)
        border.width: root.visualFocus ? 1 : 0
        border.color: Theme.tokens.accent
        radius: Metrics.radiusPill
        Behavior on color {
            enabled: !Theme.tokens.reducedMotion
            ColorAnimation {
                duration: Motion.short
                easing.type: Motion.easeStandard
            }
        }
    }
}
