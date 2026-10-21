import QtQuick
import QtQml
import "../../logic/clock.mjs" as ClockLogic

QtObject {
    id: placementController
    required property string instanceId
    required property var settings
    required property var services

    readonly property date dateTime: services.clock.date
    readonly property bool showSeconds: services.config.documents.layout.showSeconds
    // Two lines need at least 32 px of bar height; lower bars fall back to one line.
    readonly property bool stacked: services.config.documents.layout.clockLayout !== 'inline'
        && services.config.documents.layout.barHeight >= 32
    readonly property string time: Qt.formatTime(dateTime, showSeconds ? 'HH:mm:ss' : 'HH:mm')
    readonly property string date: Qt.formatDate(dateTime, 'dd.MM')
    property var timerState: ClockLogic.idleTimerState()
    property int timerSerial: 0
    property int pulseSerial: 0
    property var pulseCallback: null
    readonly property bool timerAllowed: !services.preview && !services.safeMode
    readonly property var timer: ClockLogic.createClockTimerController({
        now: function() { return Date.now(); },
        schedule: function(callback, delay) {
            placementController.pulseSerial++;
            placementController.pulseCallback = callback;
            placementController.pulse.interval = delay;
            placementController.pulse.restart();
            return placementController.pulseSerial;
        },
        cancel: function(serial) {
            if (serial !== placementController.pulseSerial) return;
            placementController.pulse.stop();
            placementController.pulseCallback = null;
        }
    })
    signal commandFinished(string requestId, var result)

    function timerCommand(action, durationSeconds) {
        var requestId = 'clock-' + instanceId + '-' + (++timerSerial);
        var result;
        if (!timerAllowed) result = { ok: false, reason: 'denied' };
        else if (action === 'start') result = timer.start(durationSeconds)
            ? { ok: true } : { ok: false, reason: 'invalid-duration' };
        else if (action === 'pause') result = timer.pause()
            ? { ok: true } : { ok: false, reason: 'not-running' };
        else if (action === 'resume') result = timer.resume()
            ? { ok: true } : { ok: false, reason: 'not-paused' };
        else if (action === 'reset') result = timer.reset()
            ? { ok: true } : { ok: false, reason: 'disposed' };
        else result = { ok: false, reason: 'unsupported' };
        Qt.callLater(function() { placementController.commandFinished(requestId, result); });
        return requestId;
    }
    function refreshTimer() { return timer.refresh(); }

    property Timer pulse: Timer {
        interval: 1000
        repeat: false
        onTriggered: {
            var callback = placementController.pulseCallback;
            placementController.pulseCallback = null;
            if (callback) callback();
        }
    }
    Component.onCompleted: {
        var owner = placementController;
        timer.subscribe(function(state) { owner.timerState = state; });
    }
    Component.onDestruction: timer.dispose()
    property Connections clockConnection: Connections {
        target: placementController.services.clock
        function onDateChanged() { placementController.refreshTimer(); }
    }
}
