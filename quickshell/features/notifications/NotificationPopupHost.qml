pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components
import qs.theme
import "../../logic/notifications.mjs" as Policy

Item {
    id: root
    required property var services
    required property var barWindow
    required property string outputId
    property var routes: ({})
    property alias popupWindow: popup
    property alias cardColumn: popupColumn
    readonly property var outputs: services.hyprland.state.kind === "ready"
        ? services.hyprland.state.value.outputs.map(function(output) { return { id: output.name, name: output.name }; }) : []
    readonly property string focusedOutputId: {
        if (services.hyprland.state.kind !== "ready") return "";
        const values = services.hyprland.state.value.outputs;
        const focused = values.find(function(output) { return output.id === services.hyprland.state.value.focusedOutputId; });
        return focused ? focused.name : "";
    }
    function refreshRoutes() {
        const records = services.notifications.state.popups || [];
        const previous = new Map(Object.keys(routes).map(function(key) { return [key, routes[key]]; }));
        const mapped = Policy.routeNotifications(records, outputs, focusedOutputId, previous);
        const next = {};
        mapped.forEach(function(output, key) { next[key] = output; });
        routes = next;
    }
    readonly property var localRecords: (services.notifications.state.popups || []).filter(function(record) {
        return routes[record.key] === outputId;
    }).slice(0, 3)
    property Connections notificationChanges: Connections {
        target: root.services.notifications
        function onStateChanged() { root.refreshRoutes(); }
    }
    property Connections outputChanges: Connections {
        target: root.services.hyprland
        function onStateChanged() { root.refreshRoutes(); }
    }
    onOutputIdChanged: refreshRoutes()
    Component.onCompleted: refreshRoutes()
    objectName: "notification-popup-host"
    property real now: Date.now()
    Timer {
        interval: 30000
        repeat: true
        triggeredOnStart: true
        running: popup.visible
        onTriggered: root.now = Date.now()
    }
    PopupWindow {
        id: popup
        objectName: "notification-popup-window"
        visible: root.localRecords.length > 0
        grabFocus: false
        color: "transparent"
        // Cards keep their place; the window adds shadow room around them.
        readonly property int room: Metrics.overlayShadowRoom
        implicitWidth: 360 + 2 * room
        implicitHeight: Math.min(popupColumn.implicitHeight,
            Math.max(124, (root.barWindow.screen ? root.barWindow.screen.height : 800)
                - root.services.config.documents.layout.barHeight - 24)) + 2 * room
        anchor.window: root.barWindow
        anchor.rect.x: Math.max(0, root.barWindow.width - width - 16 + room)
        anchor.rect.y: root.services.config.documents.layout.barHeight + 12 - room
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Top | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        mask: Region { item: popupColumn }
        Column {
            id: popupColumn
            objectName: "notification-popup-cards"
            anchors.fill: parent
            anchors.margins: popup.room
            spacing: 8
            Repeater {
                model: root.localRecords
                delegate: Item {
                    id: slot
                    required property var modelData
                    property real reveal: 0
                    width: popupColumn.width
                    height: card.implicitHeight
                    NotificationCard {
                        id: card
                        width: parent.width
                        services: root.services
                        record: parent.modelData
                        outputId: root.outputId
                        now: root.now
                        popup: true
                        // Slides in from the screen edge; the slot keeps its height so the stack never jumps.
                        opacity: slot.reveal
                        transform: Translate { x: (1 - slot.reveal) * 32 }
                    }
                    NumberAnimation on reveal {
                        from: 0
                        to: 1
                        duration: Motion.medium
                        easing.type: Easing.OutCubic
                    }
                    HoverHandler {
                        onHoveredChanged: root.services.notifications.setHovered(parent.modelData.key, hovered)
                    }
                    Component.onCompleted: Qt.callLater(function() {
                        root.services.notifications.setPresented(modelData.key, true);
                    })
                }
            }
        }
    }
}
