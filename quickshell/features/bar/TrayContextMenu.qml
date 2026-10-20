pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Item {
    id: root

    property Item anchorItem: null
    readonly property var ownerWindow: anchorItem ? anchorItem.QsWindow.window : null
    property var manager: null
    property var services: null
    property var menuHandle: null
    property bool grabFocus: true
    property var entriesOverride: null
    readonly property bool opened: menuLevel.opened
    readonly property alias surface: menuLevel.surface
    readonly property alias rowRepeater: menuLevel.rowRepeater
    readonly property var entries: menuLevel.entries
    readonly property var activeSubmenu: menuLevel.activeChild
    readonly property var window: menuLevel.window
    readonly property var focusWindows: menuLevel.branchWindows

    function open(viaKeyboard) {
        if (!anchorItem || (entriesOverride === null && !menuHandle)) return
        if (manager && typeof manager.registerChild === "function") manager.registerChild(root)
        menuLevel.open(viaKeyboard === true)
        if (!menuLevel.opened && manager && typeof manager.unregisterChild === "function")
            manager.unregisterChild(root)
    }

    function close(reason) {
        menuLevel.close(reason || "tray-owner-close")
        if (manager && typeof manager.unregisterChild === "function") manager.unregisterChild(root)
    }

    function handleRowKey(index, key) { return menuLevel.handleRowKey(index, key) }
    function activateEntry(entry) { menuLevel.activateEntry(entry) }
    function dismissTop() { return menuLevel.dismissTop() }

    TrayMenuLevel {
        id: menuLevel
        anchorItem: root.anchorItem
        services: root.services
        menuHandle: root.menuHandle
        entriesOverride: root.entriesOverride
        ownerMenu: root
        grabFocus: root.grabFocus
    }

    Connections {
        target: menuLevel
        function onDismissed() {
            if (root.manager && typeof root.manager.unregisterChild === "function")
                root.manager.unregisterChild(root)
        }
    }
    onMenuHandleChanged: if (opened) close("menu-handle-changed")
    onAnchorItemChanged: if (!anchorItem) close("anchor-removed")
    Component.onDestruction: if (manager && typeof manager.unregisterChild === "function")
        manager.unregisterChild(root)
}
