import QtQuick
import '../logic/chat.mjs' as ChatLogic
import '../logic/models-settings.mjs' as Rules

// services.modelSettings: the live state and the edits of the settings window's Models page.
// Host-internal: withheld from every widget (logic/widget-services.mjs). Network, keyring and
// worker work goes through the Capabilities service's host-internal methods; edits go through
// services.config.save('models', …) with the document's revision, one reload and retry on a
// conflict, and never while the last read of models.json failed (a broken file the user edits by
// hand is not replaced by defaults). Nothing runs until a page acquires it; while held, a 5 s timer
// reads the loaded models, the VRAM and the worker's counters. A key value is only ever a function
// argument on its way to `secret.store`: never a property, never in the document or a log.
QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property var config: null
    property var capabilities: null
    property int pollInterval: 5000

    readonly property var document: config && config.documents ? config.documents.models : null
    readonly property var writableState: preview ? ({ ok: false, reason: 'preview' })
        : config ? ChatLogic.documentWritable('models', config.documentStates) : ({ ok: false, reason: 'service-missing' })
    // Why network and keyring work does not run here: 'preview', 'safe-mode' or ''.
    readonly property string blocked: preview ? 'preview' : safeMode ? 'safe-mode' : ''
    property int consumers: 0
    readonly property bool active: consumers > 0
    // providerId -> { state: 'loading' | 'ready' | 'error', models, reason, message, signature }
    property var lists: ({})
    // providerId -> { models: [{ name, sizeBytes?, vramBytes?, expiresAt? }] }
    property var loaded: ({})
    property var vram: null
    property var stats: null
    // secret://… -> 'checking' | 'stored' | 'missing' | 'unavailable'
    property var keyStatus: ({})
    // role -> { state: 'warming' | 'warm' | 'skipped' | 'error', loadMs, wallMs, message }
    property var warmth: ({})
    // '' while idle, else the edit in flight ('add-provider', 'role:chat', …); one at a time.
    property string busy: ''
    property var saves: ({})
    // What the provider sheet (flow 'model-provider' of the settings window) edits: a provider id
    // to edit, or '' and the preset to add; keyFirst focuses the key field ("Replace key").
    property var sheet: ({ providerId: '', presetId: 'ollama', keyFirst: false })
    readonly property string providerSignature: JSON.stringify(document && Array.isArray(document.providers) ? document.providers : [])
    signal finished(string action, var result)

    function acquire() {
        consumers += 1;
        if (consumers === 1) refresh(true);
    }
    function release() {
        consumers = Math.max(0, consumers - 1);
    }
    onProviderSignatureChanged: if (active) refresh(true)

    // Every list again (on open, after a provider changed, or from "Refresh"), then the live numbers.
    function refresh(full) {
        if (full === true) {
            refreshLists();
            refreshKeys();
        }
        poll();
    }
    function providers() {
        return document && Array.isArray(document.providers) ? document.providers : [];
    }
    function refreshLists() {
        const next = {};
        for (const provider of providers()) {
            const signature = JSON.stringify(provider);
            next[provider.id] = { state: 'loading', models: root.lists[provider.id] ? root.lists[provider.id].models : [], signature: signature };
            listProvider(provider, signature);
        }
        lists = next;
    }
    function refreshProvider(providerId) {
        const provider = providers().find(item => item.id === providerId);
        if (!provider) return;
        const signature = JSON.stringify(provider);
        lists = Object.assign({}, lists, { [providerId]: { state: 'loading', models: lists[providerId] ? lists[providerId].models : [], signature: signature } });
        listProvider(provider, signature, true);
    }
    function listProvider(provider, signature, revive) {
        if (!capabilities) return;
        capabilities.hostListModels(provider, function(result) {
            const current = root.lists[provider.id];
            // A provider edited or removed meanwhile keeps its newer state.
            if (!current || current.signature !== signature) return;
            const entry = result.ok
                ? { state: 'ready', models: Array.isArray(result.value.models) ? result.value.models : [], signature: signature }
                : { state: 'error', models: [], reason: result.reason, message: result.message, signature: signature };
            root.lists = Object.assign({}, root.lists, { [provider.id]: entry });
        }, revive === true);
    }
    function refreshKeys() {
        const refs = providers().map(item => item.credential).filter(ref => typeof ref === 'string' && ref !== '');
        const next = {};
        for (const ref of refs) next[ref] = keyStatus[ref] || 'checking';
        keyStatus = next;
        for (const ref of refs) checkKey(ref);
    }
    function checkKey(ref) {
        if (!capabilities) return;
        capabilities.hostSecretStatus(ref, function(result) {
            if (root.keyStatus[ref] === undefined) return;
            const status = result.ok ? String(result.value.status || 'missing') : 'unavailable';
            root.keyStatus = Object.assign({}, root.keyStatus, { [ref]: status });
        });
    }
    function poll() {
        if (!capabilities || preview) return;
        const locals = Rules.localOllamaProviders(document);
        const kept = {};
        for (const provider of locals) {
            kept[provider.id] = loaded[provider.id] || { models: [] };
            capabilities.hostLoadedModels(provider, function(result) {
                if (!root.active) return;
                root.loaded = Object.assign({}, root.loaded, { [provider.id]: { models: result.ok && Array.isArray(result.value.models) ? result.value.models : [] } });
            });
        }
        loaded = kept;
        capabilities.hostVram(function(result) {
            if (root.active) root.vram = result.ok ? result.value : { available: false };
        });
        capabilities.hostWorkerStats(function(result) {
            if (root.active) root.stats = result.ok ? result.value : null;
        });
    }
    property Timer pollTimer: Timer {
        interval: root.pollInterval
        repeat: true
        running: root.active && !root.preview
        onTriggered: root.poll()
    }

    // --- Edits ----------------------------------------------------------------------------------

    // { ok } or { ok: false, reason, message } with the "models.json has an error" text.
    function writable() {
        if (preview) return { ok: false, reason: 'preview', message: '' };
        if (busy !== '') return { ok: false, reason: 'busy', message: '' };
        return writableState;
    }
    // mutate(current) -> { ok, value, changed? }; done(result, outcome) runs once.
    function saveDocument(mutate, done, retried) {
        const ready = ChatLogic.documentWritable('models', config.documentStates);
        if (!ready.ok) {
            done(ready, ready);
            return;
        }
        const outcome = mutate(config.documents.models);
        if (!outcome.ok || outcome.changed === false) {
            done(outcome.ok ? { ok: true } : outcome, outcome);
            return;
        }
        const requestId = config.save('models', outcome.value);
        expect(requestId, function(result) {
            if (result && result.ok === true) done({ ok: true }, outcome);
            else if (result && result.reason === 'conflict' && !retried)
                root.expect(root.config.reload('models'), function(read) {
                    if (read && read.ok === true) root.saveDocument(mutate, done, true);
                    else done(read || { ok: false, reason: 'io' }, outcome);
                });
            else done(result || { ok: false, reason: 'io' }, outcome);
        });
    }
    function expect(requestId, handler) {
        saves = Object.assign({}, saves, { [requestId]: handler });
    }
    property Connections configEvents: Connections {
        target: root.config
        ignoreUnknownSignals: true
        function onCommandFinished(requestId, result) {
            const handler = root.saves[requestId];
            if (!handler) return;
            const next = Object.assign({}, root.saves);
            delete next[requestId];
            root.saves = next;
            handler(result);
        }
    }
    // Runs one edit: refuses while another runs or the document is not writable, reports through
    // finished(action, result) and returns false when nothing started.
    function run(action, mutate, after) {
        const ready = writable();
        if (!ready.ok) {
            Qt.callLater(() => root.finished(action, ready));
            return false;
        }
        busy = action;
        saveDocument(mutate, function(result, outcome) {
            root.busy = '';
            if (result.ok && typeof after === 'function') after(outcome);
            root.finished(action, result.ok ? Object.assign({ ok: true }, outcome || {}) : result);
        });
        return true;
    }

    // Adds a provider. `key` (keyring only) is stored first under the provider's reference; the
    // document gets only that reference. A failed store saves nothing.
    function addProvider(draft, key) {
        const id = Rules.suggestProviderId(document, draft.name, draft.kind, draft.baseUrl);
        const probe = Rules.addProvider(document, draft, id);
        if (!probe.ok) {
            Qt.callLater(() => root.finished('add-provider', probe));
            return false;
        }
        const mutate = current => Rules.addProvider(current, draft, id);
        if (draft.keySource !== 'keyring' || typeof key !== 'string' || key.trim() === '')
            return run('add-provider', mutate);
        return storeThen('add-provider', probe.credential, key, mutate);
    }
    // Edits a provider; a non-empty `key` replaces the stored one first.
    function updateProvider(providerId, draft, key) {
        const probe = Rules.updateProvider(document, providerId, draft);
        if (!probe.ok) {
            Qt.callLater(() => root.finished('edit-provider', probe));
            return false;
        }
        const mutate = current => Rules.updateProvider(current, providerId, draft);
        if (draft.keySource !== 'keyring' || typeof key !== 'string' || key.trim() === '')
            return run('edit-provider', mutate);
        return storeThen('edit-provider', probe.credential, key, mutate);
    }
    function storeThen(action, ref, key, mutate) {
        const ready = writable();
        if (ready.ok && blocked !== '') {
            Qt.callLater(() => root.finished(action, { ok: false, reason: blocked, message: '' }));
            return false;
        }
        if (!ready.ok) {
            Qt.callLater(() => root.finished(action, ready));
            return false;
        }
        busy = action;
        capabilities.hostStoreSecret(ref, key, function(stored) {
            root.busy = '';
            if (!stored.ok) {
                root.finished(action, stored);
                return;
            }
            root.keyStatus = Object.assign({}, root.keyStatus, { [ref]: 'stored' });
            root.run(action, mutate);
        });
        return true;
    }
    // Removes a provider and empties the roles bound to it; clearKey also clears its keyring entry.
    function removeProvider(providerId, clearKey) {
        return run('remove-provider', current => Rules.removeProvider(current, providerId), function(outcome) {
            if (clearKey === true && outcome && outcome.credential && root.blocked === '')
                root.capabilities.hostClearSecret(outcome.credential, function(result) {
                    root.keyStatus = Object.assign({}, root.keyStatus, { [outcome.credential]: result.ok ? 'missing' : 'unavailable' });
                    root.finished('clear-key', result);
                });
        });
    }
    function setRole(role, providerId, model) {
        return run('role:' + role, current => Rules.setRole(current, role, providerId, model));
    }
    function setGrant(moduleId, remote) {
        return run('grant:' + moduleId, current => Rules.setGrant(current, moduleId, remote));
    }
    function setIdleMinutes(minutes) {
        return run('idle', current => Rules.setIdleMinutes(current, minutes));
    }
    function warm(role) {
        if (!capabilities || (warmth[role] && warmth[role].state === 'warming')) return false;
        warmth = Object.assign({}, warmth, { [role]: { state: 'warming' } });
        capabilities.hostWarmRole(role, function(result) {
            const value = result.ok ? result.value : {};
            const state = !result.ok ? 'error' : value.warmed === true ? 'warm' : 'skipped';
            root.warmth = Object.assign({}, root.warmth, { [role]: { state: state, loadMs: value.loadMs || 0, wallMs: value.wallMs || 0,
                reason: result.ok ? '' : result.reason, message: result.ok ? '' : result.message } });
            root.finished('warm:' + role, result);
            if (result.ok && root.active) root.poll();
        });
        return true;
    }
    function clearCache() {
        if (!capabilities || busy !== '') return false;
        busy = 'clear-cache';
        capabilities.hostClearCache(function(result) {
            root.busy = '';
            if (result.ok && result.value.cache) root.stats = Object.assign({}, root.stats || {}, { cache: result.value.cache });
            root.finished('clear-cache', result);
        });
        return true;
    }
}
