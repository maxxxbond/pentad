import QtQuick
import Quickshell
import qs.services
import qs.features.settings

ShellRoot {
    id: root
    property Config store: Config { preview: false }
    property int phase: 0
    property string pendingId: ''
    property string checkpointId: ''
    property var checks: []
    property int settleTicks: 0
    property LayoutEditor layoutEditor: LayoutEditor {
        services: ({ config: root.store, plugins: { catalog: {} } })
    }
    property AppearanceSettings appearance: AppearanceSettings {
        services: ({ config: root.store })
    }

    function record(name, passed, detail) {
        checks.push({ name: name, passed: passed, detail: detail || '' });
    }

    function finish() {
        var passed = checks.length === 11 && checks.every(function(check) { return check.passed; });
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }

    Connections {
        target: root.store
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingId) return;
            if (root.phase === 1) {
                root.record('initial-read', result.ok && result.revision === null,
                    result.reason || 'Expected an absent document in the disposable config root');
                root.phase = 2;
                root.pendingId = root.store.save('theme', { schemaVersion: 1, accent: '#123456' });
            } else if (root.phase === 2) {
                root.record('save', result.ok, result.reason || '');
                if (!result.ok) { root.finish(); return; }
                root.phase = 3;
                root.pendingId = root.store.checkpoint('theme');
            } else if (root.phase === 3) {
                root.checkpointId = result.checkpointId || '';
                root.record('checkpoint', result.ok && !!root.checkpointId, result.reason || '');
                if (!result.ok) { root.finish(); return; }
                root.phase = 4;
                root.pendingId = root.store.save('theme', { schemaVersion: 1, accent: '#654321' });
            } else if (root.phase === 4) {
                root.record('update-before-restore', result.ok, result.reason || '');
                if (!result.ok) { root.finish(); return; }
                root.phase = 5;
                root.pendingId = root.store.request({
                    operation: 'write', name: 'theme', text: '{}', expectedRevision: 'stale-revision'
                });
            } else if (root.phase === 5) {
                root.record('stale-write-conflict', !result.ok && result.reason === 'conflict', result.reason || '');
                root.phase = 6;
                root.pendingId = root.store.restore('theme', root.checkpointId);
            } else if (root.phase === 6) {
                var recovered = false;
                try {
                    var restored = JSON.parse(result.text);
                    recovered = result.ok && restored.accent === '#123456'
                        && root.store.documents.theme.accent === '#123456';
                } catch (error) {}
                root.record('recovery-read', recovered, recovered ? '' : (result.reason || 'Recovered value did not match checkpoint'));
                root.phase = 7;
                root.layoutEditor.move('clock-main', -1);
                root.pendingId = root.layoutEditor.pendingId;
            } else if (root.phase === 7) {
                root.record('layout-save', result.ok, result.reason || '');
                root.phase = 8;
                root.settleTicks = 0;
            } else if (root.phase === 9) {
                root.record('appearance-form-persists-confirmed-theme', result.ok
                    && root.store.documents.theme.accent === '#234567'
                    && root.store.documents.theme.fontFamily === 'Geist');
                root.phase = 10;
                Qt.callLater(function() {
                    root.appearance.barEditor.change('showSeconds', true);
                    root.pendingId = root.appearance.pendingId;
                });
            } else if (root.phase === 10) {
                root.record('bar-form-preserves-widget-settings', result.ok
                    && root.store.documents.layout.showSeconds === true
                    && root.store.documents.layout.widgets.length === 10
                    && root.store.documents.layout.widgets.find(function(widget) { return widget.instanceId === 'weather-main' }).settings.units === 'celsius');
                root.finish();
            }
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (root.phase === 8) {
                root.settleTicks++;
                if (root.settleTicks < 8) return;
                var widgets = root.store.documents.layout.widgets;
                var weather = widgets.find(function(widget) { return widget.instanceId === 'weather-main'; });
                root.record('layout-reorder-preserves-ids-and-settings', widgets.length === 10
                    && widgets[2].instanceId === 'clock-main' && widgets[3].instanceId === 'chat-main'
                    && weather.settings.units === 'celsius' && weather.settings.city === '');
                root.record('appearance-form-rejects-invalid-color', !root.appearance.themeEditor.change('accent', 'invalid-color')
                    && !root.appearance.pendingId && root.store.documents.theme.accent === '#123456');
                root.phase = 9;
                root.appearance.themeEditor.change('accent', '#234567');
                root.pendingId = root.appearance.pendingId;
                return;
            }
            if (root.phase !== 0) return;
            root.settleTicks++;
            if (root.settleTicks < 8) return;
            root.phase = 1;
            root.pendingId = root.store.reload('theme');
        }
    }
}
