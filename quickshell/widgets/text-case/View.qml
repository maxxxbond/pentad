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
    property string mode: ''
    property string result: ''
    property string message: ''
    property bool canAppendInput: true
    readonly property var modes: [
        { id: 'lower', label: 'lower' }, { id: 'upper', label: 'UPPER' }, { id: 'title', label: 'Title Case' },
        { id: 'sentence', label: 'Sentence case' }, { id: 'camel', label: 'camelCase' }, { id: 'pascal', label: 'PascalCase' },
        { id: 'snake', label: 'snake_case' }, { id: 'kebab', label: 'kebab-case' }, { id: 'constant', label: 'CONSTANT_CASE' },
        { id: 'slug', label: 'slug' }
    ]
    readonly property var stats: TextTools.textStats(source.text)
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
    function convert(id) {
        if (Tools.utf8Length(source.text) > 262144) { message = 'Input is limited to 256 KiB.'; return; }
        mode = id;
        const r = TextTools.convertCase(id, source.text);
        result = r.ok ? r.value : '';
        message = r.ok ? '' : r.reason;
    }
    Column {
        id: content
        width: root.width; spacing: 8
        TextArea {
            id: source; objectName: 'text-case-tool-source'; width: parent.width; height: 96; wrapMode: TextEdit.Wrap
            placeholderText: 'Text to convert'; text: root.services.toolWorkspace.draftFor('pentad.text-case')
            color: Theme.tokens.text; placeholderTextColor: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            onTextChanged: { root.services.toolWorkspace.setDraft('pentad.text-case', text); if (root.mode) root.convert(root.mode); }
            background: Rectangle { color: Theme.tokens.surfaceRaised; radius: Metrics.radiusSmall }
        }
        PentadText {
            objectName: 'text-case-tool-stats'
            width: parent.width; role: 'caption'; color: Theme.tokens.textMuted
            function count(value, noun) { return value + ' ' + noun + (value === 1 ? '' : 's'); }
            text: count(root.stats.characters, 'character') + ' · ' + count(root.stats.words, 'word') + ' · '
                + count(root.stats.lines, 'line') + ' · ' + count(root.stats.bytes, 'byte')
        }
        Flow {
            width: parent.width; spacing: 8
            Repeater {
                model: root.modes
                PentadButton {
                    required property var modelData
                    objectName: 'text-case-tool-mode-' + modelData.id
                    text: modelData.label; checkable: true; checked: root.mode === modelData.id
                    onPressed: root.convert(modelData.id)
                }
            }
        }
        Flow {
            width: parent.width; spacing: 8
            PentadButton { objectName: 'text-case-tool-copy'; text: 'Copy'; requestedEnabled: !!root.result; onPressed: { output.selectAll(); output.copy(); output.deselect(); } }
            PentadButton { objectName: 'text-case-tool-handoff'; text: 'Hand off'; requestedEnabled: !!root.result && root.resultTargets.length > 0; onPressed: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        TextArea {
            id: output; objectName: 'text-case-tool-output'
            width: parent.width; height: 96; visible: !!root.result
            readOnly: true; selectByMouse: true; text: root.result; wrapMode: TextEdit.Wrap
            color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.textBody
            background: Rectangle { color: Theme.tokens.surface; radius: Metrics.radiusSmall }
        }
        PentadText { objectName: 'text-case-tool-message'; visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap; width: parent.width }
    }
}
