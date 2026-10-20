import QtQuick
import '../plugins'

PentadWidget {
    readonly property var observedMedia: services.media.state
    implicitWidth: 100
    implicitHeight: 30
    function togglePlayback() { return services.media.playPause(); }
    function startTimer() { return controller.timerCommand('start'); }
}
