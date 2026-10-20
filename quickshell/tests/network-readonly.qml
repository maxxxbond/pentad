import QtQuick
import Quickshell
import "../services"

ShellRoot {
    id: root
    Network { id: network; preview: false; safeMode: true }
    Timer {
        interval: 4500
        running: true
        repeat: false
        onTriggered: {
            const state = network.state;
            const value = state.kind === "ready" ? state.value : null;
            console.log("PENTAD_NETWORK_READONLY " + JSON.stringify({
                kind: state.kind,
                reason: state.reason || "",
                connectivity: value ? value.connectivity : "",
                deviceCount: value ? value.devices.length : 0,
                wifiEnabled: value ? value.wifiEnabled : null,
                wifiScanEnabled: value ? value.wifiScanEnabled : null,
                ownerKnown: network.ownerKnown,
                ownerPresent: network.ownerPresent,
                nativeBackendAvailable: network.nativeBackendAvailable,
                safeMode: network.safeMode
            }));
            Qt.quit();
        }
    }
}
