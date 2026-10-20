import QtQuick
import QtQml
import '../logic/windowswitcher.mjs' as Switcher

QtObject {
    id: root
    required property var services
    property bool active: mode !== ''
    property string mode: ''
    property string outputId: ''
    property int generation: 0
    property var session: null
    property var snapshot: null
    property var selectedWindow: null
    property var selectedRef: null
    property string selectedWorkspaceId: ''
    property string query: ''
    property int pageStart: 1
    property bool revealed: false
    property bool visible: revealed || mode === 'overview'
    property bool inputActive: active
    property bool pickerOpen: false
    property var dragToken: null
    property var moveState: ({ kind: 'idle' })
    property string error: ''
    readonly property bool suppressWorkspaceExpansion: active
    property var _altHeld: ({})
    property bool _altReleasedBeforeBegin: false
    property var _superHeld: ({})
    property double _superPressedAt: 0
    readonly property int superTapMs: 400
    property int _tokenSerial: 0
    property var _pendingMoves: ({})
    property Timer revealTimer: Timer {
        interval: 80
        repeat: false
        onTriggered: {
            if (root.mode === 'all' || root.mode === 'application') root.revealed = true;
        }
    }
    property Connections sourceConnections: Connections {
        target: root.services ? root.services.hyprland : null
        function onOverviewSnapshotChanged() { root.reconcileSnapshot(); }
        function onCommandFinished(requestId, result) { root.finishCommand(requestId, result); }
    }
    property Connections popupConnections: Connections {
        target: root.services ? root.services.popups : null
        function onChanged() {
            if (root.services.popups.surface && root.active) root.cancel();
        }
    }

    function readySnapshot() {
        var state = services && services.hyprland ? services.hyprland.overviewSnapshot : null;
        return state && state.kind === 'ready' ? state.value : null;
    }
    function refFor(client) {
        return client ? { address: client.address, instanceId: Switcher.instanceId(client) } : null;
    }
    function clientFor(ref) {
        if (!snapshot || !ref) return null;
        if (typeof ref !== 'string' && (!ref.address || !ref.instanceId)) return null;
        var address = typeof ref === 'string' ? ref : ref.address;
        var identity = typeof ref === 'string' ? '' : ref.instanceId;
        return snapshot.clients.find(function(client) {
            return client.address === address && (!identity || Switcher.instanceId(client) === identity);
        }) || null;
    }
    function syncSelected() {
        selectedWindow = session ? Switcher.selectedWindow(session) : clientFor(selectedRef);
        if (mode === 'overview' && selectedRef && !selectedWindow) selectedRef = null;
    }
    function reconcileSnapshot() {
        var fresh = readySnapshot();
        if (!active) return;
        if (!fresh || !fresh.desktop || !fresh.desktop.outputs.some(function(item) { return item.id === outputId; })) {
            cancel();
            return;
        }
        snapshot = fresh;
        if (session) {
            session = Switcher.reconcileSwitcherSession(session, fresh);
            if (!session.candidates.length || (session.candidates.length === 1 && session.anchor
                    && session.selectedInstanceId === session.anchor.instanceId)) { cancel(); return; }
        }
        if (dragToken && !clientFor(dragToken.ref)) cancelDrag(dragToken);
        syncSelected();
    }
    function closeSession() {
        if (!active) return false;
        generation++;
        revealTimer.stop();
        mode = '';
        revealed = false;
        session = null;
        snapshot = null;
        selectedWindow = null;
        selectedRef = null;
        selectedWorkspaceId = '';
        outputId = '';
        query = '';
        pickerOpen = false;
        dragToken = null;
        moveState = ({ kind: 'idle' });
        error = '';
        return true;
    }
    function cancel() { return closeSession(); }
    function close() { return cancel(); }
    function prepareOpen() {
        if (services.popups && services.popups.surface) services.popups.close();
        if (services.hyprland && typeof services.hyprland.refreshNavigationCatalog === 'function')
            services.hyprland.refreshNavigationCatalog();
        var fresh = readySnapshot();
        if (!fresh || !fresh.desktop || !fresh.desktop.outputs.length) return null;
        var output = fresh.desktop.outputs.find(function(item) { return item.id === fresh.desktop.focusedOutputId; });
        return output ? { snapshot: fresh, output: output } : null;
    }
    function openOverview() {
        if (mode === 'overview') return true;
        if (active) closeSession();
        var prepared = prepareOpen();
        if (!prepared) return false;
        generation++;
        snapshot = prepared.snapshot;
        outputId = prepared.output.id;
        mode = 'overview';
        revealed = true;
        error = '';
        var numeric = Number(prepared.output.activeWorkspaceId);
        pageStart = Number.isSafeInteger(numeric) && numeric > 0
            ? Math.floor((numeric - 1) / 10) * 10 + 1 : 1;
        return true;
    }
    function toggleOverview() { return mode === 'overview' ? cancel() : openOverview(); }
    function overview(action) {
        if (action === 'open') return openOverview();
        if (action === 'close') return cancel();
        if (action === 'toggle') return toggleOverview();
        return false;
    }
    function beginSwitcher(nextMode, direction) {
        if (nextMode !== 'application') nextMode = 'all';
        direction = direction === -1 ? -1 : 1;
        if (mode === 'overview') closeSession();
        if (session) {
            var transitioned = session.mode === nextMode ? session : Switcher.changeSwitcherMode(session, nextMode);
            if (!transitioned.candidates.length || (nextMode === 'application' && transitioned.candidates.length === 1))
                return false;
            session = transitioned;
            session = Switcher.stepSwitcherSession(session, direction);
            mode = nextMode;
            syncSelected();
            return true;
        }
        var prepared = prepareOpen();
        if (!prepared) return false;
        var fresh = prepared.snapshot;
        var anchor = fresh.clients.find(function(client) { return client.address === fresh.activeAddress; }) || null;
        if (nextMode === 'application' && !anchor) return false;
        var next = Switcher.beginSwitcherSession({ id: generation + 1, snapshot: fresh,
            mru: fresh.mru || [], mode: nextMode, direction: direction, scope: 'all' });
        if (!next.candidates.length || (nextMode === 'application' && next.candidates.length === 1)
                || (next.candidates.length === 1 && next.anchor
                    && next.selectedInstanceId === next.anchor.instanceId)) return false;
        generation++;
        snapshot = fresh;
        outputId = prepared.output.id;
        session = next;
        mode = nextMode;
        revealed = false;
        error = '';
        syncSelected();
        if (_altReleasedBeforeBegin) {
            _altReleasedBeforeBegin = false;
            commit();
        } else revealTimer.restart();
        return true;
    }
    function stepSwitcher(direction) {
        if (!session) return beginSwitcher('all', direction);
        session = Switcher.stepSwitcherSession(session, direction === -1 ? -1 : 1);
        syncSelected();
        return true;
    }
    function selectWindow(ref) {
        if (session) {
            var id = typeof ref === 'string' ? ref : ref && ref.instanceId;
            if (!session.candidates.some(function(client) { return Switcher.instanceId(client) === id; })) return false;
            session = Object.assign({}, session, { selectedInstanceId: id });
            syncSelected();
            return true;
        }
        if (mode !== 'overview') return false;
        var client = clientFor(ref);
        selectedRef = refFor(client);
        syncSelected();
        return !!client;
    }
    function selectWorkspace(id) {
        if (mode !== 'overview') return false;
        selectedWorkspaceId = String(id);
        selectedRef = null;
        syncSelected();
        return true;
    }
    function dispatchFocus(ref) {
        if (!ref || services.preview || services.safeMode) return false;
        var requestId = services.hyprland.focusWindow(ref);
        return !!requestId;
    }
    function commit() {
        if (!session) return false;
        var target = Switcher.selectedWindow(session);
        var ref = refFor(target);
        closeSession();
        return dispatchFocus(ref);
    }
    function activateWorkspace(id) {
        if (mode !== 'overview') return false;
        var key = String(id);
        var validNumeric = /^[1-9]\d{0,9}$/.test(key) && Number(key) <= 2147483647;
        var exists = snapshot.desktop.workspaces.some(function(item) { return item.id === key; });
        if (!validNumeric && !exists) return false;
        closeSession();
        if (services.preview || services.safeMode) return false;
        return !!services.hyprland.activateOverviewWorkspace(key);
    }
    function activateSelected() {
        if (mode !== 'overview') return commit();
        if (selectedRef) {
            var ref = selectedRef;
            if (!clientFor(ref)) return false;
            closeSession();
            return dispatchFocus(ref);
        }
        return selectedWorkspaceId ? activateWorkspace(selectedWorkspaceId) : false;
    }
    function setQuery(text) { if (mode === 'overview') query = String(text || ''); }
    function changePage(delta) {
        if (mode !== 'overview' || !delta) return false;
        pageStart = Math.max(1, pageStart + (delta < 0 ? -10 : 10));
        return true;
    }
    function beginDrag(ref) {
        if (mode !== 'overview' || moveState.kind === 'moving') return null;
        if (!ref || typeof ref !== 'object' || !ref.instanceId) return null;
        var client = clientFor(ref);
        if (!client || client.pinned || (client.grouped && client.grouped.length)) return null;
        dragToken = { id: ++_tokenSerial, generation: generation, ref: refFor(client) };
        error = '';
        moveState = ({ kind: 'dragging', ref: dragToken.ref });
        return dragToken;
    }
    function cancelDrag(token) {
        if (!dragToken || token !== dragToken) return false;
        dragToken = null;
        if (moveState.kind === 'dragging') moveState = ({ kind: 'idle' });
        return true;
    }
    function canDrop(token, id) {
        if (mode !== 'overview' || !dragToken || token !== dragToken
                || token.generation !== generation || moveState.kind !== 'dragging') return false;
        var client = clientFor(token.ref);
        var key = String(id);
        return !!client && !client.pinned && !(client.grouped && client.grouped.length)
            && ((/^[1-9]\d{0,9}$/.test(key) && Number(key) <= 2147483647)
                || snapshot.desktop.workspaces.some(function(item) { return String(item.id) === key; }));
    }
    function openMovePicker() {
        if (mode !== 'overview' || moveState.kind === 'moving' || !selectedRef) return false;
        var client = clientFor(selectedRef);
        if (!client || client.pinned || (client.grouped && client.grouped.length)) return false;
        pickerOpen = true;
        return true;
    }
    function moveWindow(ref, id, point) {
        if (mode !== 'overview' || moveState.kind === 'moving') return false;
        if (!ref || typeof ref !== 'object' || !ref.instanceId) return false;
        var client = clientFor(ref);
        var key = String(id);
        var validNumeric = /^[1-9]\d{0,9}$/.test(key) && Number(key) <= 2147483647;
        var exists = snapshot.desktop.workspaces.some(function(item) { return item.id === key; });
        if (!client || client.pinned || (client.grouped && client.grouped.length) || (!validNumeric && !exists)) return false;
        if (client.workspaceId === key) { dragToken = null; pickerOpen = false; moveState = ({ kind: 'idle' }); return true; }
        if (services.preview || services.safeMode) return false;
        var exactRef = refFor(client);
        var requestId = services.hyprland.moveWindow(exactRef, key, point || null);
        if (!requestId || _pendingMoves[requestId]) return false;
        var pending = Object.assign({}, _pendingMoves);
        pending[requestId] = { ref: exactRef, destinationId: key, generation: generation };
        _pendingMoves = pending;
        error = '';
        dragToken = null;
        pickerOpen = false;
        moveState = ({ kind: 'moving', ref: exactRef, destinationId: key, requestId: requestId });
        return true;
    }
    function moveSelected(id) { return selectedRef ? moveWindow(selectedRef, id) : false; }
    // point: the drop spot in the destination workspace's global layout coordinates, if known.
    function drop(token, id, point) {
        if (!canDrop(token, id)) return false;
        return moveWindow(token.ref, id, point);
    }
    function finishCommand(requestId, result) {
        var pending = _pendingMoves[requestId];
        if (!pending) return;
        var next = Object.assign({}, _pendingMoves);
        delete next[requestId];
        _pendingMoves = next;
        if (pending.generation !== generation || mode !== 'overview') return;
        if (result && result.ok) {
            var moved = clientFor(pending.ref);
            if (moved) { selectedRef = refFor(moved); selectedWorkspaceId = ''; syncSelected(); }
            moveState = ({ kind: 'moved', ref: pending.ref, destinationId: pending.destinationId });
            error = '';
            return;
        }
        moveState = ({ kind: 'error', reason: result && result.reason || 'unavailable' });
        error = result && result.reason || 'unavailable';
    }
    function dismissTop() {
        if (!active) return false;
        if (mode === 'overview') {
            if (pickerOpen) { pickerOpen = false; return true; }
            if (dragToken) return cancelDrag(dragToken);
            if (query) { query = ''; return true; }
        }
        return cancel();
    }
    function bareSuperTap() {
        return _superPressedAt > 0 && Date.now() - _superPressedAt <= superTapMs;
    }
    function modifier(key, pressed) {
        if (pressed === 'press') pressed = true;
        if (pressed === 'release') pressed = false;
        if (key === 'Super_L' || key === 'Super_R') {
            var supers = Object.assign({}, _superHeld);
            if (pressed) {
                if (Object.keys(supers).length === 0) _superPressedAt = Date.now();
                supers[key] = true;
            }
            else delete supers[key];
            _superHeld = supers;
            services.workspaceHeld = Object.keys(supers).length > 0;
            return true;
        }
        if (key !== 'Alt_L' && key !== 'Alt_R') return false;
        var alts = Object.assign({}, _altHeld);
        var wasHeld = !!alts[key];
        if (pressed) { alts[key] = true; _altReleasedBeforeBegin = false; }
        else delete alts[key];
        _altHeld = alts;
        if (!pressed && wasHeld && Object.keys(alts).length === 0 && !session)
            _altReleasedBeforeBegin = true;
        if (!pressed && wasHeld && Object.keys(alts).length === 0 && session) commit();
        return true;
    }
    function switchWindow(action) {
        if (action === 'next') return beginSwitcher('all', 1);
        if (action === 'previous') return beginSwitcher('all', -1);
        if (action === 'application') return beginSwitcher('application', 1);
        if (action === 'back') return beginSwitcher('application', -1);
        if (action === 'commit') return commit();
        if (action === 'cancel') return cancel();
        return false;
    }
}
