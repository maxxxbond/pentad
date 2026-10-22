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
    property var rows: []
    property string message: ''
    property bool canAppendInput: false
    implicitWidth: 330
    implicitHeight: content.implicitHeight
    function acceptInput(items, choice) {
        if (!Array.isArray(items) || items.some(item => typeof item.value !== 'string')) return false;
        if (source.text && !choice) return false;
        const next = items.map(item => item.value).join(' ').trim();
        if (Tools.utf8Length(next) > 4096) { message = 'Input is limited to 4 KiB.'; return false; }
        source.text = next;
        return true;
    }
    function convert() {
        const value = source.text.trim();
        if (!value) { rows = []; message = ''; return; }
        const r = TextTools.convertTimestamp(value, Date.now());
        rows = r.ok ? r.value : [];
        message = r.ok ? '' : r.reason;
    }
    function copyRow(text) { clipboard.text = text; clipboard.selectAll(); clipboard.copy(); clipboard.deselect(); }
    TextInput { id: clipboard; visible: false; readOnly: true }
    Column {
        id: content
        width: root.width; spacing: 8
        PentadTextField {
            id: source; objectName: 'timestamp-tool-source'; width: parent.width
            placeholderText: 'Unix time, ISO 8601 or RFC 2822'
            text: root.services.toolWorkspace.draftFor('pentad.timestamp')
            error: !!root.message
            onTextChanged: { root.services.toolWorkspace.setDraft('pentad.timestamp', text); root.convert(); }
            Component.onCompleted: root.convert()
        }
        PentadButton {
            objectName: 'timestamp-tool-now'; text: 'Now'; visible: !source.text.trim()
            onPressed: source.text = String(Math.floor(Date.now() / 1000))
        }
        Repeater {
            model: root.rows
            Item {
                required property var modelData
                objectName: 'timestamp-tool-row-' + modelData.id
                width: content.width; height: 32
                PentadText { id: rowLabel; text: modelData.label; role: 'caption'; color: Theme.tokens.textMuted; width: 88; anchors.verticalCenter: parent.verticalCenter }
                PentadText {
                    text: modelData.value; wrapMode: Text.NoWrap; elide: Text.ElideRight; color: Theme.tokens.text
                    anchors { left: rowLabel.right; right: copyButton.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                }
                PentadButton {
                    id: copyButton; objectName: 'timestamp-tool-copy-' + modelData.id
                    text: 'Copy'; controlHeight: 28
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    onPressed: root.copyRow(modelData.value)
                }
            }
        }
        PentadText { objectName: 'timestamp-tool-message'; visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap; width: parent.width }
    }
}
