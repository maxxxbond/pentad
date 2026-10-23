import QtQuick
import Quickshell.Io

Process {
    id: request
    required property string helperPath
    required property string stateRoot
    required property string emojiPath
    required property var payload
    property string response: ''
    property bool startedOnce: false
    property bool settled: false
    // The raw JSON line: a JS object passed through a signal reaches the receiver as QVariant lists,
    // which Array.isArray rejects, so the caller parses it in its own context.
    signal finished(string reply)
    command: ['python3', helperPath, '--state-root', stateRoot, '--emoji-data', emojiPath]
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
        interval: 10000; running: true
        onTriggered: {
            if (request.settled) return;
            request.settled = true;
            request.finished('{"ok":false,"reason":"timeout"}');
            if (request.running) request.signal(9);
            else request.destroy();
        }
    }
}
