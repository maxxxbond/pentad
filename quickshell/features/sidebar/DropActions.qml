pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme

// Drag mode with a tool open: the tool's own area turns into one drop zone, so the input goes
// where the eye already is. A row above it names what is coming and offers the shortcuts
// elsewhere: quick actions first, then the other tools that take it. When the open tool cannot
// use the input, the zone sends it to the catalog, which lists the tools that can.
Item {
    id: root
    required property var sidebar
    readonly property var info: sidebar.dragHover
    readonly property string toolId: sidebar.toolState.selectedTool
    readonly property bool fits: !!toolId && sidebar.toolAccepts(toolId, info)
    readonly property bool findable: !fits && sidebar.generalAccepts(info)
    readonly property var actionTiles: info.quick || []
    readonly property var toolTiles: sidebar.dragUnknown(info) ? [] : (info.compatibleIds || [])
        .filter(id => id !== toolId)
        .map(id => ({ toolId: id, label: sidebar.toolName(id), symbol: sidebar.toolSymbol(id) }))
    objectName: 'sidebar-drop-actions'
    opacity: visible ? 1 : 0
    Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }

    Rectangle { anchors.fill: parent; anchors.margins: -Metrics.space1; color: Theme.tokens.surface }
    DropSummary {
        id: summary
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sidebar: root.sidebar
        tiles: root.actionTiles.concat(root.toolTiles)
    }
    PentadFileDrop {
        id: zone
        objectName: 'sidebar-drop-zone'
        anchors { left: parent.left; right: parent.right; top: summary.bottom; topMargin: Metrics.space3; bottom: parent.bottom }
        active: target.containsDrag
        opacity: root.fits || root.findable ? 1 : Metrics.stateDisabled
        iconSource: Qt.resolvedUrl('../../assets/icons/material/'
            + (root.fits ? root.sidebar.toolSymbol(root.toolId) : 'tools/input') + '-symbolic.svg')
        title: root.fits ? root.sidebar.tr('Додати до «%1»', 'Add to %1').arg(root.sidebar.toolName(root.toolId))
            : root.findable ? root.sidebar.tr('Знайти інструмент', 'Find a tool')
            : root.sidebar.tr('Жоден інструмент цього не приймає', 'No tool accepts this')
        hint: root.fits || !root.findable ? ''
            : root.sidebar.tr('«%1» цього не приймає', '%1 does not take this').arg(root.sidebar.toolName(root.toolId))
    }
    DropArea {
        id: target
        anchors.fill: zone
        onEntered: function(drag) {
            const info = root.sidebar.enterDrag(drag);
            root.sidebar.offer(drag, root.sidebar.toolAccepts(root.toolId, info) || root.sidebar.generalAccepts(info));
        }
        onExited: root.sidebar.leaveDrag()
        onDropped: function(event) { root.sidebar.dropOnTile(event, root.fits ? { toolId: root.toolId } : null, target); }
    }
}
