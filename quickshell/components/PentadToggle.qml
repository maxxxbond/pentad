import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// The knob stretches as it travels, then rounds up and bounces on arrival while the track fills
// with the accent. Two springs drive it (position and stretch), with the toggle-switch motion
// study's values; with reduced motion the knob jumps and nothing stretches.
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

    // 0 = off, 1 = on, overshooting on landing. While a finger drags the knob it follows
    // visualPosition and the spring takes over from there on release.
    readonly property real travel: Math.min(1, Math.max(0, positionSpring.value))
    readonly property real stretch: Math.min(1, Math.max(0, stretchSpring.value)) * 8
    property bool springReady: false
    Component.onCompleted: {
        positionSpring.target = checked ? 1 : 0;
        positionSpring.snap();
        springReady = true;
    }
    onCheckedChanged: {
        if (!springReady) return;
        positionSpring.target = checked ? 1 : 0;
        stretchSpring.target = 0;
        stretchSpring.push(SpringLogic.toggleStretchKick);
    }
    onVisualPositionChanged: if (down && springReady) positionSpring.jump(mirrored ? 1 - visualPosition : visualPosition)
    PentadSpring {
        id: positionSpring
        stiffness: SpringLogic.toggleSprings.position[0]
        damping: SpringLogic.toggleSprings.position[1]
    }
    PentadSpring {
        id: stretchSpring
        stiffness: SpringLogic.toggleSprings.stretch[0]
        damping: SpringLogic.toggleSprings.stretch[1]
    }
    FrameAnimation {
        running: control.visible && !(positionSpring.settled && stretchSpring.settled)
        onTriggered: {
            positionSpring.advance(frameTime);
            stretchSpring.advance(frameTime);
        }
    }

    indicator: Rectangle {
        id: track
        x: control.mirrored ? control.width - width : 0
        y: (control.height - height) / 2
        width: 44
        height: 26
        radius: height / 2
        color: control.error ? Qt.alpha(Theme.tokens.error, 0.15)
            : Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.accent, control.travel))
        // Borderless at rest; only the error state draws a softened status edge.
        border.width: control.error ? 1 : 0
        border.color: Qt.alpha(Theme.tokens.error, 0.7)
        opacity: control.enabled || control.pending ? 1 : 0.4
        Rectangle {
            id: thumb
            // The edge in front leads: when switching on, the knob's left edge is pulled back
            // by the stretch while the right edge runs ahead (and the mirror when switching off).
            readonly property real logicalX: 3 + positionSpring.value * (track.width - 26) - (control.checked ? control.stretch * control.travel : 0)
            x: control.mirrored ? track.width - logicalX - width : logicalX
            y: (track.height - height) / 2
            width: 20 + control.stretch
            height: 20
            radius: height / 2
            color: Qt.tint(Theme.tokens.textMuted, Qt.alpha(Theme.tokens.onAccent, control.travel))
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
