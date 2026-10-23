import QtQuick
import qs.components
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
    // The bar's center group ends here; past it (the right side, which owns no drop target) a drag
    // goes nowhere instead of falling through to the Stash. The center does the same during a Stash drag-out.
    property real centerRight: width
    // The left group's content, which the left zone's rim hugs.
    property real leftContentStart: 0
    property real leftContentEnd: sidebarWidth
    property string destination: ''
    property string openedSurface: ''
    // The drawer is built on first use. While it is still being built, this copy of the offer
    // (the drag event itself does not outlive its handler) lets it enter drag mode once it exists.
    property var pendingSidebarOffer: null
    readonly property bool writable: !services.preview && !services.safeMode
    // A Stash row or photo is being dragged out. Dropping it back on the Stash is a no-op, so the
    // activity side then takes nothing, silently; the left side still takes the file.
    readonly property bool stashExporting: !!services.stash && services.stash.exporting === true
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
    function sideAt(x) { return x < sidebarWidth ? 'left' : x <= centerRight && !stashExporting ? 'activity' : ''; }
    function receive(drop) {
        dwell.stop();
        root.pendingSidebarOffer = null;
        if (!writable || !destination) { drop.accepted = false; return; }
        if (destination === 'activity' && stashExporting) { drop.accepted = false; destination = ''; return; }
        root.reveal();
        if (root.destination === 'left') {
            if (root.leftHost.leftContent) root.leftHost.leftContent.handleDrop(drop, '');
            else drop.accepted = false;
        } else {
            const grid = root.surfaceHost.activityContent?.shelfGrid;
            if (grid && grid.receiveDrop(drop)) {  }
            else {
                drop.accepted = false;
                if (grid && !grid.message) grid.message = root.services.text('Не вдалося зберегти цей вміст.', 'Could not save this content.');
            }
        }
        root.destination = '';
        if (!root.inside && root.ownsSurface) leaveGrace.restart();
    }
    function offerSnapshot(drag) {
        const offer = DropLogic.readOffer(drag);
        return { formats: offer.ok ? [offer.mime] : [],
            getDataAsString: function(mime) { return offer.ok && mime === offer.mime ? offer.value : ''; } };
    }
    Timer { id: dwell; objectName: 'bar-drag-dwell'; interval: 300; onTriggered: if (root.destination) root.reveal() }
    // Moves the hover to a side of the bar. The left drawer enters drag mode at once (still hidden,
    // or as soon as it is built) so it shows quick actions the moment the dwell reveals it.
    // `entering` keeps a drag that starts over the dead right side, so moving it to a zone later
    // still reaches this area; moves over the dead side are refused.
    function enter(drag, entering) {
        const mime = DropLogic.offerMime(drag.formats);
        const side = root.sideAt(drag.x);
        const sidebar = root.leftHost.leftContent;
        if (!side) {
            drag.accepted = !!entering && root.writable && (!!mime || DropLogic.supportsShelfOffer(drag.formats));
            if (!root.destination) return;
            dwell.stop();
            if (root.destination === 'left' && sidebar && typeof sidebar.leaveDrag === 'function') sidebar.leaveDrag();
            root.destination = '';
            root.pendingSidebarOffer = null;
            if (root.ownsSurface) root.services.popups.closeSurface(root.openedSurface, root.outputId);
            return;
        }
        drag.accepted = root.writable && (side === 'left' ? !!mime : DropLogic.supportsShelfOffer(drag.formats));
        if (!drag.accepted) return;
        drag.accept(Qt.CopyAction);
        if (root.destination === side) return;
        root.pendingSidebarOffer = null;
        if (side === 'left') {
            root.leftHost.prepareSide('left');
            if (sidebar && typeof sidebar.enterDrag === 'function') sidebar.enterDrag(drag);
            else if (!sidebar) root.pendingSidebarOffer = root.offerSnapshot(drag);
        } else if (sidebar && typeof sidebar.clearDrag === 'function') sidebar.clearDrag();
        root.destination = side;
        dwell.restart();
    }
    function leave() {
        dwell.stop();
        const sidebar = root.leftHost.leftContent;
        if (root.destination === 'left' && sidebar && typeof sidebar.leaveDrag === 'function') sidebar.leaveDrag();
        root.destination = '';
        root.pendingSidebarOffer = null;
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
        target: root.leftHost
        ignoreUnknownSignals: true
        function onLeftContentChanged() {
            const sidebar = root.leftHost.leftContent;
            const offer = root.pendingSidebarOffer;
            if (!sidebar) return;
            root.pendingSidebarOffer = null;
            if (offer && root.destination === 'left' && typeof sidebar.enterDrag === 'function') sidebar.enterDrag(offer);
        }
    }
    Connections {
        target: root.surfaceHost
        function onActivityContentChanged() {
            if (root.destination === 'activity' && root.services.popups.isOpen('activity', root.outputId)
                    && root.surfaceHost.activityContent) root.surfaceHost.activityContent.selectTab(2);
        }
    }
    // The target group wears the drop rim: a dashed pill hugging the left group or the center,
    // gliding between them.
    DropOutline {
        objectName: 'bar-drag-zone'
        readonly property real pad: 8
        readonly property bool leftZone: root.destination === 'left'
        x: Math.max(2, (leftZone ? root.leftContentStart : root.sidebarWidth) - pad)
        y: 3
        width: Math.max(0, Math.min(root.width - 2, (leftZone ? root.leftContentEnd : root.centerRight) + pad) - x)
        height: Math.max(0, root.height - 6)
        capsule: true
        active: !!root.destination
        strokeWidth: 1.5
        dashLength: 6
        gapLength: 5
        fill: Qt.alpha(Theme.tokens.text, 0.04)
        opacity: root.destination ? 1 : 0
        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
        Behavior on x { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
    }
    DropArea {
        id: target
        objectName: 'bar-drag-ingress'
        anchors.fill: parent
        onEntered: drag => root.enter(drag, true)
        onPositionChanged: drag => root.enter(drag)
        onExited: root.leave()
        onDropped: drop => root.receive(drop)
    }
}
