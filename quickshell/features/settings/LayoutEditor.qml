pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import qs.components
import qs.theme
import qs.plugins

Column {
    id: editor
    required property var services
    readonly property var layout: services.config.documents.layout
    property string pendingId: ''
    property string error: ''
    spacing: 8

    function save(widgets) {
        if (pendingId) return;
        error = '';
        pendingId = services.config.save('layout', Object.assign({}, layout, { widgets: widgets }));
    }
    function edit(instanceId, patch) {
        save(layout.widgets.map(function(widget) {
            return widget.instanceId === instanceId ? Object.assign({}, widget, patch) : widget;
        }));
    }
    function move(instanceId, offset) {
        var widgets = layout.widgets.slice();
        var index = widgets.findIndex(function(widget) { return widget.instanceId === instanceId; });
        var destination = index + offset;
        if (index < 0 || destination < 0 || destination >= widgets.length) return;
        var widget = widgets.splice(index, 1)[0];
        widgets.splice(destination, 0, widget);
        save(widgets);
    }
    Connections {
        target: editor.services.config
        function onCommandFinished(requestId, result) {
            if (requestId !== editor.pendingId) return;
            editor.pendingId = '';
            if (!result.ok) editor.error = result.message || result.reason;
        }
    }
    Repeater {
        model: editor.layout.widgets
        delegate: Column {
            id: placement
            required property var modelData
            property bool editingSettings: false
            readonly property var entry: editor.services.plugins.catalog[modelData.moduleId] || null
            width: editor.width
            spacing: 4
            PentadText { text: placement.modelData.moduleId + ' · ' + placement.modelData.instanceId }
            Row {
                spacing: 8
                PentadToggle {
                    accessibleName: placement.modelData.moduleId
                    checked: placement.modelData.enabled
                    enabled: !editor.pendingId
                    onToggled: editor.edit(placement.modelData.instanceId, { enabled: checked })
                }
                PentadButton {
                    text: placement.modelData.slot
                    accessibleName: 'Widget slot'
                    requestedEnabled: !editor.pendingId
                    onClicked: {
                        var entry = editor.services.plugins.catalog[placement.modelData.moduleId];
                        var slots = entry ? entry.manifest.allowedSlots
                            : ['navigation', 'telemetry', 'center', 'tools', 'system', 'sidebar-left', 'sidebar-right'];
                        var index = slots.indexOf(placement.modelData.slot);
                        editor.edit(placement.modelData.instanceId, { slot: slots[(index + 1) % slots.length] });
                    }
                }
                PentadButton {
                    text: '↑'; accessibleName: 'Move widget earlier'
                    requestedEnabled: !editor.pendingId
                    onClicked: editor.move(placement.modelData.instanceId, -1)
                }
                PentadButton {
                    text: '↓'; accessibleName: 'Move widget later'
                    requestedEnabled: !editor.pendingId
                    onClicked: editor.move(placement.modelData.instanceId, 1)
                }
                PentadButton {
                    text: 'Settings'
                    visible: !!placement.entry && (placement.entry.manifest.settingsFields || []).length > 0
                    requestedEnabled: !editor.pendingId
                    onClicked: placement.editingSettings = !placement.editingSettings
                }
            }
            Loader {
                width: parent.width
                active: placement.editingSettings && !!placement.entry
                sourceComponent: Component {
                    SettingsForm {
                        width: placement.width
                        enabled: !editor.pendingId
                        manifest: placement.entry.manifest
                        settings: placement.modelData.settings
                        onSettingsEdited: function(value) { editor.edit(placement.modelData.instanceId, { settings: value }); }
                    }
                }
            }
        }
    }
    PentadText { text: editor.error; color: Theme.tokens.error; visible: text !== '' }
}
