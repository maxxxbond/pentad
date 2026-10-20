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
    property real trailingInset: 0
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
    // and the value at the top, and `trailingInset` reserves room at the top instead of the right.
    readonly property bool upright: referenceStyle && orientation === Qt.Vertical
    // Horizontal capsule: icon slot, optional label, value column. The label is dropped, not elided,
    // when it does not fit; the icon and the value are enough.
    readonly property real iconSlot: 44
    readonly property real valueWidth: 40
    readonly property real valueLeft: width - 16 - trailingInset - valueWidth
    readonly property real labelRoom: Math.max(0, valueLeft - 8 - 48)
    readonly property bool labelFits: label !== "" && labelMetrics.advanceWidth <= labelRoom
    readonly property real verticalValueY: trailingInset > 0 ? trailingInset + 2 : 16
    implicitWidth: upright ? 64 : 180
    implicitHeight: upright ? 160 : referenceStyle ? 48 : thick ? 40 : Metrics.controlLarge
    padding: referenceStyle ? 0 : 6
    Accessible.name: accessibleName
    Accessible.description: valueKnown ? (muted ? label + " · " + valueText : valueText) : "Unknown"
    Accessible.role: Accessible.Slider
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
    background: Item {
        x: control.leftPadding
        y: control.topPadding + (control.upright ? 0 : (control.availableHeight - height) / 2)
        width: control.availableWidth
        id: track
        height: control.upright ? control.availableHeight : control.referenceStyle ? 48 : control.thick ? 32 : 6
        readonly property real fillWidth: control.valueKnown ? control.visualPosition * width : 0
        readonly property real fillHeight: control.valueKnown ? control.position * height : 0
        Rectangle {
            anchors.fill: parent
            radius: control.referenceStyle ? Math.min(width, height) / 2 : control.thick ? 8 : 3
            color: control.joined ? Theme.tokens.surface : control.referenceStyle
                ? (control.hovered && control.enabled ? Qt.lighter(Theme.tokens.surfaceOverlay, 1.15) : Theme.tokens.surfaceOverlay) : control.thick ? Theme.tokens.surfaceRaised : Theme.tokens.outline
        }
        Rectangle {
            y: control.upright ? parent.height - height : 0
            width: control.upright ? parent.width : track.fillWidth
            height: control.upright ? track.fillHeight : parent.height
            radius: control.referenceStyle ? Math.min(width, height) / 2 : control.thick ? 8 : 3
            color: control.joined ? Theme.tokens.surface : control.error ? Theme.tokens.error : control.referenceStyle
                ? (control.muted ? Theme.tokens.outline : Theme.tokens.accent)
                : control.thick ? Theme.tokens.surfaceOverlay : Theme.tokens.accent
        }
        RangeInk {
            visible: control.referenceStyle && !control.upright
            anchors.fill: parent
            ink: control.valueKnown ? Theme.tokens.text : Theme.tokens.textMuted
        }
        Item {
            visible: control.referenceStyle && !control.upright
            width: track.fillWidth
            height: parent.height
            clip: true
            RangeInk {
                width: track.width
                height: track.height
                ink: control.muted ? Theme.tokens.textMuted : Theme.tokens.onAccent
            }
        }
        VerticalInk {
            visible: control.upright
            anchors.fill: parent
            ink: control.valueKnown ? Theme.tokens.text : Theme.tokens.textMuted
        }
        Item {
            visible: control.upright
            y: parent.height - height
            width: parent.width
            height: track.fillHeight
            clip: true
            VerticalInk {
                y: track.fillHeight - track.height
                width: track.width
                height: track.height
                ink: control.muted ? Theme.tokens.textMuted : Theme.tokens.onAccent
            }
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
            visible: control.thick && control.valueKnown && Number.isFinite(control.confirmedPosition)
                && Math.abs(control.confirmedPosition - control.position) > 0.008
            width: control.upright ? Math.min(parent.width - 8, 20) : 4
            height: control.upright ? 4 : Math.min(parent.height - 8, 20)
            radius: 2
            x: control.upright ? (parent.width - width) / 2 : control.referenceStyle
                ? Math.max(12, Math.min(control.availableWidth - width - 12,
                    (control.mirrored ? 1 - control.confirmedPosition : control.confirmedPosition) * control.availableWidth - width - 12))
                : (control.mirrored ? 1 - control.confirmedPosition : control.confirmedPosition)
                    * (control.availableWidth - control.handle.width) + (control.handle.width - width) / 2
            y: control.upright
                ? Math.max(12, Math.min(parent.height - height - 12, (1 - control.confirmedPosition) * parent.height + 12))
                : (parent.height - height) / 2
            color: control.referenceStyle ? Theme.tokens.textMuted : Theme.tokens.surfaceRaised
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
        // Shown only where it does not cover the icon, label or value.
        visible: !control.referenceStyle || (!control.muted && (control.upright
            ? y >= control.verticalValueY + 26 && y + height <= control.availableHeight - 48
            : x >= 48 + (control.labelFits ? labelMetrics.advanceWidth : 0) + 8
                && x + width <= control.valueLeft - 8))
        x: control.leftPadding + (control.upright ? (control.availableWidth - width) / 2 : control.referenceStyle
            ? Math.max(12, Math.min(control.availableWidth - width - 12, control.visualPosition * control.availableWidth - width - 12))
            : control.visualPosition * (control.availableWidth - width))
        y: control.topPadding + (control.upright
            ? Math.max(12, Math.min(control.availableHeight - height - 12, control.visualPosition * control.availableHeight + 12))
            : (control.availableHeight - height) / 2)
        implicitWidth: control.upright ? 18 : control.referenceStyle ? 4 : control.thick ? 8 : 18
        implicitHeight: control.upright ? 4 : control.referenceStyle ? 18 : control.thick ? 40 : 18
        radius: control.referenceStyle ? 2 : 4
        scale: control.thick && control.pressed ? 1.12 : 1
        color: control.referenceStyle ? (control.muted ? Theme.tokens.textMuted
            : Qt.alpha(Theme.tokens.onAccent, 0.7))
            : control.thick && control.pressed ? Theme.tokens.accent : Theme.tokens.text
        border.width: control.referenceStyle ? 0 : control.thick ? (control.activeFocus || control.hovered || control.pressed ? 2 : 0) : 2
        border.color: control.activeFocus ? Theme.tokens.accent : Theme.tokens.surface
        Behavior on scale { NumberAnimation { duration: Motion.state } }
        Behavior on color { ColorAnimation { duration: Motion.state } }
    }

    component RangeInk: Item {
        required property color ink
        PentadIcon {
            x: (control.iconSlot - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            pixelSize: control.referenceStyle ? Metrics.menuIcon : 22
            source: control.iconSource
            color: parent.ink
            Accessible.ignored: true
        }
        Text {
            x: 48
            visible: control.labelFits
            width: control.labelRoom
            anchors.verticalCenter: parent.verticalCenter
            text: control.label
            color: parent.ink
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            elide: Text.ElideRight
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16 + control.trailingInset
            anchors.verticalCenter: parent.verticalCenter
            width: control.valueWidth
            text: control.valueText
            color: parent.ink
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Metrics.textBody
            font.features: ({ "tnum": 1 })
            horizontalAlignment: Text.AlignRight
        }
    }

    component VerticalInk: Item {
        required property color ink
        Text {
            y: control.verticalValueY
            width: parent.width
            text: control.valueText
            color: parent.ink
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
            color: parent.ink
            Accessible.ignored: true
        }
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
