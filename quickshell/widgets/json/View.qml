import QtQuick
import QtQuick.Controls.Basic
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
    property string message: ''
    property bool canAppendInput: true
    readonly property var resultItem: ({ kind: 'json', mimeType: 'application/json', value: root.result, compatibleTypes: ['application/json','text/plain'] })
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
    Column {
        id: content
        width: root.width; spacing: 8
        TextArea {
            id: source; objectName: 'json-tool-source'; width: parent.width; height: 112; wrapMode: TextEdit.Wrap
            placeholderText: 'Paste or drop JSON'; text: root.services.toolWorkspace.draftFor('pentad.json')
            color: Theme.tokens.text; placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            onTextChanged: root.services.toolWorkspace.setDraft('pentad.json', text)
            background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
        }
        Row {
            spacing: 6
            PentadButton { text: 'Format and validate'; onPressed: { if (Tools.utf8Length(source.text) > 262144) { root.message = 'Input is limited to 256 KiB.'; return; } var r = Tools.formatJson(source.text); root.result = r.ok ? r.value : ''; root.message = r.ok ? '' : r.reason; } }
            PentadButton { text: 'Copy'; requestedEnabled: !!root.result; onPressed: { output.selectAll(); output.copy(); output.deselect(); } }
            PentadButton { text: 'Use in another tool'; requestedEnabled: !!root.result && root.resultTargets.length > 0; onPressed: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        TextArea {
            id: output
            width: parent.width; height: 126; visible: !!root.result
            readOnly: true; selectByMouse: true; text: root.result; wrapMode: TextEdit.Wrap
            color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            background: Rectangle { color: Theme.tokens.surface; radius: Metrics.radiusSmall }
        }
        PentadText { visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap }
    }
}
