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
    readonly property var outputs: services.hyprland.state.kind === "ready" ? services.hyprland.state.value.outputs.map(function (output) {
        return {
            id: output.name,
            name: output.name
        };
    }) : []
    readonly property string focusedOutputId: {
        if (services.hyprland.state.kind !== "ready")
            return "";
        const values = services.hyprland.state.value.outputs;
        const focused = values.find(function (output) {
            return output.id === services.hyprland.state.value.focusedOutputId;
        });
        return focused ? focused.name : "";
    }
    function refreshRoutes() {
        const records = services.notifications.state.popups || [];
        const previous = new Map(Object.keys(routes).map(function (key) {
            return [key, routes[key]];
        }));
        const mapped = Policy.routeNotifications(records, outputs, focusedOutputId, previous);
        const next = {};
        mapped.forEach(function (output, key) {
            next[key] = output;
        });
        routes = next;
    }
    readonly property var localRecords: (services.notifications.state.popups || []).filter(function (record) {
        return routes[record.key] === outputId;
    }).slice(0, 3)
    property Connections notificationChanges: Connections {
        target: root.services.notifications
        function onStateChanged() {
            root.refreshRoutes();
        }
    }
    property Connections outputChanges: Connections {
        target: root.services.hyprland
        function onStateChanged() {
            root.refreshRoutes();
        }
    }
    onOutputIdChanged: refreshRoutes()
    Component.onCompleted: refreshRoutes()
    objectName: "notification-popup-host"
    // Notification stack: with several toasts the front card sits at full size and two edges peek out
    // behind it (scale -5% per level); hovering the pile fans it out. Timing follows Kokonut UI's
    // Notification stack (MIT): 300 ms, cubic-bezier(0.23, 1, 0.32, 1), 10 px peek, 8 px gap.
    readonly property int peek: 10
    readonly property int gap: 8
    readonly property int stackDuration: Motion.reducedMotion ? 0 : 300
    readonly property var stackCurve: [0.23, 1, 0.32, 1, 1, 1]
    property int layoutRev: 0
    readonly property int count: localRecords.length
    readonly property bool stacked: count > 1 && !stackHover.hovered
    function slotHeight(index) {
        const slot = stackRepeater.itemAt(index);
        return slot ? slot.height : 0;
    }
    function offsetOf(index) {
        layoutRev;
        let y = 0;
        for (let i = 0; i < index; i++)
            y += slotHeight(i) + gap;
        return y;
    }
    readonly property real frontHeight: {
        layoutRev;
        return slotHeight(0);
    }
    readonly property real expandedHeight: {
        layoutRev;
        return count > 0 ? offsetOf(count - 1) + slotHeight(count - 1) : 0;
    }
    readonly property real stackedHeight: frontHeight + Math.max(0, Math.min(count, 3) - 1) * peek
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
        implicitHeight: Math.min(root.expandedHeight, Math.max(124, (root.barWindow.screen ? root.barWindow.screen.height : 800) - root.services.config.documents.layout.barHeight - 24)) + 2 * room
        anchor.window: root.barWindow
        anchor.rect.x: Math.max(0, root.barWindow.width - width - 16 + room)
        anchor.rect.y: root.services.config.documents.layout.barHeight + 12 - room
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Top | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeY
        mask: Region {
            item: stackBox
        }
        // The window always has room for the expanded list, so the stack grows and shrinks without
        // resizing a surface every frame; only the masked box follows the animation.
        Item {
            id: popupColumn
            objectName: "notification-popup-cards"
            anchors.fill: parent
            anchors.margins: popup.room
            implicitHeight: root.expandedHeight
            Item {
                id: stackBox
                width: parent.width
                height: root.stacked ? root.stackedHeight : root.expandedHeight
                Behavior on height {
                    enabled: root.stackDuration > 0
                    NumberAnimation {
                        duration: root.stackDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.stackCurve
                    }
                }
                HoverHandler {
                    id: stackHover
                }
                Repeater {
                    id: stackRepeater
                    model: root.localRecords
                    onItemAdded: root.layoutRev++
                    onItemRemoved: root.layoutRev++
                    delegate: Item {
                        id: slot
                        required property var modelData
                        required property int index
                        property real reveal: 0
                        // Cards behind the front one show only their edge.
                        readonly property bool muted: root.stacked && index > 0
                        readonly property real depthScale: root.stacked ? 1 - index * 0.05 : 1
                        width: stackBox.width
                        height: card.implicitHeight
                        z: root.count - index
                        transformOrigin: Item.Top
                        scale: depthScale
                        y: root.stacked ? root.frontHeight + index * root.peek - height * depthScale : root.offsetOf(index)
                        Behavior on scale {
                            enabled: root.stackDuration > 0
                            NumberAnimation {
                                duration: root.stackDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.stackCurve
                            }
                        }
                        Behavior on y {
                            enabled: root.stackDuration > 0
                            NumberAnimation {
                                duration: root.stackDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.stackCurve
                            }
                        }
                        onHeightChanged: root.layoutRev++
                        NotificationCard {
                            id: card
                            width: parent.width
                            enabled: !slot.muted
                            services: root.services
                            record: slot.modelData
                            outputId: root.outputId
                            now: root.now
                            popup: true
                            // Slides in from the screen edge; the slot keeps its height so the stack never jumps.
                            opacity: slot.reveal
                            transform: Translate {
                                x: (1 - slot.reveal) * 32
                            }
                        }
                        Rectangle {
                            objectName: "notification-stack-veil"
                            anchors.fill: parent
                            radius: Metrics.radiusCard
                            color: Theme.tokens.surfaceRaised
                            opacity: slot.muted ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity {
                                enabled: root.stackDuration > 0
                                NumberAnimation {
                                    duration: root.stackDuration
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: root.stackCurve
                                }
                            }
                        }
                        NumberAnimation on reveal {
                            from: 0
                            to: 1
                            duration: Motion.medium
                            easing.type: Easing.OutCubic
                        }
                        HoverHandler {
                            enabled: !slot.muted
                            onHoveredChanged: root.services.notifications.setHovered(slot.modelData.key, hovered)
                        }
                        Component.onCompleted: Qt.callLater(function () {
                            root.services.notifications.setPresented(slot.modelData.key, true);
                        })
                    }
                }
            }
        }
    }
}
