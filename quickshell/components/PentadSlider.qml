import QtQuick
import QtQuick.Controls.Basic
import qs.theme

Slider {
    id: control
    property string accessibleName: ""
    property bool error: false
    property bool thick: false
    property bool referenceStyle: false
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
    // The reference capsule can stand up: it fills from the bottom, keeps the icon at the bottom
    // and the value at the top.
    readonly property bool upright: referenceStyle && orientation === Qt.Vertical
    // Room at the far end (right, or top when upright) for an action the parent places there, such as
    // the device chevron. A separator marks it. The fill runs the whole capsule and passes under the
    // slot near the top, so 100 % is a full capsule; pointer input stops at the separator, and the parent
    // switches its action to `onAccent` ink on `endOnFill`, once the fill end passes the action's centre.
    property real trailingSlot: 0
    readonly property real separatorAt: trackLength - trailingSlot
    readonly property bool separatorOnFill: trailingSlot > 0 && !inkMuted && fillExtent >= separatorAt + 4
    readonly property bool endOnFill: trailingSlot > 0 && !inkMuted && fillExtent >= trackLength - trailingSlot / 2
    // Horizontal capsule: icon slot, optional label, value column. The label is dropped, not elided,
    // when it does not fit; the icon and the value are enough.
    readonly property real iconSlot: 44
    readonly property real labelX: 56
    readonly property real valueWidth: 40
    readonly property real valueLeft: span - 16 - valueWidth
    readonly property real labelRoom: Math.max(0, valueLeft - textGap - labelX)
    readonly property bool labelFits: label !== "" && labelMetrics.advanceWidth <= labelRoom
    readonly property real verticalValueY: availableHeight - span + 16
    // Reference capsule: the fill is a capsule of its own that never gets shorter than the icon end,
    // and the grip is a quiet stick 12 px inside the fill end that hides only by a trailing slot. Lengths run along the
    // axis: from the left, or from the bottom when upright.
    readonly property real trackLength: upright ? availableHeight : availableWidth
    readonly property real span: trackLength - (trailingSlot > 0 ? trailingSlot + 4 : 0)
    readonly property real fillMin: Math.max(56, upright ? availableWidth : availableHeight)
    readonly property real travel: Math.max(1, trackLength - fillMin)
    property real shownPosition: valueKnown ? position : 0
    Behavior on shownPosition {
        enabled: control.referenceStyle && !control.grabbing
        NumberAnimation { duration: Motion.state }
    }
    readonly property real fillExtent: valueKnown ? fillMin + shownPosition * travel : 0
    readonly property real stickWidth: 3
    readonly property real stickStart: fillExtent - 12 - stickWidth
    readonly property real stickTop: availableHeight - stickStart - stickWidth
    // No text comes closer than `textGap` to the stick: the value hops to the stick's near side once
    // the stick reaches it, and the label steps aside while the stick or the value covers it. In a
    // short capsule the near side may have no room past the icon; the value then rides on the track,
    // 8 px clear of the fill end, instead of covering the icon.
    readonly property real textGap: 12
    readonly property real labelEnd: labelX + labelMetrics.advanceWidth
    readonly property bool labelOnFill: valueKnown && labelX < stickStart
    readonly property real valueTextWidth: Math.min(valueWidth, valueMetrics.advanceWidth(valueText))
    readonly property bool stickAtValue: valueKnown && stickStart + stickWidth + textGap > valueLeft
    readonly property bool valueBeforeStick: stickAtValue && stickStart - textGap - valueTextWidth >= iconSlot
    readonly property real valueX: valueBeforeStick ? Math.min(stickStart - textGap - valueWidth, valueLeft)
        : stickAtValue ? fillExtent + 8 - (valueWidth - valueTextWidth) : valueLeft
    readonly property bool labelShown: labelFits && (!valueKnown
        || (!(stickStart + stickWidth + textGap > labelX && stickStart - textGap < labelEnd) && labelEnd + textGap <= valueX))
    readonly property bool valueBelowStick: upright && valueKnown && verticalValueY < stickTop + stickWidth + textGap
        && verticalValueY + valueMetrics.height > stickTop - textGap
    readonly property real valueY: valueBelowStick ? Math.max(stickTop + stickWidth + textGap, verticalValueY) : verticalValueY
    readonly property bool valueOnFill: upright ? valueBelowStick : valueBeforeStick
    // Ink on the accent fill is `onAccent`, on the bare track `text`; a muted or unknown level is muted throughout.
    readonly property bool inkMuted: muted || !valueKnown
    property real stickLength: grabbing ? 24 : 20
    Behavior on stickLength { NumberAnimation { duration: Motion.state } }
    readonly property bool grabbing: grip.pressed && grip.dragged
    // Wheel steps count as steering until the wheel has rested a moment, like a drag.
    property bool wheeling: false
    // A value the device has not confirmed after a moment shows in muted ink, without a second marker;
    // while the user is still steering, a device that trails behind is expected, not lagging.
    readonly property bool settling: referenceStyle && valueKnown && !grabbing && !wheeling && Number.isFinite(confirmedPosition)
        && Math.abs(confirmedPosition - position) > 0.008
    property bool lagging: false
    onSettlingChanged: if (!settling) lagging = false
    implicitWidth: upright ? 64 : 180
    implicitHeight: upright ? 160 : referenceStyle ? 48 : thick ? 40 : Metrics.controlLarge
    padding: referenceStyle ? 0 : 6
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
        x: control.leftPadding
        y: control.topPadding + (control.upright ? 0 : (control.availableHeight - height) / 2)
        width: control.availableWidth
        id: track
        height: control.upright ? control.availableHeight : control.referenceStyle ? 48 : control.thick ? 32 : 6
        readonly property real fillWidth: control.valueKnown ? control.visualPosition * width : 0
        Rectangle {
            anchors.fill: parent
            radius: control.referenceStyle ? Math.min(width, height) / 2 : control.thick ? 8 : 3
            color: control.joined ? Theme.tokens.surface : control.referenceStyle
                ? (control.hovered && control.enabled ? Qt.lighter(Theme.tokens.surfaceOverlay, 1.15) : Theme.tokens.surfaceOverlay) : control.thick ? Theme.tokens.surfaceRaised : Theme.tokens.outline
        }
        Rectangle {
            y: control.upright ? parent.height - height : 0
            width: control.upright ? parent.width : control.referenceStyle ? control.fillExtent : track.fillWidth
            height: control.upright ? control.fillExtent : parent.height
            // The reference fill keeps the track's radius, so its end is always a full half circle.
            radius: control.referenceStyle ? Math.min(track.width, track.height) / 2 : control.thick ? 8 : 3
            color: control.joined ? Theme.tokens.surface : control.error ? Theme.tokens.error : control.referenceStyle
                ? (control.muted ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.08)) : Theme.tokens.accent)
                : control.thick ? Theme.tokens.surfaceOverlay : Theme.tokens.accent
        }
        Rectangle {
            visible: control.referenceStyle && control.trailingSlot > 0
            x: control.upright ? (parent.width - width) / 2 : parent.width - control.trailingSlot
            y: control.upright ? control.trailingSlot - 1 : (parent.height - height) / 2
            width: control.upright ? 20 : 1
            height: control.upright ? 1 : 20
            color: control.separatorOnFill ? Qt.alpha(Theme.tokens.onAccent, 0.3) : Qt.alpha(Theme.tokens.text, 0.16)
        }
        RangeInk {
            visible: control.referenceStyle && !control.upright
            anchors.fill: parent
        }
        VerticalInk {
            visible: control.upright
            anchors.fill: parent
        }
        Rectangle {
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            color: "transparent"
            border.width: control.referenceStyle && control.activeFocus ? 2 : 0
            border.color: Theme.tokens.accent
        }
        Rectangle {
            objectName: control.objectName ? control.objectName + "Confirmed" : ""
            visible: control.thick && !control.referenceStyle && control.valueKnown && Number.isFinite(control.confirmedPosition)
                && Math.abs(control.confirmedPosition - control.position) > 0.008
            width: 4
            height: Math.min(parent.height - 8, 20)
            radius: 2
            x: (control.mirrored ? 1 - control.confirmedPosition : control.confirmedPosition)
                * (control.availableWidth - control.handle.width) + (control.handle.width - width) / 2
            y: (parent.height - height) / 2
            color: Theme.tokens.surfaceRaised
            border.width: 1
            border.color: Theme.tokens.textMuted
        }
        Text {
            visible: control.thick && !control.referenceStyle && control.label !== ""
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: valueLabel.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: control.label
            color: control.valueKnown ? Theme.tokens.text : Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textCaption
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Text {
            id: valueLabel
            visible: control.thick && !control.referenceStyle && control.valueText !== ""
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            text: control.valueText
            color: control.valueKnown ? Theme.tokens.text : Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textCaption
            font.features: ({ "tnum": 1 })
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    }
    handle: Rectangle {
        visible: !control.referenceStyle || control.valueKnown
        x: control.leftPadding + (control.upright ? (control.availableWidth - width) / 2
            : control.referenceStyle ? control.stickStart
            : control.visualPosition * (control.availableWidth - width))
        y: control.topPadding + (control.upright ? control.stickTop : (control.availableHeight - height) / 2)
        implicitWidth: control.upright ? control.stickLength : control.referenceStyle ? control.stickWidth : control.thick ? 8 : 18
        implicitHeight: control.upright ? control.stickWidth : control.referenceStyle ? control.stickLength : control.thick ? 40 : 18
        radius: control.referenceStyle ? control.stickWidth / 2 : 4
        scale: control.thick && control.pressed ? 1.12 : 1
        // The grip fades out over the last 8 px before the separator, so it never meets the action.
        opacity: control.trailingSlot > 0 ? Math.max(0, Math.min(1, (control.separatorAt - control.stickStart - control.stickWidth) / 8)) : 1
        // Quiet at rest, solid while held.
        color: control.referenceStyle ? Qt.alpha(control.muted ? Theme.tokens.textMuted : Theme.tokens.onAccent, control.grabbing ? 1 : 0.7)
            : control.thick && control.pressed ? Theme.tokens.accent : Theme.tokens.text
        border.width: control.referenceStyle ? 0 : control.thick ? (control.activeFocus || control.hovered || control.pressed ? 2 : 0) : 2
        border.color: control.activeFocus ? Theme.tokens.accent : Theme.tokens.surface
        Behavior on scale { NumberAnimation { duration: Motion.state } }
        Behavior on color { ColorAnimation { duration: Motion.state } }
    }

    component RangeInk: Item {
        PentadIcon {
            x: (control.iconSlot - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            pixelSize: Metrics.menuIcon
            source: control.iconSource
            color: control.inkMuted ? Theme.tokens.textMuted : Theme.tokens.onAccent
            Accessible.ignored: true
        }
        Text {
            x: control.labelX
            visible: control.labelFits
            opacity: control.labelShown ? 1 : 0
            width: control.labelRoom
            anchors.verticalCenter: parent.verticalCenter
            text: control.label
            color: control.inkMuted ? Theme.tokens.textMuted : control.labelOnFill ? Theme.tokens.onAccent : Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            elide: Text.ElideRight
            Behavior on opacity { NumberAnimation { duration: Motion.state } }
        }
        Text {
            x: control.valueX
            anchors.verticalCenter: parent.verticalCenter
            width: control.valueWidth
            text: control.valueText
            color: control.inkMuted || control.lagging ? Theme.tokens.textMuted
                : control.valueOnFill ? Theme.tokens.onAccent : Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.features: ({ "tnum": 1 })
            horizontalAlignment: Text.AlignRight
        }
    }

    component VerticalInk: Item {
        Text {
            y: control.valueY
            width: parent.width
            text: control.valueText
            color: control.inkMuted || control.lagging ? Theme.tokens.textMuted
                : control.valueOnFill ? Theme.tokens.onAccent : Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.features: ({ "tnum": 1 })
            horizontalAlignment: Text.AlignHCenter
        }
        PentadIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 24 - height / 2
            pixelSize: Metrics.menuIcon
            source: control.iconSource
            color: control.inkMuted ? Theme.tokens.textMuted : Theme.tokens.onAccent
            Accessible.ignored: true
        }
    }

    // The reference capsule moves relative to the press, so grabbing it never jumps the value;
    // a press released without moving still sets the value under the pointer.
    MouseArea {
        id: grip
        property real origin: 0
        property real originPosition: 0
        property bool dragged: false
        function along(mouse) { return control.upright ? control.height - y - mouse.y : mouse.x; }
        visible: control.referenceStyle
        enabled: control.enabled
        // The range up to the separator; the trailing slot belongs to the parent's action.
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
            // The stick centre lands under the pointer; the last 12 px before the separator mean 100 %,
            // since the top of the fill lies under the action.
            if (!dragged) control.setPosition(control.trailingSlot > 0 && along(mouse) >= control.span - 8 ? 1
                : (along(mouse) + 12 + control.stickWidth / 2 - control.fillMin) / control.travel);
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
