import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import qs.theme

// A quiet "i" ring that explains one setting: a tooltip on hover, a popover on click.
PentadButton {
    id: control
    required property string helpText
    readonly property alias helpPopup: explanation
    readonly property bool engaged: hovered || visualFocus || explanation.visible
    text: "i"
    accessibleName: "Information"
    implicitWidth: 24
    controlHeight: 24
    iconSize: Metrics.panelIcon
    checked: explanation.visible
    ToolTip.text: helpText
    ToolTip.visible: (hovered || visualFocus) && !explanation.visible
    ToolTip.delay: hovered ? Metrics.tooltipDelay : 0
    onClicked: explanation.openFor(control)

    contentItem: Item {
        implicitWidth: control.iconSize
        implicitHeight: control.iconSize
        PentadIcon {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../assets/icons/pentad/info-symbolic.svg")
            pixelSize: control.iconSize
            color: control.engaged ? Theme.tokens.text : Qt.alpha(Theme.tokens.textMuted, 0.9)
            Accessible.ignored: true
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        }
    }
    background: Rectangle {
        radius: width / 2
        color: explanation.visible || control.down ? Theme.tokens.surfaceOverlay
            : control.hovered ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.tokens.accent
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }

    PentadPopup {
        id: explanation
        padding: 12
        implicitWidth: Math.min(280, control.Window.window ? control.Window.window.width - 24 : 280)
        contentItem: PentadText {
            text: control.helpText
            textFormat: Text.PlainText
            role: "caption"
            wrapMode: Text.Wrap
        }
    }
}
