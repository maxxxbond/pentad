import QtQml

QtObject {
    required property string instanceId
    required property var settings
    required property var services
    property var timerState: ({ status: 'idle' })
    function timerCommand(action) {
        timerState = { status: action === 'start' ? 'running'
            : action === 'pause' ? 'paused' : action === 'reset' ? 'idle' : 'running' };
        return true;
    }
    // Counted on a member widgets do receive: `services` is the per-instance facade.
    Component.onCompleted: services.media.controllerCreates++
    Component.onDestruction: services.media.controllerDisposals++
}
