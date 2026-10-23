import QtQuick
import Quickshell.Io
import '../logic/spotlight-helper.mjs' as Protocol

// One long-lived `pentad_spotlight.py --serve` process for Spotlight's requests, so typing
// does not start an interpreter and re-read the emoji bundle per keystroke. It starts with
// the first request, restarts after a crash or a stuck reply, and stops once Spotlight has
// been closed and idle for `idleInterval`. Replies are parsed here and handed to `done` as
// plain JS objects (no signal in between, so arrays stay arrays).
QtObject {
    id: root
    required property string helperPath
    required property string stateRoot
    required property string emojiPath
    // Spotlight is open: keep the helper warm.
    property bool active: false
    property int idleInterval: 60000
    property int replyTimeout: 10000
    property var client: new Protocol.HelperClient()
    property bool workerStarted: false

    onActiveChanged: watch()

    // `key` (optional) coalesces per-keystroke requests: see logic/spotlight-helper.mjs.
    function request(payload, done, key) {
        const sent = client.request(payload, done, key);
        if (sent.error) {
            Qt.callLater(() => done({ ok: false, reason: sent.error }));
            return;
        }
        send(sent.lines);
        if (!worker.running)
            worker.running = true;
        watch();
        settle(sent.calls);
    }
    function send(lines) {
        for (const line of lines)
            worker.write(line);
    }
    function settle(calls) {
        for (const call of calls)
            call[0](call[1]);
    }
    function watch() {
        if (!client.waiting)
            watchdog.stop();
        else if (!watchdog.running)
            watchdog.restart();
        if (!active && client.idle && worker.running)
            idleTimer.restart();
        else
            idleTimer.stop();
    }
    function kill() {
        // processId is 0 until the process has started, and signalling pid 0 would hit
        // Quickshell's own process group.
        if (worker.running && worker.processId > 0)
            worker.signal(9);
    }
    function receive(line) {
        const outcome = client.receive(line);
        if (outcome.broken) {
            client.retire();
            kill();
        }
        send(outcome.lines);
        if (outcome.calls.length)
            watchdog.stop();
        watch();
        settle(outcome.calls);
    }

    property Process worker: Process {
        command: ['python3', root.helperPath, '--state-root', root.stateRoot, '--emoji-data', root.emojiPath, '--serve']
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.receive(line)
        }
        onStarted: {
            root.workerStarted = true;
            root.send(root.client.started());
            root.watch();
        }
        onRunningChanged: {
            if (running)
                return;
            const outcome = root.client.stopped(root.workerStarted);
            root.workerStarted = false;
            if (outcome.restart)
                running = true;
            root.watch();
            root.settle(outcome.calls);
        }
        // A new helper path or state root applies to the next process.
        onCommandChanged: if (running) {
            root.client.retire();
            running = false;
        }
    }
    property Timer watchdog: Timer {
        interval: root.replyTimeout
        onTriggered: {
            const calls = root.client.timeout();
            root.kill();
            root.watch();
            root.settle(calls);
        }
    }
    property Timer idleTimer: Timer {
        interval: root.idleInterval
        onTriggered: if (!root.active && root.client.idle && root.worker.running) {
            root.client.retire();
            root.worker.running = false;
        }
    }
}
