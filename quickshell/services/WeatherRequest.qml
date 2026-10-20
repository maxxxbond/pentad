import QtQuick
import Quickshell.Io

Process {
    id: request
    required property string url
    property bool startedOnce: false
    property bool settled: false
    signal completed(bool ok, var value, string message)
    command: ['curl', '--silent', '--show-error', '--fail', '--location',
        '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '5',
        '--max-time', '12', '--max-filesize', '262144', '--write-out', '\n%{http_code}',
        '--url', url]
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    function finish(ok, value, message) {
        if (settled) return;
        settled = true;
        deadline.stop();
        completed(ok, value, message);
        destroy();
    }
    function cancel() {
        if (settled) return;
        settled = true;
        deadline.stop();
        if (running) signal(9);
        destroy();
    }

    onStarted: {
        startedOnce = true;
        deadline.restart();
    }
    onRunningChanged: {
        if (!running && !startedOnce && !settled)
            finish(false, null, 'Weather request could not start.');
    }
    onExited: function(code, exitStatus) {
        if (settled) return;
        const text = stdout.text || '';
        const footer = /\n(\d{3})$/.exec(text);
        const status = footer ? Number(footer[1]) : 0;
        const body = footer ? text.slice(0, footer.index) : '';
        if (code !== 0 || exitStatus !== 0 || status < 200 || status >= 300) {
            finish(false, null, 'Weather service request failed.');
            return;
        }
        try { finish(true, JSON.parse(body), ''); }
        catch (error) { finish(false, null, 'Weather service returned invalid data.'); }
    }

    property Timer deadline: Timer {
        interval: 13000
        running: false
        onTriggered: {
            if (request.running) request.signal(9);
            request.finish(false, null, 'Weather request timed out.');
        }
    }
}
