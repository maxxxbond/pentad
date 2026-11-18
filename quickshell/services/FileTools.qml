import QtQuick

// Runs sidebar file operations through the resident worker (`file.run`) when it is available,
// otherwise through tools/pentad_file_tool.py, one helper process per job. Either way a job ends
// with one jobFinished(requestId, result) in the helper's shape: the success object, or
// { ok: false, reason: <message for people>, cancelled? }.
QtObject {
    id: root
    required property string helperPath
    // The Worker service, or null: jobs then always use the one-shot helper.
    property var worker: null
    property int serial: 0
    property var requests: ({})
    // Recent results by request id, so a tool reopened after its job ended can still show the outcome.
    property var finished: ({})
    // Newest-first published outputs of finished jobs, shown as Recent results in the catalog.
    property var history: []
    readonly property int activeCount: Object.keys(requests).length
    signal jobFinished(string requestId, var result)
    function forget(uri) { history = history.filter(item => item.uri !== uri); }
    property Component requestFactory: Component { FileToolRequest {} }
    function run(operation, inputs, options, text, timeoutMs) {
        const requestId = 'file-tool-' + (++serial);
        const payload = { operation: operation, inputs: inputs || [], options: options || {} };
        if (typeof text === 'string') payload.text = text;
        const limit = Math.max(1000, timeoutMs || 300000);
        // A worker that went down gets one fresh start per 30 s window; until then the helper runs the job.
        if (worker && typeof worker.recover === 'function') worker.recover();
        if (worker && worker.accepts('file.run')) runOnWorker(requestId, payload, limit);
        else runHelper(requestId, payload, limit);
        return requestId;
    }
    function track(requestId, request) {
        requests = Object.assign({}, requests, { [requestId]: request });
    }
    function runHelper(requestId, payload, limit) {
        const request = requestFactory.createObject(root, { helperPath: helperPath, payload: payload, timeoutMs: limit });
        if (!request) {
            Qt.callLater(function() { root.jobFinished(requestId, { ok: false, reason: 'Could not create the local file tool.' }); });
            return;
        }
        track(requestId, request);
        request.completed.connect(function(result) { root.complete(requestId, result); });
        request.running = true;
    }
    function runOnWorker(requestId, payload, limit) {
        const job = { workerId: 0, cancelled: false };
        track(requestId, job);
        // The worker never answers before request() returns, so workerId is set in time for cancel().
        job.workerId = worker.request('file.run', payload, { timeoutMs: limit,
            onResult: result => root.workerFinished(requestId, payload, limit, result) });
    }
    function workerFinished(requestId, payload, limit, result) {
        const job = requests[requestId];
        if (!job) return;
        // The worker could not take the job at all (it never ran): the one-shot helper runs it instead.
        if (!job.cancelled && result && result.ok === false && (result.reason === 'unavailable' || result.reason === 'unsupported')) {
            const next = Object.assign({}, requests);
            delete next[requestId];
            requests = next;
            runHelper(requestId, payload, limit);
            return;
        }
        complete(requestId, helperResult(result));
    }
    // The worker reports { ok, value } / { ok: false, reason: <Result reason>, message }; consumers
    // keep the helper's shape, where the message for people is `reason`.
    function helperResult(result) {
        if (result && result.ok === true) return Object.assign({}, result.value || {}, { ok: true });
        const reason = result ? result.reason : '';
        const message = result && typeof result.message === 'string' ? result.message : '';
        if (reason === 'cancelled') return { ok: false, cancelled: true, reason: 'Cancelled' };
        if (reason === 'timeout') return { ok: false, cancelled: true, reason: message || 'Stopped after the time limit' };
        if (reason === 'busy') return { ok: false, reason: 'Too many file jobs are waiting; try again shortly.' };
        return { ok: false, reason: message || 'The file tool stopped unexpectedly.' };
    }
    function complete(requestId, result) {
        const next = Object.assign({}, root.requests);
        delete next[requestId];
        root.requests = next;
        const kept = Object.keys(root.finished).slice(-15);
        const done = {};
        for (const key of kept) done[key] = root.finished[key];
        done[requestId] = result;
        root.finished = done;
        // Signal arguments may arrive as list wrappers rather than JS arrays, so copy by index.
        const outputs = result.ok && result.outputs ? Array.prototype.slice.call(result.outputs) : [];
        if (outputs.length) {
            const added = outputs.reverse();
            const uris = added.map(item => item.uri);
            root.history = added.concat(root.history.filter(item => uris.indexOf(item.uri) < 0)).slice(0, 12);
        }
        root.jobFinished(requestId, result);
    }
    function cancel(requestId) {
        const request = requests[requestId];
        if (!request) return;
        if (request.workerId !== undefined) {
            request.cancelled = true;
            if (worker) worker.cancel(request.workerId);
        } else request.cancel('Cancelled');
    }
}
