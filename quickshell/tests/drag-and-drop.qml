import QtQuick
import Quickshell
import qs.shell
import qs.features.shelf
import qs.theme
import '../logic/shelf.mjs' as ShelfLogic

ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property PopupManager popups: PopupManager {}
    property QtObject services: QtObject {
        property bool preview: false
        property bool safeMode: false
        property var popups: root.popups
        readonly property var shelf: root.shelf
        readonly property QtObject stash: QtObject { property bool exporting: false }
        readonly property QtObject toolWorkspace: QtObject { property int exports: 0 }
        function text(uk, en) { return en; }
    }
    property QtObject shelf: QtObject {
        property bool ready: true
        property bool writable: true
        property var entries: []
        property var offers: []
        property var files: ({ metadata: ({}) })
        property string loadError: ''
        property int serial: 0
        signal commandFinished(string requestId, var result)
        // Web content goes to the content helper in the real service; here it becomes a link.
        function addOffer(offer) {
            const request = 'offer-' + (++serial);
            offers = offers.concat([offer]);
            entries = entries.concat([{ id: 'link-' + serial, kind: 'link', uri: offer.uris.trim(), label: offer.uris.trim(),
                addedAt: new Date().toISOString(), pinned: false }]);
            Qt.callLater(() => commandFinished(request, { ok: true }));
            return request;
        }
        function addUris(uris) {
            const request = 'add-' + (++serial);
            const mutation = ShelfLogic.addShelfUris({ schemaVersion: 2, entries: entries }, uris,
                () => 'file-' + serial);
            if (mutation.ok) entries = mutation.document.entries;
            Qt.callLater(() => commandFinished(request, mutation));
            return request;
        }
    }
    property QtObject host: QtObject {
        property bool dragHovered: false
        property bool pointerHovered: false
        property var activityContent: menu
        property var leftContent: sidebar
        property var prepared: []
        function prepareSide(side) { prepared = prepared.concat([side]); }
    }
    // Opening a menu that is not built yet builds it at once, as SurfaceHost does.
    property bool activityUnbuilt: false
    Connections {
        target: root.popups
        function onChanged() {
            if (!root.activityUnbuilt || !root.popups.isOpen('activity', 'fixture')) return;
            root.activityUnbuilt = false;
            root.host.activityContent = root.menu;
        }
    }
    property QtObject menu: QtObject {
        property int currentIndex: 0
        property var shelfGrid: quick
        function selectTab(index) { currentIndex = index; }
    }
    property QtObject sidebar: QtObject {
        property string text: ''
        property string dragState: ''
        function handleDrop(drop, target) { text = drop.getDataAsString(drop.formats[0]); drop.accept(Qt.CopyAction); }
        function enterDrag(drag) { dragState = 'entered'; return { mime: 'text/uri-list' }; }
        function leaveDrag() { dragState = 'left'; }
        function clearDrag() { dragState = 'cleared'; }
    }
    // A bar hover at x; the bar is 500 wide and its left zone 100.
    function hover(x) {
        return { formats: ['text/uri-list'], x: x, accepted: false, getDataAsString: () => 'file:///tmp/a.png\r\n',
            accept: function(action) { this.accepted = action === Qt.CopyAction; } };
    }
    FloatingWindow {
        visible: true
        implicitWidth: 500; implicitHeight: 400
        color: Theme.tokens.surface
        Rectangle { id: barBackdrop; width: 500; height: 40; color: Theme.tokens.surface }
        DragIngress { id: ingress; parent: barBackdrop; width: 500; height: 40; sidebarWidth: 100; centerRight: 400;
            services: root.services; surfaceHost: root.host; outputId: 'fixture' }
        StashQuick { id: quick; x: 54; y: 60; width: 392; services: root.services; readOnly: root.services.preview }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function check(name, passed) { checks = checks.concat([{ name: name, passed: !!passed }]); }
    function offer(mime, value) {
        return { formats: [mime], accepted: false, getDataAsString: () => value,
            accept: function(action) { this.accepted = action === Qt.CopyAction; } };
    }
    Timer {
        interval: 260; repeat: true; running: true
        onTriggered: {
            if (root.phase === 0) {
                const parsed = ShelfLogic.parseUriList('file:///tmp/Caf%C3%A9%20notes.txt\r\n');
                root.check('qml-uri-decoder-does-not-require-TextEncoder', parsed.ok);
                ingress.destination = 'activity';
                const drop = root.offer('text/uri-list', 'file:///tmp/Caf%C3%A9%20notes.txt\r\n');
                ingress.receive(drop);
                root.check('bar-file-drop-reveals-shelf-and-adds-reference', drop.accepted
                    && root.popups.surface === 'activity' && root.menu.currentIndex === 2
                    && root.shelf.entries.length === 1);
                root.host.dragHovered = true;
            } else if (root.phase === 1) {
                root.check('drag-in-panel-keeps-auto-opened-shelf', root.popups.surface === 'activity');
                const row = quick.rows.length === 1 ? root.find(quick, 'stash-quick-row-' + quick.rows[0].id) : null;
                root.check('bar-drop-over-activity-lands-in-stash', !!row && row.visible
                    && quick.rows[0].uri === 'file:///tmp/Caf%C3%A9%20notes.txt' && quick.message === '');
                root.host.dragHovered = false;
            } else if (root.phase === 2) {
                root.check('leaving-auto-opened-panel-closes-after-grace', root.popups.surface === '');
                root.popups.open('activity', 'fixture');
                ingress.destination = 'activity'; ingress.reveal();
                root.host.dragHovered = true; root.host.dragHovered = false;
            } else if (root.phase === 3) {
                root.check('manual-panel-is-not-closed-by-drag-leave', root.popups.surface === 'activity');
                // The Stash keeps links: a remote URI goes to the content helper instead of being refused.
                const remote = root.offer('text/uri-list', 'https://example.test/file.txt');
                ingress.destination = 'activity'; ingress.receive(remote);
                root.check('remote-link-drop-lands-in-stash', remote.accepted && root.shelf.offers.length === 1
                    && root.shelf.offers[0].uris === 'https://example.test/file.txt' && root.shelf.entries.length === 2);
                const unreadable = { formats: ['text/uri-list'], accepted: false, getDataAsString: () => null,
                    accept: function(action) { this.accepted = action === Qt.CopyAction; } };
                ingress.destination = 'activity'; ingress.receive(unreadable);
                root.check('unreadable-drop-rejected-with-message', !unreadable.accepted
                    && root.shelf.entries.length === 2 && !!quick.message);
                root.services.preview = true;
                ingress.destination = 'activity';
                const blocked = root.offer('text/uri-list', 'file:///tmp/ignored.txt');
                ingress.receive(blocked);
                root.check('preview-rejects-writes', !blocked.accepted && root.shelf.entries.length === 2);
                root.services.preview = false;
                // A Stash row dragged out and released over the bar's center: no zone, no save, no error.
                quick.message = '';
                root.services.stash.exporting = true;
                const self = root.hover(300);
                ingress.enter(self, true);
                const noZone = ingress.destination === '';
                ingress.receive(self);
                ingress.destination = 'activity';
                const late = root.offer('text/uri-list', 'file:///tmp/Caf%C3%A9%20notes.txt\r\n');
                ingress.receive(late);
                root.check('stash-self-drop-is-silent', noZone && !self.accepted && !late.accepted
                    && ingress.destination === '' && quick.message === '' && root.shelf.entries.length === 2);
                root.services.stash.exporting = false;
                ingress.destination = 'left';
                const text = root.offer('text/plain;charset=utf-8', 'hello');
                ingress.receive(text);
                root.check('bar-text-drop-routes-to-sidebar', text.accepted && root.sidebar.text === 'hello'
                    && root.popups.surface === 'left');
                // A drop is a decision to use the drawer: it no longer closes on its own.
                root.check('dropped-on-drawer-stays-until-dismissed', ingress.openedSurface === '');
                root.popups.closeSurface('left', 'fixture');
                root.popups.closeSurface('activity', 'fixture');
                ingress.openedSurface = '';
            } else if (root.phase === 4) {
                // Crossing the center on the way to the left corner must not open Shelf.
                ingress.enter(root.hover(300));
                root.check('center-hover-does-not-open-shelf-at-once', !root.popups.isOpen('activity', 'fixture'));
                ingress.enter(root.hover(40));
                root.check('left-hover-puts-drawer-in-drag-mode-early', root.sidebar.dragState === 'entered');
            } else if (root.phase === 5) {
                // The left zone's 150 ms dwell has passed; the center's 300 ms outlasts one 260 ms tick.
                root.check('left-zone-answers-sooner-than-the-center', root.popups.isOpen('left', 'fixture')
                    && ingress.leftDwell < ingress.centerDwell);
                root.check('bar-zone-capsule-rises-over-the-left-group', ingress.zoneLift > 0.7);
                barBackdrop.grabToImage(result => result.saveToFile('/tmp/pentad-dnd-zone-left.png'));
            } else if (root.phase === 6) {
                root.check('left-dwell-opens-only-the-drawer', root.popups.isOpen('left', 'fixture')
                    && !root.popups.isOpen('activity', 'fixture'));
                ingress.enter(root.hover(300));
                root.check('moving-to-center-clears-drawer-drag-mode', root.sidebar.dragState === 'cleared');
            } else if (root.phase === 7) {
                root.check('bar-zone-capsule-stays-up-gliding-to-the-center', ingress.zoneLift > 0.7);
                barBackdrop.grabToImage(result => result.saveToFile('/tmp/pentad-dnd-zone-center.png'));
            } else if (root.phase === 8) {
                root.check('switching-sides-closes-the-drag-opened-drawer', root.popups.isOpen('activity', 'fixture')
                    && !root.popups.isOpen('left', 'fixture'));
                // Past the center group the bar owns no target: no zone, no Shelf. The drag-opened
                // panel gets the same grace as leaving the bar, then closes.
                const dead = root.hover(460);
                ingress.enter(dead);
                root.check('right-side-is-not-a-drop-target', ingress.destination === '' && !dead.accepted
                    && ingress.offZone && root.popups.isOpen('activity', 'fixture'));
                const deadEntry = root.hover(460);
                ingress.enter(deadEntry, true);
                root.check('drag-entering-on-the-right-is-still-tracked', deadEntry.accepted && ingress.destination === '');
                ingress.leave();
            } else if (root.phase === 9) {
                root.check('leaving-the-bar-closes-the-drag-opened-panel', !root.popups.isOpen('activity', 'fixture'));
                // The drawer is built on first use: one that does not exist yet enters drag mode
                // with a copy of the offer as soon as it is built.
                root.sidebar.dragState = '';
                root.host.leftContent = null;
                ingress.enter(root.hover(40));
                const offer = ingress.pendingSidebarOffer;
                const waiting = root.sidebar.dragState === '' && !!offer
                    && offer.getDataAsString('text/uri-list') === 'file:///tmp/a.png\r\n';
                root.host.leftContent = root.sidebar;
                root.check('unbuilt-drawer-enters-drag-mode-once-built', waiting && root.sidebar.dragState === 'entered'
                    && ingress.pendingSidebarOffer === null);
                ingress.leave();
                // The activity menu is built on first use too: a drag over the center starts building
                // it, and a drop that arrives before it exists lands in the Stash once opening builds it.
                root.host.activityContent = null;
                root.host.prepared = [];
                root.menu.currentIndex = 0;
                root.activityUnbuilt = true;
                const before = root.shelf.entries.length;
                ingress.enter(root.hover(250), true);
                const preparing = root.host.prepared.indexOf('activity') >= 0 && ingress.destination === 'activity';
                const early = root.offer('text/uri-list', 'file:///tmp/early.txt\r\n');
                ingress.receive(early);
                root.check('unbuilt-activity-menu-takes-a-drop-once-built', preparing && early.accepted
                    && root.host.activityContent === root.menu && root.menu.currentIndex === 2
                    && root.shelf.entries.length === before + 1 && quick.message === '');
                root.popups.closeSurface('activity', 'fixture');
                // Content the tools cannot use: the enter is accepted so the drag stays tracked, the
                // zone refuses it, and only a drag that rests there is told why.
                const html = { formats: ['text/html'], x: 40, accepted: false, getDataAsString: () => '<img src="a.png">',
                    accept: function(action) { this.accepted = action === Qt.CopyAction; } };
                ingress.enter(html, true);
                const moved = { formats: ['text/html'], x: 44, accepted: true, getDataAsString: () => '' };
                ingress.enter(moved);
                root.check('unusable-drag-is-tracked-but-refused', html.accepted && !moved.accepted && ingress.destination === ''
                    && ingress.refusing && !ingress.refused && !root.popups.isOpen('left', 'fixture'));
            } else if (root.phase === 10) {
                root.check('resting-unusable-drag-is-told-why', ingress.refused && !root.popups.isOpen('left', 'fixture'));
                // The usable drag follows once the refused capsule is captured.
                barBackdrop.grabToImage(result => {
                    result.saveToFile('/tmp/pentad-dnd-zone-refused.png');
                    ingress.enter(root.hover(40));
                    root.check('usable-drag-clears-the-refusal', !ingress.refused && !ingress.refusing && ingress.destination === 'left');
                });
            } else if (root.phase === 11) {
                // Straying onto the dead side and back within the grace keeps the drag-opened drawer.
                const opened = root.popups.isOpen('left', 'fixture') && ingress.openedSurface === 'left';
                ingress.enter(root.hover(460));
                const strayed = root.popups.isOpen('left', 'fixture');
                ingress.enter(root.hover(40));
                root.check('straying-right-does-not-close-at-once', opened && strayed);
            } else if (root.phase === 12) {
                root.check('coming-back-within-the-grace-keeps-the-drawer', root.popups.isOpen('left', 'fixture'));
                // A plain pointer in the drawer means it is in use: leaving no longer closes it.
                root.host.pointerHovered = true;
                root.check('drawer-in-use-is-no-longer-drag-owned', ingress.openedSurface === '');
                root.host.pointerHovered = false;
                ingress.leave();
            } else if (root.phase === 13) {
                root.check('drawer-in-use-stays-open-after-the-drag-leaves', root.popups.isOpen('left', 'fixture'));
                root.popups.closeSurface('left', 'fixture');
                // A drop that beats the drawer's build is kept and handed over once the drawer exists.
                root.sidebar.text = '';
                root.host.leftContent = null;
                ingress.enter(root.hover(40));
                const early = root.offer('text/plain', 'queued');
                ingress.receive(early);
                const kept = early.accepted && !!ingress.pendingSidebarDrop && root.sidebar.text === '';
                root.host.leftContent = root.sidebar;
                root.check('drop-before-the-drawer-is-built-is-delivered', kept && root.sidebar.text === 'queued'
                    && ingress.pendingSidebarDrop === null && root.popups.isOpen('left', 'fixture'));
                root.popups.closeSurface('left', 'fixture');
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(c => c.passed) ? 'pass' : 'fail', checks: root.checks }));
                Qt.quit();
            }
            root.phase++;
        }
    }
}
