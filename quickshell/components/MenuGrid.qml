import QtQuick
import qs.theme
import "../logic/control-model.mjs" as ControlModel

Item {
    id: root

    property var placements: []
    property int columns: 4
    property real cellHeight: 72
    property real spacing: 8
    property Component delegate
    // Editing shows the true spans and the free cells; at rest a short line stretches to the edge.
    property bool editing: false
    property string draggingId: ""
    property point dragPosition: Qt.point(0, 0)

    readonly property int resolvedColumns: Math.max(1, columns)
    readonly property var resolvedLayout: ControlModel.layoutMenu(placements, resolvedColumns, { fill: !editing })
    readonly property real cellWidth: Math.max(0, (width - spacing * (resolvedColumns - 1)) / resolvedColumns)
    readonly property var placementById: {
        const result = {};
        resolvedLayout.items.forEach(function(entry) { result[entry.instanceId] = entry; });
        return result;
    }
    readonly property real layoutHeight: resolvedLayout.rows > 0
        ? resolvedLayout.rows * cellHeight + (resolvedLayout.rows - 1) * spacing
        : 0
    // Delegates are keyed by instance, so a reorder or resize moves them instead of rebuilding them.
    property var delegateKeys: []

    implicitHeight: layoutHeight
    Behavior on implicitHeight {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }

    function syncKeys() {
        const keys = resolvedLayout.items.map(function(entry) { return entry.instanceId; }).sort();
        if (keys.join("\n") !== delegateKeys.join("\n")) delegateKeys = keys;
    }
    onResolvedLayoutChanged: syncKeys()
    Component.onCompleted: syncKeys()

    function cellAt(x, y) {
        const column = Math.max(0, Math.min(resolvedColumns - 1, Math.floor(x / Math.max(1, cellWidth + spacing))));
        const row = Math.max(0, Math.floor(y / Math.max(1, cellHeight + spacing)));
        return { row: row, column: column };
    }
    function rectFor(entry) {
        return Qt.rect(entry.displayColumn * (cellWidth + spacing), entry.row * (cellHeight + spacing),
            entry.displaySpan * cellWidth + (entry.displaySpan - 1) * spacing,
            entry.rowSpan * cellHeight + (entry.rowSpan - 1) * spacing);
    }

    Repeater {
        model: root.editing ? root.resolvedLayout.free : []
        // An empty socket: a recessed stadium the size of one cell, so free space reads as a place to drop.
        delegate: Rectangle {
            required property var modelData
            objectName: "menu-grid-free-cell"
            x: modelData.column * (root.cellWidth + root.spacing)
            y: modelData.row * (root.cellHeight + root.spacing)
            width: root.cellWidth
            height: root.cellHeight
            radius: Math.min(width, height) / 2
            color: Qt.alpha(Theme.tokens.text, 0.04)
            border.width: 1
            border.color: Qt.alpha(Theme.tokens.text, 0.16)
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic } }
        }
    }

    Repeater {
        model: root.delegateKeys

        delegate: Loader {
            id: cell
            required property string modelData

            readonly property var entry: root.placementById[modelData] || null
            readonly property rect target: entry ? root.rectFor(entry) : Qt.rect(0, 0, 0, 0)
            readonly property bool dragged: root.draggingId !== "" && root.draggingId === modelData
            property var placement: entry
            property bool settled: false
            visible: !!entry
            x: dragged ? root.dragPosition.x : target.x
            y: dragged ? root.dragPosition.y : target.y
            z: dragged ? 10 : 0
            width: target.width
            height: target.height
            sourceComponent: root.delegate
            Behavior on x {
                enabled: cell.settled && !cell.dragged
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: cell.settled && !cell.dragged
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }
            Behavior on width {
                enabled: cell.settled
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }
            Behavior on height {
                enabled: cell.settled
                NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
            }

            function updateDelegatePlacement() {
                if (item && "placement" in item && placement) item.placement = placement;
            }

            onLoaded: { updateDelegatePlacement(); Qt.callLater(function() { cell.settled = true; }); }
            onPlacementChanged: updateDelegatePlacement()
        }
    }
}
