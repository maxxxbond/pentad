import QtQuick
import QtQml
import qs.components
import qs.plugins
import qs.theme

Column {
    id: root
    required property var services
    property string pendingId: ''
    property string error: ''
    readonly property alias themeEditor: themeForm
    readonly property alias barEditor: barForm
    spacing: 12
    readonly property var themeFields: ({ defaults: {}, settingsFields: [
        { key: 'appearance', label: 'Appearance', kind: 'select', options: [
            { value: 'dark', label: 'Dark' }, { value: 'light', label: 'Light' }
        ] },
        { key: 'accent', label: 'Accent color', kind: 'color' },
        { key: 'fontFamily', label: 'Font family', kind: 'text' },
        { key: 'reducedMotion', label: 'Reduce motion', kind: 'boolean' }
    ] })
    readonly property var barFields: ({ defaults: {}, settingsFields: [
        { key: 'showActiveTitle', label: 'Active window title', kind: 'boolean' },
        { key: 'showWorkspaces', label: 'Workspaces', kind: 'boolean' },
        { key: 'showSeconds', label: 'Clock seconds', kind: 'boolean' },
        { key: 'clockLayout', label: 'Clock', kind: 'select', options: [
            { value: 'stacked', label: 'Two lines' }, { value: 'inline', label: 'One line' }
        ] },
        { key: 'trayIcons', label: 'Tray icons', kind: 'select', options: [
            { value: 'soft', label: 'Soft' }, { value: 'color', label: 'Color' },
            { value: 'monochrome', label: 'Monochrome' }
        ] }
    ] })
    function save(name, value) {
        if (pendingId) return;
        error = '';
        pendingId = services.config.save(name, Object.assign({}, services.config.documents[name], value));
    }
    function fieldsFor(name, manifest) {
        const document = services.config.documents[name];
        const fields = {};
        manifest.settingsFields.forEach(function(field) { fields[field.key] = document[field.key]; });
        return fields;
    }
    Connections {
        target: root.services.config
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingId) return;
            root.pendingId = '';
            root.error = result.ok ? '' : result.message || result.reason;
        }
    }
    PentadText { text: 'Appearance'; role: 'section' }
    SettingsForm {
        id: themeForm
        width: parent.width
        enabled: !root.pendingId
        manifest: root.themeFields
        settings: root.fieldsFor('theme', root.themeFields)
        onSettingsEdited: function(value) { root.save('theme', value) }
    }
    PentadText { text: 'Bar'; role: 'section' }
    SettingsForm {
        id: barForm
        width: parent.width
        enabled: !root.pendingId
        manifest: root.barFields
        settings: root.fieldsFor('layout', root.barFields)
        onSettingsEdited: function(value) { root.save('layout', value) }
    }
    PentadText { text: root.error; visible: text !== ''; color: Theme.tokens.error }
}
