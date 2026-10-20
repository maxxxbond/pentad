import QtQuick
import Quickshell.Io

Process {
    id: request
    required property string helperPath
    required property var payload
    property bool startedOnce: false
    property bool settled: false
    signal completed(var result)
    command: ['python3', helperPath]
    stdinEnabled: true
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    function finish(result) {
        if (settled) return;
        settled = true;
        deadline.stop();
        completed(result);
    }
    function cancel() {
        if (settled) return;
        finish({ ok: false, reason: 'File read cancelled.' });
        if (running) signal(15);
        else destroy();
    }
    onStarted: {
        startedOnce = true;
        deadline.restart();
        write(JSON.stringify(payload));
        stdinEnabled = false;
    }
    onRunningChanged: if (!running && !startedOnce && !settled) finish({ ok: false, reason: 'Could not start local file reader.' });
    onExited: function(code, status) {
        if (settled) { destroy(); return; }
        try {
            const result = JSON.parse(stdout.text || '{}');
            if (code !== 0 || status !== 0 || result.ok !== true) finish({ ok: false, reason: result.reason || 'Could not read selected file.' });
            else finish(result);
        } catch (error) { finish({ ok: false, reason: 'Local file reader returned invalid data.' }); }
    }
    property Timer deadline: Timer {
        interval: 8000
        running: false
        onTriggered: {
            request.finish({ ok: false, reason: 'Local file read timed out.' });
            if (request.running) request.signal(15);
        }
    }
}
