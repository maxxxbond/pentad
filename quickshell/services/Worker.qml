import QtQuick
import Quickshell
import Quickshell.Io
import '../logic/worker-protocol.mjs' as Protocol

// Supervises the resident `pentad_worker.py --serve` process (protocol v1, see
// logic/worker-protocol.mjs and the tool's docstring). It starts with the first request, waits
// 5 s for the worker's hello, restarts a crashed worker with backoff, stops after a crash loop,
// and retires the process once it has been idle for `idleExitSeconds`. Preview never starts it.
// Callbacks receive plain JS objects and never fire before request() has returned.
QtObject {
    id: root
    required property string helperPath
    property string cacheRoot: (Quickshell.env('XDG_CACHE_HOME') || Quickshell.env('HOME') + '/.cache') + '/pentad/worker'
    property bool preview: false
    property int idleExitSeconds: 600
    property int cacheMiB: 64
    property int helloTimeout: Protocol.WORKER_HELLO_TIMEOUT_MS
    property var client: new Protocol.WorkerClient({
        write: line => root.writeLine(line)
    })
    property string workerState: 'idle'
    // idle | starting | ready | crash-loop | unavailable
    readonly property string state: preview ? 'unavailable' : workerState
    property bool processStarted: false
    property int previewSerial: 0

    // callbacks: { onProgress(data), onPartial(chunk), onResult(result), timeoutMs }. Returns the request id.
    function request(op, payload, callbacks) {
        const handlers = callbacks || {};
        if (preview) {
            const previewId = -(++previewSerial);
            if (typeof handlers.onResult === 'function')
                Qt.callLater(() => handlers.onResult({
                    ok: false,
                    reason: 'preview',
                    message: 'The worker does not run in preview'
                }));
            return previewId;
        }
        let returned = false;
        const deliver = (handler, value) => {
            if (typeof handler !== 'function')
                return;
            if (returned)
                handler(value);
            else
                Qt.callLater(() => handler(value));
        };
        const id = client.request(op, payload, {
            timeoutMs: handlers.timeoutMs,
            onProgress: data => deliver(handlers.onProgress, data),
            onPartial: chunk => deliver(handlers.onPartial, chunk),
            onResult: result => {
                deliver(handlers.onResult, result);
                root.update();
            }
        });
        returned = true;
        if (client.needsStart)
            start();
        update();
        return id;
    }
    function cancel(id) {
        if (client.cancel(id))
            update();
    }
    function accepts(op) {
        return !preview && client.accepts(op);
    }
    // Leaves crash-loop or unavailable so the next request tries a fresh process.
    function retry() {
        client.reset();
        update();
    }
    // For user-initiated work: a worker that has been down for 30 s gets one fresh start per
    // window (see WorkerClient.recover). Returns true when the next request will start a process.
    function recover() {
        if (preview || !client.recover(Date.now()))
            return false;
        update();
        return true;
    }
    function writeLine(line) {
        if (worker.running)
            worker.write(line);
    }
    function start() {
        if (preview || worker.running)
            return;
        restartTimer.stop();
        processStarted = false;
        // Also bounds a process that never reports it started.
        helloTimer.restart();
        worker.running = true;
    }
    function kill() {
        // processId is 0 until the process has started, and signalling pid 0 would hit
        // Quickshell's own process group.
        if (worker.running && worker.processId > 0)
            worker.signal(9);
    }
    function update() {
        workerState = client.state;
        if (worker.running && client.state === 'ready' && client.busyCount === 0)
            idleTimer.restart();
        else
            idleTimer.stop();
    }
    function receive(line) {
        const outcome = client.receive(line);
        if (client.state !== 'starting')
            helloTimer.stop();
        if (outcome.kill)
            kill();
        update();
    }

    property Process worker: Process {
        command: ['python3', '-I', root.helperPath, '--serve', '--cache-root', root.cacheRoot, '--cache-mib', String(root.cacheMiB)]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.receive(line)
        }
        onStarted: {
            root.processStarted = true;
            root.client.started();
            root.helloTimer.restart();
            root.update();
        }
        onRunningChanged: {
            if (running)
                return;
            root.helloTimer.stop();
            // A process that never started is treated like one that never said hello.
            if (!root.processStarted && root.client.state !== 'unavailable' && root.client.state !== 'crash-loop') {
                root.client.started();
                root.client.helloTimedOut();
            }
            root.processStarted = false;
            const outcome = root.client.stopped(Date.now());
            if (outcome.restart) {
                if (outcome.delayMs > 0) {
                    root.restartTimer.interval = outcome.delayMs;
                    root.restartTimer.restart();
                } else
                    root.start();
            }
            root.update();
        }
        // New settings (cache size, paths) apply to the next process.
        onCommandChanged: if (running) {
            root.client.retire();
            running = false;
        }
    }
    property Timer helloTimer: Timer {
        interval: root.helloTimeout
        onTriggered: {
            if (!root.processStarted)
                root.client.started();
            root.client.helloTimedOut();
            if (root.worker.running && root.worker.processId > 0)
                root.kill();
            else
                root.worker.running = false;
            root.update();
        }
    }
    property Timer restartTimer: Timer {
        onTriggered: root.start()
    }
    property Timer idleTimer: Timer {
        interval: Math.max(1, root.idleExitSeconds) * 1000
        onTriggered: if (root.worker.running && root.client.busyCount === 0) {
            root.client.retire();
            root.worker.running = false;
        }
    }
    Component.onDestruction: {
        helloTimer.stop();
        restartTimer.stop();
        idleTimer.stop();
        client.retire();
        worker.running = false;
    }
}
