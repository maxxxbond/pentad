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
    Component.onCompleted: services.controllerCreates++
    Component.onDestruction: services.controllerDisposals++
}
