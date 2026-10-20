import QtQuick
import Quickshell
import qs.shell
import qs.features.shelf
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
    }
    property QtObject shelf: QtObject {
        property bool ready: true
        property bool writable: true
        property var entries: []
        property string loadError: ''
        property int serial: 0
        signal commandFinished(string requestId, var result)
        function addUris(uris) {
            const request = 'add-' + (++serial);
            const mutation = ShelfLogic.addShelfUris({ schemaVersion: 1, entries: entries }, uris,
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
        function prepareSide(side) {}
    }
    property QtObject menu: QtObject {
        property int currentIndex: 0
        property var shelfGrid: grid
        function selectTab(index) { currentIndex = index; }
    }
    property QtObject sidebar: QtObject {
        property string text: ''
        function handleDrop(drop, target) { text = drop.getDataAsString(drop.formats[0]); drop.accept(Qt.CopyAction); }
    }
    FloatingWindow {
        visible: true
        implicitWidth: 500; implicitHeight: 400
        DragIngress { id: ingress; width: 500; height: 40; sidebarWidth: 100;
            services: root.services; surfaceHost: root.host; outputId: 'fixture' }
        ShelfGrid { id: grid; x: 40; y: 60; width: 420; shelf: root.shelf; readOnly: root.services.preview }
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
                root.host.dragHovered = false;
            } else if (root.phase === 2) {
                root.check('leaving-auto-opened-panel-closes-after-grace', root.popups.surface === '');
                root.popups.open('activity', 'fixture');
                ingress.destination = 'activity'; ingress.reveal();
                root.host.dragHovered = true; root.host.dragHovered = false;
            } else if (root.phase === 3) {
                root.check('manual-panel-is-not-closed-by-drag-leave', root.popups.surface === 'activity');
                const bad = root.offer('text/uri-list', 'https://example.test/file.txt');
                ingress.destination = 'activity'; ingress.receive(bad);
                root.check('remote-uri-rejected-without-changing-shelf', !bad.accepted
                    && root.shelf.entries.length === 1 && !!grid.message);
                root.services.preview = true;
                ingress.destination = 'activity';
                const blocked = root.offer('text/uri-list', 'file:///tmp/ignored.txt');
                ingress.receive(blocked);
                root.check('preview-rejects-writes', !blocked.accepted && root.shelf.entries.length === 1);
                root.services.preview = false;
                ingress.destination = 'left';
                const text = root.offer('text/plain;charset=utf-8', 'hello');
                ingress.receive(text);
                root.check('bar-text-drop-routes-to-sidebar', text.accepted && root.sidebar.text === 'hello'
                    && root.popups.surface === 'left');
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.checks.every(c => c.passed) ? 'pass' : 'fail', checks: root.checks }));
                Qt.quit();
            }
            root.phase++;
        }
    }
}
