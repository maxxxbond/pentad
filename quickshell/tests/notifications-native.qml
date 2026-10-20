import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: root
    property bool actionSent: false
    property bool dndSent: false
    property bool quietSent: false
    property bool expirySent: false
    property bool hoverSent: false
    property string hoverKey: ''
    Config { id: config }
    Notifications { id: service; config: config; preview: false; safeMode: false }
    Connections {
        target: service
        function onStateChanged() {
            const state = service.state;
            console.log("PENTAD_NOTIFICATION_STATE " + JSON.stringify({ status: state.status,
                dnd: state.dnd, history: state.history.map(function(item) { return { key: item.key, title: item.title, wireId: item.wireId }; }) }));
            const replacement = state.history.find(function(item) { return item.title === "Replacement title"; });
            if (replacement && !root.actionSent) {
                root.actionSent = true;
                Qt.callLater(function() {
                    console.log("PENTAD_NOTIFICATION_ACTION_RESULT " + service.invoke(replacement.key, "open"));
                });
            }
            if (!root.dndSent && state.history.some(function(item) { return item.title === 'Enable DND'; })) {
                root.dndSent = true;
                Qt.callLater(function() { service.setDnd(true); console.log('PENTAD_NOTIFICATION_DND_READY'); });
            }
            if (!root.quietSent && state.history.some(function(item) { return item.title === 'Quiet notification'; })) {
                root.quietSent = true;
                Qt.callLater(function() { service.setDnd(false); console.log('PENTAD_NOTIFICATION_DND_DONE'); });
            }
            const expiry = state.popups.find(function(item) { return item.title === 'Expiry notification'; });
            if (expiry && !root.expirySent) {
                root.expirySent = true;
                Qt.callLater(function() { service.setPresented(expiry.key, true); });
            }
            const hover = state.popups.find(function(item) { return item.title === 'Hover notification'; });
            if (hover && !root.hoverSent) {
                root.hoverSent = true;
                root.hoverKey = hover.key;
                Qt.callLater(function() { service.setPresented(root.hoverKey, true); pauseHover.start(); });
            }
        }
    }
    Window { visible: true; width: 64; height: 64 }
    Timer {
        id: pauseHover
        interval: 2000
        onTriggered: {
            service.setHovered(root.hoverKey, true);
            console.log('PENTAD_NOTIFICATION_HOVER_PAUSED');
            resumeHover.start();
        }
    }
    Timer {
        id: resumeHover
        interval: 600
        onTriggered: {
            service.setHovered(root.hoverKey, false);
            console.log('PENTAD_NOTIFICATION_HOVER_RESUMED');
        }
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (service.state.status === "available") {
                console.log("PENTAD_NOTIFICATION_READY");
                stop();
            }
        }
    }
}
