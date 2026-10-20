import QtQuick
import Quickshell.Io

Process {
    id: request
    required property string helperPath
    required property string stateRoot
    required property string emojiPath
    required property var payload
    property var response: null
    property bool startedOnce: false
    property bool settled: false
    signal finished(var result)
    command: ['python3', helperPath, '--state-root', stateRoot, '--emoji-data', emojiPath]
    stdinEnabled: true
    onStarted: { startedOnce = true; write(JSON.stringify(payload) + '\n'); stdinEnabled = false; }
    onRunningChanged: {
        if (!running && !startedOnce && !settled) {
            settled = true;
            finished({ ok: false, reason: 'unavailable' });
            destroy();
        }
    }
    stdout: SplitParser {
        onRead: function(line) {
            try { request.response = JSON.parse(line); }
            catch (error) { request.response = { ok: false, reason: 'io' }; }
        }
    }
    onExited: {
        if (!settled) { settled = true; finished(response || { ok: false, reason: 'io' }); }
        destroy();
    }
    property Timer deadline: Timer {
        interval: 10000; running: true
        onTriggered: {
            if (request.settled) return;
            request.settled = true;
            request.finished({ ok: false, reason: 'timeout' });
            if (request.running) request.signal(9);
            else request.destroy();
        }
    }
}
