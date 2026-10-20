import QtQuick
import Quickshell
import "../services"
import '../logic/organizer.mjs' as OrganizerLogic

ShellRoot {
    id: root
    property Services services: Services { preview: true; safeMode: true }
    property int phase: 0
    property var checks: []
    property var stableDocument: null
    property QtObject fakeConfig: QtObject {
        property bool preview: false
        property bool failWrites: true
        property int serial: 0
        property int revision: 0
        property var documents: ({ organizer: OrganizerLogic.DEFAULT_ORGANIZER })
        property var revisions: ({ organizer: null })
        property var documentStates: ({ organizer: { kind: 'ready' } })
        signal documentChanged(string name)
        signal commandFinished(string requestId, var result)
        function save(name, value) {
            const id = 'fixture-save-' + (++serial);
            const snapshot = OrganizerLogic.parseOrganizer(value);
            Qt.callLater(function() {
                if (root.fakeConfig.failWrites) {
                    root.fakeConfig.commandFinished(id, { ok: false, reason: 'io' });
                    return;
                }
                root.fakeConfig.documents = { organizer: snapshot };
                root.fakeConfig.revisions = { organizer: 'fixture-' + (++root.fakeConfig.revision) };
                root.fakeConfig.documentChanged(name);
                root.fakeConfig.commandFinished(id, { ok: true });
            });
            return id;
        }
        function reload(name) { return 'fixture-read'; }
    }
    property Organizer organizer: Organizer { config: root.fakeConfig }
    function check(name, passed) { checks = checks.concat([{ name: name, passed: passed }]); }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({
            status: checks.every(function(item) { return item.passed; }) ? 'pass' : 'fail', checks: checks,
        }));
        Qt.quit();
    }

    Timer {
        interval: 30
        running: true
        repeat: true
        onTriggered: {
            if (root.phase === 1) {
                if (root.organizer.saving) return;
                root.check('organizer-save-failure-keeps-unsaved-task',
                    root.organizer.error === 'organizer-save-failed' && root.organizer.dirty
                    && root.organizer.document.tasks.length === 1);
                root.fakeConfig.documentStates = { organizer: { kind: 'ready' }, theme: { kind: 'ready' } };
                root.phase = 2;
                return;
            }
            if (root.phase === 2) {
                root.check('unrelated-config-state-preserves-save-failure', root.organizer.error === 'organizer-save-failed');
                root.fakeConfig.failWrites = false;
                root.organizer.retrySave();
                root.phase = 3;
                return;
            }
            if (root.phase === 3) {
                if (root.organizer.saving) return;
                root.check('explicit-retry-persists-task-and-clears-dirty', !root.organizer.dirty
                    && root.organizer.error === '' && root.fakeConfig.documents.organizer.tasks.length === 1);
                root.fakeConfig.failWrites = true;
                root.organizer.setDone(root.organizer.document.tasks[0].id, true);
                root.phase = 4;
                return;
            }
            if (root.phase === 4) {
                if (root.organizer.saving) return;
                root.fakeConfig.revisions = { organizer: 'external-revision' };
                root.fakeConfig.documentChanged('organizer');
                root.check('external-revision-detects-conflict-without-discarding-local-edit',
                    root.organizer.error === 'organizer-conflict' && root.organizer.persistenceDisabled
                    && root.organizer.document.tasks[0].done);
                root.fakeConfig.failWrites = false;
                root.organizer.retrySave();
                root.phase = 5;
                return;
            }
            if (root.phase === 5) {
                if (root.organizer.saving) return;
                root.check('explicit-conflict-retry-retains-local-edit', !root.organizer.dirty
                    && root.organizer.error === '' && root.fakeConfig.documents.organizer.tasks[0].done);
                root.stableDocument = root.organizer.document;
                root.fakeConfig.documentStates = { organizer: { kind: 'ready' }, theme: { kind: 'ready', revision: 'theme-2' } };
                root.phase = 6;
                return;
            }
            if (root.phase === 6) {
                root.check('unrelated-ready-state-keeps-organizer-model-identity',
                    root.organizer.document === root.stableDocument);
                root.finish();
                return;
            }
            const tasks = OrganizerLogic.addTask([], 'Купити молоко', 'fixture-task', 123);
            const edited = OrganizerLogic.updateTask(tasks, 'fixture-task', { text: 'Купити хліб', done: true });
            root.checks = [
                { name: 'qml-services-load-organizer-config', passed:
                    root.services.config.documents.organizer.schemaVersion === 1
                    && root.services.config.documents.organizer.tasks.length === 0 },
                { name: 'qml-organizer-edit-preserves-original-and-identity', passed:
                    tasks[0].text === 'Купити молоко' && !tasks[0].done
                    && edited[0].text === 'Купити хліб' && edited[0].done
                    && edited[0].id === 'fixture-task' && edited[0].createdAt === 123 },
            ];
            root.check('organizer-is-ready-before-edit', root.organizer.initialized);
            root.organizer.setDraftText('Нове завдання');
            root.organizer.addTask(root.organizer.draftText);
            root.phase = 1;
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { root.check('organizer-fixture-completes', false); root.finish(); } }
}
