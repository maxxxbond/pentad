pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import "../logic/spring.mjs" as SpringLogic

// The scrubber: a quiet tonal capsule (fully rounded, per the design contract) with a soft fill, a row of
// tick marks, the label on the left and the value on the right. A slim capsule rides the fill edge; at
// rest it is faint and small, under the pointer or a drag it springs to full size. Drawn from SmoothUI's
// Scrubber (MIT).
//   - The fill and the capsule follow the value with a 150 ms ease-out; a drag follows the pointer exactly.
//   - The capsule's size and opacity use one spring (0.25 s, a hint of bounce); reduced motion makes it instant.
//   - Arrow keys step, Home and End jump to the ends, the wheel steps, a click or drag sets the value.
//   - The capsule steps aside wherever it would touch the icon, the label, the value or the separator.
// By default a press sets the value under the pointer. With `relativeDrag` a press only grabs: the value
// moves with the pointer relative to the press, and a click that does not move sets the value under it,
// so touching a volume bar never jumps it.
// A row can reserve room at the start for an icon (`iconSource`) and at the end for an action the parent
// places there (`trailingSlot`, marked by a separator): the fill runs the whole capsule and passes under
// the slot, so 100 % is a full capsule, while pointer input stops at the separator.
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
    property string accessibleName: ""
    property string iconSource: ""
    property real trailingSlot: 0
    property bool relativeDrag: false
    // The capsule joins an open menu: the track takes the surface colour.
    property bool joined: false
    // A muted or unknown level is drawn in muted ink with a quiet fill.
    property bool muted: false
    property bool valueKnown: true
    // What the device last confirmed; a value it has not confirmed after a moment shows in muted ink.
    property real confirmedValue: NaN
    property real wheelStepSize: NaN
    signal moved(real value)

    readonly property int orientation: Qt.Horizontal
    readonly property real range: to - from
    readonly property real position: range > 0 ? Math.max(0, Math.min(1, (value - from) / range)) : 0
    readonly property real confirmedPosition: Number.isFinite(confirmedValue) && range > 0
        ? Math.max(0, Math.min(1, (confirmedValue - from) / range)) : NaN
    readonly property bool held: pointer.pressed
    // Held and moved (a plain press counts as moving unless `relativeDrag`); wheel steps count as steering too.
    readonly property bool grabbing: relativeDrag ? pointer.pressed && pointer.dragged : pointer.pressed
    property bool wheeling: false
    readonly property bool steering: grabbing || wheeling
    readonly property bool active: held || hover.hovered
    readonly property string shownValue: valueText !== "" ? valueText : value.toFixed(decimals)
    readonly property bool inkMuted: muted || !valueKnown
    readonly property color ink: inkMuted ? Theme.tokens.textMuted : Theme.tokens.text
    readonly property bool settling: valueKnown && !steering && Number.isFinite(confirmedPosition)
        && Math.abs(confirmedPosition - position) > 0.008
    property bool lagging: false
    onSettlingChanged: if (!settling) lagging = false
    property real wheelRemainder: 0
    property int wheelDirection: 0

    // Lengths run along the track from the start edge.
    readonly property real trackLength: availableWidth
    readonly property real separatorAt: trackLength - trailingSlot
    readonly property real span: trackLength - (trailingSlot > 0 ? trailingSlot + 4 : 0)
    readonly property real travel: Math.max(1, trackLength)
    // The icon sits in a square as wide as the bar is tall and the label starts 10 px after it, like the
    // round toggle of the button tiles beside it (Wi-Fi, Bluetooth), so the inside of the bar lines up with theirs.
    readonly property real leadingSlot: iconSource !== "" ? height : 0
    readonly property real labelStart: leadingSlot > 0 ? leadingSlot + 10 : Metrics.space4
    // The fill edge as a fraction of the track, 0..1; a drag follows the pointer exactly.
    property real shown: valueKnown ? position : 0
    readonly property real fillExtent: valueKnown ? shown * trackLength : 0
    readonly property bool separatorOnFill: trailingSlot > 0 && !inkMuted && fillExtent >= separatorAt + 4
    readonly property alias handle: thumb
    readonly property real thumbLevel: thumbSpring.value
    // The capsule sits 5 px inside the fill edge. Where it would touch the icon, the label or the value
    // it steps aside (a drag keeps it faintly visible), so the text is never cut by it; before the
    // separator it is gone at once, so it never meets the parent's action.
    readonly property real thumbCentre: fillExtent - 5
    readonly property real thumbMargin: Metrics.space1 + 2
    readonly property bool thumbOverText: (iconSource !== "" && thumbCentre + thumbMargin > iconBox.x
        && thumbCentre - thumbMargin < iconBox.x + iconBox.width)
        || (label !== "" && thumbCentre + thumbMargin > labelText.x
            && thumbCentre - thumbMargin < labelText.x + labelText.width)
        || (thumbCentre + thumbMargin > valueLabel.x && thumbCentre - thumbMargin < valueLabel.x + valueLabel.width)
    readonly property bool thumbOverSeparator: trailingSlot > 0 && thumbCentre + thumbMargin > separatorAt
    property real thumbClear: thumbOverText ? (grabbing ? 0.3 : 0) : 1
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
    Accessible.name: accessibleName !== "" ? accessibleName : label
    Accessible.description: valueKnown ? (muted ? label + " · " + shownValue : shownValue) : "Unknown"

    // A position along the whole range, 0..1.
    function setPosition(target) {
        setValue(from + Math.max(0, Math.min(1, target)) * range);
    }
    function setValue(next) {
        const step = Math.max(stepSize, 0.000001);
        const stepped = from + Math.round((next - from) / step) * step;
        const clamped = Math.max(from, Math.min(to, stepped));
        if (Math.abs(clamped - value) < 0.000001) return;
        value = clamped;
        moved(clamped);
    }
    // The last 8 px before the separator (or the capsule end) mean 100 %: the end of the fill lies under the action.
    function positionAt(x) {
        return x >= span - Metrics.space2 ? 1 : x / travel;
    }
    function handleWheel(event) {
        const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y / 40 : event.angleDelta.y / 120;
        if (!enabled) {
            event.accepted = false;
            return;
        }
        event.accepted = true;
        if (delta === 0) return;
        const direction = Math.sign(delta);
        if (wheelDirection !== 0 && direction !== wheelDirection) wheelRemainder = 0;
        wheelDirection = direction;
        wheelRemainder += delta;
        const ticks = Math.trunc(wheelRemainder);
        if (!ticks) return;
        wheelRemainder -= ticks;
        const step = Math.max(stepSize > 0 ? stepSize : range / 100, 0.000001);
        const increment = Math.max(Number.isFinite(wheelStepSize) && wheelStepSize > 0
            ? wheelStepSize : stepSize > 0 ? stepSize : range / 100, 0.000001);
        const next = Math.max(from, Math.min(to, from + Math.round((value - from + ticks * increment) / step) * step));
        if (Math.abs(next - value) > 0.000001) {
            wheeling = true;
            wheelRest.restart();
            value = next;
            moved(next);
        }
    }

    // The fill and the capsule glide to a new value; while dragging they are the pointer.
    Behavior on shown {
        enabled: !root.grabbing && !Motion.reducedMotion
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
    Timer {
        interval: 300
        running: root.settling && !root.lagging
        onTriggered: root.lagging = true
    }
    Timer {
        id: wheelRest
        interval: 400
        onTriggered: root.wheeling = false
    }

    background: Rectangle {
        id: track
        radius: height / 2
        color: root.joined ? Theme.tokens.surface : Theme.tokens.surfaceOverlay

        // The fill is the capsule itself, shown through a window as wide as the value, so a sliver
        // at 1 % follows the curve of the end instead of poking out of it.
        Item {
            width: root.fillExtent
            height: parent.height
            clip: true
            Rectangle {
                width: track.width
                height: track.height
                radius: track.radius
                color: Qt.alpha(Theme.tokens.text, root.muted ? 0.06 : 0.14)
            }
        }
        // Ticks stay between the icon and the separator, where they do not meet either.
        Repeater {
            model: root.ticks
            Rectangle {
                required property int index
                readonly property real centre: (index + 1) / (root.ticks + 1) * track.width
                visible: centre > root.leadingSlot + Metrics.space2
                    && (root.trailingSlot === 0 || centre < root.separatorAt - Metrics.space2)
                x: centre - width / 2
                y: (track.height - height) / 2
                width: 1
                height: 6
                radius: width / 2
                color: Qt.alpha(Theme.tokens.text, 0.25)
            }
        }
        Rectangle {
            visible: root.trailingSlot > 0
            x: root.separatorAt
            y: (track.height - height) / 2
            width: 1
            height: 20
            color: Qt.alpha(Theme.tokens.text, root.separatorOnFill ? 0.3 : 0.16)
        }
        // The capsule sits just inside the fill edge. Clipped by the track, it leaves at 0 %.
        Item {
            anchors.fill: parent
            clip: true
            Rectangle {
                id: thumb
                visible: root.valueKnown
                width: 4
                height: 22
                radius: width / 2
                x: root.thumbCentre - width / 2
                y: (track.height - height) / 2
                color: Qt.alpha(root.inkMuted ? Theme.tokens.textMuted : Theme.tokens.text, 0.9)
                opacity: root.thumbOverSeparator ? 0
                    : (0.15 + 0.65 * Math.max(0, Math.min(1, root.thumbLevel))) * root.thumbClear
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
        PentadIcon {
            id: iconBox
            visible: root.iconSource !== ""
            x: (root.leadingSlot - width) / 2
            y: (parent.height - height) / 2
            pixelSize: Metrics.menuIcon
            source: root.iconSource
            color: root.ink
            Accessible.ignored: true
        }
        Text {
            id: labelText
            x: root.labelStart
            width: Math.min(implicitWidth, Math.max(0, valueLabel.x - Metrics.space3 - x))
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.ink
            elide: Text.ElideRight
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.weight: Font.Medium
            Accessible.ignored: true
        }
        Text {
            id: valueLabel
            x: root.span - Metrics.space4 - width
            anchors.verticalCenter: parent.verticalCenter
            text: root.shownValue
            color: root.lagging && !root.inkMuted ? Theme.tokens.textMuted : root.ink
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
            Accessible.ignored: true
        }
    }

    MouseArea {
        id: pointer
        property real origin: 0
        property real originPosition: 0
        property bool dragged: false
        // The range up to the separator; the trailing slot belongs to the parent's action.
        width: root.trailingSlot > 0 ? root.span + 4 : root.width
        height: root.height
        enabled: root.enabled
        z: 1
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
            origin = mouse.x;
            originPosition = root.position;
            dragged = false;
            if (!root.relativeDrag) root.setPosition(root.positionAt(mouse.x));
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return;
            if (!root.relativeDrag) {
                root.setPosition(root.positionAt(mouse.x));
                return;
            }
            const delta = mouse.x - origin;
            if (!dragged && Math.abs(delta) < Application.styleHints.startDragDistance) return;
            dragged = true;
            root.setPosition(originPosition + delta / root.travel);
        }
        onReleased: function(mouse) {
            if (root.relativeDrag && !dragged) root.setPosition(root.positionAt(mouse.x));
            dragged = false;
        }
        onCanceled: dragged = false
    }
    HoverHandler {
        id: hover
        enabled: root.enabled
        onHoveredChanged: if (!hovered) {
            root.wheelRemainder = 0;
            root.wheelDirection = 0;
        }
    }
    WheelHandler {
        objectName: "rangeWheelHandler"
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        target: null
        onWheel: function(event) { root.handleWheel(event) }
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
