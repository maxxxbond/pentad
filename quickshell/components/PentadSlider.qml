import QtQuick
import QtQuick.Controls.Basic
import qs.theme

// One slider anatomy at three sizes. The track is a tonal capsule; the fill is the accent, clipped by
// the track's capsule so its leading edge is straight; the handle is a 4 px capsule bar on the fill's edge.
//   size: "large"   48 px capsule with icon, label and value inside (control center); can stand upright.
//   size: "regular" 16 px track, 28 px handle (settings, device rows); fill and rest stop 4 px short of it.
//   size: "thin"    4 px track, 12 px handle shown on hover, drag and keyboard focus (mixers, seek bars).
Slider {
    id: control
    property string accessibleName: ""
    property bool error: false
    // Deprecated inputs kept for existing callers: `referenceStyle` selects the large size, `thick`
    // alone the regular one. Setting `size` directly overrides both.
    property bool thick: false
    property bool referenceStyle: false
    property string size: referenceStyle ? "large" : "regular"
    readonly property bool large: size === "large"
    readonly property bool thin: size === "thin"
    readonly property bool plain: !large && !thin
    readonly property real plainGap: 4
    property bool joined: false
    property bool muted: false
    property real wheelStepSize: NaN
    property string iconSource: ""
    property bool valueKnown: true
    property string label: ""
    property string valueText: ""
    property real confirmedValue: NaN
    property real wheelRemainder: 0
    property int wheelDirection: 0
    readonly property real confirmedPosition: Number.isFinite(confirmedValue)
        ? Math.max(0, Math.min(1, (confirmedValue - from) / (to - from))) : NaN
    // The large capsule can stand up: it fills from the bottom, keeps the icon at the bottom and the value at the top.
    readonly property bool upright: large && orientation === Qt.Vertical
    // Lengths run along the axis: from the start edge (left, right when mirrored, bottom when upright).
    readonly property real trackLength: upright ? availableHeight : availableWidth
    // Room at the far end for an action the parent places there, such as the device chevron, marked by a
    // separator. The fill runs the whole capsule and passes under the slot, so 100 % is a full capsule;
    // pointer input stops at the separator, the handle fades before it, and the parent switches its action
    // to `onAccent` ink on `endOnFill`, once the fill passes the action's centre.
    property real trailingSlot: 0
    readonly property real separatorAt: trackLength - trailingSlot
    readonly property real span: trackLength - (trailingSlot > 0 ? trailingSlot + 4 : 0)
    readonly property bool separatorOnFill: trailingSlot > 0 && !inkMuted && fillExtent >= separatorAt + 4
    readonly property bool endOnFill: trailingSlot > 0 && !inkMuted && fillExtent >= trackLength - trailingSlot / 2
    // 0 % is an empty track: the fill grows from the start edge with nothing reserved for the icon.
    readonly property real fillMin: 0
    readonly property real travel: Math.max(1, trackLength)
    // Wheel, keyboard and external changes settle with a soft spring; a drag follows the pointer exactly.
    property real shownPosition: valueKnown ? position : 0
    Behavior on shownPosition {
        enabled: !Motion.reducedMotion && !control.grabbing
        SpringAnimation {
            spring: Motion.springSoft
            damping: Motion.springSoftDamping
            epsilon: 0.001
        }
    }
    readonly property real visualShown: mirrored && !upright ? 1 - shownPosition : shownPosition
    readonly property real fillExtent: valueKnown ? shownPosition * trackLength : 0
    // Ink inside the large capsule: icon slot, optional label, value column. Nothing moves with the value;
    // each ink is drawn twice and clipped at the fill edge, so it changes colour exactly where the fill ends.
    readonly property real iconSlot: 44
    readonly property real textGap: Metrics.space3
    readonly property real labelX: iconSlot + Metrics.space3
    readonly property real valueTextWidth: valueMetrics.advanceWidth(valueText)
    readonly property real valueWidth: Math.max(valueMetrics.advanceWidth("100%"), valueTextWidth)
    readonly property real valueLeft: span - Metrics.space4 - valueWidth
    readonly property real valueX: valueLeft
    readonly property real labelRoom: Math.max(0, valueLeft - textGap - labelX)
    // A label that does not fit whole is elided while a readable stub remains, and dropped below that.
    readonly property bool labelFits: label !== "" && !upright
        && labelRoom >= Math.min(labelMetrics.advanceWidth, Metrics.space6 + Metrics.space4)
    readonly property bool labelShown: labelFits
    readonly property real labelEnd: labelX + Math.min(labelMetrics.advanceWidth, labelRoom)
    readonly property bool labelOnFill: valueKnown && fillExtent > labelX
    readonly property bool valueOnFill: valueKnown && fillExtent > (upright ? trackLength - verticalValueY : valueLeft)
    readonly property real verticalValueY: availableHeight - span + Metrics.space4
    readonly property real valueY: verticalValueY
    // Ink on the accent fill is `onAccent` (`surface` on an error fill), on the bare track `text`;
    // a muted or unknown level is muted throughout.
    readonly property bool inkMuted: muted || !valueKnown
    readonly property color fillColor: joined ? Theme.tokens.surface : error ? Theme.tokens.error
        : muted ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.08)) : Theme.tokens.accent
    readonly property color fillInk: joined ? Theme.tokens.text : error ? Theme.tokens.surface : Theme.tokens.onAccent
    // The large handle sits flush inside the fill edge. It is quiet at rest, solid while held, and fades
    // out where the capsule rounds off and before the separator, so it never meets the parent's action.
    readonly property real stickWidth: 4
    readonly property real stickStart: fillExtent - stickWidth
    readonly property real stickTop: availableHeight - fillExtent
    property real stickLength: (large ? 20 : thin ? 12 : 28) + (held ? 4 : 0)
    Behavior on stickLength {
        enabled: !Motion.reducedMotion
        SpringAnimation {
            spring: Motion.springSnappy
            damping: Motion.springSnappyDamping
        }
    }
    readonly property real handleReveal: !large || !valueKnown ? 1
        : Math.max(0, Math.min(1, Math.min(stickStart - Metrics.space1,
            (trailingSlot > 0 ? separatorAt - Metrics.space2 : trackLength - Metrics.space1) - fillExtent) / Metrics.space2))
    // At rest the handle steps back where it would cut the icon, the label or the value: the two-toned ink
    // marks the level there. It returns under the pointer, while held and with keyboard focus.
    readonly property bool handleOverInk: large && valueKnown && [
        [(upright ? 24 : iconSlot / 2) - Metrics.menuIcon / 2, (upright ? 24 : iconSlot / 2) + Metrics.menuIcon / 2],
        labelShown ? [labelX, labelEnd] : [-1, -1],
        upright ? [availableHeight - valueY - valueMetrics.height, availableHeight - valueY]
            : [span - Metrics.space4 - valueTextWidth, span - Metrics.space4]
    ].some(function(box) { return box[1] > stickStart - 2 && box[0] < fillExtent + 2 })
    property real handleRoom: handleOverInk && !hovered && !held && !steering && !visualFocus ? 0 : 1
    Behavior on handleRoom { NumberAnimation { duration: Motion.state } }
    readonly property real handleShown: handleReveal * handleRoom
    // Glyphs keep 2 px clear of the handle on both sides while it shows.
    readonly property real inkBefore: (stickWidth + 2) * handleShown
    readonly property real inkAfter: 2 * handleShown
    // The thin handle shows on hover, drag and keyboard focus; the track opens around it as it appears.
    property real thinReveal: thin && enabled && (hovered || pressed || visualFocus) ? 1 : 0
    Behavior on thinReveal {
        enabled: !Motion.reducedMotion
        SpringAnimation {
            spring: Motion.springSnappy
            damping: Motion.springSnappyDamping
            epsilon: 0.01
        }
    }
    // Held from the press on; grabbing once the pointer has moved the value.
    readonly property bool held: large ? grip.pressed : pressed
    readonly property bool grabbing: large ? grip.pressed && grip.dragged : pressed
    // Wheel steps count as steering until the wheel has rested a moment, like a drag.
    property bool wheeling: false
    readonly property bool steering: grabbing || wheeling
    // A value the device has not confirmed after a moment shows in muted ink (large) or as a small marker
    // where the device is (regular, thin); while the user is still steering, a trailing device is expected.
    readonly property bool settling: valueKnown && !steering && Number.isFinite(confirmedPosition)
        && Math.abs(confirmedPosition - position) > 0.008
    property bool lagging: false
    onSettlingChanged: if (!settling) lagging = false
    implicitWidth: upright ? 64 : 180
    implicitHeight: upright ? 160 : large ? 48 : thin ? Metrics.controlSmall : Metrics.controlLarge
    padding: plain ? 6 : 0
    Accessible.name: accessibleName
    Accessible.description: valueKnown ? (muted ? label + " · " + valueText : valueText) : "Unknown"
    Accessible.role: Accessible.Slider
    function setPosition(target) {
        const step = Math.max(stepSize > 0 ? stepSize : (to - from) / 100, 0.000001)
        const raw = from + Math.max(0, Math.min(1, target)) * (to - from)
        const next = Math.max(from, Math.min(to, from + Math.round((raw - from) / step) * step))
        if (Math.abs(next - value) > 0.000001) {
            value = next
            moved()
        }
    }
    function handleWheel(event) {
        const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y / 40 : event.angleDelta.y / 120
        if (!enabled) {
            event.accepted = false
            return
        }
        event.accepted = true
        if (delta === 0) return
        const direction = Math.sign(delta)
        if (wheelDirection !== 0 && direction !== wheelDirection) wheelRemainder = 0
        wheelDirection = direction
        wheelRemainder += delta
        const ticks = Math.trunc(wheelRemainder)
        if (!ticks) return
        wheelRemainder -= ticks
        const step = Math.max(stepSize > 0 ? stepSize : (to - from) / 100, 0.000001)
        const increment = Math.max(Number.isFinite(wheelStepSize) && wheelStepSize > 0
            ? wheelStepSize : stepSize > 0 ? stepSize : (to - from) / 100, 0.000001)
        const next = Math.max(from, Math.min(to, from + Math.round((value - from + ticks * increment) / step) * step))
        if (Math.abs(next - value) > 0.000001) {
            wheeling = true
            wheelRest.restart()
            value = next
            moved()
        }
    }
    TextMetrics {
        id: labelMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
        text: control.label
    }
    FontMetrics {
        id: valueMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
    }
    Timer {
        interval: 300
        running: control.settling && !control.lagging
        onTriggered: control.lagging = true
    }
    Timer {
        id: wheelRest
        interval: 400
        onTriggered: control.wheeling = false
    }
    background: Item {
        id: track
        // Geometry below is computed from `control.mirrored`; children must not mirror it a second time.
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true
        x: control.leftPadding
        y: control.topPadding + (control.upright ? 0 : (control.availableHeight - height) / 2)
        width: control.availableWidth
        height: control.upright ? control.availableHeight : control.large ? control.availableHeight : control.thin ? 4 : 16
        opacity: !control.large && !control.enabled ? 0.4 : 1
        // The start-edge-anchored box of the given length along the axis, in track coordinates.
        function spanX(start, length) {
            return control.upright ? 0 : control.mirrored ? width - start - length : start
        }
        function spanY(start, length) {
            return control.upright ? height - start - length : 0
        }

        // Large: tonal capsule, clipped accent fill, separator, two-toned ink, keyboard focus ring.
        Rectangle {
            visible: control.large
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            color: control.joined ? Theme.tokens.surface : control.hovered && control.enabled
                ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, Metrics.stateHover)) : Theme.tokens.surfaceOverlay
            Behavior on color { ColorAnimation { duration: Motion.state } }
        }
        Clip {
            visible: control.large
            extent: control.fillExtent
            Rectangle {
                x: -parent.x
                y: -parent.y
                width: track.width
                height: track.height
                radius: Math.min(width, height) / 2
                color: control.fillColor
                Behavior on color { ColorAnimation { duration: Motion.state } }
            }
        }
        Rectangle {
            visible: control.large && control.trailingSlot > 0
            x: control.upright ? (parent.width - width) / 2 : parent.spanX(control.separatorAt, 1)
            y: control.upright ? control.trailingSlot - 1 : (parent.height - height) / 2
            width: control.upright ? 20 : 1
            height: control.upright ? 1 : 20
            color: control.separatorOnFill ? Qt.alpha(control.fillInk, 0.3) : Qt.alpha(Theme.tokens.text, 0.16)
        }
        Clip {
            visible: control.large
            extent: Math.max(0, control.fillExtent - control.inkBefore)
            Ink {
                fillSide: true
                x: -parent.x
                y: -parent.y
            }
        }
        Clip {
            visible: control.large
            start: Math.min(control.trackLength, control.fillExtent + control.inkAfter)
            extent: control.trackLength - start
            Ink {
                fillSide: false
                x: -parent.x
                y: -parent.y
            }
        }
        Rectangle {
            visible: control.large && control.visualFocus
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.tokens.accent
        }

        // Regular and thin: two segments that stop short of the handle.
        PlainTrack {
            visible: !control.large
            anchors.fill: parent
        }
        Rectangle {
            objectName: control.objectName ? control.objectName + "Confirmed" : ""
            readonly property bool besideFill: control.confirmedPosition < control.shownPosition
            visible: !control.large && control.lagging
            width: 4
            height: control.thin ? 8 : 6
            radius: width / 2
            x: (control.mirrored ? 1 - control.confirmedPosition : control.confirmedPosition)
                * (control.availableWidth - control.handle.width) + (control.handle.width - width) / 2
            y: (parent.height - height) / 2
            color: besideFill && !control.thin ? Qt.alpha(control.fillInk, 0.8) : Theme.tokens.textMuted
        }
    }
    handle: Rectangle {
        visible: !control.large || control.valueKnown
        x: control.leftPadding + (control.upright ? (control.availableWidth - width) / 2
            : control.large ? (control.mirrored ? control.trackLength - control.fillExtent : control.stickStart)
            : control.visualShown * (control.availableWidth - width))
        y: control.topPadding + (control.upright ? control.stickTop : (control.availableHeight - height) / 2)
        implicitWidth: control.upright ? control.stickLength : control.stickWidth
        implicitHeight: control.upright ? control.stickWidth : control.stickLength
        radius: Math.min(width, height) / 2
        opacity: control.large ? control.handleShown
            : (control.thin ? control.thinReveal : 1) * (control.enabled ? 1 : 0.4)
        color: control.large ? Qt.alpha(control.inkMuted ? Theme.tokens.textMuted : control.fillInk, control.held ? 1 : 0.7)
            : !control.valueKnown ? Theme.tokens.textMuted : control.error ? Theme.tokens.error : Theme.tokens.accent
        Behavior on color { ColorAnimation { duration: Motion.state } }
        // Keyboard focus only: a soft halo around the grip.
        Rectangle {
            visible: !control.large && control.visualFocus
            anchors.centerIn: parent
            width: parent.width + 8
            height: parent.height + 8
            radius: width / 2
            z: -1
            color: Qt.alpha(Theme.tokens.accent, 0.35)
        }
    }

    // A clip box along the axis, from `start` for `extent`, in track coordinates.
    component Clip: Item {
        property real start: 0
        property real extent: 0
        clip: true
        x: control.background.spanX(start, extent)
        y: control.background.spanY(start, extent)
        width: control.upright ? control.background.width : Math.max(0, extent)
        height: control.upright ? Math.max(0, extent) : control.background.height
    }

    component PlainTrack: Item {
        id: plainTrack
        // The grip's centre along the track; each segment stops short of it. The regular grip always
        // shows with `plainGap` on each side; the thin track closes up while its grip is hidden.
        readonly property real handleCentre: control.handle.x - control.leftPadding + control.handle.width / 2
        // With its grip hidden the thin track splits at the value itself, so 0 % and 100 % show no sliver.
        readonly property real gripCentre: control.thin
            ? control.visualShown * width + control.thinReveal * (handleCentre - control.visualShown * width)
            : handleCentre
        readonly property real half: control.thin ? control.thinReveal * (control.stickWidth / 2 + 2)
            : control.handle.width / 2 + control.plainGap
        readonly property real leftWidth: Math.max(0, gripCentre - half)
        readonly property real rightStart: Math.min(width, gripCentre + half)
        readonly property real innerRadius: control.thin ? Math.min(height / 2, half) : 2
        readonly property color fillColor: !control.valueKnown ? restColor : control.error ? Theme.tokens.error : Theme.tokens.accent
        // The thin track is a hairline, so its rest carries a little more ink to stay visible.
        readonly property real restAlpha: control.thin ? 0.18 : 0.11
        readonly property color restColor: Qt.alpha(Theme.tokens.text, control.hovered && control.enabled
            ? restAlpha + Metrics.stateHover : restAlpha)
        // The outer ends are full half circles; the ends at the grip stay nearly square.
        Rectangle {
            width: plainTrack.leftWidth
            height: parent.height
            topLeftRadius: Math.min(width, height) / 2
            bottomLeftRadius: topLeftRadius
            topRightRadius: Math.min(plainTrack.innerRadius, width / 2)
            bottomRightRadius: topRightRadius
            color: control.mirrored ? plainTrack.restColor : plainTrack.fillColor
        }
        Rectangle {
            x: plainTrack.rightStart
            width: parent.width - plainTrack.rightStart
            height: parent.height
            topRightRadius: Math.min(width, height) / 2
            bottomRightRadius: topRightRadius
            topLeftRadius: Math.min(plainTrack.innerRadius, width / 2)
            bottomLeftRadius: topLeftRadius
            color: control.mirrored ? plainTrack.fillColor : plainTrack.restColor
        }
    }

    // Icon, label and value of the large capsule, laid out over the whole track in one ink.
    component Ink: Item {
        id: ink
        property bool fillSide: false
        readonly property color strong: control.inkMuted ? Theme.tokens.textMuted : fillSide ? control.fillInk : Theme.tokens.text
        readonly property color valueInk: control.lagging && !control.inkMuted
            ? (fillSide ? Qt.alpha(control.fillInk, 0.6) : Theme.tokens.textMuted) : strong
        width: control.background.width
        height: control.background.height
        PentadIcon {
            x: control.upright ? (ink.width - width) / 2 : control.background.spanX((control.iconSlot - width) / 2, width)
            y: control.upright ? ink.height - 24 - height / 2 : (ink.height - height) / 2
            pixelSize: Metrics.menuIcon
            source: control.iconSource
            color: ink.strong
            Accessible.ignored: true
        }
        Text {
            visible: control.labelShown
            x: control.background.spanX(control.labelX, width)
            width: control.labelRoom
            anchors.verticalCenter: parent.verticalCenter
            text: control.label
            color: ink.strong
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
            elide: Text.ElideRight
            Accessible.ignored: true
        }
        Text {
            x: control.upright ? 0 : control.background.spanX(control.valueLeft, width)
            y: control.upright ? control.valueY : (ink.height - height) / 2
            width: control.upright ? ink.width : control.valueWidth
            text: control.valueText
            color: ink.valueInk
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.features: ({ "tnum": 1 })
            horizontalAlignment: control.upright ? Text.AlignHCenter : control.mirrored ? Text.AlignLeft : Text.AlignRight
            Accessible.ignored: true
        }
    }

    // The large capsule moves relative to the press, so grabbing it never jumps the value;
    // a press released without moving puts the fill edge under the pointer.
    MouseArea {
        id: grip
        property real origin: 0
        property real originPosition: 0
        property bool dragged: false
        function along(mouse) {
            return control.upright ? control.height - y - mouse.y
                : control.mirrored ? control.width - x - mouse.x : x + mouse.x
        }
        visible: control.large
        enabled: control.enabled && control.large
        // The range up to the separator; the trailing slot belongs to the parent's action.
        x: control.upright || !control.mirrored ? 0 : control.width - width
        y: control.upright ? control.height - height : 0
        width: control.upright ? control.width : control.span + 4
        height: control.upright ? control.span + 4 : control.height
        z: 1
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
            origin = along(mouse);
            originPosition = control.position;
            dragged = false;
        }
        onPositionChanged: function(mouse) {
            const delta = along(mouse) - origin;
            if (!dragged && Math.abs(delta) < Application.styleHints.startDragDistance) return;
            dragged = true;
            control.setPosition(originPosition + delta / control.travel);
        }
        onReleased: function(mouse) {
            // The last 8 px before the separator (or the capsule end) mean 100 %, since the end of the
            // fill lies under the action.
            const at = along(mouse);
            if (!dragged) control.setPosition(at >= control.span - Metrics.space2 ? 1 : at / control.travel);
            dragged = false;
        }
        onCanceled: dragged = false
    }

    HoverHandler {
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: if (!hovered) {
            control.wheelRemainder = 0
            control.wheelDirection = 0
        }
    }
    WheelHandler {
        objectName: "rangeWheelHandler"
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        target: null
        onWheel: function(event) { control.handleWheel(event) }
    }
}
