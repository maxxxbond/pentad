import QtQuick

// Makes its parent a native drag source for local files and web addresses (CopyAction,
// text/uri-list), the same way Stash rows export. Web addresses also go as text/plain, so a
// text field takes the link. A click without movement activates instead. While the blocking
// native drag runs, ToolWorkspace.exports keeps the drawer open and its focus grab released.
MouseArea {
    id: root
    required property var services
    property var uris: []
    property Item visual: parent
    // From the 10 px threshold until the drag ends: the cursor and the tooltips follow it.
    property bool exporting: false
    // Only while the compositor holds the native drag: set from inside Drag.startDrag's nested event
    // loop, cleared when it returns. A surface that lets input through during a drag-out keys on this,
    // not on `exporting`: dropping its input region before start_drag reaches the compositor moves the
    // pointer focus away, and Qt then finds no origin window and starts no drag at all.
    property bool dragging: false
    property point pressPoint
    signal activated()
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: exporting ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    preventStealing: true
    Drag.dragType: Drag.None
    Drag.supportedActions: Qt.CopyAction
    Drag.proposedAction: Qt.CopyAction
    Drag.mimeData: root.uris.every(uri => uri.startsWith('file:')) ? { 'text/uri-list': root.uris.join('\r\n') + '\r\n' }
        : { 'text/uri-list': root.uris.join('\r\n') + '\r\n', 'text/plain': root.uris.join('\n') }
    onPressed: function(mouse) { pressPoint = Qt.point(mouse.x, mouse.y); }
    onClicked: if (!exporting) activated()
    onPositionChanged: function(mouse) {
        if (!pressed || exporting || !uris.length) return;
        if (Math.abs(mouse.x - pressPoint.x) + Math.abs(mouse.y - pressPoint.y) < 10) return;
        exporting = true;
        // grabToImage returns false when it cannot grab (no window yet); then no callback ends the export.
        const grabbing = visual.grabToImage(function(result) {
            if (!root.pressed) { root.exporting = false; return; }
            root.Drag.imageSource = result.url;
            root.Drag.hotSpot = Qt.point(Math.min(root.visual.width / 2, 40), Math.min(root.visual.height / 2, 40));
            root.services.toolWorkspace.exports++;
            root.Drag.active = true;
            handedOver.start();
            root.Drag.startDrag(Qt.CopyAction);
            handedOver.stop();
            root.dragging = false;
            root.Drag.active = false;
            root.services.toolWorkspace.exports--;
            root.exporting = false;
        }, Qt.size(Math.max(1, Math.round(visual.width)), Math.max(1, Math.round(visual.height))));
        if (!grabbing) exporting = false;
    }
    // Fires inside startDrag's nested event loop, once the start_drag request has been flushed.
    Timer {
        id: handedOver
        interval: 50
        onTriggered: if (root.Drag.active) root.dragging = true
    }
    // The native drag takes the pointer grab, which cancels this area mid-drag; that export ends when startDrag returns.
    onCanceled: if (!Drag.active) exporting = false
}
