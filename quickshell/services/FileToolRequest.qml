import QtQuick
import Quickshell.Io

Process {
    id: request
    required property string helperPath
    required property var payload
    required property int timeoutMs
    property bool startedOnce: false
    property bool settled: false
    property bool cancelling: false
    property string cancelReason: ''
    signal completed(var result)
    command: ['python3', '-I', helperPath]
    stdinEnabled: true
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    function finish(result) {
        if (settled) return;
        settled = true;
        deadline.stop();
        escalation.stop();
        completed(result);
    }
    // The helper answers SIGTERM by stopping its CLI and removing partial output, so cancel
    // waits for that answer and only forces the stop if the helper does not exit in time.
    function cancel(reason) {
        if (settled || cancelling) return;
        cancelling = true;
        cancelReason = reason || 'Cancelled';
        if (running) { signal(15); escalation.restart(); }
        else finish({ ok: false, cancelled: true, reason: cancelReason });
    }
    onStarted: {
        startedOnce = true;
        deadline.restart();
        write(JSON.stringify(payload));
        stdinEnabled = false;
    }
    onRunningChanged: if (!running && !startedOnce && !settled) finish({ ok: false, reason: 'Could not start the local file tool.' });
    onExited: function(code, status) {
        let result;
        try { result = JSON.parse(stdout.text || '{}'); }
        catch (error) { result = { ok: false, reason: 'The file tool returned invalid data.' }; }
        if (cancelling) result = Object.assign({}, result, { ok: false, cancelled: true, reason: cancelReason });
        else if (code !== 0 || status !== 0 || typeof result.ok !== 'boolean') result = { ok: false, reason: result.reason || 'The file tool stopped unexpectedly.' };
        finish(result);
        destroy();
    }
    property Timer deadline: Timer {
        interval: request.timeoutMs
        onTriggered: request.cancel('Stopped after the time limit')
    }
    property Timer escalation: Timer {
        interval: 6000
        onTriggered: if (request.running) request.signal(9)
    }
}
