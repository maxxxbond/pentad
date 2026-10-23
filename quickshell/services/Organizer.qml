import QtQuick
import QtQml
import "../logic/organizer.mjs" as OrganizerLogic

QtObject {
    id: root
    required property var config
    property var calendarSources: []
    property int firstDayOfWeek: Qt.locale().firstDayOfWeek
    property var document: OrganizerLogic.DEFAULT_ORGANIZER
    property string draftText: ""
    property string selectedDayKey: OrganizerLogic.dayKey(new Date())
    property string monthKey: selectedDayKey.slice(0, 7)
    property var events: []
    property var sourceErrors: []
    property string error: ""
    property string notice: ""
    property bool dirty: false
    property bool initialized: false
    property bool saving: false
    property bool saveQueued: false
    property bool persistenceDisabled: false
    property int localRevision: 0
    property int savedRevision: 0
    property var observedConfigRevision: null
    property int serial: 0
    property int taskSerial: 0
    property int sourceGeneration: 0
    property var sourceCancellation: null
    property var sourceUnsubscribers: []
    property string saveRequestId: ""
    property int saveRevision: 0
    readonly property int incompleteCount: document.tasks.filter(function(task) { return !task.done; }).length
    readonly property var orderedTasks: OrganizerLogic.orderedTasks(document.tasks)
    signal commandFinished(string requestId, var result)

    function nextRequestId() { return "organizer-" + (++serial); }
    function finish(requestId, result) { Qt.callLater(function() { commandFinished(requestId, result); }); }
    function syncFromConfig() {
        if (config.preview) {
            if (!initialized) { document = OrganizerLogic.parseOrganizer(OrganizerLogic.DEFAULT_ORGANIZER); initialized = true; }
            persistenceDisabled = true;
            return;
        }
        const state = config.documentStates.organizer;
        if (!state || state.kind === "loading") return;
        if (state.kind === "invalid" || state.kind === "error") {
            persistenceDisabled = true;
            error = state.kind === "invalid" ? "organizer-invalid" : "organizer-read-failed";
            initialized = true;
            return;
        }
        if (!dirty && error !== "organizer-conflict") persistenceDisabled = false;
        if (!dirty && !saving) {
            try {
                const currentRevision = config.revisions.organizer || null;
                const nextDocument = OrganizerLogic.parseOrganizer(config.documents.organizer || OrganizerLogic.DEFAULT_ORGANIZER);
                if (!initialized || currentRevision !== observedConfigRevision) document = nextDocument;
                initialized = true;
                observedConfigRevision = currentRevision;
                error = "";
            } catch (parseError) {
                persistenceDisabled = true;
                error = "organizer-invalid";
                initialized = true;
            }
        } else if (dirty && !saving && (config.revisions.organizer || null) !== observedConfigRevision) {
            observedConfigRevision = config.revisions.organizer || null;
            error = "organizer-conflict";
            persistenceDisabled = true;
        }
    }
    function mutateDocument(next) {
        if (!initialized) { error = "organizer-loading"; return false; }
        document = OrganizerLogic.parseOrganizer(next);
        localRevision++;
        dirty = true;
        notice = "";
        if (initialized) queueSave();
        return true;
    }
    function queueSave() {
        if (persistenceDisabled || config.preview) return;
        if (saving) { saveQueued = true; return; }
        saving = true;
        saveQueued = false;
        saveRevision = localRevision;
        saveRequestId = config.save("organizer", document);
    }
    function handleConfigResult(requestId, result) {
        if (requestId !== saveRequestId) return;
        saving = false;
        saveRequestId = "";
        if (result.ok) {
            error = "";
            savedRevision = saveRevision;
            observedConfigRevision = config.revisions.organizer || null;
            if (localRevision === saveRevision) dirty = false;
        } else if (result.reason === "conflict") {
            error = "organizer-conflict";
            persistenceDisabled = true;
            config.reload("organizer");
        } else if (result.reason === "invalid") {
            persistenceDisabled = true;
            error = "organizer-invalid";
        } else {
            error = "organizer-save-failed";
        }
        if (saveQueued || (dirty && !persistenceDisabled && result.ok && localRevision !== saveRevision)) {
            saveQueued = false;
            queueSave();
        }
    }
    function setTab(tab) {
        const requestId = nextRequestId();
        if (!initialized) { finish(requestId, { ok: false, reason: "loading" }); return requestId; }
        if (!['calendar', 'tasks'].includes(tab)) { finish(requestId, { ok: false, reason: "invalid" }); return requestId; }
        if (document.tab !== tab) mutateDocument(Object.assign({}, document, { tab: tab }));
        finish(requestId, { ok: true });
        return requestId;
    }
    function setCollapsed(collapsed) {
        const requestId = nextRequestId();
        if (!initialized) { finish(requestId, { ok: false, reason: "loading" }); return requestId; }
        if (typeof collapsed !== "boolean") { finish(requestId, { ok: false, reason: "invalid" }); return requestId; }
        if (document.collapsed !== collapsed) mutateDocument(Object.assign({}, document, { collapsed: collapsed }));
        finish(requestId, { ok: true });
        return requestId;
    }
    function setDraftText(text) {
        draftText = String(text).slice(0, 500);
    }
    function addTask(text) {
        const requestId = nextRequestId();
        if (!initialized) { finish(requestId, { ok: false, reason: "loading" }); return requestId; }
        try {
            const id = "task-" + Date.now().toString(36) + "-" + (++taskSerial).toString(36);
            const tasks = OrganizerLogic.addTask(document.tasks, text, id, Date.now());
            mutateDocument(Object.assign({}, document, { tasks: tasks }));
            draftText = "";
            finish(requestId, { ok: true, id: id });
        } catch (error) {
            finish(requestId, { ok: false, reason: "invalid", message: error.message });
        }
        return requestId;
    }
    function editTask(id, text) {
        const requestId = nextRequestId();
        if (!initialized) { finish(requestId, { ok: false, reason: "loading" }); return requestId; }
        try { mutateDocument(Object.assign({}, document, { tasks: OrganizerLogic.updateTask(document.tasks, id, { text: String(text).trim() }) }));
            finish(requestId, { ok: true });
        } catch (error) { finish(requestId, { ok: false, reason: "invalid", message: error.message }); }
        return requestId;
    }
    function setDone(id, done) {
        const requestId = nextRequestId();
        if (!initialized) { finish(requestId, { ok: false, reason: "loading" }); return requestId; }
        try { mutateDocument(Object.assign({}, document, { tasks: OrganizerLogic.updateTask(document.tasks, id, { done: done }) }));
            finish(requestId, { ok: true });
        } catch (error) { finish(requestId, { ok: false, reason: "invalid", message: error.message }); }
        return requestId;
    }
    function removeTask(id) {
        const requestId = nextRequestId();
        if (!initialized) { finish(requestId, { ok: false, reason: "loading" }); return requestId; }
        if (!document.tasks.some(function(task) { return task.id === id; })) {
            finish(requestId, { ok: false, reason: "missing" }); return requestId;
        }
        mutateDocument(Object.assign({}, document, { tasks: OrganizerLogic.removeTask(document.tasks, id) }));
        finish(requestId, { ok: true });
        return requestId;
    }
    function retrySave() {
        const requestId = nextRequestId();
        if (!["organizer-conflict", "organizer-save-failed"].includes(error) || !dirty || !config.documentStates.organizer
            || config.documentStates.organizer.kind !== "ready") {
            finish(requestId, { ok: false, reason: "recovery-required" });
            return requestId;
        }
        persistenceDisabled = false;
        error = "";
        queueSave();
        finish(requestId, { ok: true, reason: "explicit-overwrite" });
        return requestId;
    }
    function recoverInvalidStorage() {
        const requestId = nextRequestId();
        if (error !== "organizer-invalid" && error !== "organizer-read-failed") {
            finish(requestId, { ok: false, reason: "not-invalid" });
            return requestId;
        }
        persistenceDisabled = false;
        error = "";
        dirty = true;
        localRevision++;
        queueSave();
        finish(requestId, { ok: true, reason: "explicit-recovery" });
        return requestId;
    }
    function setSelectedDay(key) {
        if (!OrganizerLogic.parseDayKey(key)) return false;
        selectedDayKey = key;
        monthKey = key.slice(0, 7);
        refreshEvents();
        return true;
    }
    function setMonth(date) {
        monthKey = OrganizerLogic.dayKey(new Date(date.getFullYear(), date.getMonth(), 1)).slice(0, 7);
        refreshEvents();
    }
    function cancelSourceRead() {
        sourceGeneration++;
        if (sourceCancellation) sourceCancellation.cancel();
        sourceCancellation = null;
    }
    function disconnectSources() {
        sourceUnsubscribers.forEach(function(unsubscribe) { if (typeof unsubscribe === "function") unsubscribe(); });
        sourceUnsubscribers = [];
    }
    function connectSources() {
        disconnectSources();
        (calendarSources || []).forEach(function(source) {
            if (source && typeof source.subscribe === "function") {
                const unsubscribe = source.subscribe(function() { refreshEvents(); });
                if (typeof unsubscribe === "function") sourceUnsubscribers.push(unsubscribe);
            }
        });
        refreshEvents();
    }
    function refreshEvents() {
        cancelSourceRead();
        const generation = sourceGeneration;
        const listeners = [];
        const cancellation = {
            cancelled: false,
            onCancel: function(listener) {
                if (cancellation.cancelled) listener(); else listeners.push(listener);
                return function() { const index = listeners.indexOf(listener); if (index >= 0) listeners.splice(index, 1); };
            },
            cancel: function() {
                if (cancellation.cancelled) return;
                cancellation.cancelled = true;
                listeners.splice(0).forEach(function(listener) { listener(); });
            },
        };
        sourceCancellation = cancellation;
        const month = OrganizerLogic.parseDayKey(monthKey + "-01");
        if (!month || !calendarSources || !calendarSources.length) { events = []; sourceErrors = []; return; }
        const dates = OrganizerLogic.monthDates(month, firstDayOfWeek);
        const range = { start: dates[0], end: new Date(dates[41].getFullYear(), dates[41].getMonth(), dates[41].getDate() + 1) };
        // The QML engine has no Promise.allSettled; each read settles into { source, items } or { source, failed }.
        Promise.all(calendarSources.map(function(source) {
            return Promise.resolve().then(function() { return source.read(range, cancellation); })
                .then(function(items) { return { source: source, items: Array.isArray(items) ? items : [] }; },
                    function() { return { source: source, failed: true }; });
        })).then(function(results) {
            if (generation !== sourceGeneration || cancellation.cancelled) return;
            const nextEvents = [], errors = [];
            results.forEach(function(result) {
                const source = result.source;
                if (result.failed) { errors.push(String(source.label || source.id)); return; }
                result.items.forEach(function(event) {
                    nextEvents.push(Object.assign({}, event, { sourceId: source.id,
                        color: OrganizerLogic.eventColor(event.color) || OrganizerLogic.eventColor(source.color) }));
                });
            });
            events = nextEvents;
            sourceErrors = errors;
        });
    }
    property Connections configConnections: Connections {
        target: root.config
        function onDocumentChanged(name) { if (name === "organizer") root.syncFromConfig(); }
        function onDocumentStatesChanged() { root.syncFromConfig(); }
        function onCommandFinished(requestId, result) { root.handleConfigResult(requestId, result); }
    }
    onCalendarSourcesChanged: connectSources()
    onMonthKeyChanged: refreshEvents()
    onFirstDayOfWeekChanged: refreshEvents()
    Component.onCompleted: { syncFromConfig(); connectSources(); }
    Component.onDestruction: { cancelSourceRead(); disconnectSources(); }
}
