import QtQuick
import Quickshell.Io

Process {
    id: worker
    required property var argv
    signal finished(var result)
    property bool startedOnce: false
    property bool settled: false
    command: argv
    onStarted: startedOnce = true
    onRunningChanged: {
        if (!running && !startedOnce && !settled) {
            settled = true; finished({ ok: false, reason: 'unavailable' }); destroy();
        }
    }
    onExited: function(code, status) {
        if (!settled) { settled = true; finished({ ok: code === 0 && status === 0 }); }
        destroy();
    }
    property Timer deadline: Timer {
        interval: 5000; running: true
        onTriggered: {
            if (worker.settled) return;
            worker.settled = true; worker.finished({ ok: false, reason: 'timeout' });
            if (worker.running) worker.signal(9);
            else worker.destroy();
        }
    }
}
