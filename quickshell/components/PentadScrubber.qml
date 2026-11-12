pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// The scrubber: a quiet tonal capsule (fully rounded, per the design contract) with a soft fill, a row of tick marks, the label on the left and
// the value on the right. A slim capsule rides the fill edge; at rest it is faint and small, under
// the pointer or a drag it springs to full size. Drawn from SmoothUI's Scrubber (MIT).
//   - The fill and the capsule follow the value with a 150 ms ease-out; a drag follows the pointer exactly.
//   - The capsule's size and opacity use one spring (0.25 s, a hint of bounce); reduced motion makes it instant.
//   - Arrow keys step, Home and End jump to the ends, a click or drag sets the value under the pointer.
// The caller owns the value: bind `value` and write it back from moved().
Control {
    id: root
    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property int decimals: 2
    // Tick marks between the ends; 0 hides them.
    property int ticks: 9
    property string label: ""
    // Replaces the number on the right, for example "42%".
    property string valueText: ""
    signal moved(real value)

    readonly property real range: to - from
    readonly property real position: range > 0 ? Math.max(0, Math.min(1, (value - from) / range)) : 0
    readonly property bool dragging: pointer.pressed
    readonly property bool active: dragging || hover.hovered
    readonly property string shownValue: valueText !== "" ? valueText : value.toFixed(decimals)
    // The fill edge as a fraction of the track, 0..1.
    property real shown: position
    readonly property real thumbLevel: thumbSpring.value
    // The capsule sits 5 px inside the fill edge. Where it would touch the label or the value it steps
    // aside (a drag keeps it faintly visible), so the text is never cut by it.
    readonly property real thumbCentre: shown * track.width - 5
    readonly property real thumbMargin: Metrics.space1 + 2
    readonly property bool thumbOverText: (label !== "" && thumbCentre + thumbMargin > labelText.x
        && thumbCentre - thumbMargin < labelText.x + labelText.width)
        || (thumbCentre + thumbMargin > valueLabel.x && thumbCentre - thumbMargin < valueLabel.x + valueLabel.width)
    property real thumbClear: thumbOverText ? (dragging ? 0.3 : 0) : 1
    Behavior on thumbClear {
        NumberAnimation { duration: Motion.state }
    }
    readonly property real springStiffness: SpringLogic.scrubberSprings.thumb[0]
    readonly property real springDamping: SpringLogic.scrubberSprings.thumb[1]

    implicitWidth: 240
    implicitHeight: Metrics.space6 + Metrics.space1
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.4
    Accessible.role: Accessible.Slider
    Accessible.name: label
    Accessible.description: shownValue

    function setValue(next) {
        const step = Math.max(stepSize, 0.000001);
        const stepped = from + Math.round((next - from) / step) * step;
        const clamped = Math.max(from, Math.min(to, stepped));
        if (Math.abs(clamped - value) < 0.000001) return;
        value = clamped;
        moved(clamped);
    }
    function valueAt(x) {
        return from + Math.max(0, Math.min(1, x / Math.max(1, track.width))) * range;
    }

    // The fill and the capsule glide to a new value; while dragging they are the pointer.
    Behavior on shown {
        enabled: !root.dragging && !Motion.reducedMotion
        NumberAnimation {
            duration: 150
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
        }
    }

    PentadSpring {
        id: thumbSpring
        stiffness: root.springStiffness
        damping: root.springDamping
        value: 0
        target: root.active ? 1 : 0
    }
    // Runs only while the capsule moves; a scrubber at rest does no work.
    FrameAnimation {
        running: root.visible && !thumbSpring.settled
        onTriggered: thumbSpring.advance(frameTime)
    }

    background: Rectangle {
        id: track
        radius: height / 2
        color: Theme.tokens.surfaceOverlay

        Rectangle {
            width: root.shown * parent.width
            height: parent.height
            radius: parent.radius
            color: Qt.alpha(Theme.tokens.text, 0.14)
        }
        Repeater {
            model: root.ticks
            Rectangle {
                required property int index
                x: (index + 1) / (root.ticks + 1) * track.width - width / 2
                y: (track.height - height) / 2
                width: 1
                height: 6
                radius: width / 2
                color: Qt.alpha(Theme.tokens.text, 0.25)
            }
        }
        // The capsule sits just inside the fill edge. Clipped by the track, it leaves at 0 %.
        Item {
            anchors.fill: parent
            clip: true
            Rectangle {
                width: 4
                height: 22
                radius: width / 2
                x: root.shown * track.width - 5 - width / 2
                y: (track.height - height) / 2
                color: Qt.alpha(Theme.tokens.text, 0.9)
                opacity: (0.15 + 0.65 * Math.max(0, Math.min(1, root.thumbLevel))) * root.thumbClear
                scale: 0.7 + 0.3 * root.thumbLevel
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: root.visualFocus ? 2 : 0
            border.color: Theme.tokens.accent
        }
    }

    contentItem: Item {
        Text {
            id: labelText
            x: Metrics.space4
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.weight: Font.Medium
            Accessible.ignored: true
        }
        Text {
            id: valueLabel
            anchors.right: parent.right
            anchors.rightMargin: Metrics.space4
            anchors.verticalCenter: parent.verticalCenter
            text: root.shownValue
            color: Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
            Accessible.ignored: true
        }
    }

    // A press sets the value under the pointer and a drag keeps following it.
    MouseArea {
        id: pointer
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) { root.setValue(root.valueAt(mouse.x)) }
        onPositionChanged: function(mouse) { if (pressed) root.setValue(root.valueAt(mouse.x)) }
    }
    HoverHandler {
        id: hover
        enabled: root.enabled
    }

    Keys.onPressed: function(event) {
        const step = Math.max(stepSize, 0.000001);
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) setValue(value + step);
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) setValue(value - step);
        else if (event.key === Qt.Key_Home) setValue(from);
        else if (event.key === Qt.Key_End) setValue(to);
        else return;
        event.accepted = true;
    }
}
