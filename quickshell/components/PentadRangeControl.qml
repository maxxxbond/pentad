pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme

Item {
    id: root
    property var definition: ({})
    property var controlState: ({})
    property string presentation: "range-horizontal"
    property bool vertical: presentation === "range-vertical"
    readonly property var range: definition && definition.capabilities
        ? definition.capabilities.range || ({}) : ({})
    readonly property real minimum: finite(range.from) ? Number(range.from) : 0
    readonly property real maximum: finite(range.to) ? Number(range.to) : 1
    readonly property real step: finite(range.step) && Number(range.step) > 0
        ? Number(range.step) : Math.max((maximum - minimum) / 100, 0.01)
    readonly property real currentValue: controlState && finite(controlState.value)
        ? Number(controlState.value) : minimum
    readonly property real confirmedValue: controlState && finite(controlState.confirmedValue)
        ? Number(controlState.confirmedValue) : NaN
    readonly property string valueDescription: range && range.unit
        ? String(Math.round(currentValue * (typeof range.scale === "number" ? range.scale : 1))) + String(range.unit)
        : String(currentValue)
    readonly property string accessibleDescription: [controlState && controlState.unavailableReason
        ? String(controlState.unavailableReason) : "",
        controlState && controlState.pending ? "In progress" : "",
        controlState && controlState.error ? String(controlState.error) : "", valueDescription]
        .filter(function(value) { return value !== "" }).join(" · ")
    property real wheelRemainder: 0
    property int wheelDirection: 0
    readonly property alias slider: slider
    signal commandRequested(string action, var value)

    implicitWidth: vertical ? Metrics.controlLarge : 220
    implicitHeight: vertical ? 188 : Metrics.controlLarge
    Accessible.role: Accessible.Slider
    Accessible.name: definition && definition.label ? String(definition.label) : "Range"
    Accessible.description: accessibleDescription

    function finite(value) {
        return typeof value === "number" && Number.isFinite(value)
    }

    function clamp(value) {
        return Math.max(minimum, Math.min(maximum, value))
    }

    function snapped(value) {
        return clamp(minimum + Math.round((value - minimum) / step) * step)
    }

    function sendValue(value) {
        if (!controlState || controlState.available === false)
            return
        const action = range && range.action ? String(range.action) : ""
        if (action !== "")
            commandRequested(action, snapped(value))
    }

    function handleWheel(event) {
        const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y / 40 : event.angleDelta.y / 120
        if (!controlState || controlState.available === false) {
            event.accepted = false
            return
        }
        event.accepted = true
        if (delta === 0)
            return
        const direction = delta > 0 ? 1 : -1
        if (wheelDirection !== 0 && direction !== wheelDirection)
            wheelRemainder = 0
        wheelDirection = direction
        wheelRemainder += delta
        const ticks = wheelRemainder < 0 ? Math.ceil(wheelRemainder) : Math.floor(wheelRemainder)
        if (ticks !== 0) {
            wheelRemainder -= ticks
            sendValue(currentValue + ticks * step)
        }
    }

    Slider {
        id: slider
        objectName: "controlRange"
        anchors.fill: parent
        orientation: root.vertical ? Qt.Vertical : Qt.Horizontal
        from: root.minimum
        to: Math.max(root.minimum, root.maximum)
        stepSize: root.step
        snapMode: Slider.SnapAlways
        enabled: root.controlState && root.controlState.available !== false
        Accessible.name: root.definition && root.definition.label ? String(root.definition.label) : "Range"
        Accessible.description: root.accessibleDescription
        Accessible.role: Accessible.Slider
        Binding {
            target: slider
            property: "value"
            value: root.currentValue
            when: !slider.pressed
        }
        onMoved: root.sendValue(value)

        background: Item {
            id: track
            x: slider.leftPadding + (root.vertical ? (slider.availableWidth - width) / 2 : 0)
            y: slider.topPadding + (root.vertical ? 0 : (slider.availableHeight - height) / 2)
            width: root.vertical ? 6 : slider.availableWidth
            height: root.vertical ? slider.availableHeight : 6
            scale: !root.vertical && slider.mirrored ? -1 : 1
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.tokens.outline
            }
            Rectangle {
                x: root.vertical ? 0 : 0
                y: root.vertical ? slider.visualPosition * track.height : 0
                width: root.vertical ? track.width : slider.visualPosition * track.width
                height: root.vertical ? slider.position * track.height : track.height
                radius: height / 2
                color: Theme.tokens.accent
            }
            Rectangle {
                visible: Number.isFinite(root.confirmedValue) && root.maximum > root.minimum
                    && Math.abs(root.currentValue - root.confirmedValue) > root.step / 2
                width: root.vertical ? track.width + 8 : 4
                height: root.vertical ? 4 : track.height + 8
                x: root.vertical ? -4 : Math.max(0, Math.min(track.width - width,
                    (root.confirmedValue - root.minimum) / (root.maximum - root.minimum) * track.width - width / 2))
                y: root.vertical ? Math.max(0, Math.min(track.height - height,
                    (1 - (root.confirmedValue - root.minimum) / (root.maximum - root.minimum)) * track.height - height / 2)) : -4
                radius: 2
                color: Theme.tokens.textMuted
            }
        }
        handle: Rectangle {
            implicitWidth: 18
            implicitHeight: 18
            x: root.vertical ? (slider.availableWidth - width) / 2
                : slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: root.vertical ? slider.topPadding + slider.visualPosition * (slider.availableHeight - height)
                : (slider.availableHeight - height) / 2 + slider.topPadding
            radius: 6
            color: slider.pressed ? Theme.tokens.accent : Theme.tokens.text
            border.width: slider.activeFocus ? 2 : 0
            border.color: Theme.tokens.accent
            opacity: slider.enabled ? 1 : 0.55
        }
    }

    HoverHandler {
        onHoveredChanged: if (!hovered) { root.wheelRemainder = 0; root.wheelDirection = 0 }
    }

    WheelHandler {
        objectName: "rangeWheelHandler"
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        target: null
        onWheel: function(event) { root.handleWheel(event) }
    }
}
