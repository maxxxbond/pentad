import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
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
    property string message: ''
    property string svg: ''
    property bool startedOnce: false
    property bool running: false
    property bool cancelRequested: false
    property bool canAppendInput: true
    property string exportPath: ''
    property bool exporting: false
    property bool exportCancelled: false
    implicitWidth: 330
    implicitHeight: content.implicitHeight
    function acceptInput(items, choice) {
        if (!Array.isArray(items) || items.some(item => typeof item.value !== 'string')) return false;
        const incoming = items.map(item => item.value).join('\n');
        if (source.text && !choice) return false;
        const next = choice === 'append' && source.text ? source.text + incoming : incoming;
        if (Tools.utf8Length(next) > 4096) { message = 'Combined input is limited to 4 KiB.'; return false; }
        source.text = next;
        message = '';
        return true;
    }
    function generate() {
        if (!source.text.trim()) { message = 'Enter text or a URL first.'; return; }
        if (Tools.utf8Length(source.text) > 4096) { message = 'QR input is limited to 4 KiB.'; return; }
        message = 'Generating locally…'; svg = ''; startedOnce = false; cancelRequested = false;
        process.stdinEnabled = true; running = true; process.running = true;
    }
    function cancel() {
        if (process.running) { cancelRequested = true; process.signal(15); message = 'Cancelling…'; }
    }
    Process {
        id: process
        command: ['qrencode', '-t', 'SVG', '-o', '-']
        stdinEnabled: true
        stdout: StdioCollector { }
        stderr: StdioCollector {}
        onStarted: { root.startedOnce = true; write(source.text); stdinEnabled = false; }
        onRunningChanged: if (!running && !root.startedOnce) { root.running = false; root.message = 'QR generation is unavailable: qrencode could not start.'; }
        onExited: function(code, status) {
            root.running = false;
            if (root.cancelRequested) root.message = 'Generation cancelled.';
            else if (code !== 0 || status !== 0) root.message = root.startedOnce ? 'QR generation failed.' : 'QR generation is unavailable: qrencode could not start.';
            else root.complete();
        }
    }
    Process {
        id: exportProcess
        command: ['qrencode', '-t', 'SVG', '-o', root.exportPath]
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onStarted: { root.exporting = true; write(source.text); stdinEnabled = false; }
        onRunningChanged: if (!running && root.exporting) { root.exporting = false; root.message = 'Could not start QR export.'; }
        onExited: function(code, status) {
            root.exporting = false;
            root.message = root.exportCancelled ? 'QR export cancelled.' : code === 0 && status === 0 ? 'QR SVG saved.' : 'Could not save the QR SVG.';
        }
    }
    FileDialog {
        id: saveDialog
        title: 'Save QR code as SVG'
        fileMode: FileDialog.SaveFile
        nameFilters: ['SVG image (*.svg)']
        onAccepted: {
            const uri = String(selectedFile);
            if (!uri.startsWith('file:///') || uri.indexOf('?') >= 0 || uri.indexOf('#') >= 0) { root.message = 'Choose a local file path.'; return; }
            root.exportPath = decodeURIComponent(uri.replace(/^file:\/\//, ''));
            root.exportCancelled = false;
            root.exporting = true;
            exportProcess.stdinEnabled = true;
            exportProcess.running = true;
        }
    }
    function complete() {
        if (!startedOnce) return;
        const output = process.stdout.text || '';
        if (output.length > 262144 || !/<svg\b/.test(output)) { message = 'QR generator returned invalid or oversized SVG.'; return; }
        svg = output; message = '';
    }
    Column {
        id: content
        width: root.width; spacing: 8
        TextArea {
            id: source; width: parent.width; height: 84
            placeholderText: 'Text or URL (up to 4 KiB)'
            text: root.services.toolWorkspace.draftFor('pentad.qr')
            color: Theme.tokens.text; placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            onTextChanged: root.services.toolWorkspace.setDraft('pentad.qr', text)
            background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
        }
        Flow {
            width: parent.width
            spacing: 6
            PentadButton { text: root.running ? 'Cancel' : 'Generate QR'; onPressed: root.running ? root.cancel() : root.generate() }
            PentadButton { text: root.exporting ? 'Cancel save' : 'Save SVG'; requestedEnabled: !!root.svg; onPressed: { if (root.exporting) { root.exportCancelled = true; exportProcess.signal(15); } else saveDialog.open(); } }
            PentadButton { text: 'Copy SVG'; requestedEnabled: !!root.svg; onPressed: { svgOutput.selectAll(); svgOutput.copy(); svgOutput.deselect(); } }
            PentadButton { text: 'Use in another tool'; requestedEnabled: !!root.svg && root.resultTargets.length > 0; onPressed: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        TextArea { id: svgOutput; visible: !!root.svg; readOnly: true; selectByMouse: true; text: root.svg; width: parent.width; height: 76; wrapMode: TextEdit.Wrap; color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textCaption }
        Image { visible: !!root.svg; width: 180; height: 180; source: root.svg ? 'data:image/svg+xml,' + encodeURIComponent(root.svg) : ''; fillMode: Image.PreserveAspectFit; cache: false }
        PentadText { visible: !!root.message; text: root.message; role: 'caption'; color: root.message.indexOf('unavailable') >= 0 || root.message.indexOf('failed') >= 0 ? Theme.tokens.error : Theme.tokens.textMuted }
    }
    readonly property var resultItem: ({ kind: 'image', mimeType: 'image/svg+xml', value: root.svg, compatibleTypes: ['image/svg+xml'] })
    readonly property var resultTargets: Tools.compatibleTools(Tools.toolEntries(root.services.plugins.catalog), [root.resultItem]).map(entry => entry.manifest.id)
}
