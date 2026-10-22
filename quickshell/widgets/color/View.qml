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
    property var formats: null
    property string message: ''
    property bool canAppendInput: false
    readonly property var formatRows: [
        { id: 'hex', label: 'Hex' }, { id: 'rgb', label: 'RGB' }, { id: 'hsl', label: 'HSL' }, { id: 'oklch', label: 'OKLCH' }
    ]
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
        if (!value) { formats = null; message = ''; return; }
        const r = TextTools.convertColor(value);
        formats = r.ok ? r.value : null;
        message = r.ok ? '' : r.reason;
    }
    function copyRow(text) { clipboard.text = text; clipboard.selectAll(); clipboard.copy(); clipboard.deselect(); }
    TextInput { id: clipboard; visible: false; readOnly: true }
    Column {
        id: content
        width: root.width; spacing: 8
        PentadTextField {
            id: source; objectName: 'color-tool-source'; width: parent.width
            placeholderText: '#12abef, rgb(), hsl() or oklch()'
            text: root.services.toolWorkspace.draftFor('pentad.color')
            error: !!root.message
            onTextChanged: { root.services.toolWorkspace.setDraft('pentad.color', text); root.convert(); }
            Component.onCompleted: root.convert()
        }
        Rectangle {
            objectName: 'color-tool-swatch'
            visible: root.formats !== null
            width: parent.width; height: 48; radius: Metrics.radiusSmall
            color: root.formats ? root.formats.css : 'transparent'
        }
        Repeater {
            model: root.formats ? root.formatRows : []
            Item {
                required property var modelData
                objectName: 'color-tool-row-' + modelData.id
                width: content.width; height: 32
                PentadText { id: rowLabel; text: modelData.label; role: 'caption'; color: Theme.tokens.textMuted; width: 52; anchors.verticalCenter: parent.verticalCenter }
                PentadText {
                    text: root.formats[modelData.id]; wrapMode: Text.NoWrap; elide: Text.ElideRight; color: Theme.tokens.text
                    anchors { left: rowLabel.right; right: copyButton.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                }
                PentadButton {
                    id: copyButton; objectName: 'color-tool-copy-' + modelData.id
                    text: 'Copy'; controlHeight: 28
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    onPressed: root.copyRow(root.formats[modelData.id])
                }
            }
        }
        PentadText { objectName: 'color-tool-message'; visible: !!root.message; text: root.message; role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap; width: parent.width }
    }
}
