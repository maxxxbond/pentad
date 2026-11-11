pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../logic/plugin-manifest.mjs' as Rules

Column {
    id: form
    required property var manifest
    required property var settings
    property string error: ''
    signal settingsEdited(var validatedSettings)
    readonly property var validatedSettings: Rules.validateSettings(manifest, settings)
    spacing: 8
    function change(key, value) {
        var next = Object.assign({}, settings, { [key]: value });
        var result = Rules.validateSettings(manifest, next);
        if (result.ok) { error = ''; settingsEdited(result.settings); }
        else error = result.errors.join('; ');
        return result.ok;
    }
    Repeater {
        model: form.manifest.settingsFields || []
        delegate: Column {
            id: fieldRow
            required property var modelData
            width: form.width
            spacing: 4
            readonly property string label: modelData.label || modelData.labelKey || modelData.key
            readonly property var value: {
                var validated = form.validatedSettings;
                return validated.ok ? validated.settings[modelData.key] : form.settings[modelData.key];
            }
            PentadText { text: fieldRow.label; role: 'caption' }
            PentadToggle {
                visible: fieldRow.modelData.kind === 'boolean'
                accessibleName: fieldRow.label
                checked: fieldRow.value === true
                onToggled: form.change(fieldRow.modelData.key, checked)
            }
            PentadButton {
                visible: fieldRow.modelData.kind === 'select'
                accessibleName: fieldRow.label
                text: { var options = fieldRow.modelData.options || [];
                    var option = options.find(function(item) { return item.value === fieldRow.value; });
                    return option ? option.label : 'Select'; }
                onClicked: {
                    var options = fieldRow.modelData.options;
                    var index = options.findIndex(function(item) { return item.value === fieldRow.value; });
                    form.change(fieldRow.modelData.key, options[(index + 1) % options.length].value);
                }
            }
            PentadTextField {
                visible: !['boolean', 'select'].includes(fieldRow.modelData.kind)
                width: parent.width
                accessibleName: fieldRow.label
                text: fieldRow.value === undefined ? '' : String(fieldRow.value)
                onEditingFinished: {
                    var numeric = ['integer', 'number'].includes(fieldRow.modelData.kind);
                    var value = numeric && text.trim() ? Number(text) : text;
                    error = !form.change(fieldRow.modelData.key, value);
                }
            }
        }
    }
    PentadText { text: form.error; visible: text !== ''; color: Theme.tokens.error }
}
