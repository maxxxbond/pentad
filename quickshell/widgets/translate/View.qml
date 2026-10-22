pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/tool-catalog.mjs' as Tools

// Sends text to the translation service through translate-shell only when Translate is pressed.
Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    property var controller: null
    property bool canAppendInput: true
    property string result: ''
    property string message: ''
    property string jobId: ''
    property string target: 'uk'
    readonly property var languages: [
        { id: 'uk', text: 'Ukrainian' }, { id: 'en', text: 'English' }, { id: 'de', text: 'German' },
        { id: 'pl', text: 'Polish' }, { id: 'fr', text: 'French' }, { id: 'es', text: 'Spanish' }]
    readonly property var resultItem: ({ kind: 'text', mimeType: 'text/plain', value: root.result, compatibleTypes: ['text/plain'] })
    readonly property var resultTargets: Tools.compatibleTools(Tools.toolEntries(root.services.plugins.catalog), [root.resultItem]).map(entry => entry.manifest.id)
    implicitWidth: 330
    implicitHeight: content.implicitHeight
    function acceptInput(items, choice) {
        if (!Array.isArray(items) || items.some(item => typeof item.value !== 'string')) return false;
        const incoming = items.map(item => item.value).join('\n');
        if (source.text && !choice) return false;
        const next = choice === 'append' && source.text ? source.text + '\n' + incoming : incoming;
        if (Tools.utf8Length(next) > 65536) { message = 'Text is limited to 64 KiB.'; return false; }
        source.text = next;
        message = '';
        return true;
    }
    function translate() {
        if (!source.text.trim()) { message = 'Enter text first.'; return; }
        if (Tools.utf8Length(source.text) > 65536) { message = 'Text is limited to 64 KiB.'; return; }
        message = ''; result = '';
        jobId = services.fileTools.run('text.translate', [], { target: target }, source.text, 60000);
    }
    Connections {
        target: root.services.fileTools
        function onJobFinished(requestId, value) {
            if (requestId !== root.jobId) return;
            root.jobId = '';
            if (value.ok) root.result = value.text || '';
            else root.message = value.reason || 'Translation failed.';
        }
    }
    Column {
        id: content
        width: root.width
        spacing: 12
        TextArea {
            id: source
            objectName: 'translate-tool-source'
            width: parent.width; height: 112; wrapMode: TextEdit.Wrap
            placeholderText: 'Text to translate'
            text: root.services.toolWorkspace.draftFor('pentad.translate')
            color: Theme.tokens.text; placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            onTextChanged: root.services.toolWorkspace.setDraft('pentad.translate', text)
            background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
        }
        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: root.languages
                delegate: PentadButton {
                    required property var modelData
                    objectName: 'translate-tool-target-' + modelData.id
                    text: modelData.text
                    controlHeight: Metrics.controlSmall
                    checkable: true
                    checked: root.target === modelData.id
                    onClicked: root.target = modelData.id
                }
            }
        }
        Row {
            spacing: 8
            PentadButton {
                objectName: 'translate-tool-run'
                text: root.jobId ? 'Cancel' : 'Translate'
                onClicked: root.jobId ? root.services.fileTools.cancel(root.jobId) : root.translate()
            }
            PentadButton { text: 'Copy'; visible: !!root.result; onClicked: { output.selectAll(); output.copy(); output.deselect(); } }
            PentadButton { text: 'Hand off'; visible: !!root.result && root.resultTargets.length > 0; onClicked: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        TextArea {
            id: output
            objectName: 'translate-tool-output'
            visible: !!root.result
            width: parent.width; height: Math.min(200, Math.max(72, implicitHeight))
            readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
            text: root.result
            color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            background: Rectangle { color: Theme.tokens.surface; radius: Metrics.radiusSmall }
        }
        PentadText {
            visible: !!root.message
            width: parent.width
            text: root.message
            role: 'caption'; color: root.message === 'Cancelled' ? Theme.tokens.textMuted : Theme.tokens.error; wrapMode: Text.Wrap
        }
    }
}
