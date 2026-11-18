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
//   - With `confirmedValue`, a level the device has not reached yet shows as a fainter band from the real
//     level to the asked one.
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
    // False for a coloured icon, such as an application's, which must not be tinted to the ink.
    property bool iconSymbolic: true
    // The icon is a button of its own, with a round halo on hover: a mute toggle, for example.
    property bool iconButton: false
    property bool iconButtonEnabled: true
    property string iconButtonName: ""
    property string iconButtonObjectName: ""
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
    signal iconPressed

    readonly property int orientation: Qt.Horizontal
    readonly property real range: to - from
    readonly property real position: range > 0 ? Math.max(0, Math.min(1, (value - from) / range)) : 0
    readonly property real confirmedPosition: Number.isFinite(confirmedValue) && range > 0
        ? Math.max(0, Math.min(1, (confirmedValue - from) / range)) : NaN
    readonly property bool held: pointer.pressed
    readonly property bool pressed: held
    // Held and moved (a plain press counts as moving unless `relativeDrag`); wheel steps count as steering too.
    readonly property bool grabbing: relativeDrag ? pointer.pressed && pointer.dragged : pointer.pressed
    property bool wheeling: false
    readonly property bool steering: grabbing || wheeling
    readonly property bool active: held || hover.hovered
    readonly property string shownValue: valueText !== "" ? valueText : value.toFixed(decimals)
    readonly property bool inkMuted: muted || !valueKnown
    // The fill is the accent; a muted level is a quiet tint, and a bar joined to an open menu merges with it.
    // Ink on the accent fill is `onAccent`, on the bare track `text`: each glyph is drawn twice and clipped
    // at the fill edge, so it changes colour exactly where the fill ends.
    readonly property color fillColor: joined ? Theme.tokens.surface
        : muted ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.08)) : Theme.tokens.accent
    readonly property color fillInk: joined ? Theme.tokens.text : Theme.tokens.onAccent
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
    // Asked and real level: the fill is full strength up to the level the device reports and fainter on to
    // the level asked for (or beyond it, while the device is ahead), so both show until the device catches
    // up. The real level glides like the fill. While the user steers and for the moment after, a trailing
    // device is expected, so the fill stays solid to the asked level: the band only marks a real lag.
    readonly property bool showsReal: valueKnown && !inkMuted && lagging && Number.isFinite(confirmedPosition)
    property real confirmedShown: Number.isFinite(confirmedPosition) ? confirmedPosition : position
    Behavior on confirmedShown {
        enabled: !Motion.reducedMotion
        NumberAnimation {
            duration: Motion.glideDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
        }
    }
    readonly property real confirmedExtent: showsReal ? confirmedShown * trackLength : fillExtent
    readonly property real solidExtent: Math.min(fillExtent, confirmedExtent)
    readonly property real bandExtent: Math.max(fillExtent, confirmedExtent)
    readonly property bool separatorOnFill: trailingSlot > 0 && !inkMuted && fillExtent >= separatorAt + 4
    // Once the fill passes the action's centre the parent switches that action to `onAccent` ink.
    readonly property bool endOnFill: trailingSlot > 0 && !inkMuted && !joined && fillExtent >= trackLength - trailingSlot / 2
    readonly property alias handle: thumb
    readonly property real thumbLevel: thumbSpring.value
    // The capsule sits 5 px inside the fill edge. Where it would touch the icon, the label or the value
    // it steps aside (a drag keeps it faintly visible), so the text is never cut by it; before the
    // separator it is gone at once, so it never meets the parent's action.
    readonly property real thumbCentre: fillExtent - 5
    readonly property real thumbMargin: Metrics.space1 + 2
    readonly property bool thumbOverText: (iconSource !== "" && thumbCentre + thumbMargin > baseInk.iconItem.x
        && thumbCentre - thumbMargin < baseInk.iconItem.x + baseInk.iconItem.width)
        || (label !== "" && thumbCentre + thumbMargin > baseInk.labelItem.x
            && thumbCentre - thumbMargin < baseInk.labelItem.x + baseInk.labelItem.width)
        || (thumbCentre + thumbMargin > baseInk.valueItem.x
            && thumbCentre - thumbMargin < baseInk.valueItem.x + baseInk.valueItem.width)
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
            duration: Motion.glideDuration
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
        // at 1 % follows the curve of the end instead of poking out of it. The band between the real
        // and the asked level is a second, fainter window right after it.
        Item {
            width: root.solidExtent
            height: parent.height
            clip: true
            Rectangle {
                width: track.width
                height: track.height
                radius: track.radius
                color: root.fillColor
                Behavior on color {
                    ColorAnimation { duration: Motion.state }
                }
            }
        }
        Item {
            objectName: "scrubberAskedBand"
            visible: root.bandExtent > root.solidExtent + 0.5
            x: root.solidExtent
            width: root.bandExtent - root.solidExtent
            height: parent.height
            clip: true
            Rectangle {
                x: -root.solidExtent
                width: track.width
                height: track.height
                radius: track.radius
                color: Qt.alpha(Theme.tokens.text, 0.06)
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
                color: centre < root.fillExtent && !root.muted ? Qt.alpha(root.fillInk, 0.35) : Qt.alpha(Theme.tokens.text, 0.25)
            }
        }
        Rectangle {
            visible: root.trailingSlot > 0
            x: root.separatorAt
            y: (track.height - height) / 2
            width: 1
            height: 20
            color: root.separatorOnFill ? Qt.alpha(root.fillInk, 0.3) : Qt.alpha(Theme.tokens.text, 0.16)
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
                color: Qt.alpha(root.inkMuted ? Theme.tokens.textMuted : root.fillInk, 0.9)
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
        Ink {
            id: baseInk
            anchors.fill: parent
        }
        // The same glyphs again in the ink for the fill, seen only over the fill.
        Item {
            width: root.fillExtent
            height: parent.height
            clip: true
            Ink {
                width: root.trackLength
                height: parent.height
                onFill: true
            }
        }
    }

    // Icon, label and value laid out over the whole track in one ink.
    component Ink: Item {
        id: ink
        property bool onFill: false
        readonly property alias iconItem: iconGlyph
        readonly property alias labelItem: labelGlyph
        readonly property alias valueItem: valueGlyph
        readonly property color strong: root.inkMuted ? Theme.tokens.textMuted
            : onFill ? root.fillInk : Theme.tokens.text
        readonly property color valueInk: root.lagging && !root.inkMuted
            ? (onFill ? Qt.alpha(root.fillInk, 0.6) : Theme.tokens.textMuted) : strong
        PentadIcon {
            id: iconGlyph
            visible: root.iconSource !== ""
            x: (root.leadingSlot - width) / 2
            y: (parent.height - height) / 2
            pixelSize: Metrics.menuIcon
            source: root.iconSource
            symbolic: root.iconSymbolic
            opacity: root.iconSymbolic || !root.inkMuted ? 1 : 0.5
            color: ink.strong
            Accessible.ignored: true
        }
        Text {
            id: labelGlyph
            x: root.labelStart
            width: Math.min(implicitWidth, Math.max(0, valueGlyph.x - Metrics.space3 - x))
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: ink.strong
            elide: Text.ElideRight
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.weight: Font.Medium
            Accessible.ignored: true
        }
        Text {
            id: valueGlyph
            x: root.span - Metrics.space4 - width
            anchors.verticalCenter: parent.verticalCenter
            text: root.shownValue
            color: ink.valueInk
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
    Button {
        id: iconPad
        objectName: root.iconButtonObjectName
        visible: root.iconButton && root.iconSource !== ""
        enabled: root.enabled && root.iconButtonEnabled
        width: root.leadingSlot
        height: root.height
        z: 2
        Accessible.name: root.iconButtonName
        onPressed: root.iconPressed()
        // A round halo around the icon says it is a button of its own, on the fill and the track alike.
        background: Item {
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(40, iconPad.height - 4)
                height: width
                radius: width / 2
                color: Qt.alpha(Theme.tokens.text, iconPad.pressed ? 0.22 : 0.14)
                opacity: iconPad.enabled && (iconPad.hovered || iconPad.pressed) ? 1 : 0
                border.width: iconPad.visualFocus ? 2 : 0
                border.color: Theme.tokens.accent
                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.state
                    }
                }
            }
        }
        contentItem: Item {}
        HoverHandler {
            cursorShape: iconPad.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
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
