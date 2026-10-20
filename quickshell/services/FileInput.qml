import QtQuick

QtObject {
    id: root
    required property string helperPath
    property int serial: 0
    property var requests: ({})
    signal commandFinished(string requestId, var result)
    property Component requestFactory: Component { FileInputRequest {} }
    function readUris(uris, maxBytes) {
        const requestId = 'file-input-' + (++serial);
        const request = requestFactory.createObject(root, { helperPath: helperPath,
            payload: { uris: uris, maxBytes: maxBytes } });
        if (!request) {
            Qt.callLater(function() { root.commandFinished(requestId, { ok: false, reason: 'Could not create local file reader.' }); });
            return requestId;
        }
        requests = Object.assign({}, requests, { [requestId]: request });
        request.completed.connect(function(result) {
            const next = Object.assign({}, root.requests);
            delete next[requestId];
            root.requests = next;
            root.commandFinished(requestId, result);
            if (!request.running) request.destroy();
        });
        request.running = true;
        return requestId;
    }
    function cancel(requestId) {
        const request = requests[requestId];
        if (request) request.cancel();
    }
}
