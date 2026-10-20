import QtQuick
import QtQml
import Quickshell.Services.SystemTray
import "../logic/tray.mjs" as TrayLogic

QtObject {
    id: root

    required property var services
    readonly property bool preview: services.preview === true
    readonly property bool safeMode: services.safeMode === true
    readonly property var nativeSystemTray: preview ? null : SystemTray
    readonly property var state: TrayLogic.trayAvailability(snapshot())
    readonly property var items: nativeSystemTray ? nativeSystemTray.items.values : null

    function snapshot() {
        var result = []
        if (!items) return result
        for (var index = 0; index < items.length; index++) result.push(items[index])
        return result
    }

    function nativeItemFor(id) {
        if (!items) return null
        for (var index = 0; index < items.length; index++) {
            var item = items[index]
            if (item && item.id === id) return item
        }
        return null
    }
}
