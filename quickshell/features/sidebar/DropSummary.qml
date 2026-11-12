pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/file-tools.mjs' as Files

// What is being dragged over the drawer, and its one-step destinations: a thumbnail with the
// item's name and kind, then up to four tiles in one row. Releasing on a tile opens that tool
// with the input and, for a quick action, the action selected.
Column {
    id: root
    required property var sidebar
    // Tiles as QuickTile takes them: { toolId, actionId?, options?, label, symbol }.
    property var tiles: []
    readonly property var items: sidebar.dragHover.items || []
    readonly property var first: items.length ? items[0] : null
    readonly property var shownTiles: tiles.slice(0, 4)
    spacing: Metrics.space2

    Row {
        width: parent.width
        spacing: Metrics.space3
        FileThumb {
            width: 40; height: 40
            services: root.sidebar.services
            uri: root.first && root.first.uri ? root.first.uri : ''
            mimeType: root.first ? root.first.mimeType || '' : ''
            kind: root.first ? root.first.kind : 'file'
            iconSize: Metrics.statusIcon
            radius: Metrics.radiusMedium
        }
        Column {
            width: parent.width - 40 - Metrics.space3
            anchors.verticalCenter: parent.verticalCenter
            PentadText {
                objectName: 'sidebar-drop-summary'
                width: parent.width
                text: Files.dragSummary(root.items) || root.sidebar.tr('Перетягування', 'Dragged content')
                role: 'section'; font.weight: Font.Medium
                wrapMode: Text.NoWrap; elide: Text.ElideMiddle
                solid: true
            }
            PentadText {
                objectName: 'sidebar-drop-kind'
                readonly property bool refused: !root.sidebar.generalAccepts(root.sidebar.dragHover)
                width: parent.width
                text: refused ? root.sidebar.tr('Жоден інструмент цього не приймає', 'No tool accepts this')
                    : Files.kindLabel(root.items) || root.sidebar.tr('Відпустіть, щоб вибрати інструмент', 'Release to choose a tool')
                role: 'caption'
                color: refused ? Theme.tokens.error : Theme.tokens.textMuted
                wrapMode: Text.NoWrap; elide: Text.ElideRight
                solid: true
            }
        }
    }
    Grid {
        objectName: 'sidebar-drop-tiles'
        visible: root.shownTiles.length > 0
        width: parent.width
        columns: 4
        columnSpacing: Metrics.space2
        Repeater {
            model: root.shownTiles
            delegate: QuickTile {
                required property var modelData
                width: (root.width - 3 * Metrics.space2) / 4
                stacked: true
                sidebar: root.sidebar
                tile: modelData
            }
        }
    }
}
