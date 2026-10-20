import QtQuick
import QtQuick.Controls.Basic
import qs.theme

Switch {
    id: control
    property string accessibleName: text
    property bool pending: false
    property bool error: false
    property bool requestedEnabled: true
    enabled: requestedEnabled && !pending
    implicitHeight: 36
    implicitWidth: Math.max(indicator.width, contentItem.implicitWidth)
    padding: 0
    spacing: 10
    Accessible.name: accessibleName
    Accessible.role: Accessible.CheckBox
    Accessible.checked: checked
    Accessible.description: pending ? "In progress" : error ? "Error" : ""
    indicator: Rectangle {
        id: track
        x: control.mirrored ? control.width - width : 0
        y: (control.height - height) / 2
        width: 44
        height: 26
        radius: height / 2
        color: control.error ? Qt.alpha(Theme.tokens.error, 0.15)
            : control.checked ? Theme.tokens.accent : Theme.tokens.surfaceOverlay
        // Borderless at rest; only the error state draws a softened status edge.
        border.width: control.error ? 1 : 0
        border.color: Qt.alpha(Theme.tokens.error, 0.7)
        opacity: control.enabled || control.pending ? 1 : 0.4
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        Rectangle {
            id: thumb
            x: 3 + control.visualPosition * (track.width - width - 6)
            y: (track.height - height) / 2
            width: control.down ? 24 : 20
            height: 20
            radius: height / 2
            color: control.checked ? Theme.tokens.onAccent : Theme.tokens.textMuted
            Behavior on x { enabled: !control.down && !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
            BusyIndicator {
                anchors.centerIn: parent
                width: 16
                height: 16
                running: control.pending
                visible: running
                palette.dark: control.checked ? Theme.tokens.accent : Theme.tokens.surface
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: height / 2
            color: "transparent"
            border.width: control.visualFocus ? 2 : 0
            border.color: Theme.tokens.accent
        }
    }
    contentItem: Text {
        leftPadding: control.text && !control.mirrored ? control.indicator.width + control.spacing : 0
        rightPadding: control.text && control.mirrored ? control.indicator.width + control.spacing : 0
        text: control.text
        color: control.enabled ? Theme.tokens.text : Theme.tokens.textMuted
        font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
        verticalAlignment: Text.AlignVCenter
    }
}
