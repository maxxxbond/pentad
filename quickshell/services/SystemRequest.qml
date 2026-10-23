import QtQuick
import Quickshell.Io

// One run of tools/pentad_system.py: a JSON request on stdin, one JSON line back.
Process {
    id: request
    required property string helperPath
    required property var payload
    // Changing the time zone or NTP may wait on a polkit password prompt.
    property int timeout: 70000
    property string response: ''
    property bool startedOnce: false
    property bool settled: false
    // The raw JSON line: a JS object passed through a signal reaches the receiver as QVariant lists,
    // which Array.isArray rejects, so the caller parses it in its own context.
    signal finished(string reply)
    command: ['python3', helperPath]
    stdinEnabled: true
    onStarted: { startedOnce = true; write(JSON.stringify(payload) + '\n'); stdinEnabled = false; }
    onRunningChanged: {
        if (!running && !startedOnce && !settled) {
            settled = true;
            finished('{"ok":false,"reason":"unavailable"}');
            destroy();
        }
    }
    stdout: SplitParser {
        onRead: function(line) { request.response = line; }
    }
    onExited: {
        if (!settled) { settled = true; finished(response || '{"ok":false,"reason":"io"}'); }
        destroy();
    }
    property Timer deadline: Timer {
        interval: request.timeout; running: true
        onTriggered: {
            if (request.settled) return;
            request.settled = true;
            request.finished('{"ok":false,"reason":"timeout"}');
            if (request.running) request.signal(9);
            else request.destroy();
        }
    }
}
