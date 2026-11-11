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
    readonly property var resultItem: ({ kind: 'text', mimeType: 'text/plain', value: root.result, compatibleTypes: ['text/plain'] })
    readonly property var resultTargets: Tools.compatibleTools(Tools.toolEntries(root.services.plugins.catalog), [root.resultItem]).map(entry => entry.manifest.id)
    implicitWidth: 330
    implicitHeight: content.implicitHeight
    function acceptInput(items, choice) {
        const merged = Tools.mergeTextInput(source.text, items, choice, 65536);
        if (!merged.ok) {
            if (merged.reason === 'too-large') root.message = root.services.text('Загальний обсяг введення обмежено до 64 КіБ.', 'Combined input is limited to 64 KiB.');
            return false;
        }
        source.text = merged.value;
        root.message = '';
        return true;
    }
    Column {
        id: content
        width: root.width; spacing: 8
        TextArea {
            id: source
            objectName: 'text-cleaner-source'
            width: parent.width; height: 104; wrapMode: TextEdit.Wrap
            placeholderText: 'Paste or drop text'; text: root.services.toolWorkspace.draftFor('pentad.text-cleaner')
            color: Theme.tokens.text; placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            onTextChanged: root.services.toolWorkspace.setDraft('pentad.text-cleaner', text)
            background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
        }
        Row {
            spacing: 6
            PentadButton { text: 'Clean'; onPressed: { if (Tools.utf8Length(source.text) > 65536) { root.message = 'Input is limited to 64 KiB.'; return; } root.result = Tools.cleanText(source.text); root.message = ''; } }
            PentadButton { text: 'Replace input'; requestedEnabled: !!root.result; onPressed: source.text = root.result }
            PentadButton { text: 'Copy'; requestedEnabled: !!root.result; onPressed: { output.selectAll(); output.copy(); output.deselect(); } }
            PentadButton { text: 'Use in another tool'; requestedEnabled: !!root.result && root.resultTargets.length > 0; onPressed: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        TextArea {
            id: output
            width: parent.width; height: Math.min(96, Math.max(42, implicitHeight)); visible: !!root.result
            readOnly: true; selectByMouse: true; text: root.result; wrapMode: TextEdit.Wrap
            color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            background: Rectangle { color: Theme.tokens.surface; radius: Metrics.radiusSmall }
        }
        PentadText { visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error }
    }
}
