import QtQuick
import QtQml
import '../logic/chat.mjs' as ChatLogic
import '../logic/settings-bindings.mjs' as Bindings
import '../logic/settings-catalog.mjs' as Catalog
import '../logic/settings-controller.mjs' as Logic
import '../logic/settings-nav.mjs' as Nav
import '../logic/settings-state.mjs' as State

QtObject {
    id: root

    required property var services
    property bool open: false
    property string pageId: Nav.initialNav(Catalog.pages).pageId
    property string tabId: Nav.initialNav(Catalog.pages).tabId
    property string query: ''
    property string pendingId: ''
    property string pendingKey: ''
    property string error: ''
    property string flow: ''
    property var checkpoints: ({})
    property var checkpointRequests: ({})
    readonly property var actionDocuments: ['layout', 'theme']
    // Instance id of the widget whose settings replace the page, or ''.
    property string widgetId: ''
    // '' | 'saving' | 'saved' | 'undo', shown in the page header.
    property string status: ''
    property var pendingChange: null
    property var lastChange: null
    property var resetQueue: []
    property bool recordUndo: true
    // Documents written only after their last read succeeded (a broken hand-edited file is never
    // replaced by defaults), and whose save is retried once after a reload on `conflict`.
    readonly property var guardedDocuments: ['models']
    // The commit in flight, for that one retry: { item, value, recordUndo, retried }.
    property var pendingCommit: null
    property string retryReload: ''

    function openWidget(instanceId) {
        widgetId = instanceId === undefined || instanceId === null ? '' : String(instanceId);
        return widgetId !== '';
    }

    function closeWidget() {
        widgetId = '';
    }

    function modified(page) {
        return State.modifiedItems(services.config.documents, page);
    }

    function resetPage(targetPageId) {
        if (pendingId) return false;
        const page = typeof targetPageId === 'object' && targetPageId !== null ? targetPageId
            : Catalog.pages.find(function(entry) { return entry.id === targetPageId; });
        const items = modified(page);
        if (items.length === 0) return false;
        lastChange = null;
        resetQueue = items;
        nextReset();
        return true;
    }

    function nextReset() {
        const item = resetQueue[0];
        resetQueue = resetQueue.slice(1);
        recordUndo = false;
        const requestId = commit(item, item.default);
        recordUndo = true;
        if (!requestId) {
            resetQueue = [];
            status = '';
        }
    }

    function undo() {
        if (pendingId || !lastChange) return false;
        const change = lastChange;
        lastChange = null;
        status = '';
        recordUndo = false;
        const requestId = commit(change.item, change.previous);
        recordUndo = true;
        return requestId !== '';
    }

    property Timer statusTimer: Timer {
        interval: 1200
        onTriggered: {
            if (root.status === 'saved' && root.lastChange) {
                root.status = 'undo';
                interval = 5000;
                restart();
            } else {
                root.status = '';
                interval = 1200;
            }
        }
    }

    function currentState() {
        return { pendingId: pendingId, pendingKey: pendingKey, error: error };
    }

    function applyState(state) {
        pendingId = state.pendingId;
        pendingKey = state.pendingKey;
        error = state.error;
    }

    // Pages that moved into a tab of another page keep working for IPC and older callers.
    readonly property var pageAliases: ({ 'bar-tools': { pageId: 'bar', tabId: 'tools' } })

    function openPage(requestedId, requestedTab) {
        const current = { pageId: pageId, tabId: tabId, query: query };
        let nav = current;
        if (requestedId !== undefined && requestedId !== null && requestedId !== '') {
            const alias = pageAliases[requestedId];
            const target = alias ? alias.pageId : requestedId;
            const known = Catalog.pages.some(function(page) { return page.id === target; });
            nav = known ? Nav.selectPage(current, Catalog.pages, target) : Nav.initialNav(Catalog.pages);
            if (known && alias) nav = Nav.selectTab(nav, Catalog.pages, alias.tabId);
            if (known && requestedTab) nav = Nav.selectTab(nav, Catalog.pages, requestedTab);
        }
        pageId = nav.pageId;
        tabId = nav.tabId;
        query = nav.query;
        flow = '';
        widgetId = '';
        open = true;
        return true;
    }

    function close() {
        flow = '';
        widgetId = '';
        open = false;
    }

    function setQuery(text) {
        query = text === undefined || text === null ? '' : String(text);
    }

    function commit(item, value, retried) {
        if (!Logic.canCommit(currentState())) return '';
        if (guardedDocuments.indexOf(item.document) >= 0) {
            const ready = ChatLogic.documentWritable(item.document, services.config.documentStates);
            if (!ready.ok) {
                error = ChatLogic.documentFailureMessage(ready, function(uk, en) { return services.text(uk, en); }) || ready.reason;
                return '';
            }
        }
        const checked = Bindings.commitCheck(services.config.documents, item, value);
        if (!checked.ok) {
            error = checked.message || 'invalid';
            return '';
        }
        const previous = item.document !== undefined ? Bindings.readValue(services.config.documents, item) : undefined;
        const requestId = services.config.save(checked.name, checked.document);
        const reduced = Logic.reduceCommit(currentState(), item.key, requestId);
        if (!reduced.accepted) return '';
        applyState(reduced.state);
        pendingCommit = { item: item, value: value, recordUndo: recordUndo, retried: retried === true };
        pendingChange = recordUndo && item.document !== undefined ? { item: item, previous: previous } : null;
        status = 'saving';
        statusTimer.stop();
        return requestId;
    }

    function runAction(name) {
        if (name === 'screenshots.open') return services.screenshot.openSettings();
        if (name === 'widgets.add') {
            flow = 'add-widget';
            return true;
        }
        if (name === 'config.checkpoint') {
            const requests = Object.assign({}, checkpointRequests);
            actionDocuments.forEach(function(document) { requests[services.config.checkpoint(document)] = document; });
            checkpointRequests = requests;
            return true;
        }
        if (name === 'config.restore') {
            if (pendingId) return false;
            const ready = actionDocuments.filter(function(document) { return !!checkpoints[document]; });
            if (ready.length === 0) return false;
            ready.forEach(function(document) { services.config.restore(document, checkpoints[document]); });
            return true;
        }
        return false;
    }

    function finishRetryReload(result) {
        const again = pendingCommit;
        retryReload = '';
        pendingCommit = null;
        pendingId = '';
        pendingKey = '';
        if (!again || !result || result.ok !== true) {
            error = result && (result.message || result.reason) || 'conflict';
            pendingChange = null;
            resetQueue = [];
            status = '';
            return;
        }
        recordUndo = again.recordUndo;
        const requestId = commit(again.item, again.value, true);
        recordUndo = true;
        if (!requestId) status = '';
    }

    property Connections configEvents: Connections {
        target: root.services.config
        function onCommandFinished(requestId, result) {
            if (root.checkpointRequests[requestId] !== undefined) {
                const document = root.checkpointRequests[requestId];
                const requests = Object.assign({}, root.checkpointRequests);
                delete requests[requestId];
                root.checkpointRequests = requests;
                if (result && result.ok && result.checkpointId)
                    root.checkpoints = Object.assign({}, root.checkpoints, { [document]: result.checkpointId });
                return;
            }
            if (root.retryReload !== '' && requestId === root.retryReload) {
                root.finishRetryReload(result);
                return;
            }
            const wasPending = root.pendingId !== '' && root.pendingId === requestId;
            const again = wasPending ? root.pendingCommit : null;
            if (again && !again.retried && result && result.reason === 'conflict'
                    && root.guardedDocuments.indexOf(again.item.document) >= 0) {
                // The file changed underneath: read it once more and apply the same change to it.
                root.retryReload = root.services.config.reload(again.item.document);
                root.pendingId = root.retryReload;
                return;
            }
            if (wasPending) root.pendingCommit = null;
            root.applyState(Logic.reduceFinished(root.currentState(), requestId, result));
            if (!wasPending) return;
            if (root.error !== '') {
                root.pendingChange = null;
                root.resetQueue = [];
                root.status = '';
                return;
            }
            if (root.pendingChange) root.lastChange = root.pendingChange;
            root.pendingChange = null;
            if (root.resetQueue.length > 0) {
                root.nextReset();
                return;
            }
            root.status = 'saved';
            root.statusTimer.interval = 1200;
            root.statusTimer.restart();
        }
    }
}
