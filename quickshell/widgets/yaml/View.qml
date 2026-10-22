import QtQuick
import QtQuick.Controls.Basic
import Quickshell.Io
import qs.components
import qs.theme
import '../../logic/tool-catalog.mjs' as Tools

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    property var controller: null
    property string result: ''
    property string resultMime: 'application/json'
    property string pendingMime: 'application/json'
    property string message: ''
    property bool startedOnce: false
    property bool running: false
    property bool cancelRequested: false
    property bool canAppendInput: true
    readonly property var resultItem: ({ kind: 'text', mimeType: root.resultMime, value: root.result, compatibleTypes: [root.resultMime, 'text/plain'] })
    readonly property var resultTargets: Tools.compatibleTools(Tools.toolEntries(root.services.plugins.catalog), [root.resultItem]).map(entry => entry.manifest.id)
    implicitWidth: 330
    implicitHeight: content.implicitHeight
    function acceptInput(items, choice) {
        if (!Array.isArray(items) || items.some(item => typeof item.value !== 'string')) return false;
        const incoming = items.map(item => item.value).join('\n');
        if (source.text && !choice) return false;
        const next = choice === 'append' && source.text ? source.text + incoming : incoming;
        if (Tools.utf8Length(next) > 262144) { message = 'Combined input is limited to 256 KiB.'; return false; }
        source.text = next;
        message = '';
        return true;
    }
    function convert(toJson) {
        if (running) return;
        if (!source.text.trim()) { message = 'Enter YAML or JSON first.'; return; }
        if (Tools.utf8Length(source.text) > 262144) { message = 'Input is limited to 256 KiB.'; return; }
        process.command = toJson ? ['yq', '-p', 'yaml', '-o', 'json', '-'] : ['yq', '-p', 'json', '-o', 'yaml', '-'];
        pendingMime = toJson ? 'application/json' : 'text/yaml';
        message = ''; result = ''; startedOnce = false; cancelRequested = false;
        process.stdinEnabled = true; running = true; process.running = true;
    }
    function cancel() {
        if (process.running) { cancelRequested = true; process.signal(15); message = 'Cancelling…'; }
    }
    function firstLine(text) {
        const line = String(text || '').split('\n').filter(l => l.trim())[0] || '';
        const trimmed = line.trim();
        return trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
    }
    Process {
        id: process
        command: ['yq', '-p', 'yaml', '-o', 'json', '-']
        stdinEnabled: true
        stdout: StdioCollector { }
        stderr: StdioCollector { }
        onStarted: { root.startedOnce = true; write(source.text); stdinEnabled = false; }
        onRunningChanged: if (!running && !root.startedOnce) { root.running = false; root.message = 'Conversion is unavailable: yq could not start.'; }
        onExited: function(code, status) {
            root.running = false;
            if (root.cancelRequested) { root.message = 'Conversion cancelled.'; return; }
            if (code !== 0 || status !== 0) {
                root.message = root.startedOnce ? (root.firstLine(process.stderr.text) || 'Conversion failed.') : 'Conversion is unavailable: yq could not start.';
                return;
            }
            const output = process.stdout.text || '';
            if (output.length > 1048576) { root.message = 'Converted output is too large.'; return; }
            root.result = output.replace(/\n$/, '');
            root.resultMime = root.pendingMime;
            root.message = '';
        }
    }
    Column {
        id: content
        width: root.width; spacing: 8
        TextArea {
            id: source; objectName: 'yaml-tool-source'; width: parent.width; height: 112; wrapMode: TextEdit.Wrap
            placeholderText: 'Paste or drop YAML or JSON'; text: root.services.toolWorkspace.draftFor('pentad.yaml')
            color: Theme.tokens.text; placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            onTextChanged: root.services.toolWorkspace.setDraft('pentad.yaml', text)
            background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
        }
        Flow {
            width: parent.width; spacing: 8
            PentadButton { objectName: 'yaml-tool-to-json'; text: 'To JSON'; requestedEnabled: !root.running; onPressed: root.convert(true) }
            PentadButton { objectName: 'yaml-tool-to-yaml'; text: 'To YAML'; requestedEnabled: !root.running; onPressed: root.convert(false) }
            PentadButton { objectName: 'yaml-tool-cancel'; text: 'Cancel'; visible: root.running; onPressed: root.cancel() }
            PentadButton { objectName: 'yaml-tool-copy'; text: 'Copy'; requestedEnabled: !!root.result; onPressed: { output.selectAll(); output.copy(); output.deselect(); } }
            PentadButton { objectName: 'yaml-tool-handoff'; text: 'Use in another tool'; requestedEnabled: !!root.result && root.resultTargets.length > 0; onPressed: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        TextArea {
            id: output; objectName: 'yaml-tool-output'
            width: parent.width; height: 126; visible: !!root.result
            readOnly: true; selectByMouse: true; text: root.result; wrapMode: TextEdit.Wrap
            color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            background: Rectangle { color: Theme.tokens.surface; radius: Metrics.radiusSmall }
        }
        PentadText { objectName: 'yaml-tool-message'; visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap; width: parent.width }
    }
}
