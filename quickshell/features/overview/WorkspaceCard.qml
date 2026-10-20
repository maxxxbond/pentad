pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import qs.theme
import qs.components
import "../../logic/overview-layout.mjs" as Layout
import "../../logic/overview-presentation.mjs" as Presentation

Rectangle {
    id: root
    objectName: 'overview-workspace-' + workspaceId
    required property var workspace
    required property var clients
    required property var workarea
    required property var services
    required property var navigation
    property Item dragLayer: root
    property var captureIds: []
    property var capturePool: null
    property bool otherOutput: false
    property bool scene: false
    property bool miniature: false
    property bool cell: false
    readonly property int cellPadding: 6
    property bool highlighted: selected
    signal workspaceSelected(string id)
    property string query: ""
    property bool dropHover: false
    readonly property string workspaceId: String(workspace?.id ?? '')
    readonly property bool occupied: clients.length > 0
    readonly property var game: Presentation.workspaceGame(workspace, clients)
    readonly property bool selected: workspace?.active === true ||
        String(navigation?.snapshot?.desktop?.outputs?.find(o => o.id === navigation.outputId)?.activeWorkspaceId ?? '') === workspaceId
    readonly property var screenFit: cell
        ? Layout.fitPreview(workarea.width, workarea.height,
            Math.max(1, width - 2 * cellPadding), Math.max(1, height - 2 * cellPadding))
        : ({ width: 0, height: 0 })
    radius: cell ? Metrics.radiusCard : 16
    readonly property bool windowSelectedHere: !!navigation?.selectedWindow
        && String(navigation.selectedWindow.workspaceId) === workspaceId
    color: scene ? 'transparent'
        : Qt.alpha(Theme.tokens.text, dropHover ? 0.16 : highlighted ? 0.1 : workspaceHover.hovered ? 0.07 : 0.035)
    implicitHeight: 44 + Math.max(0, width - 16) * workarea.height / Math.max(1, workarea.width)
        + (otherOutput ? 22 : 0)
    height: implicitHeight
    clip: true
    Accessible.name: game ? services.text('Ігровий простір: ', 'Game workspace: ') + game.title
        : occupied ? (workspace.name || workspaceId) + ', ' + clients.length + ' windows' : workspaceId
    Accessible.role: Accessible.Button
    HoverHandler { id: workspaceHover }
    Behavior on color { ColorAnimation { duration: Motion.short } }
    ToolTip.visible: miniature && workspaceHover.hovered && !!game
    ToolTip.text: game?.title || ''

    PentadIcon {
        visible: !root.scene && !root.cell && !!root.game
        x: 10; y: root.miniature ? 6 : 10; pixelSize: 16
        source: Qt.resolvedUrl('../../assets/icons/spotlight/game.svg')
        color: Theme.tokens.text
    }

    Rectangle {
        visible: !root.scene && !root.cell && (root.selected || root.dropHover)
        x: parent.width - 18; y: 16; width: 5; height: 5; radius: 2.5
        color: Theme.tokens.text
    }
    Text {
        visible: !root.scene && !root.cell
        z: 3
        x: root.game ? 32 : 12; y: root.miniature ? 5 : 9
        text: root.game ? root.game.title : root.workspace.name && String(root.workspace.name) !== root.workspaceId
            ? root.workspaceId + ' · ' + root.workspace.name : root.workspaceId
        textFormat: Text.PlainText
        color: Qt.alpha(Theme.tokens.text, root.selected ? 1 : 0.6)
        font.family: Theme.tokens.fontFamily; font.pixelSize: 13
        elide: Text.ElideRight
        width: Math.max(0, parent.width - x - 24)
    }
    PentadIcon {
        visible: root.cell && !!root.game
        z: 3
        x: 10; y: 10; pixelSize: 16
        source: Qt.resolvedUrl('../../assets/icons/spotlight/game.svg')
        color: Theme.tokens.text
    }
    Text {
        visible: root.cell && root.otherOutput
        z: 3
        x: 10; y: parent.height - 20
        text: String(root.workspace.monitor || '')
        color: Qt.alpha(Theme.tokens.text, 0.55)
        font.family: Theme.tokens.fontFamily; font.pixelSize: 11
        elide: Text.ElideRight; width: parent.width - 20
    }
    Text {
        visible: !root.scene && !root.cell && !root.miniature && root.otherOutput
        z: 3
        x: 12; y: parent.height - 22
        text: String(root.workspace.monitor || '')
        color: Qt.alpha(Theme.tokens.text, 0.55)
        font.family: Theme.tokens.fontFamily; font.pixelSize: 11
        elide: Text.ElideRight; width: parent.width - 24
    }
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.miniature) root.workspaceSelected(root.workspaceId);
            else if (root.cell && root.navigation.pickerOpen && root.navigation.selectedWindow)
                root.navigation.moveSelected(root.workspaceId);
            else root.navigation.activateWorkspace(root.workspaceId);
        }
    }
    DropArea {
        id: destination
        anchors.fill: parent
        keys: ['pentad-window']
        onEntered: drag => {
            drag.accepted = !!drag.source && root.navigation.canDrop(drag.source.windowToken, root.workspaceId);
            root.dropHover = drag.accepted;
            if (drag.accepted) drag.accept(Qt.MoveAction);
        }
        onExited: root.dropHover = false
        onDropped: drag => {
            root.dropHover = false;
            const local = destination.mapToItem(canvas, drag.x, drag.y);
            const point = Layout.unprojectPoint(local, root.workarea, { width: canvas.width, height: canvas.height });
            if (drag.source && root.navigation.drop(drag.source.windowToken, root.workspaceId, point))
                drag.accept(Qt.MoveAction);
            else drag.accepted = false;
        }
        Connections {
            target: root.navigation
            function onDragTokenChanged() { if (!root.navigation.dragToken) root.dropHover = false; }
        }
    }
    ContinuousSurface {
        id: canvas
        objectName: 'overview-workspace-screen-' + root.workspaceId
        x: root.cell ? (root.width - width) / 2 : root.scene ? 0 : 8
        y: root.cell ? (root.height - height) / 2 : root.scene ? 0 : root.miniature ? 26 : 36
        width: root.cell ? root.screenFit.width : Math.max(0, root.width - (root.scene ? 0 : 16))
        height: root.cell ? root.screenFit.height : Math.max(0, root.height - y - (root.scene ? 0 : 8)
            - (!root.scene && !root.miniature && root.otherOutput ? 22 : 0))
        extent: root.scene ? 20 : root.cell ? Metrics.radiusMedium : 10
        fill: Qt.alpha(Theme.tokens.surface, root.scene ? 0.12 : root.cell ? 0.62 : 0.48)
        Text {
            visible: root.cell
            anchors.centerIn: parent
            text: /^[0-9]+$/.test(root.workspaceId) ? root.workspaceId
                : String(root.workspace.name || root.workspaceId).slice(0, 3)
            color: Qt.alpha(Theme.tokens.text, root.occupied ? 0.1 : 0.2)
            font.family: Theme.tokens.fontFamily
            font.pixelSize: Math.max(18, Math.min(96, parent.height * 0.5))
            font.weight: Font.Medium
        }
        Rectangle {
            visible: !root.occupied && !root.cell
            anchors.centerIn: parent
            width: 30; height: 22; radius: 5
            color: Qt.alpha(Theme.tokens.text, 0.08)
        }
        PentadText {
            visible: root.scene && !root.occupied && canvas.width >= 180 && canvas.height >= 100
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + 28
            text: root.services.text('Порожній простір', 'Empty workspace')
            color: Qt.alpha(Theme.tokens.text, 0.55)
        }
        Repeater {
            model: ScriptModel { values: Presentation.overviewWindowIds(root.clients) }
            delegate: Item {
                id: windowItem
                objectName: (root.miniature ? 'overview-mini-client-' : 'overview-client-') + client.address
                required property string modelData
                required property int index
                readonly property var client: root.clients.find(client => client.instanceId === modelData)
                    || ({ instanceId: modelData, address: '', width: 0, height: 0 })
                readonly property var windowRef: ({ address: client.address, instanceId: client.instanceId })
                readonly property var projection: Layout.projectWindow(client, root.workarea,
                    { width: canvas.width, height: canvas.height })
                readonly property bool selected: root.navigation.selectedWindow
                    && root.navigation.selectedWindow.instanceId === client.instanceId
                x: projection ? projection.x : 0
                y: projection ? projection.y : 0
                width: projection ? projection.width : 0
                height: projection ? projection.height : 0
                visible: projection !== null
                opacity: proxy.windowToken ? 0.3
                    : !root.miniature && root.windowSelectedHere && !selected && !hoverHandler.hovered ? 0.55 : 1
                z: selected ? 2 : 1
                Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
                WindowPreview {
                    anchors.fill: parent; anchors.margins: 1
                    client: windowItem.client
                    showFallbackTitle: false
                    showIconWithContent: false
                    sharedCapture: !!root.capturePool
                    frame: root.capturePool ? root.capturePool.frameFor(windowItem.client.instanceId) : null
                    source: !root.capturePool && !root.miniature && root.captureIds.indexOf(windowItem.client.instanceId) >= 0
                        && !(root.services?.preview || root.services?.safeMode)
                        && root.services && root.services.hyprland
                        ? root.services.hyprland.captureSourceFor(windowItem.windowRef) : null
                    captureEnabled: !root.miniature && root.captureIds.indexOf(windowItem.client.instanceId) >= 0
                        && !(root.services?.preview || root.services?.safeMode)
                    opacity: !root.query || (String(windowItem.client.title || '') + ' '
                        + String(windowItem.client.appId || windowItem.client.appClass || '')).toLocaleLowerCase().includes(root.query.toLocaleLowerCase())
                        ? 1 : 0.35
                }
                Item {
                    id: hitTarget
                    objectName: (root.miniature ? 'overview-mini-hit-' : 'overview-hit-') + windowItem.client.instanceId
                    readonly property var windowRef: windowItem.windowRef
                    property bool dragged: false
                    property bool completingDrop: false
                    width: Math.max(28, windowItem.width)
                    height: Math.max(28, windowItem.height)
                    x: (windowItem.width - width) / 2
                    y: (windowItem.height - height) / 2
                    function cancelDrag() {
                        const token = proxy.windowToken;
                        proxy.Drag.cancel();
                        proxy.windowToken = null;
                        root.navigation.cancelDrag(token);
                    }
                    Rectangle {
                        id: proxy
                        objectName: (root.miniature ? 'overview-mini-drag-' : 'overview-drag-') + windowItem.client.instanceId
                        parent: root.dragLayer
                        property var windowToken: null
                        readonly property var previewSize: Layout.fitPreview(
                            Math.max(1, windowItem.client.width), Math.max(1, windowItem.client.height), 320, 220)
                        width: previewSize.width; height: previewSize.height
                        visible: !!windowToken
                        radius: 12
                        color: Qt.alpha(Theme.tokens.surface, 0.95)
                        opacity: 0.9
                        Drag.active: !!windowToken
                        Drag.source: proxy
                        Drag.keys: ['pentad-window']
                        Drag.supportedActions: Qt.MoveAction
                        Drag.proposedAction: Qt.MoveAction
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2
                        WindowPreview {
                            anchors.fill: parent; anchors.margins: 2
                            client: windowItem.client
                            source: null; captureEnabled: false
                            sharedCapture: true
                            frame: root.capturePool ? root.capturePool.frameFor(windowItem.client.instanceId) : null
                            showFallbackTitle: true; showIconWithContent: false
                        }
                    }
                    Connections {
                        target: root.navigation
                        function onDragTokenChanged() {
                            if (!hitTarget.completingDrop && proxy.windowToken && root.navigation.dragToken !== proxy.windowToken) {
                                proxy.Drag.cancel();
                                proxy.windowToken = null;
                            }
                        }
                    }
                    Component.onDestruction: cancelDrag()
                    HoverHandler { id: hoverHandler }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: hitTarget.dragged = false
                        onClicked: {
                            if (hitTarget.dragged) return;
                            if (root.miniature) root.workspaceSelected(root.workspaceId);
                            else {
                                root.navigation.selectWindow(windowItem.windowRef);
                                root.navigation.activateSelected();
                            }
                        }
                    }
                    DragHandler {
                        id: dragHandler
                        enabled: !windowItem.client.pinned
                            && (!windowItem.client.grouped || windowItem.client.grouped.length === 0)
                        target: null
                        function positionProxy() {
                            const point = root.dragLayer.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y);
                            proxy.x = point.x - proxy.width / 2;
                            proxy.y = point.y - proxy.height / 2;
                        }
                        onCentroidChanged: if (active) positionProxy()
                        onCanceled: hitTarget.cancelDrag()
                        onActiveChanged: {
                            if (active) {
                                hitTarget.dragged = true;
                                positionProxy();
                                proxy.windowToken = root.navigation.beginDrag(windowItem.windowRef);
                            } else {
                                if (proxy.windowToken) {
                                    const token = proxy.windowToken;
                                    hitTarget.completingDrop = true;
                                    proxy.Drag.drop();
                                    hitTarget.completingDrop = false;
                                    proxy.windowToken = null;
                                    root.navigation.cancelDrag(token);
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    visible: !root.miniature && (windowItem.selected || hoverHandler.hovered) && windowItem.width >= 88 && windowItem.height >= 44
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 4
                    height: 24; radius: 6
                    color: Qt.alpha(Theme.tokens.surface, 0.9)
                    Text {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                        verticalAlignment: Text.AlignVCenter
                        text: String(windowItem.client.title || windowItem.client.appClass || '')
                        textFormat: Text.PlainText
                        color: Theme.tokens.text
                        font.family: Theme.tokens.fontFamily; font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
