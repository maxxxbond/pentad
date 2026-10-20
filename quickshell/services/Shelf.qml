import QtQuick
import QtQml
import Quickshell.Io
import '../logic/shelf.mjs' as ShelfLogic

QtObject {
    id: root
    required property var config
    property bool preview: false
    property bool safeMode: false
    property bool ready: false
    property bool disposed: false
    property string loadRequestId: ''
    property string loadError: ''
    property int serial: 0
    property int idSerial: 0
    property var document: ShelfLogic.emptyShelfDocument()
    property var entries: []
    readonly property ShelfFiles files: ShelfFiles {
        entries: root.entries.filter(entry => !!ShelfLogic.shelfLocalUri(entry))
        helperPath: root.config.helperPath ? root.config.helperPath.replace(/pentad-files\.py$/, 'pentad_shelf_preview.py') : ''
        enabled: !root.preview && !root.safeMode
    }
    property var queue: []
    property var inFlight: null
    property var downloads: ({})
    readonly property string contentHelperPath: root.config.helperPath
        ? root.config.helperPath.replace(/pentad-files\.py$/, 'pentad_shelf_content.py') : ''
    property var helperPayload: ({})
    property var helperResult: null
    readonly property bool writable: !preview && !safeMode && !config.preview
    signal commandFinished(string requestId, var result)

    property Connections configConnections: Connections {
        target: root.config
        function onCommandFinished(requestId, result) { root.configFinished(requestId, result); }
        function onDocumentChanged(name) {
            if (name === 'shelf' && root.ready && !root.inFlight) root.syncDocument();
        }
    }

    Component.onCompleted: {
        if (preview || safeMode || config.preview) {
            ready = true;
        } else Qt.callLater(function() {
            if (!root.disposed) root.loadRequestId = root.config.reload('shelf');
        });
    }
    Component.onDestruction: { disposed = true; queue = []; inFlight = null; if (contentWorker.running) contentWorker.signal(9); }

    function syncDocument() {
        var parsed = ShelfLogic.parseShelfDocument(config.documents.shelf);
        if (!parsed.ok) { loadError = parsed.reason; return; }
        document = parsed.value;
        entries = document.entries;
        loadError = '';
    }
    function createId() {
        idSerial++;
        return 'shelf-' + Date.now().toString(36) + '-' + idSerial.toString(36);
    }
    function addUris(uris) { return enqueue('add', { uris: uris }); }
    function addOffer(offer) { return enqueue('drop', { offer: offer }); }
    function download(id) {
        if (!writable || !ready || downloads[id]?.pending) return '';
        const entry = entries.find(item => item.id === id && item.kind === 'image' && !item.localUri);
        if (!entry) return '';
        downloads = Object.assign({}, downloads, { [id]: { pending: true, error: '' } });
        return enqueue('download', { id: id });
    }
    function remove(id) { return enqueue('remove', { id: id }); }
    function enqueue(action, payload) {
        var requestId = 'shelf-' + (++serial);
        queue = queue.concat([{ requestId: requestId, action: action, payload: payload || {} }]);
        processQueue();
        return requestId;
    }
    function processQueue() {
        if (disposed || !ready || inFlight || !queue.length) return;
        var request = queue[0];
        if (loadError) { finishRequest(request, { ok: false, reason: loadError }); return; }
        if (!writable) { finishRequest(request, { ok: false, reason: preview ? 'preview' : 'read-only' }); return; }
        if (request.action === 'drop' || request.action === 'download') {
            if (!contentHelperPath) { finishRequest(request, { ok: false, reason: 'helper-unavailable' }); return; }
            if (request.action === 'download') {
                const entry = entries.find(item => item.id === request.payload.id && item.kind === 'image');
                if (!entry || entry.localUri) { finishRequest(request, { ok: false, reason: 'not-found' }); return; }
                helperPayload = { operation: 'download', url: entry.imageUrl, label: entry.label };
            } else helperPayload = { operation: 'extract', offer: request.payload.offer };
            inFlight = { request: request, helper: true };
            helperResult = null;
            contentWorker.stdinEnabled = true;
            contentWorker.running = true;
            helperWatchdog.restart();
            return;
        }
        var mutation = request.action === 'add'
            ? ShelfLogic.addShelfUris(document, request.payload.uris, createId)
            : request.action === 'remove'
                ? ShelfLogic.removeShelfEntry(document, request.payload.id)
                : { ok: false, reason: 'unsupported' };
        saveMutation(request, mutation);
    }
    function saveMutation(request, mutation) {
        if (!mutation.ok) { inFlight = null; finishRequest(request, { ok: false, reason: mutation.reason }); return; }
        if (!mutation.changed) { finishRequest(request, { ok: true, added: mutation.added || [] }); return; }
        inFlight = { configRequestId: config.save('shelf', mutation.document), request: request, mutation: mutation };
    }
    property Process contentWorker: Process {
        command: ['python3', root.contentHelperPath]
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.helperPayload)); stdinEnabled = false; }
        stdout: SplitParser {
            onRead: line => {
                try { root.helperResult = JSON.parse(line); }
                catch (error) { root.helperResult = { ok: false, message: 'Invalid content helper response' }; }
            }
        }
        onExited: code => {
            helperWatchdog.stop();
            if (root.disposed || !root.inFlight?.helper) return;
            const request = root.inFlight.request;
            const result = root.helperResult || { ok: false, message: 'Could not process content. Try again.' };
            root.inFlight = null;
            if (code !== 0 || !result.ok) { root.finishRequest(request, result.ok ? { ok: false, reason: 'helper-failed' } : result); return; }
            const mutation = request.action === 'drop'
                ? ShelfLogic.addShelfItems(root.document, result.items, root.createId)
                : ShelfLogic.setShelfDownloadedFile(root.document, request.payload.id, result.uri);
            root.saveMutation(request, mutation);
        }
    }
    property Timer helperWatchdog: Timer {
        interval: 65000
        onTriggered: if (contentWorker.running) contentWorker.signal(9)
    }
    function configFinished(requestId, result) {
        if (disposed) return;
        if (requestId === loadRequestId) {
            loadRequestId = '';
            if (!result.ok) loadError = result.reason || 'io';
            else syncDocument();
            ready = true;
            processQueue();
            return;
        }
        if (!inFlight || requestId !== inFlight.configRequestId) return;
        var request = inFlight.request;
        var mutation = inFlight.mutation;
        inFlight = null;
        if (result.ok) {
            document = mutation.document;
            entries = document.entries;
            loadError = '';
            finishRequest(request, { ok: true, added: mutation.added || [] });
        } else {
            if (result.reason === 'conflict') {
                ready = false;
                loadRequestId = config.reload('shelf');
            }
            finishRequest(request, { ok: false, reason: result.reason || 'io', message: result.message || '' });
        }
        processQueue();
    }
    function finishRequest(request, result) {
        if (request.action === 'download') downloads = Object.assign({}, downloads,
            { [request.payload.id]: { pending: false, error: result.ok ? '' : result.message || result.reason || 'Download failed. Try again.' } });
        queue = queue.slice(1);
        var requestId = request.requestId;
        Qt.callLater(function() { if (!root.disposed) root.commandFinished(requestId, result); });
        processQueue();
    }
}
