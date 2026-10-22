pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/file-tools.mjs' as Files

// Drag mode: while something is dragged over the drawer, it shows what is coming and where
// it can go. Releasing on a tile opens that tool with the input and the action selected;
// releasing elsewhere falls back to the compatible-tool list.
Item {
    id: root
    required property var sidebar
    readonly property var info: sidebar.dragHover
    readonly property var items: info.items || []
    readonly property var first: items.length ? items[0] : null
    readonly property var current: sidebar.toolState.selectedTool && (info.compatibleIds || []).indexOf(sidebar.toolState.selectedTool) >= 0
        ? [{ toolId: sidebar.toolState.selectedTool, label: 'Add to ' + sidebar.toolName(sidebar.toolState.selectedTool),
             symbol: sidebar.toolSymbol(sidebar.toolState.selectedTool) }] : []
    readonly property var actionTiles: current.concat(info.quick || []).slice(0, 6)
    readonly property var toolTiles: (info.compatibleIds || [])
        .filter(id => id !== sidebar.toolState.selectedTool && !actionTiles.some(tile => tile.toolId === id && !tile.actionId))
        .map(id => ({ toolId: id, label: sidebar.toolName(id), symbol: sidebar.toolSymbol(id) }))
        .slice(0, actionTiles.length ? 6 : 9)
    objectName: 'sidebar-drop-actions'
    opacity: visible ? 1 : 0
    Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }

    Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
    DropArea {
        anchors.fill: parent
        onEntered: function(drag) { const value = root.sidebar.enterDrag(drag); drag.accepted = !!value.mime; if (drag.accepted) drag.accept(Qt.CopyAction); }
        onExited: root.sidebar.leaveDrag()
        onDropped: function(event) { root.sidebar.dropOnTile(event, null); }
    }
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 16
        Row {
            width: parent.width
            spacing: 12
            FileThumb {
                width: 56; height: 56
                services: root.sidebar.services
                uri: root.first && root.first.uri ? root.first.uri : ''
                mimeType: root.first ? root.first.mimeType || '' : ''
                kind: root.first ? root.first.kind : 'file'
                iconSize: 24
                radius: Metrics.radiusCard
            }
            Column {
                width: parent.width - 68
                anchors.verticalCenter: parent.verticalCenter
                PentadText {
                    objectName: 'sidebar-drop-summary'
                    width: parent.width
                    text: Files.dragSummary(root.items)
                    role: 'section'; font.weight: Font.Medium
                    wrapMode: Text.NoWrap; elide: Text.ElideMiddle
                    solid: true
                }
                PentadText {
                    width: parent.width
                    text: root.actionTiles.length || root.toolTiles.length ? Files.kindLabel(root.items) : 'No tool accepts this'
                    role: 'caption'
                    color: root.actionTiles.length || root.toolTiles.length ? Theme.tokens.textMuted : Theme.tokens.error
                    wrapMode: Text.NoWrap; elide: Text.ElideRight
                    solid: true
                }
            }
        }
        Grid {
            visible: root.actionTiles.length > 0
            width: parent.width
            columns: 2
            rowSpacing: 8; columnSpacing: 8
            Repeater {
                model: root.actionTiles
                delegate: QuickTile {
                    required property var modelData
                    width: (root.width - 32 - 8) / 2
                    sidebar: root.sidebar
                    tile: modelData
                }
            }
        }
        PentadText {
            visible: root.toolTiles.length > 0 && root.actionTiles.length > 0
            text: 'Open in'
            role: 'caption'; color: Theme.tokens.textMuted
        }
        Grid {
            visible: root.toolTiles.length > 0
            width: parent.width
            columns: 3
            rowSpacing: 8; columnSpacing: 8
            Repeater {
                model: root.toolTiles
                delegate: QuickTile {
                    required property var modelData
                    width: (root.width - 32 - 16) / 3
                    stacked: true
                    sidebar: root.sidebar
                    tile: modelData
                }
            }
        }
    }
}
