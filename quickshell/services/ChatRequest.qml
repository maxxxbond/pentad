import QtQuick
import Quickshell.Io

Process {
    id: request
    required property string url
    required property string provider
    required property string credential
    required property string body
    property bool startedOnce: false
    property bool settled: false
    property bool gotDone: false
    property int receivedBytes: 0
    property var eventData: []
    signal delta(var value)
    signal completed(bool ok, string message)

    command: ['curl', '--config', '-', '--no-buffer', '--silent', '--show-error', '--fail',
        '--connect-timeout', '8', '--max-time', '600', '--max-filesize', '1048576',
        '--speed-time', '120', '--speed-limit', '1']
    stdinEnabled: true
    stdout: SplitParser {
        splitMarker: '\n'
        onRead: function(line) { request.readLine(line); }
    }
    stderr: StdioCollector {}

    function quoteConfig(value) {
        return '"' + String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')
            .replace(/\r/g, '\\r').replace(/\n/g, '\\n') + '"';
    }
    function startConfig() {
        const lines = [
            'url = ' + quoteConfig(url),
            'request = "POST"',
            'header = "Content-Type: application/json"',
            'header = ' + quoteConfig(provider === 'api' ? 'Accept: text/event-stream' : 'Accept: application/x-ndjson'),
        ];
        if (provider === 'api') lines.push('header = ' + quoteConfig('Authorization: Bearer ' + credential));
        lines.push('data = ' + quoteConfig(body));
        return lines.join('\n') + '\n';
    }
    function readLine(rawLine) {
        if (settled) return;
        const line = String(rawLine).replace(/\r$/, '');
        receivedBytes += new TextEncoder().encode(line).byteLength + 1;
        if (receivedBytes > 1048576) { finish(false, 'Chat response exceeded 1 MiB.'); signal(9); return; }
        try {
            if (provider === 'ollama') {
                if (!line.trim()) return;
                const event = JSON.parse(line);
                if (event.error) throw new Error('The Ollama provider returned an error.');
                if (event.message && typeof event.message.content === 'string' && event.message.content)
                    delta({ type: 'text', text: event.message.content });
                if (event.done === true) {
                    gotDone = true;
                    delta({ type: 'done', reason: event.done_reason === 'length' ? 'length' : 'stop' });
                }
                return;
            }
            if (line === '') { dispatchEvent(); return; }
            if (line.startsWith(':')) return;
            if (line.startsWith('data:')) {
                let value = line.slice(5);
                if (value.startsWith(' ')) value = value.slice(1);
                eventData.push(value);
                if (eventData.join('\n').length > 1048576) throw new Error('Chat event exceeded 1 MiB.');
            }
        } catch (error) {
            finish(false, error instanceof Error ? error.message : 'Invalid provider stream.');
            if (running) signal(9);
        }
    }
    function dispatchEvent() {
        if (!eventData.length) return;
        const payload = eventData.join('\n');
        eventData = [];
        if (payload === '[DONE]') {
            gotDone = true;
            delta({ type: 'done', reason: finishReason || 'stop' });
            return;
        }
        const event = JSON.parse(payload);
        if (event.error) throw new Error('The API provider returned an error.');
        const choice = Array.isArray(event.choices) ? event.choices[0] : null;
        const text = choice && choice.delta && choice.delta.content;
        if (typeof text === 'string' && text) delta({ type: 'text', text });
        const reason = choice && choice.finish_reason;
        if (reason === 'length' || reason === 'content_filter') {
            finishReason = reason === 'length' ? 'length' : 'content-filter';
        }
    }
    property string finishReason: ''
    function finish(ok, message) {
        if (settled) return;
        settled = true;
        deadline.stop();
        completed(ok, message);
        destroy();
    }
    function cancel() {
        if (settled) return;
        settled = true;
        deadline.stop();
        if (running) signal(15);
        destroy();
    }
    onStarted: {
        startedOnce = true;
        deadline.restart();
        write(startConfig());
        stdinEnabled = false;
    }
    onRunningChanged: if (!running && !startedOnce && !settled) finish(false, 'Chat request could not start.');
    onExited: function(code, exitStatus) {
        if (settled) return;
        if (code !== 0 || exitStatus !== 0) { finish(false, 'Provider request failed. Check the endpoint, credentials, and service status.'); return; }
        if (provider === 'api' && eventData.length) {
            try { dispatchEvent(); } catch (error) { finish(false, 'Provider returned an invalid stream.'); return; }
        }
        if (!gotDone) { finish(false, 'Provider stream ended without a completion marker.'); return; }
        finish(true, '');
    }
    property Timer deadline: Timer {
        interval: 605000
        running: false
        onTriggered: {
            if (request.running) request.signal(15);
            request.finish(false, 'Chat request timed out.');
        }
    }
}
