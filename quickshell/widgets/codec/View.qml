import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/tool-catalog.mjs' as Tools
import '../../logic/text-tools.mjs' as TextTools

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    property var controller: null
    property string mode: 'base64'
    property string result: ''
    property string message: ''
    property bool canAppendInput: true
    readonly property var modes: [
        { id: 'base64', label: 'Base64' }, { id: 'base64url', label: 'Base64URL' }, { id: 'url', label: 'URL' },
        { id: 'html', label: 'HTML entities' }, { id: 'hex', label: 'Hex' }, { id: 'jwt', label: 'JWT' }
    ]
    readonly property var resultItem: ({ kind: 'text', mimeType: 'text/plain', value: root.result, compatibleTypes: ['text/plain'] })
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
    function apply(r, label) {
        if (r.ok) { result = r.value; message = ''; }
        else { result = ''; message = r.reason; }
    }
    function run(decode) {
        if (Tools.utf8Length(source.text) > 262144) { message = 'Input is limited to 256 KiB.'; return; }
        if (!source.text) { message = 'Enter text first.'; return; }
        apply(decode ? TextTools.decodeText(mode, source.text, Date.now()) : TextTools.encodeText(mode, source.text));
    }
    function runAuto() {
        if (Tools.utf8Length(source.text) > 262144) { message = 'Input is limited to 256 KiB.'; return; }
        const r = TextTools.autoDecode(source.text, Date.now());
        if (r.ok) { for (const m of modes) if (m.id === r.mode) mode = m.id; }
        apply(r);
    }
    Column {
        id: content
        width: root.width; spacing: 8
        TextArea {
            id: source; objectName: 'codec-tool-source'; width: parent.width; height: 96; wrapMode: TextEdit.Wrap
            placeholderText: 'Text to encode or decode'; text: root.services.toolWorkspace.draftFor('pentad.codec')
            color: Theme.tokens.text; placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            onTextChanged: root.services.toolWorkspace.setDraft('pentad.codec', text)
            background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
        }
        Flow {
            objectName: 'codec-tool-modes'
            width: parent.width; spacing: 8
            Repeater {
                model: root.modes
                PentadButton {
                    required property var modelData
                    objectName: 'codec-tool-mode-' + modelData.id
                    text: modelData.label; checkable: true; checked: root.mode === modelData.id
                    onPressed: root.mode = modelData.id
                }
            }
        }
        Flow {
            width: parent.width; spacing: 8
            PentadButton { objectName: 'codec-tool-encode'; text: 'Encode'; requestedEnabled: root.mode !== 'jwt'; onPressed: root.run(false) }
            PentadButton { objectName: 'codec-tool-decode'; text: 'Decode'; onPressed: root.run(true) }
            PentadButton { objectName: 'codec-tool-auto'; text: 'Auto'; onPressed: root.runAuto() }
            PentadButton { objectName: 'codec-tool-copy'; text: 'Copy'; requestedEnabled: !!root.result; onPressed: { output.selectAll(); output.copy(); output.deselect(); } }
            PentadButton { objectName: 'codec-tool-handoff'; text: 'Hand off'; requestedEnabled: !!root.result && root.resultTargets.length > 0; onPressed: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        TextArea {
            id: output; objectName: 'codec-tool-output'
            width: parent.width; height: 126; visible: !!root.result
            readOnly: true; selectByMouse: true; text: root.result; wrapMode: TextEdit.Wrap
            color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            background: Rectangle { color: Theme.tokens.surface; radius: Metrics.radiusSmall }
        }
        PentadText { objectName: 'codec-tool-message'; visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap; width: parent.width }
    }
}
