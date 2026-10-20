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
    property string message: ''
    property string result: ''
    property string resultMessage: ''
    readonly property var unitList: category.currentText === 'mass' ? ['kg','g','mg','lb','oz']
        : category.currentText === 'time' ? ['s','min','h','day']
            : category.currentText === 'temperature' ? ['C','F','K'] : ['km','m','cm','mm','mi','ft']
    readonly property var resultItem: ({ kind: 'text', mimeType: 'text/plain', value: root.result, compatibleTypes: ['text/plain'] })
    readonly property var resultTargets: Tools.compatibleTools(Tools.toolEntries(root.services.plugins.catalog), [root.resultItem]).map(entry => entry.manifest.id)
    implicitWidth: 330
    implicitHeight: content.implicitHeight
    function acceptInput(items, choice) {
        if ((choice !== 'replace' && !(choice === '' && !amount.text)) || !Array.isArray(items) || items.length !== 1 || typeof items[0].value !== 'string') return false;
        if (Tools.utf8Length(items[0].value) > 4096) { message = 'Input is limited to 4 KiB.'; return false; }
        amount.text = items[0].value;
        return true;
    }
    Column {
        id: content
        width: root.width
        spacing: 8
        PentadTextField { id: amount; width: parent.width; placeholderText: 'Value'; text: root.services.toolWorkspace.draftFor('pentad.units'); onTextChanged: root.services.toolWorkspace.setDraft('pentad.units', text) }
        PentadComboBox { id: category; width: parent.width; model: ['length','mass','time','temperature'] }
        Row {
            width: parent.width; spacing: 8
            PentadComboBox { id: from; width: (parent.width - 8) / 2; model: root.unitList }
            PentadComboBox { id: to; width: (parent.width - 8) / 2; model: root.unitList; currentIndex: Math.min(1, count - 1) }
        }
        Row {
            spacing: 6
            PentadButton { text: 'Convert'; onPressed: { if (Tools.utf8Length(amount.text) > 4096) { root.message = 'Input is limited to 4 KiB.'; return; } var r = Tools.convertUnit(amount.text, from.currentText, to.currentText, category.currentText); root.result = r.ok ? String(r.value) + ' ' + to.currentText : ''; root.message = r.ok ? '' : r.reason; } }
        }
        Row {
            spacing: 6
            TextArea { id: output; visible: !!root.result; readOnly: true; selectByMouse: true; text: root.result; width: 190; height: 42 }
            PentadButton { text: 'Copy'; visible: !!root.result; onPressed: { output.selectAll(); output.copy(); output.deselect(); } }
            PentadButton { text: 'Hand off'; visible: !!root.result && root.resultTargets.length > 0; onPressed: root.services.toolWorkspace.receive([root.resultItem], root.resultTargets, '') }
        }
        PentadText { visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error }
    }
}
