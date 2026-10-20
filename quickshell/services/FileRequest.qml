import QtQuick
import QtQml
import Quickshell.Io

Process {
    id: request
    required property string helperPath
    required property string configRoot
    required property string stateRoot
    required property var payload
    property var response: null
    signal finished(var result)
    command: ['python3', helperPath, '--config-root', configRoot, '--state-root', stateRoot]
    stdinEnabled: true
    onStarted: { write(JSON.stringify(payload) + '\n'); stdinEnabled = false; }
    stdout: SplitParser {
        onRead: function(line) {
            try { request.response = JSON.parse(line); }
            catch (error) { request.response = { ok: false, reason: 'io', message: 'Invalid helper reply' }; }
        }
    }
    onExited: function(code, status) {
        finished(response || { ok: false, reason: 'io', message: 'File helper did not reply' });
        destroy();
    }
    property Timer deadline: Timer {
        interval: 12000
        running: true
        onTriggered: {
            request.response = { ok: false, reason: 'timeout', message: 'File helper timed out' };
            if (request.running) request.signal(9);
            else {
                request.finished(request.response);
                request.destroy();
            }
        }
    }
}
