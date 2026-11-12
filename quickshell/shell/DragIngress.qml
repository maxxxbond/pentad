import QtQuick
import qs.components
import qs.theme
import '../logic/drag-drop.mjs' as DropLogic
import '../logic/shelf.mjs' as ShelfLogic
import '../logic/spring.mjs' as SpringLogic

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
    // A drop that reached the bar before the drawer existed: it is handed over once the drawer is built.
    property var pendingSidebarDrop: null
    // The bar face, which owns the bar's shared tooltip; the refusal hint shows through it.
    property Item barFace: null
    // The left zone answers sooner than the center: its drawer is the usual target, while the center
    // is crossed on the way there and must not flash the Stash.
    readonly property int leftDwell: 150
    readonly property int centerDwell: 300
    // The drag is over the bar but over nothing that takes it: the dead right side, or a zone that
    // cannot use this content. It then counts as outside, so a drag-opened panel closes after the grace.
    property bool offZone: false
    // The tools cannot use what rests over the left zone. After the dwell the zone says so (`refused`)
    // instead of staying silent; a drag that only passes by shows nothing.
    property bool refusing: false
    property bool refused: false
    readonly property bool writable: !services.preview && !services.safeMode
    // A Stash row or photo is being dragged out. Dropping it back on the Stash is a no-op, so the
    // activity side then takes nothing, silently; the left side still takes the file.
    readonly property bool stashExporting: !!services.stash && services.stash.exporting === true
    readonly property bool inside: (target.containsDrag && !offZone) || surfaceHost.dragHovered || surfaceHost.pointerHovered || !!surfaceHost.dragOutActive
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
    function stopRefusing() {
        refuseDwell.stop();
        refusing = false;
        refused = false;
    }
    function receive(drop) {
        dwell.stop();
        root.stopRefusing();
        root.offZone = false;
        root.pendingSidebarOffer = null;
        if (!writable || !destination) { drop.accepted = false; return; }
        if (destination === 'activity' && stashExporting) { drop.accepted = false; destination = ''; return; }
        root.reveal();
        if (root.destination === 'left') {
            if (root.leftHost.leftContent) root.leftHost.leftContent.handleDrop(drop, '');
            else {
                // Opening builds the drawer at once; one that is still missing gets a copy of the drop
                // (the event does not outlive this handler) as soon as it exists.
                root.pendingSidebarDrop = root.offerSnapshot(drop);
                drop.accept(Qt.CopyAction);
            }
            // A drop is a decision to use the drawer, and a refused one leaves its reason there to
            // read: from here on the drawer closes like one opened by hand.
            root.destination = '';
            if (root.openedSurface === 'left') root.openedSurface = '';
            return;
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
        return { formats: offer.ok ? [offer.mime] : [], accepted: false,
            getDataAsString: function(mime) { return offer.ok && mime === offer.mime ? offer.value : ''; },
            accept: function() { this.accepted = true; } };
    }
    Timer {
        id: dwell
        objectName: 'bar-drag-dwell'
        interval: root.destination === 'left' ? root.leftDwell : root.centerDwell
        onTriggered: if (root.destination) root.reveal()
    }
    Timer { id: refuseDwell; interval: root.leftDwell; onTriggered: if (root.refusing) root.refused = true }
    // Moves the hover to a side of the bar. The left drawer enters drag mode at once (still hidden,
    // or as soon as it is built) so it shows quick actions the moment the dwell reveals it. Over the
    // center, the activity menu (whose Stash tab takes the drop) starts building during the dwell; a
    // drop that comes first opens it, which finishes the build before the drop is handed over.
    // A refused enter ends the tracking of that drag, so the entering event is always accepted and
    // only later moves are refused: a drag that starts over the dead right side, or over a zone that
    // cannot use it, still reaches the other zones.
    function enter(drag, entering) {
        const mime = DropLogic.offerMime(drag.formats);
        const side = root.sideAt(drag.x);
        const sidebar = root.leftHost.leftContent;
        const taken = root.writable && (side === 'left' ? !!mime : side === 'activity' && DropLogic.supportsShelfOffer(drag.formats));
        if (!taken) {
            drag.accepted = !!entering && root.writable;
            root.offZone = true;
            if (root.writable && side === 'left') {
                if (!root.refusing) {
                    root.refusing = true;
                    refuseDwell.restart();
                }
            } else root.stopRefusing();
            if (!root.destination) return;
            dwell.stop();
            if (root.destination === 'left' && sidebar && typeof sidebar.leaveDrag === 'function') sidebar.leaveDrag();
            root.destination = '';
            root.pendingSidebarOffer = null;
            // The same grace as leaving the bar: a pointer that strays here and comes back keeps the panel.
            if (root.ownsSurface) leaveGrace.restart();
            return;
        }
        root.offZone = false;
        root.stopRefusing();
        leaveGrace.stop();
        drag.accepted = true;
        drag.accept(Qt.CopyAction);
        if (root.destination === side) return;
        root.pendingSidebarOffer = null;
        if (side === 'left') {
            root.leftHost.prepareSide('left');
            if (sidebar && typeof sidebar.enterDrag === 'function') sidebar.enterDrag(drag);
            else if (!sidebar) root.pendingSidebarOffer = root.offerSnapshot(drag);
        } else {
            root.surfaceHost.prepareSide('activity');
            if (sidebar && typeof sidebar.clearDrag === 'function') sidebar.clearDrag();
        }
        root.destination = side;
        dwell.restart();
    }
    function leave() {
        dwell.stop();
        root.stopRefusing();
        root.offZone = false;
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
            const drop = root.pendingSidebarDrop;
            root.pendingSidebarDrop = null;
            if (drop && typeof sidebar.handleDrop === 'function') sidebar.handleDrop(drop, '');
        }
        // A plain pointer in the drawer (hover is silent during a drag) means it is in use: it then
        // closes like one opened by hand, not when the pointer leaves it.
        function onPointerHoveredChanged() {
            if (root.leftHost.pointerHovered && root.openedSurface === 'left') root.openedSurface = '';
        }
    }
    // So does a drop released inside the drawer, taken or refused.
    Connections {
        target: root.leftHost.leftContent || null
        ignoreUnknownSignals: true
        function onDropHandled() { if (root.openedSurface === 'left') root.openedSurface = ''; }
    }
    Connections {
        target: root.surfaceHost
        function onActivityContentChanged() {
            if (root.destination === 'activity' && root.services.popups.isOpen('activity', root.outputId)
                    && root.surfaceHost.activityContent) root.surfaceHost.activityContent.selectTab(2);
        }
    }
    // While a file the Stash takes is held over the bar's activity side, the panel's drop zones are
    // already awake, so the target is visible before the pointer reaches it.
    Binding {
        target: root.surfaceHost.activityContent ?? null
        property: "dragAwake"
        value: root.destination === 'activity'
        when: !!root.surfaceHost.activityContent && root.surfaceHost.activityContent.dragAwake !== undefined
        restoreMode: Binding.RestoreValue
    }
    // How far the bar's target capsule has risen, 0..1, for tests.
    readonly property real zoneLift: zoneLiftSpring.value
    // The target group wears a soft tinted capsule with no rim, rising on the drop zones' hover
    // spring and gliding between the left group and the center on the soft preset. A refused drag
    // gets a fainter capsule that stays still, with the reason in the bar's tooltip.
    Item {
        id: zone
        objectName: 'bar-drag-zone'
        readonly property real pad: 8
        readonly property bool leftZone: root.destination === 'left' || root.refused
        readonly property real targetX: Math.max(2, (leftZone ? root.leftContentStart : root.sidebarWidth) - pad)
        readonly property real targetWidth: Math.max(0, Math.min(root.width - 2, (leftZone ? root.leftContentEnd : root.centerRight) + pad) - targetX)
        readonly property real lift: Math.max(0, Math.min(1, zoneLiftSpring.value))
        // While the capsule is hidden it jumps to the new side instead of gliding there.
        readonly property bool shown: lift > 0.02 || root.refused
        x: zoneX.value
        width: zoneWidth.value
        height: root.height
        visible: shown

        PentadSpring {
            id: zoneLiftSpring
            stiffness: SpringLogic.fileDropSprings.hover[0]
            damping: SpringLogic.fileDropSprings.hover[1]
            target: root.destination ? 1 : 0
        }
        PentadSpring {
            id: zoneX
            stiffness: SpringLogic.sharedSprings.soft[0]
            damping: SpringLogic.sharedSprings.soft[1]
            target: zone.targetX
        }
        PentadSpring {
            id: zoneWidth
            stiffness: SpringLogic.sharedSprings.soft[0]
            damping: SpringLogic.sharedSprings.soft[1]
            target: zone.targetWidth
        }
        function place() {
            zoneX.snap();
            zoneWidth.snap();
        }
        // A refused drag's capsule stands still: it never glides into place.
        readonly property bool still: root.refused && !root.destination
        onShownChanged: if (shown) place()
        onStillChanged: if (still) place()
        Component.onCompleted: place()
        FrameAnimation {
            running: root.visible && (!zoneLiftSpring.settled || !zoneX.settled || !zoneWidth.settled)
            onTriggered: {
                if (!zone.shown || zone.still)
                    zone.place();
                [zoneLiftSpring, zoneX, zoneWidth].forEach(spring => spring.advance(frameTime));
            }
        }
        // The capsule rises from a slimmer band to nearly the bar's height as it lifts.
        Rectangle {
            readonly property real fullHeight: Math.max(0, root.height - 6)
            width: parent.width
            height: root.refused && !root.destination ? fullHeight : fullHeight * (0.7 + 0.3 * zone.lift)
            y: Math.round((root.height - height) / 2)
            radius: height / 2
            color: Qt.alpha(Theme.tokens.text, Math.max(0.1 * zone.lift, root.refused ? 0.05 : 0))
        }
    }
    Item {
        parent: root.barFace || root
        x: Math.max(2, root.leftContentStart - zone.pad)
        width: Math.max(0, Math.min(root.width - 2, root.leftContentEnd + zone.pad) - x)
        height: root.height
        PentadToolTip {
            objectName: 'bar-drag-refusal'
            visible: root.refused
            delay: 0
            text: root.services.text('Інструменти беруть файли, посилання й текст', 'Tools take files, links and text')
        }
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
