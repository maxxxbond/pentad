import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import '../logic/config.mjs' as Rules

QtObject {
    id: store
    property bool preview: false
    property string configRoot: (Quickshell.env('XDG_CONFIG_HOME') || Quickshell.env('HOME') + '/.config') + '/pentad'
    property string stateRoot: (Quickshell.env('XDG_STATE_HOME') || Quickshell.env('HOME') + '/.local/state') + '/pentad'
    property string helperPath: decodeURIComponent(Qt.resolvedUrl('../helpers/pentad-files.py').toString().replace(/^file:\/\//, ''))
    property var documents: ({ theme: Rules.defaults.theme, layout: Rules.defaults.layout,
        interface: Rules.defaults.interface, spotlight: Rules.defaults.spotlight, organizer: Rules.defaults.organizer,
        notifications: Rules.defaults.notifications, screenshots: Rules.defaults.screenshots,
        wallpaper: Rules.defaults.wallpaper, models: Rules.defaults.models })
    property var revisions: ({})
    property var generations: ({})
    property var documentStates: ({ organizer: { kind: "loading" }, notifications: { kind: "loading" } })
    property int serial: 0
    property string lastError: ''
    readonly property var names: ['theme', 'layout', 'interface', 'session', 'spotlight', 'plugin-state', 'screenshots', 'wallpaper', 'models', 'notifications', 'shelf', 'activity', 'organizer']
    signal documentChanged(string name)
    signal commandFinished(string requestId, var result)
    function request(payload) {
        var requestId = 'file-' + (++serial);
        if (preview) {
            Qt.callLater(function() { store.commandFinished(requestId, { ok: false, reason: 'denied', message: 'Preview does not write user data' }); });
            return requestId;
        }
        var generation = (generations[payload.name] || 0) + 1;
        generations = Object.assign({}, generations, { [payload.name]: generation });
        if (payload.operation === 'read')
            documentStates = Object.assign({}, documentStates, { [payload.name]: { kind: 'loading' } });
        var component = Qt.createComponent('FileRequest.qml');
        if (component.status !== Component.Ready) {
            lastError = component.errorString();
            if (payload.operation === 'read')
                documentStates = Object.assign({}, documentStates, { [payload.name]: { kind: 'error', reason: 'io' } });
            Qt.callLater(function() { store.commandFinished(requestId, { ok: false, reason: 'io', message: store.lastError }); });
            return requestId;
        }
        var worker = component.createObject(store, { helperPath: helperPath, configRoot: configRoot, stateRoot: stateRoot, payload: payload });
        if (!worker) {
            if (payload.operation === 'read')
                documentStates = Object.assign({}, documentStates, { [payload.name]: { kind: 'error', reason: 'io' } });
            Qt.callLater(function() { store.commandFinished(requestId, { ok: false, reason: 'io', message: 'Cannot create file helper request' }); });
            return requestId;
        }
        worker.finished.connect(function(result) {
            if (generations[payload.name] !== generation) {
                if (result.ok && payload.operation !== 'read' && payload.operation !== 'checkpoint')
                    store.reload(payload.name);
                commandFinished(requestId, payload.operation === 'read'
                    ? { ok: false, reason: 'conflict', message: 'Superseded read' }
                    : result);
                return;
            }
            if (result.ok) {
                if (payload.operation === 'read')
                    revisions = Object.assign({}, revisions, { [payload.name]: result.revision || null });
                var text = payload.operation === 'write' ? payload.text : result.text;
                if (text !== undefined) {
                    var parsed = Rules.parseDocument(payload.name, text);
                    if (parsed.ok) {
                        documents = Object.assign({}, documents, { [payload.name]: parsed.value });
                        revisions = Object.assign({}, revisions, { [payload.name]: result.revision });
                        documentChanged(payload.name);
                    } else result = parsed;
                }
                if (payload.operation === 'read' && result.ok) {
                    documentStates = Object.assign({}, documentStates, { [payload.name]: { kind: 'ready' } });
                } else if (payload.operation === 'read') {
                    documentStates = Object.assign({}, documentStates, { [payload.name]: { kind: 'invalid', reason: result.reason || 'invalid' } });
                } else if (result.ok) {
                    documentStates = Object.assign({}, documentStates, { [payload.name]: { kind: 'ready' } });
                }
            }
            if (!result.ok && payload.operation === 'read')
                documentStates = Object.assign({}, documentStates, { [payload.name]: {
                    kind: result.reason === 'invalid' ? 'invalid' : 'error', reason: result.reason || 'io'
                } });
            if (!result.ok) lastError = result.message || result.reason;
            commandFinished(requestId, result);
        });
        worker.running = true;
        return requestId;
    }
    function reload(name) { return request({ operation: 'read', name: name }); }
    function checkpoint(name) { return request({ operation: 'checkpoint', name: name }); }
    function restore(name, checkpointId) {
        return request({ operation: 'restore', name: name, checkpointId: checkpointId,
            expectedRevision: revisions[name] || null });
    }
    function save(name, value) {
        var parsed = Rules.parseDocument(name, JSON.stringify(value));
        if (!parsed.ok) {
            var id = 'file-' + (++serial);
            Qt.callLater(function() { store.commandFinished(id, parsed); });
            return id;
        }
        return request({ operation: 'write', name: name, text: JSON.stringify(parsed.value), expectedRevision: revisions[name] || null });
    }
    property Variants watches: Variants {
        model: store.preview ? [] : store.names
        delegate: Component {
            FileView {
                required property var modelData
                path: (['notifications', 'shelf', 'activity', 'organizer'].includes(modelData) ? store.stateRoot : store.configRoot) + '/' + modelData + '.json'
                watchChanges: true
                printErrors: false
                onFileChanged: store.reload(modelData)
                onLoaded: store.reload(modelData)
            }
        }
    }
    Component.onCompleted: { if (!preview) names.forEach(function(name) { store.reload(name); }); }
}
