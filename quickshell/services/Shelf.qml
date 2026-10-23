import QtQuick
import QtQml
import Quickshell.Io
import '../logic/shelf.mjs' as ShelfLogic
import '../logic/stash-view.mjs' as StashView

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
    readonly property int limitUnpinned: ShelfLogic.MAX_UNPINNED_ENTRIES
    readonly property int unpinnedCount: entries.filter(entry => !entry.pinned).length
    readonly property ShelfFiles files: ShelfFiles {
        // Newest first, in the order the window shows them, so the first chunk covers the top rows.
        entries: StashView.newestFirst(root.entries.filter(entry => !!ShelfLogic.shelfLocalUri(entry)))
        helperPath: root.config.helperPath ? root.config.helperPath.replace(/pentad-files\.py$/, 'pentad_shelf_preview.py') : ''
        enabled: !root.preview && !root.safeMode
    }
    property var queue: []
    property var inFlight: null
    property var downloads: ({})
    readonly property string contentHelperPath: root.config.helperPath
        ? root.config.helperPath.replace(/pentad-files\.py$/, 'pentad_shelf_content.py') : ''
    readonly property string clipboardHelperPath: root.config.helperPath
        ? root.config.helperPath.replace(/pentad-files\.py$/, 'pentad_stash_clipboard.py') : ''
    property var helperPayload: ({})
    property var helperResult: null
    property var clipboardPayload: ({})
    property var clipboardResult: null
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
    Component.onDestruction: {
        disposed = true; queue = []; inFlight = null;
        helperWatchdog.stop(); clipboardWatchdog.stop();
        if (contentWorker.running) contentWorker.signal(9);
        if (clipboardWorker.running) clipboardWorker.signal(9);
    }

    // Returns whether the stored document was an older schema, now held in memory as v2.
    function syncDocument() {
        var parsed = ShelfLogic.parseShelfDocument(config.documents.shelf);
        if (!parsed.ok) { loadError = parsed.reason; return false; }
        document = parsed.value;
        entries = document.entries;
        loadError = '';
        return parsed.migrated === true;
    }
    function createId() {
        idSerial++;
        return 'shelf-' + Date.now().toString(36) + '-' + idSerial.toString(36);
    }
    function now() { return new Date().toISOString(); }
    function addUris(uris) { return enqueue('add', { uris: uris }); }
    function addOffer(offer) { return enqueue('drop', { offer: offer }); }
    function addNote(text) { return enqueue('note', { text: text }); }
    function pin(id, pinned) { return enqueue('pin', { id: id, pinned: pinned === true }); }
    function pasteClipboard() { return enqueue('paste', {}); }
    function copy(id) { return enqueue('copy', { id: id }); }
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
        if (request.action === 'paste' || request.action === 'copy') { startClipboard(request); return; }
        if (request.action === 'drop' || request.action === 'download') {
            if (!contentHelperPath) { finishRequest(request, { ok: false, reason: 'helper-unavailable' }); return; }
            if (request.action === 'download') {
                const entry = entries.find(item => item.id === request.payload.id && item.kind === 'image');
                if (!entry || entry.localUri) { finishRequest(request, { ok: false, reason: 'not-found' }); return; }
                helperPayload = { operation: 'download', url: entry.imageUrl, label: entry.label };
            } else helperPayload = { operation: 'extract', offer: request.payload.offer };
            inFlight = { request: request, helper: 'content' };
            helperResult = null;
            contentWorker.stdinEnabled = true;
            contentWorker.running = true;
            helperWatchdog.restart();
            return;
        }
        saveMutation(request, mutationFor(request));
    }
    function mutationFor(request) {
        const payload = request.payload;
        switch (request.action) {
        case 'add': return ShelfLogic.addShelfUris(document, payload.uris, createId, now());
        case 'remove': return ShelfLogic.removeShelfEntry(document, payload.id);
        case 'pin': return ShelfLogic.setShelfPinned(document, payload.id, payload.pinned);
        case 'note': return noteMutation(payload.text);
        // The loaded v1 document is written back as v2 once; `document` is already the v2 form.
        case 'migrate': return { ok: true, changed: true, document: document };
        default: return { ok: false, reason: 'unsupported' };
        }
    }
    function noteMutation(text) {
        const composed = ShelfLogic.composerItem(text);
        return composed.ok ? ShelfLogic.addShelfItems(document, [composed.item], createId, now()) : composed;
    }
    function saveMutation(request, mutation) {
        if (!mutation.ok) { inFlight = null; finishRequest(request, { ok: false, reason: mutation.reason }); return; }
        if (!mutation.changed) { inFlight = null; finishRequest(request, { ok: true, added: mutation.added || [] }); return; }
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
            if (root.disposed || root.inFlight?.helper !== 'content') return;
            const request = root.inFlight.request;
            const result = root.helperResult || { ok: false, message: 'Could not process content. Try again.' };
            root.inFlight = null;
            if (code !== 0 || !result.ok) { root.finishRequest(request, result.ok ? { ok: false, reason: 'helper-failed' } : result); return; }
            const mutation = request.action === 'drop'
                ? ShelfLogic.addShelfItems(root.document, result.items, root.createId, root.now())
                : ShelfLogic.setShelfDownloadedFile(root.document, request.payload.id, result.uri);
            root.saveMutation(request, mutation);
        }
    }
    property Timer helperWatchdog: Timer {
        interval: 65000
        onTriggered: if (contentWorker.running) contentWorker.signal(9)
    }

    // Clipboard helper: paste, copy and the deletion of files the stash owns.
    function startClipboard(request) {
        if (!clipboardHelperPath) { finishRequest(request, { ok: false, reason: 'helper-unavailable' }); return; }
        if (request.action === 'copy') {
            const payload = copyPayload(entries.find(item => item.id === request.payload.id));
            if (!payload) { finishRequest(request, { ok: false, reason: 'not-found' }); return; }
            clipboardPayload = payload;
        } else clipboardPayload = { operation: 'paste' };
        runClipboard(request);
    }
    function copyPayload(entry) {
        if (!entry) return null;
        if (entry.kind === 'text') return { operation: 'copy', mode: 'text', value: entry.text };
        if (entry.kind === 'link' || entry.kind === 'spotify') return { operation: 'copy', mode: 'text', value: entry.uri };
        const local = ShelfLogic.shelfLocalUri(entry);
        // A web image without a downloaded copy has only its source address to offer.
        if (!local) return { operation: 'copy', mode: 'text', value: entry.uri };
        if (entry.kind === 'image' || entry.owned === true) {
            const paths = ShelfLogic.localFilePaths([local]);
            return paths.ok ? { operation: 'copy', mode: 'image', path: paths.paths[0] } : null;
        }
        return { operation: 'copy', mode: 'uris', value: local };
    }
    function startDelete(request, removed) {
        const paths = ShelfLogic.localFilePaths([removed.uri]);
        if (!clipboardHelperPath || !paths.ok) {
            finishRequest(request, { ok: true, deleted: false, reason: 'delete-failed', message: 'The stored file could not be deleted.' });
            return;
        }
        clipboardPayload = { operation: 'delete', path: paths.paths[0] };
        runClipboard(request);
    }
    function runClipboard(request) {
        inFlight = { request: request, helper: 'clipboard' };
        clipboardResult = null;
        clipboardWorker.stdinEnabled = true;
        clipboardWorker.running = true;
        clipboardWatchdog.restart();
    }
    property Process clipboardWorker: Process {
        command: ['python3', root.clipboardHelperPath]
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.clipboardPayload)); stdinEnabled = false; }
        stdout: SplitParser {
            onRead: line => {
                try { root.clipboardResult = JSON.parse(line); }
                catch (error) { root.clipboardResult = { ok: false, reason: 'helper-failed', message: 'Invalid clipboard helper response' }; }
            }
        }
        onExited: code => {
            root.clipboardWatchdog.stop();
            if (root.disposed || root.inFlight?.helper !== 'clipboard') return;
            const request = root.inFlight.request;
            const result = root.clipboardResult || { ok: false, reason: 'helper-failed', message: 'Could not reach the clipboard. Try again.' };
            root.inFlight = null;
            const failed = code !== 0 || !result.ok;
            if (request.action === 'remove') {
                // The entry is already gone from the document; a leftover file is reported, not restored.
                root.finishRequest(request, failed
                    ? { ok: true, deleted: false, reason: 'delete-failed', message: result.message || 'The stored file could not be deleted.' }
                    : { ok: true, deleted: true });
                return;
            }
            if (failed) { root.finishRequest(request, result.ok ? { ok: false, reason: 'helper-failed' } : result); return; }
            if (request.action === 'copy') { root.finishRequest(request, { ok: true }); return; }
            const mutation = Array.isArray(result.items) && result.items.length
                ? ShelfLogic.addShelfItems(root.document, result.items, root.createId, root.now())
                : typeof result.text === 'string' ? root.noteMutation(result.text) : { ok: false, reason: 'empty' };
            root.saveMutation(request, mutation);
        }
    }
    property Timer clipboardWatchdog: Timer {
        interval: 10000
        onTriggered: if (root.clipboardWorker.running) root.clipboardWorker.signal(9)
    }

    function configFinished(requestId, result) {
        if (disposed) return;
        if (requestId === loadRequestId) {
            loadRequestId = '';
            let migrated = false;
            if (!result.ok) loadError = result.reason || 'io';
            else migrated = syncDocument();
            ready = true;
            // A failed migration save is tolerated: the entries stay loaded and the next mutation writes v2.
            if (migrated && writable) enqueue('migrate', {});
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
            if (request.action === 'remove' && mutation.removed?.owned === true) { startDelete(request, mutation.removed); return; }
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
