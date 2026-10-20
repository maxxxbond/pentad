import QtQuick
import QtQml
import Quickshell.Io

Process {
    id: request
    required property string helperPath
    required property string cacheRoot
    required property var payload
    signal finished(var result)
    property bool startedOnce: false
    property bool settled: false
    command: ['python3', helperPath, '--config-root', '', '--state-root', '', '--cache-root', cacheRoot]
    stdinEnabled: true
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onStarted: { startedOnce = true; write(JSON.stringify(payload) + '\n'); stdinEnabled = false; }
    onRunningChanged: {
        if (!running && !startedOnce && !settled) {
            settled = true;
            finished({ ok: false, reason: 'unavailable' });
            destroy();
        }
    }
    onExited: function(code, status) {
        if (settled) return;
        settled = true;
        var result = null;
        try { result = JSON.parse(stdout.text); }
        catch (error) { result = { ok: false, reason: 'io' }; }
        if (code !== 0 && result.ok) result = { ok: false, reason: 'io' };
        finished(result);
        destroy();
    }
    property Timer deadline: Timer {
        interval: 12000
        running: true
        onTriggered: {
            if (request.settled) return;
            request.settled = true;
            if (request.running) request.signal(9);
            request.finished({ ok: false, reason: 'timeout' });
            if (!request.running) request.destroy();
        }
    }
}
