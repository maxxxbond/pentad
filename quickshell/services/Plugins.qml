pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQml.Models
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import '../logic/plugin-manifest.mjs' as Rules

QtObject {
    id: registry
    property bool safeMode: false
    property var services: null
    property string pluginsRoot: (Quickshell.env('XDG_CONFIG_HOME') || Quickshell.env('HOME') + '/.config') + '/pentad/plugins'
    property var catalog: ({})
    property var errors: ({})
    property var controllers: ({})
    property int revision: 0
    property var builtinEntries: []
    signal changed()
    signal pluginLoadFailed(string id, string message)
    function registerManifest(manifest, baseUrl, builtin) {
        var result = Rules.validateManifest(manifest);
        if (!result.ok) return result;
        if (safeMode && !builtin) return { ok: false, errors: ['Safe mode excludes external plugins'] };
        var existing = catalog[manifest.id];
        if (existing && existing.builtin && !builtin) return { ok: false, errors: ['External plugin cannot replace a built-in ID'] };
        if (existing && existing.manifest.controller !== manifest.controller)
            return { ok: false, errors: ['Controller entry changed; restart required'] };
        catalog = Object.assign({}, catalog, { [manifest.id]: { manifest: manifest, baseUrl: baseUrl, builtin: builtin } });
        revision++;
        changeNotice.restart();
        return { ok: true };
    }
    // Manifests load one file at a time; changed() fires once after a burst of them, so the
    // placements are reconciled once at startup instead of once per manifest.
    property Timer changeNotice: Timer {
        interval: 50
        onTriggered: registry.changed()
    }
    function loadText(text, baseUrl, builtin) {
        try {
            var manifest = JSON.parse(text);
            var result = registerManifest(manifest, baseUrl, builtin);
            if (!result.ok) throw new Error(result.errors.join('; '));
            if (Object.prototype.hasOwnProperty.call(errors, baseUrl)) {
                const remaining = Object.assign({}, errors);
                delete remaining[baseUrl];
                errors = remaining;
            }
        } catch (error) {
            errors = Object.assign({}, errors, { [baseUrl]: error.message });
            pluginLoadFailed(baseUrl, error.message);
        }
    }
    function entryFor(id, slot) {
        var entry = catalog[id];
        if (!entry) return null;
        if (!Rules.validateManifest(entry.manifest, { slot: slot }).ok) return null;
        return entry;
    }
    function reconcile(placements) {
        var retained = {};
        placements.forEach(function(placement) {
            if (!placement.enabled) return;
            var entry = entryFor(placement.moduleId, placement.slot);
            if (!entry || !entry.manifest.controller) return;
            var result = Rules.validateSettings(entry.manifest, placement.settings);
            if (!result.ok) return;
            var controller = controllers[placement.instanceId];
            if (controller && controller.moduleId !== placement.moduleId) { controller.destroy(); controller = null; }
            if (!controller) {
                var component = Qt.createComponent('../plugins/PlacementController.qml');
                if (component.status !== Component.Ready) return;
                controller = component.createObject(registry, { instanceId: placement.instanceId, moduleId: placement.moduleId,
                    settings: result.settings, services: services, entry: entry });
            } else controller.settings = result.settings;
            retained[placement.instanceId] = controller;
        });
        Object.keys(controllers).forEach(function(id) { if (!retained[id]) controllers[id].destroy(); });
        controllers = retained;
    }
    property FileView bundled: FileView {
        path: Qt.resolvedUrl('../builtin-registry.json')
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { registry.builtinEntries = JSON.parse(text()); }
            catch (error) { registry.pluginLoadFailed('builtins', error.message); }
        }
    }
    property Variants builtinReaders: Variants {
        model: registry.builtinEntries
        delegate: Component {
            FileView {
                required property var modelData
                path: Qt.resolvedUrl('../' + modelData.path)
                watchChanges: true
                onFileChanged: reload()
                onLoaded: registry.loadText(text(), Qt.resolvedUrl('../' + modelData.path.replace(/[^/]+$/, '')), true)
            }
        }
    }
    property FolderListModel externalFolders: FolderListModel {
        folder: registry.safeMode ? '' : 'file://' + registry.pluginsRoot
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        showHidden: false
    }
    property Instantiator externalReaders: Instantiator {
        model: registry.safeMode ? null : registry.externalFolders
        delegate: FileView {
            required property url fileUrl
            path: fileUrl + '/manifest.json'
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: registry.loadText(text(), fileUrl + '/', false)
        }
    }
}
