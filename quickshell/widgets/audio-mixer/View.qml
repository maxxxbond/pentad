pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.features.system
import qs.theme

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var controller
    required property var services
    readonly property bool compact: context && (context.slot === "tools" || context.slot === "system")
    readonly property bool effectivelyVisible: {
        let item = root
        while (item) {
            if (!item.visible) return false
            item = item.parent
        }
        return true
    }
    readonly property bool presented: compact ? popover.opened && effectivelyVisible
        : !(context && context.presented === false) && effectivelyVisible
    readonly property alias popup: popover
    readonly property var listComponent: compact ? popupMixer.listComponent : mixer.listComponent

    width: compact ? Metrics.controlLarge : Math.max(280, parent ? parent.width : 340)
    height: compact ? Metrics.controlLarge : mixer.implicitHeight
    implicitWidth: compact ? Metrics.controlLarge : 340
    implicitHeight: compact ? Metrics.controlLarge : mixer.implicitHeight
    visible: compact || !(context && context.presented === false)
    onCompactChanged: if (!compact) popover.close()
    onEffectivelyVisibleChanged: if (!effectivelyVisible) popover.close()

    ApplicationMixer {
        id: mixer
        anchors.fill: compact ? undefined : parent
        width: compact ? 340 : parent.width
        height: compact ? implicitHeight : parent.height
        services: root.services
        consumerId: "application-mixer:" + root.instanceId + ":" + String(root.context && root.context.outputId || "default")
        presented: !root.compact && root.presented
        visible: !root.compact && root.visible
    }

    Button {
        id: trigger
        objectName: "mixer-trigger"
        visible: root.compact
        anchors.fill: parent
        focusPolicy: Qt.StrongFocus
        Accessible.name: root.services && typeof root.services.text === "function"
            ? root.services.text("Гучність застосунків", "Application volume") : "Application volume"
        Accessible.description: root.services && typeof root.services.text === "function"
            ? root.services.text("Відкрити мікшер застосунків", "Open application mixer") : "Open application mixer"
        onPressed: popover.toggle()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                popover.toggle()
                event.accepted = true
            }
        }
        background: ContinuousSurface {
            fill: popover.opened ? Theme.tokens.surface
                : trigger.down || trigger.hovered ? Theme.tokens.surfaceOverlay : "transparent"
            edge: trigger.activeFocus ? Theme.tokens.accent : "transparent"
            extent: Metrics.radiusPill
        }
        contentItem: PentadIcon {
            source: Qt.resolvedUrl("../../assets/icons/material/volume-up-symbolic.svg").toString()
            pixelSize: Metrics.statusIcon
            color: Theme.tokens.text
            anchors.centerIn: parent
            Accessible.ignored: true
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onPressedChanged: if (pressed) popover.toggle()
        }
        PentadToolTip {
            visible: trigger.hovered && !popover.opened
            text: trigger.Accessible.name
        }
    }

    AttachedPopover {
        id: popover
        objectName: "mixer-popup"
        anchorItem: trigger
        barItem: trigger
        pointerDismissEnabled: false
        manager: root.services && root.services.popups ? root.services.popups : null
        fill: Theme.tokens.surface
        contentWidthFollowsPopover: true
        Item {
            id: popoverContent
            width: 340
            height: popupMixer.implicitHeight
            ApplicationMixer {
                id: popupMixer
                width: parent.width
                height: implicitHeight
                services: root.services
                consumerId: "application-mixer:" + root.instanceId + ":" + String(root.context && root.context.outputId || "default")
                presented: root.compact && root.presented
            }
        }
    }
}
