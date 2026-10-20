import QtQuick
import QtQml
import Quickshell
import qs.services
import qs.features.shelf
import qs.theme
import Quickshell.Io

ShellRoot {
    id: root
    property int phase: 0
    property var checks: []
    property int saves: 0
    property string baseUrl: ''
    property string downloadedUri: ''
    property QtObject fakeConfig: QtObject {
        property bool preview: false
        property string helperPath: decodeURIComponent(Qt.resolvedUrl('helpers/pentad-files.py').toString().replace(/^file:\/\//, ''))
        property var documents: ({})
        property int serial: 0
        signal commandFinished(string requestId, var result)
        signal documentChanged(string name)
        function reload(name) {
            var requestId = 'read-' + (++serial);
            if (documents.shelf === undefined)
                documents = Object.assign({}, documents, { shelf: { schemaVersion: 1, entries: [] } });
            Qt.callLater(function() { commandFinished(requestId, { ok: true }); });
            return requestId;
        }
        function save(name, value) {
            var requestId = 'save-' + (++serial);
            root.saves++;
            documents = Object.assign({}, documents, { [name]: value });
            documentChanged(name);
            Qt.callLater(function() { commandFinished(requestId, { ok: true }); });
            return requestId;
        }
    }
    property Shelf shelf: Shelf { config: root.fakeConfig }
    FloatingWindow {
        visible: true
        implicitWidth: 520; implicitHeight: 600
        color: Theme.tokens.surface
        ShelfGrid { id: grid; x: 16; y: 16; width: 488; shelf: root.shelf; readOnly: false }
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
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function drop(data) {
        return { formats: Object.keys(data), accepted: false, getDataAsString: mime => data[mime],
            accept: function(action) { this.accepted = action === Qt.CopyAction; } };
    }

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
            if (root.phase === 0 && root.shelf.ready) {
                root.check('shelf loads managed state', root.shelf.entries.length === 0);
                root.shelf.addUris(['file:///tmp/shelf%20one.txt', 'file:///tmp/shelf%20one.txt']);
                root.phase = 1;
            } else if (root.phase === 1 && root.shelf.entries.length === 1 && root.saves === 1) {
                root.check('duplicate URI in one drop is stored once', root.shelf.entries[0].label === 'shelf one.txt');
                root.shelf.addUris(['file:///tmp/shelf%20one.txt']);
                root.phase = 2;
            } else if (root.phase === 2 && root.saves === 1) {
                root.shelf.remove(root.shelf.entries[0].id);
                root.phase = 3;
            } else if (root.phase === 3 && root.shelf.entries.length === 0 && root.saves === 2) {
                root.check('remove persists the managed shelf document', root.fakeConfig.documents.shelf.entries.length === 0);
                root.phase = 4;
            } else if (root.phase === 4 && root.baseUrl) {
                const photo = root.drop({ 'text/uri-list': root.baseUrl + '/source',
                    'text/html': '<a href="' + root.baseUrl + '/source"><img alt="Saved photo" src="' + root.baseUrl + '/image" srcset="' + root.baseUrl + '/bad 2x"></a>' });
                root.check('web-image-drop-is-accepted-by-shared-grid', grid.receiveDrop(photo) && photo.accepted);
                grid.receiveDrop(root.drop({ 'text/uri-list': '', 'text/plain': 'https://open.spotify.com/track/7h2ABjmIKKbT7VBWFM2nZD' }));
                grid.receiveDrop(root.drop({ 'text/html': '<a href="https://weather.com/forecast">Hourly Weather Forecast</a>' }));
                grid.receiveDrop(root.drop({ 'text/plain': 'Read this later\nA text note' }));
                root.phase = 5;
            } else if (root.phase === 5 && root.shelf.entries.length === 4 && !root.shelf.inFlight) {
                const photo = root.shelf.entries[0], spotify = root.shelf.entries[1];
                root.check('queued-web-drops-persist-without-lost-updates', root.saves === 6
                    && root.shelf.entries[2].label === 'Hourly Weather Forecast' && root.shelf.entries[3].kind === 'text');
                root.check('photo-drop-does-not-download-local-file', photo.kind === 'image' && !photo.localUri);
                grid.selectEntry(spotify.id, Qt.NoModifier);
                const button = root.find(grid, 'shelf-selection-secondary');
                root.check('spotify-loader-stub-is-disabled', spotify.kind === 'spotify' && button && !button.enabled);
                grid.selectEntry(photo.id, Qt.NoModifier);
                const action = root.find(grid, 'shelf-selection-secondary');
                action.clicked();
                root.check('download-click-sets-pending-and-blocks-repeat', root.shelf.downloads[photo.id]?.pending
                    && root.shelf.download(photo.id) === '');
                root.phase = 6;
            } else if (root.phase === 6 && !root.shelf.inFlight && root.shelf.downloads[root.shelf.entries[0].id]?.error) {
                const photo = root.shelf.entries[0];
                root.check('invalid-image-retains-card-and-offers-retry', !photo.localUri
                    && root.find(grid, 'shelf-selection-secondary').text === 'Retry download');
                root.shelf.document = { schemaVersion: 1, entries: root.shelf.entries.map(entry =>
                    entry.id === photo.id ? Object.assign({}, entry, { imageUrl: root.baseUrl + '/image' }) : entry) };
                root.shelf.entries = root.shelf.document.entries;
                grid.downloadFile(photo.id);
                root.phase = 7;
            } else if (root.phase === 7 && !root.shelf.inFlight && root.shelf.entries[0].localUri) {
                const photo = root.shelf.entries[0];
                root.downloadedUri = photo.localUri;
                const tile = grid.tileFor(photo.id);
                root.check('explicit-download-persists-local-file-and-preserves-source', photo.localUri.startsWith('file://')
                    && photo.uri === root.baseUrl + '/source' && photo.localUri.indexOf('/Downloads/Pentad/') >= 0);
                root.check('downloaded-card-exports-local-uri', tile.Drag.mimeData['text/uri-list'] === photo.localUri + '\r\n');
                root.shelf.preview = true;
                root.check('preview-blocks-download-actions', root.shelf.download(photo.id) === '');
                root.shelf.preview = false;
                root.phase = 8;
            } else if (root.phase === 8 && root.find(grid, 'shelf-content-preview-' + root.shelf.entries[0].id).status === Image.Ready) {
                root.check('downloaded-image-decodes-in-card', true);
                const textEntry = root.shelf.entries[3];
                grid.selectEntry(textEntry.id, Qt.NoModifier);
                const readNote = root.find(grid, 'shelf-selection-open');
                readNote.clicked();
                root.check('text-card-opens-readable-note', grid.selectedTile.notePopup.visible);
                grid.selectedTile.notePopup.close();
                grid.grabToImage(result => {
                    root.check('universal-shelf-card-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')));
                    root.finish();
                });
                stop();
            }
        }
    }
}
