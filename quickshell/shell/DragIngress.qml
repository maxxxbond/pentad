import QtQuick
import qs.theme
import '../logic/drag-drop.mjs' as DropLogic
import '../logic/shelf.mjs' as ShelfLogic

Item {
    id: root
    required property var services
    required property var surfaceHost
    property var leftHost: surfaceHost
    required property string outputId
    property real sidebarWidth: 0
    property string destination: ''
    property string openedSurface: ''
    readonly property bool writable: !services.preview && !services.safeMode
    readonly property bool inside: target.containsDrag || surfaceHost.dragHovered || surfaceHost.pointerHovered || !!surfaceHost.dragOutActive
        || leftHost.dragHovered || leftHost.pointerHovered || !!leftHost.dragOutActive
    readonly property bool ownsSurface: openedSurface !== '' && services.popups.isOpen(openedSurface, outputId)
    onInsideChanged: {
        if (inside) leaveGrace.stop();
        else if (ownsSurface) leaveGrace.restart();
    }
    function reveal() {
        if (!destination || !writable) return;
        const name = destination === 'left' ? 'left' : 'activity';
        if (ownsSurface && openedSurface !== name) services.popups.closeSurface(openedSurface, outputId);
        if (!services.popups.isOpen(name, outputId)) {
            services.popups.open(name, outputId);
            openedSurface = name;
        }
        if (name === 'activity' && surfaceHost.activityContent)
            surfaceHost.activityContent.selectTab(2);
    }
    function receive(drop) {
        dwell.stop();
        if (!writable) { drop.accepted = false; return; }
        root.reveal();
        if (root.destination === 'left') {
            if (root.leftHost.leftContent) root.leftHost.leftContent.handleDrop(drop, '');
            else drop.accepted = false;
        } else {
            const grid = root.surfaceHost.activityContent?.shelfGrid;
            if (grid && grid.receiveDrop(drop)) {  }
            else {
                drop.accepted = false;
                if (grid && !grid.message) grid.message = 'Could not save this content.';
            }
        }
        root.destination = '';
        if (!root.inside && root.ownsSurface) leaveGrace.restart();
    }
    Timer { id: dwell; objectName: 'bar-drag-dwell'; interval: 300; onTriggered: if (root.destination) root.reveal() }
    // Moves the hover to a side of the bar. The left drawer enters drag mode at once (preloaded,
    // still hidden) so it shows quick actions the moment the dwell reveals it.
    function enter(drag) {
        const mime = DropLogic.offerMime(drag.formats);
        const side = drag.x < root.sidebarWidth ? 'left' : 'activity';
        drag.accepted = root.writable && (side === 'left' ? !!mime : DropLogic.supportsShelfOffer(drag.formats));
        if (!drag.accepted) return;
        drag.accept(Qt.CopyAction);
        if (root.destination === side) return;
        const sidebar = root.leftHost.leftContent;
        if (side === 'left') {
            root.leftHost.prepareSide('left');
            if (sidebar && typeof sidebar.enterDrag === 'function') sidebar.enterDrag(drag);
        } else if (sidebar && typeof sidebar.clearDrag === 'function') sidebar.clearDrag();
        root.destination = side;
        dwell.restart();
    }
    function leave() {
        dwell.stop();
        const sidebar = root.leftHost.leftContent;
        if (root.destination === 'left' && sidebar && typeof sidebar.leaveDrag === 'function') sidebar.leaveDrag();
        root.destination = '';
        if (root.ownsSurface) leaveGrace.restart();
    }
    Timer {
        id: leaveGrace
        interval: 220
        onTriggered: {
            if (!root.inside && root.ownsSurface) root.services.popups.closeSurface(root.openedSurface, root.outputId);
            root.openedSurface = '';
        }
    }
    Connections {
        target: root.services.popups
        function onChanged() { if (!root.ownsSurface) root.openedSurface = ''; }
    }
    Connections {
        target: root.surfaceHost
        function onActivityContentChanged() {
            if (root.destination === 'activity' && root.services.popups.isOpen('activity', root.outputId)
                    && root.surfaceHost.activityContent) root.surfaceHost.activityContent.selectTab(2);
        }
    }
    Rectangle {
        objectName: 'bar-drag-zone'
        x: root.destination === 'left' ? 0 : root.sidebarWidth
        width: root.destination === 'left' ? root.sidebarWidth : Math.max(0, parent.width - root.sidebarWidth)
        height: parent.height
        color: Qt.alpha(Theme.tokens.text, 0.05)
        opacity: root.destination ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 120 } }
    }
    DropArea {
        id: target
        objectName: 'bar-drag-ingress'
        anchors.fill: parent
        onEntered: drag => root.enter(drag)
        onPositionChanged: drag => root.enter(drag)
        onExited: root.leave()
        onDropped: drop => root.receive(drop)
    }
}
