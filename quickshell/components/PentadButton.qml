import QtQuick
import QtQuick.Controls.Basic
import qs.theme

Button {
    id: control
    property string accessibleName: text
    property bool pending: false
    property bool error: false
    property bool requestedEnabled: true
    property int controlHeight: Metrics.controlMedium
    property url iconSource: ""
    property int iconSize: Metrics.statusIcon
    property string chevron: ""
    // Ink for the label, icon and chevron; a button that sits on an accent fill passes `onAccent`.
    property color ink: Theme.tokens.text
    // Resting fill; a button on a raised card passes the next elevation step so it stays visible.
    property color restFill: Theme.tokens.surfaceRaised
    readonly property bool customFill: restFill !== Theme.tokens.surfaceRaised
    readonly property bool glyph: iconSource.toString() !== "" || chevron !== ""
    enabled: requestedEnabled && !pending
    implicitHeight: controlHeight
    implicitWidth: Math.max(controlHeight, contentItem.implicitWidth + 24)
    Accessible.name: accessibleName
    Accessible.role: Accessible.Button
    Accessible.description: pending ? "In progress" : error ? "Error" : ""
    contentItem: Item {
        implicitWidth: control.glyph ? control.iconSize : label.implicitWidth
        implicitHeight: control.glyph ? control.iconSize : label.implicitHeight
        Text {
            id: label
            anchors.fill: parent
            visible: control.pending || !control.glyph
            text: control.pending ? "…" : control.text
            textFormat: Text.PlainText
            color: control.enabled ? (control.checked ? Theme.tokens.accent : control.ink) : Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        PentadIcon {
            anchors.centerIn: parent
            visible: !control.pending && control.iconSource.toString() !== ""
            source: control.iconSource
            pixelSize: control.iconSize
            color: control.enabled ? (control.checked ? Theme.tokens.accent : control.ink) : Theme.tokens.textMuted
            Accessible.ignored: true
        }
        PentadChevron {
            anchors.centerIn: parent
            visible: !control.pending && control.chevron !== ""
            direction: control.chevron === "" ? "right" : control.chevron
            engaged: control.hovered || control.activeFocus || control.down
            pixelSize: control.iconSize
            color: control.enabled ? control.ink : Theme.tokens.textMuted
        }
    }
    // Capsule by default (a square icon button becomes a circle); the focus edge appears
    // only when focus came from the keyboard.
    background: ContinuousSurface {
        fill: control.error ? Theme.tokens.error : control.down || control.checked || control.hovered
            ? (control.customFill ? Qt.tint(control.restFill, Qt.alpha(Theme.tokens.text, 0.08)) : Theme.tokens.surfaceOverlay)
            : control.restFill
        edge: control.visualFocus ? Theme.tokens.accent : "transparent"
        extent: height / 2
        opacity: control.enabled ? 1 : 0.55
        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state } }
    }
}
