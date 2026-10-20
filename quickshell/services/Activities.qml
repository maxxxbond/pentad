import QtQuick
import QtQml
import "../logic/activity.mjs" as ActivityLogic

QtObject {
    id: root
    required property var config
    property bool preview: false
    property bool safeMode: false
    property var timerState: null
    property var player: null
    property bool dnd: false
    property double clockNow: Date.now()
    property int serial: 0
    property bool ready: false
    property bool disposed: false
    property string loadRequestId: ""
    property string loadError: ""
    property var document: ActivityLogic.emptyActivityDocument()
    property var activities: []
    property var queue: []
    property var inFlight: null
    readonly property bool writable: !preview && !safeMode && !config.preview
    readonly property var state: ActivityLogic.selectActivity(timerState, activities, player, clockNow, dnd)
    signal commandFinished(string requestId, var result)
    onWritableChanged: scheduleExpiry()

    property Timer expiryTimer: Timer {
        repeat: false
        onTriggered: {
            root.clockNow = Date.now();
            root.publishActivities();
            root.enqueue("expire", {}, false);
        }
    }

    property Connections configConnections: Connections {
        target: root.config
        function onCommandFinished(requestId, result) { root.configFinished(requestId, result); }
        function onDocumentChanged(name) {
            if (name === "activity" && root.ready && !root.inFlight) root.syncDocument();
        }
    }

    Component.onCompleted: {
        if (preview || safeMode || config.preview) {
            const parsed = ActivityLogic.parseActivityDocument(config.documents.activity);
            ready = true;
            document = parsed.ok ? parsed.value : ActivityLogic.emptyActivityDocument();
            if (!parsed.ok) loadError = parsed.reason;
            publishActivities();
        } else loadRequestId = config.reload("activity");
    }
    Component.onDestruction: dispose()

    function syncDocument() {
        const parsed = ActivityLogic.parseActivityDocument(config.documents.activity);
        if (!parsed.ok) { loadError = parsed.reason; return; }
        document = parsed.value;
        loadError = "";
        publishActivities();
        if (document.activities.some(activity => activity.expiresAt <= Date.now()))
            enqueue("expire", {}, false);
    }

    function publishActivities() {
        const now = Date.now();
        clockNow = now;
        activities = document.activities.filter(activity => activity.expiresAt > now);
        scheduleExpiry();
    }

    function scheduleExpiry() {
        expiryTimer.stop();
        if (disposed || !ready || !writable || !activities.length) return;
        const earliest = Math.min.apply(null, activities.map(activity => activity.expiresAt));
        expiryTimer.interval = Math.max(1000, Math.min(2147483647, earliest - Date.now()));
        expiryTimer.start();
    }

    function enqueue(action, payload, notify) {
        const requestId = notify === false ? "" : "activity-" + (++serial);
        queue = queue.concat([{ requestId: requestId, action: action, payload: payload || {}, notify: notify !== false }]);
        processQueue();
        return requestId;
    }

    function start(id, title, options) { return enqueue("start", { id: id, title: title, options: options || {} }, true); }
    function update(id, options) { return enqueue("update", { id: id, options: options || {} }, true); }
    function end(id) { return enqueue("end", { id: id }, true); }

    function processQueue() {
        if (disposed || !ready || inFlight || !queue.length) return;
        const request = queue[0];
        if (loadError) { finishRequest(request, { ok: false, reason: loadError }); return; }
        if (!writable) { finishRequest(request, { ok: false, reason: preview ? "preview" : "read-only" }); return; }
        const mutation = ActivityLogic.mutateActivities(document, request.action, request.payload, Date.now());
        if (!mutation.ok) { finishRequest(request, { ok: false, reason: mutation.reason }); return; }
        if (!mutation.changed) {
            if (request.action === "expire") { document = mutation.document; publishActivities(); }
            finishRequest(request, { ok: true, value: mutation.value });
            return;
        }
        const configRequestId = config.save("activity", mutation.document);
        inFlight = { configRequestId: configRequestId, request: request, mutation: mutation };
    }

    function configFinished(requestId, result) {
        if (disposed) return;
        if (requestId === loadRequestId) {
            loadRequestId = "";
            if (!result.ok) loadError = result.reason || "io";
            else {
                const parsed = ActivityLogic.parseActivityDocument(config.documents.activity);
                if (!parsed.ok) loadError = parsed.reason;
                else { document = parsed.value; loadError = ""; }
            }
            ready = true;
            publishActivities();
            if (!loadError && document.activities.some(activity => activity.expiresAt <= Date.now()))
                enqueue("expire", {}, false);
            processQueue();
            return;
        }
        if (!inFlight || requestId !== inFlight.configRequestId) return;
        const request = inFlight.request;
        const mutation = inFlight.mutation;
        inFlight = null;
        if (result.ok) {
            document = mutation.document;
            loadError = "";
            publishActivities();
            finishRequest(request, { ok: true, value: mutation.value });
        } else {
            const conflict = result.reason === "conflict";
            if (conflict) ready = false;
            finishRequest(request, { ok: false, reason: result.reason || "io", message: result.message || "" });
            if (conflict) loadRequestId = config.reload("activity");
        }
        processQueue();
    }

    function finishRequest(request, result) {
        queue = queue.slice(1);
        if (request.notify) {
            const id = request.requestId;
            Qt.callLater(function() { if (!root.disposed) root.commandFinished(id, result); });
        }
        processQueue();
    }

    function dispose() {
        if (disposed) return;
        disposed = true;
        expiryTimer.stop();
        queue = [];
        inFlight = null;
    }
}
