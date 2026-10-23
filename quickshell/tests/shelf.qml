import QtQuick
import QtQml
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import qs.features.shelf
import qs.theme

ShellRoot {
    id: root
    property int phase: 0
    property var checks: []
    property string baseUrl: ''
    property string downloadedUri: ''
    property var results: ({})
    property var ids: ({})
    property var bulkUris: Array.from({ length: 60 }, (unused, index) => 'file:///tmp/bulk%20' + index + '.txt')
    readonly property string stateHome: Quickshell.env('XDG_STATE_HOME')
    // The one v1 seed: both fake stores start from it, so the migration runs on load.
    readonly property var legacyDocument: ({ schemaVersion: 1, entries: [{ id: 'legacy', uri: 'file:///tmp/legacy%20note.txt', label: 'legacy note.txt' }] })
    // A v2 store already at the unpinned limit; links only, so no file metadata is fetched for it.
    readonly property var fullDocument: ({ schemaVersion: 2, entries: Array.from({ length: 300 }, (unused, index) =>
        ({ id: 'link-' + index, kind: 'link', uri: 'https://example.test/' + index, label: 'Link ' + index, addedAt: '', pinned: false })) })
    component FakeConfig: QtObject {
        property bool preview: false
        property var seed: root.legacyDocument
        property string helperPath: decodeURIComponent(Qt.resolvedUrl('helpers/pentad-files.py').toString().replace(/^file:\/\//, ''))
        property var documents: ({})
        property int serial: 0
        property int saves: 0
        property int failSaves: 0
        property var lastSaved: null
        signal commandFinished(string requestId, var result)
        signal documentChanged(string name)
        function reload(name) {
            var requestId = 'read-' + (++serial);
            if (documents.shelf === undefined)
                documents = Object.assign({}, documents, { shelf: seed });
            Qt.callLater(function() { commandFinished(requestId, { ok: true }); });
            return requestId;
        }
        function save(name, value) {
            var requestId = 'save-' + (++serial);
            saves++;
            lastSaved = value;
            if (failSaves > 0) {
                failSaves--;
                Qt.callLater(function() { commandFinished(requestId, { ok: false, reason: 'too-large' }); });
                return requestId;
            }
            // Like the real store, the document and its change signal arrive with the write result.
            Qt.callLater(function() {
                documents = Object.assign({}, documents, { [name]: value });
                documentChanged(name);
                commandFinished(requestId, { ok: true });
            });
            return requestId;
        }
    }
    property FakeConfig fakeConfig: FakeConfig {}
    property FakeConfig failingConfig: FakeConfig { failSaves: 1 }
    property FakeConfig fullConfig: FakeConfig { seed: root.fullDocument }
    property Shelf shelf: Shelf { config: root.fakeConfig }
    // The Stash view on the shelf, with its own controller (selection, query, filter).
    property QtObject viewServices: QtObject {
        function text(uk, en) { return uk; }
        readonly property var shelf: root.shelf
        readonly property StashController stash: StashController { config: root.fakeConfig }
        readonly property QtObject toolWorkspace: QtObject { property int exports: 0 }
        readonly property QtObject filePicker: QtObject { property bool busy: false }
    }
    // The Activity quick tab on the same shelf, with its own Stash controller.
    property TestEvent pointer: TestEvent {}
    property int quickCloses: 0
    property QtObject quickServices: QtObject {
        function text(uk, en) { return uk; }
        readonly property var shelf: root.shelf
        readonly property StashController stash: StashController { config: root.fakeConfig }
        readonly property QtObject toolWorkspace: QtObject { property int exports: 0 }
    }
    property Shelf failingShelf: Shelf { config: root.failingConfig }
    property Shelf fullShelf: Shelf { config: root.fullConfig }
    property Connections resultLog: Connections {
        target: root.shelf
        function onCommandFinished(requestId, result) { root.results = Object.assign({}, root.results, { [requestId]: result }); }
    }
    property Connections fullResultLog: Connections {
        target: root.fullShelf
        function onCommandFinished(requestId, result) { root.results = Object.assign({}, root.results, { ['full:' + requestId]: result }); }
    }
    // What the fake clipboard helper recorded, one JSON object per line; read on demand.
    property var helperLog: null
    property Process logReader: Process {
        command: ['cat', root.stateHome + '/stash-clipboard-requests.jsonl']
        stdout: StdioCollector { onStreamFinished: root.helperLog = text.split('\n').filter(line => line.trim().length > 0).map(line => JSON.parse(line)) }
    }
    function readHelperLog() { helperLog = null; logReader.running = true; }
    FloatingWindow {
        visible: true
        implicitWidth: 520; implicitHeight: 600
        color: Theme.tokens.surface
        StashView { id: view; width: 520; height: 600; services: root.viewServices; framed: true }
    }
    FloatingWindow {
        visible: true
        implicitWidth: 420; implicitHeight: 480
        color: Theme.tokens.surface
        Rectangle {
            id: quickBackdrop
            width: 420; height: quick.height + 28
            color: Theme.tokens.surface
            StashQuick { id: quick; x: 14; y: 14; width: 392; services: root.quickServices; readOnly: false; onCloseRequested: root.quickCloses++ }
        }
    }
    Process {
        id: server
        running: true
        command: ['python3', '-u', '-c',
            "import http.server,base64\nimage=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNom1YOAAM5AZS5D+zuAAAAAElFTkSuQmCC')\nclass Handler(http.server.BaseHTTPRequestHandler):\n def do_GET(self):\n  self.send_response(200); self.end_headers(); self.wfile.write(b'<html>login</html>' if self.path=='/bad' else image)\n def log_message(self,*args): pass\ns=http.server.HTTPServer(('127.0.0.1',0),Handler)\nprint('http://127.0.0.1:'+str(s.server_port),flush=True)\ns.serve_forever()"]
        stdout: SplitParser { onRead: line => root.baseUrl = line }
    }
    Component.onDestruction: if (server.running) server.signal(9)
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = Array.prototype.slice.call(item.children || []);
        if (item.contentItem && children.indexOf(item.contentItem) < 0) children.push(item.contentItem);
        for (const child of children) { const found = find(child, name); if (found) return found; }
        return null;
    }
    // The first descendant satisfying a predicate; used for items that carry no objectName.
    function findWhere(item, test) {
        if (!item) return null;
        if (test(item)) return item;
        const children = Array.prototype.slice.call(item.children || []);
        if (item.contentItem && children.indexOf(item.contentItem) < 0) children.push(item.contentItem);
        for (const child of children) { const found = findWhere(child, test); if (found) return found; }
        return null;
    }
    // The native drag source of a Stash row or photo tile.
    function dragSourceOf(item) { return findWhere(item, child => child.uris !== undefined && child.exporting !== undefined); }
    // What the item menu offers for an entry; the menu is read, not shown.
    function menuFor(id) { view.itemMenu.entryId = id; return view.itemMenu.entries; }
    function menuAction(id, action) { return menuFor(id).find(entry => entry.action === action) || null; }
    function drop(data) {
        return { formats: Object.keys(data), accepted: false, getDataAsString: mime => data[mime],
            accept: function(action) { this.accepted = action === Qt.CopyAction; } };
    }
    function isoTime(value) { return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value); }
    function localPath(uri) { return decodeURIComponent(uri.replace(/^file:\/\//, '')); }

    function check(name, passed) { checks.push({ name: name, passed: passed === true }); }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({
            status: checks.every(function(item) { return item.passed; }) ? 'pass' : 'fail',
            checks: checks
        }));
        Qt.quit();
    }
    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            const shelf = root.shelf, config = root.fakeConfig;
            if (root.phase === 0 && shelf.ready && config.saves === 1 && !shelf.inFlight) {
                const legacy = shelf.entries[0];
                root.check('shelf loads managed state', shelf.entries.length === 1 && legacy.id === 'legacy'
                    && legacy.addedAt === '' && legacy.pinned === false);
                root.check('migrates-once', config.saves === 1 && config.documents.shelf.schemaVersion === 2
                    && config.documents.shelf.entries.length === 1 && config.documents.shelf.entries[0].addedAt === '');
                shelf.addUris(['file:///tmp/shelf%20one.txt', 'file:///tmp/shelf%20one.txt']);
                root.phase = 1;
            } else if (root.phase === 1 && shelf.entries.length === 2 && config.saves === 2) {
                root.check('duplicate URI in one drop is stored once', shelf.entries[1].label === 'shelf one.txt');
                root.check('added-entries-stamp-time', root.isoTime(shelf.entries[1].addedAt) && shelf.entries[1].pinned === false);
                shelf.addUris(['file:///tmp/shelf%20one.txt']);
                root.phase = 2;
            } else if (root.phase === 2 && config.saves === 2 && !shelf.inFlight && !shelf.queue.length) {
                const removed = shelf.entries.map(entry => entry.id);
                shelf.remove(removed[0]);
                shelf.remove(removed[1]);
                root.phase = 3;
            } else if (root.phase === 3 && shelf.entries.length === 0 && config.saves === 4) {
                root.check('remove persists the managed shelf document', config.documents.shelf.entries.length === 0);
                root.phase = 4;
            } else if (root.phase === 4 && root.baseUrl) {
                const photo = root.drop({ 'text/uri-list': root.baseUrl + '/source',
                    'text/html': '<a href="' + root.baseUrl + '/source"><img alt="Saved photo" src="' + root.baseUrl + '/image" srcset="' + root.baseUrl + '/bad 2x"></a>' });
                root.check('web-image-drop-is-accepted-by-stash-view', view.receiveDrop(photo) && photo.accepted);
                view.receiveDrop(root.drop({ 'text/uri-list': '', 'text/plain': 'https://open.spotify.com/track/7h2ABjmIKKbT7VBWFM2nZD' }));
                view.receiveDrop(root.drop({ 'text/html': '<a href="https://weather.com/forecast">Hourly Weather Forecast</a>' }));
                view.receiveDrop(root.drop({ 'text/plain': 'Read this later\nA text note' }));
                root.phase = 5;
            } else if (root.phase === 5 && shelf.entries.length === 4 && !shelf.inFlight) {
                const photo = shelf.entries[0], spotify = shelf.entries[1];
                root.check('queued-web-drops-persist-without-lost-updates', config.saves === 8
                    && shelf.entries[2].label === 'Hourly Weather Forecast' && shelf.entries[3].kind === 'text');
                root.check('photo-drop-does-not-download-local-file', photo.kind === 'image' && !photo.localUri);
                root.check('spotify-has-no-download-action', spotify.kind === 'spotify' && root.menuFor(spotify.id).length > 0
                    && !root.menuAction(spotify.id, 'download'));
                const action = root.menuAction(photo.id, 'download');
                root.check('web-photo-offers-download', !!action && action.enabled === true);
                view.itemMenu.activated(action);
                root.check('download-click-sets-pending-and-blocks-repeat', shelf.downloads[photo.id]?.pending
                    && shelf.download(photo.id) === '' && root.menuAction(photo.id, 'download').enabled === false);
                root.phase = 6;
            } else if (root.phase === 6 && !shelf.inFlight && shelf.downloads[shelf.entries[0].id]?.error) {
                const photo = shelf.entries[0];
                root.check('invalid-image-retains-entry-and-offers-retry', !photo.localUri
                    && root.menuAction(photo.id, 'download').enabled === true);
                shelf.document = { schemaVersion: 2, entries: shelf.entries.map(entry =>
                    entry.id === photo.id ? Object.assign({}, entry, { imageUrl: root.baseUrl + '/image' }) : entry) };
                shelf.entries = shelf.document.entries;
                shelf.download(photo.id);
                root.phase = 7;
            } else if (root.phase === 7 && !shelf.inFlight && shelf.entries[0].localUri) {
                const photo = shelf.entries[0];
                root.downloadedUri = photo.localUri;
                root.check('explicit-download-persists-local-file-and-preserves-source', photo.localUri.startsWith('file://')
                    && photo.uri === root.baseUrl + '/source' && photo.localUri.indexOf('/Downloads/Pentad/') >= 0);
                root.check('downloaded-entry-exports-local-uri', view.dragUrisFor(photo).join() === photo.localUri);
                shelf.preview = true;
                root.check('preview-blocks-download-actions', shelf.download(photo.id) === '');
                shelf.preview = false;
                root.phase = 8;
            } else if (root.phase === 8 && root.findWhere(root.find(view, 'stash-photo-' + shelf.entries[0].id), item => item.status === Image.Ready)) {
                root.check('downloaded-image-decodes-in-card', true);
                const source = root.dragSourceOf(root.find(view, 'stash-photo-' + shelf.entries[0].id));
                root.check('downloaded-card-exports-local-uri', !!source && source.Drag.mimeData['text/uri-list'] === shelf.entries[0].localUri + '\r\n');
                const textEntry = shelf.entries[3];
                root.check('text-entry-opens-readable-note', view.openEntry(textEntry.id)
                    && view.data.some(item => item && item.visible === true && item.text === textEntry.text));
                view.data.forEach(item => { if (item && item.text === textEntry.text && item.close) item.close(); });
                root.phase = -1;
                view.grabToImage(result => {
                    root.check('stash-view-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')));
                    root.phase = 9;
                });
            } else if (root.phase === 9) {
                // v2 actions on the four entries: photo (downloaded), spotify, link, text.
                root.ids = Object.assign({}, root.ids, { pin: shelf.pin(shelf.entries[3].id, true) });
                root.phase = 10;
            } else if (root.phase === 10 && root.results[root.ids.pin] && !shelf.inFlight) {
                const textId = shelf.entries[3].id;
                root.check('pin-persists', config.saves === 10 && config.documents.shelf.entries.find(entry => entry.id === textId).pinned === true
                    && shelf.entries[3].pinned === true && shelf.unpinnedCount === 3 && shelf.limitUnpinned === 300
                    && root.results[root.ids.pin].ok === true);
                shelf.addNote('Купити кабель');
                shelf.addNote('https://example.test/a');
                root.phase = 11;
            } else if (root.phase === 11 && shelf.entries.length === 6 && config.saves === 12 && !shelf.inFlight) {
                root.check('note-added', shelf.entries[4].kind === 'text' && shelf.entries[4].text === 'Купити кабель'
                    && root.isoTime(shelf.entries[4].addedAt));
                root.check('link-added', shelf.entries[5].kind === 'link' && shelf.entries[5].uri === 'https://example.test/a'
                    && config.documents.shelf.entries[5].kind === 'link');
                root.ids = Object.assign({}, root.ids, { blank: shelf.addNote('  \n ') });
                shelf.pasteClipboard();
                shelf.pasteClipboard();
                shelf.addUris(['file:///tmp/plain%20file.txt']);
                root.phase = 12;
            } else if (root.phase === 12 && shelf.entries.length === 9 && config.saves === 15 && !shelf.inFlight && root.results[root.ids.blank]) {
                const pasted = shelf.entries[6], owned = shelf.entries[7];
                root.check('empty-note-rejected', root.results[root.ids.blank]?.ok === false && root.results[root.ids.blank]?.reason === 'empty');
                root.check('paste-text-adds-note', pasted.kind === 'text' && pasted.text === 'Вставлено з буфера' && root.isoTime(pasted.addedAt));
                root.check('paste-image-adds-owned-file', owned.owned === true && !owned.kind && owned.label === 'clip-fixture.png'
                    && owned.uri.indexOf('/pentad/stash/clip-fixture.png') > 0
                    && config.documents.shelf.entries[7].owned === true);
                root.ids = Object.assign({}, root.ids, {
                    copyNote: shelf.copy(shelf.entries[4].id), copySpotify: shelf.copy(shelf.entries[1].id),
                    copyPhoto: shelf.copy(shelf.entries[0].id), copyFile: shelf.copy(shelf.entries[8].id),
                    copyOwned: shelf.copy(owned.id), copyMissing: shelf.copy('absent'), emptyPaste: shelf.pasteClipboard()
                });
                root.phase = 13;
            } else if (root.phase === 13 && root.results[root.ids.emptyPaste] && root.results[root.ids.copyMissing] && !shelf.inFlight) {
                // Newest first: plain file.txt, then the owned clipboard image (a photo), the pasted
                // note and the link. Photos go to the strip; the three rows skip them.
                const expected = [shelf.entries[8].id, shelf.entries[6].id, shelf.entries[5].id];
                const rendered = expected.map(id => root.find(quick, 'stash-quick-row-' + id));
                root.check('activity-quick-latest', quick.rows.map(entry => entry.id).join() === expected.join()
                    && rendered.every(row => row && row.visible && row.compact)
                    && rendered[0].y < rendered[1].y && rendered[1].y < rendered[2].y
                    && quick.photos.map(entry => entry.id).join() === [shelf.entries[7].id, shelf.entries[0].id].join());
                const openAll = root.find(quick, 'stash-quick-open-all');
                const label = openAll ? openAll.text : '';
                if (openAll) root.pointer.mouseClick(openAll, openAll.width / 2, openAll.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check('activity-open-all', label === 'Увесь Сховок · 9' && root.quickServices.stash.visible === true
                    && root.quickCloses === 1);
                root.phase = -1;
                quickBackdrop.grabToImage(result => {
                    root.check('activity-quick-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.quick.png'));
                    root.readHelperLog();
                    root.phase = 131;
                });
            } else if (root.phase === 131 && root.helperLog) {
                const copies = root.helperLog.filter(request => request.operation === 'copy');
                root.check('copy-text-sends-note-text', copies[0]?.mode === 'text' && copies[0].value === 'Купити кабель'
                    && root.results[root.ids.copyNote]?.ok === true);
                root.check('copy-spotify-sends-uri', copies[1]?.mode === 'text' && copies[1].value === shelf.entries[1].uri);
                root.check('copy-downloaded-image-sends-local-path', copies[2]?.mode === 'image'
                    && copies[2].path === root.localPath(shelf.entries[0].localUri));
                root.check('copy-file-sends-uri-list', copies[3]?.mode === 'uris' && copies[3].value === 'file:///tmp/plain%20file.txt');
                root.check('copy-owned-image-sends-local-path', copies[4]?.mode === 'image'
                    && copies[4].path === root.stateHome + '/pentad/stash/clip-fixture.png' && copies.length === 5);
                root.check('copy-unknown-entry-reports-not-found', root.results[root.ids.copyMissing]?.reason === 'not-found');
                root.check('paste-empty-reports-reason', root.results[root.ids.emptyPaste]?.ok === false
                    && root.results[root.ids.emptyPaste]?.reason === 'empty' && config.saves === 15);
                root.ids = Object.assign({}, root.ids, { removeOwned: shelf.remove(shelf.entries[7].id) });
                root.phase = 14;
            } else if (root.phase === 14 && root.results[root.ids.removeOwned] && !shelf.inFlight) {
                root.readHelperLog();
                root.phase = 141;
            } else if (root.phase === 141 && root.helperLog) {
                const deletes = root.helperLog.filter(request => request.operation === 'delete');
                root.check('owned-delete-requested', deletes.length === 1
                    && deletes[0].path === root.stateHome + '/pentad/stash/clip-fixture.png'
                    && root.results[root.ids.removeOwned].ok === true && shelf.entries.length === 8
                    && !shelf.entries.some(entry => entry.owned) && config.saves === 16);
                // The next paste returns an owned image, but its save fails: the image must be deleted again.
                config.failSaves = 1;
                root.ids = Object.assign({}, root.ids, { failedPaste: shelf.pasteClipboard() });
                root.phase = 142;
            } else if (root.phase === 142 && root.results[root.ids.failedPaste] && !shelf.inFlight) {
                root.readHelperLog();
                root.phase = 143;
            } else if (root.phase === 143 && root.helperLog) {
                const deletes = root.helperLog.filter(request => request.operation === 'delete');
                const failure = root.results[root.ids.failedPaste];
                root.check('rejected-paste-deletes-owned-file', failure.ok === false && failure.reason === 'too-large'
                    && deletes.length === 2 && deletes[1].path === root.stateHome + '/pentad/stash/clip-second.png'
                    && shelf.entries.length === 8 && config.saves === 17 && config.documents.shelf.entries.length === 8
                    && root.helperLog.filter(request => request.operation === 'paste').length === 4);
                shelf.addUris(root.bulkUris);
                root.phase = 15;
            } else if (root.phase === 15 && shelf.entries.length === 68 && !shelf.inFlight
                       && root.bulkUris.every(uri => shelf.files.metadata[uri])) {
                const files = shelf.files.entries;
                root.check('files-fetch-all-entries-in-chunks', root.bulkUris.every(uri => shelf.files.metadata[uri].available === false)
                    && files.length === 62 && shelf.files.requestedUris.length === 62);
                root.check('files-order-newest-first', files[0].uri === root.bulkUris[59]
                    && files[files.length - 1].id === shelf.entries[0].id);
                const failing = root.failingShelf, failingConfig = root.failingConfig;
                root.check('migration-save-failure-keeps-entries', failing.ready && failing.loadError === ''
                    && failing.entries.length === 1 && failing.entries[0].id === 'legacy'
                    && failingConfig.saves === 1 && failingConfig.lastSaved.schemaVersion === 2
                    && failingConfig.documents.shelf.schemaVersion === 1);
                failing.addNote('Після збою');
                root.phase = 16;
            } else if (root.phase === 16 && root.failingConfig.saves === 2 && root.failingShelf.entries.length === 2) {
                root.check('next-mutation-saves-v2', root.failingConfig.documents.shelf.schemaVersion === 2
                    && root.failingConfig.documents.shelf.entries.length === 2
                    && root.failingConfig.documents.shelf.entries[1].kind === 'text');
                root.ids = Object.assign({}, root.ids, { fullPaste: 'full:' + root.fullShelf.pasteClipboard() });
                root.phase = 17;
            } else if (root.phase === 17 && root.fullShelf.ready && !root.fullShelf.inFlight && !root.fullShelf.queue.length) {
                root.readHelperLog();
                root.phase = 171;
            } else if (root.phase === 171 && root.helperLog) {
                root.check('paste-at-limit-skips-helper', root.fullShelf.unpinnedCount === 300
                    && root.helperLog.filter(request => request.operation === 'paste').length === 4
                    && root.fullConfig.saves === 0 && root.fullShelf.entries.length === 300);
                root.phase = 172;
            } else if (root.phase === 172 && root.results[root.ids.fullPaste] !== undefined) {
                root.check('paste-at-limit-reports-limit', root.results[root.ids.fullPaste].ok === false
                    && root.results[root.ids.fullPaste].reason === 'limit');
                root.finish();
                stop();
            }
        }
    }
}
