import QtQuick

// Runs sidebar file operations through tools/pentad_file_tool.py, one helper process per job.
QtObject {
    id: root
    required property string helperPath
    property int serial: 0
    property var requests: ({})
    // Recent results by request id, so a tool reopened after its job ended can still show the outcome.
    property var finished: ({})
    readonly property int activeCount: Object.keys(requests).length
    signal jobFinished(string requestId, var result)
    property Component requestFactory: Component { FileToolRequest {} }
    function run(operation, inputs, options, text, timeoutMs) {
        const requestId = 'file-tool-' + (++serial);
        const payload = { operation: operation, inputs: inputs || [], options: options || {} };
        if (typeof text === 'string') payload.text = text;
        const request = requestFactory.createObject(root, { helperPath: helperPath, payload: payload,
            timeoutMs: Math.max(1000, timeoutMs || 300000) });
        if (!request) {
            Qt.callLater(function() { root.jobFinished(requestId, { ok: false, reason: 'Could not create the local file tool.' }); });
            return requestId;
        }
        requests = Object.assign({}, requests, { [requestId]: request });
        request.completed.connect(function(result) {
            const next = Object.assign({}, root.requests);
            delete next[requestId];
            root.requests = next;
            const kept = Object.keys(root.finished).slice(-15);
            const done = {};
            for (const key of kept) done[key] = root.finished[key];
            done[requestId] = result;
            root.finished = done;
            root.jobFinished(requestId, result);
        });
        request.running = true;
        return requestId;
    }
    function cancel(requestId) {
        const request = requests[requestId];
        if (request) request.cancel('Cancelled');
    }
}
