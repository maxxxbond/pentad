import QtQuick
import QtQml
import qs.services as Adapters
import '../../logic/media.mjs' as MediaLogic
import '../../logic/clock.mjs' as ClockLogic
import '../../logic/activity.mjs' as ActivityLogic

QtObject {
    id: root
    required property string instanceId
    required property var settings
    required property var services
    property string selectedId: settings.preferredId || ''
    property string appliedPreference: ''
    property bool initialized: false
    property int serial: 0
    onSettingsChanged: {
        var preferred = settings.preferredId || '';
        if (initialized && preferred !== appliedPreference) {
            appliedPreference = preferred;
            selectedId = preferred;
        }
    }
    Component.onCompleted: { appliedPreference = settings.preferredId || ''; initialized = true; syncTimerStatus(); }
    readonly property QtObject media: QtObject {
        id: selection
        readonly property bool writable: root.services.media.writable !== false
        readonly property var source: root.services.media.state
        readonly property var state: source.kind === 'ready' ? ({ kind: 'ready', value: {
            players: source.value.players, selectedId: root.selectedId,
            current: MediaLogic.chooseMprisPlayer(source.value.players, root.selectedId)
        } }) : source
        signal commandFinished(string requestId, var result)
        function acquire(id) { root.services.media.acquire(id) }
        function release(id) { root.services.media.release(id) }
        function command(id, action) { return root.services.media.command(id, action) }
        function seek(id, track, position, revision) { return root.services.media.seek(id, track, position, revision) }
        function selectPlayer(id) {
            var requestId = 'selection-' + root.instanceId + '-' + (++root.serial);
            var valid = source.kind === 'ready' && source.value.players.some(function(player) { return player.id === id });
            if (valid) root.selectedId = id;
            Qt.callLater(function() { selection.commandFinished(requestId, { ok: valid, reason: valid ? '' : 'unavailable' }) });
            return requestId;
        }
        property Connections completions: Connections {
            target: root.services.media
            function onCommandFinished(requestId, result) { selection.commandFinished(requestId, result) }
        }
    }
    readonly property Adapters.Lyrics lyrics: Adapters.Lyrics {
        media: root.media
        preview: root.services.preview
        safeMode: root.services.safeMode
    }
    readonly property var timerController: {
        var widgets = services.config.documents.layout.widgets || [];
        for (var i = 0; i < widgets.length; i++) {
            if (widgets[i].enabled && widgets[i].moduleId === 'pentad.clock') {
                var wrapper = services.plugins.controllers[widgets[i].instanceId];
                return wrapper ? wrapper.item : null;
            }
        }
        return null;
    }
    property string lastTimerStatus: 'idle'
    property double finishedAt: 0
    readonly property var timerState: {
        var state = timerController ? timerController.timerState : ClockLogic.idleTimerState();
        return ActivityLogic.timerForActivity(state, finishedAt) || ClockLogic.idleTimerState();
    }
    function syncTimerStatus() {
        var status = timerController ? timerController.timerState.status : 'idle';
        if (status === lastTimerStatus) return;
        lastTimerStatus = status;
        if (status === 'finished') {
            finishedAt = Date.now();
            finishedDismissal.restart();
        } else {
            finishedAt = 0;
            finishedDismissal.stop();
        }
    }
    onTimerControllerChanged: syncTimerStatus()
    property Timer finishedDismissal: Timer {
        interval: 5000
        repeat: false
        onTriggered: root.finishedAt = -1
    }
    property Connections timerStateConnection: Connections {
        target: root.timerController
        function onTimerStateChanged() { root.syncTimerStatus(); }
    }
    function timerCommand(action) {
        if (!timerController) return '';
        var duration = timerController.settings.defaultDurationSeconds || 1500;
        return timerController.timerCommand(action, duration);
    }
    readonly property QtObject activity: QtObject {
        property bool karaoke: false
        readonly property var timerState: root.timerState
        function timerCommand(action) { return root.timerCommand(action); }
    }
    readonly property QtObject serviceFacade: QtObject {
        readonly property var media: root.media
        readonly property var artwork: root.services.artwork
        readonly property var lyrics: root.lyrics
        readonly property var activity: root.activity
        readonly property var visualizer: root.services.visualizer
        readonly property var config: root.services.config
        readonly property var popups: root.services.popups
    }
}
