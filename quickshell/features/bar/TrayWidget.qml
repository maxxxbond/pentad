pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../components"
import "../../logic/tray.mjs" as TrayLogic

Item {
    id: root

    required property var services
    property string outputId: ""
    property string mode: "soft"

    readonly property string iconMode: TrayLogic.trayIconMode(mode)
    readonly property bool blocked: actionsBlocked()
    readonly property var trayService: services.tray || null
    readonly property var trayState: trayService
        ? trayService.state : ({ kind: "unavailable", reason: "binding-missing" })
    readonly property var trayItems: trayState.kind === "ready" ? trayState.value.items : []
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: trayItems.length > 0

    function actionsBlocked() {
        return !trayService || services.preview === true || services.safeMode === true
    }

    function openItemMenu(entry, viaKeyboard) {
        if (actionsBlocked() || !entry.nativeItem || !entry.nativeItem.hasMenu) return
        closeMenusExcept(entry.contextMenu)
        entry.contextMenu.open(viaKeyboard === true)
    }

    function closeMenusExcept(menu) {
        for (let i = 0; i < trayRepeater.count; i++) {
            const cell = trayRepeater.itemAt(i)
            if (cell && cell.contextMenu !== menu && cell.contextMenu.opened)
                cell.contextMenu.close("tray-sibling-open")
        }
    }

    function handleTrayKey(entry, key, modifiers) {
        if (actionsBlocked() || !entry.nativeItem) return false
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            entry.nativeItem.activate()
            return true
        }
        if (key === Qt.Key_Menu || (key === Qt.Key_F10 && (modifiers & Qt.ShiftModifier))) {
            openItemMenu(entry, true)
            return true
        }
        return false
    }

    Row {
        id: row
        spacing: Metrics.statusGap
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            id: trayRepeater
            model: root.trayItems

            delegate: Item {
                id: trayEntry
                objectName: "tray-icon-cell"
                required property var modelData
                readonly property var nativeItem: root.trayService
                    ? root.trayService.nativeItemFor(modelData.id) : null
                readonly property bool symbolicSource: !!nativeItem
                    && String(nativeItem.icon).indexOf('-symbolic') >= 0
                readonly property bool showingColor: root.iconMode === "color"
                    || (root.iconMode === "soft" && activeFocus)
                    || (root.iconMode === "soft" && pointer.containsMouse)
                property var testMenuEntries: null
                readonly property alias contextMenu: menuPopup

                width: 24
                height: Metrics.panelControl
                enabled: !root.blocked
                activeFocusOnTab: true
                Accessible.name: nativeItem ? nativeItem.title : modelData.id
                Accessible.role: Accessible.Button
                TrayContextMenu {
                    id: menuPopup
                    objectName: "tray-context-menu"
                    anchorItem: trayEntry
                    manager: root.services.popups || null
                    services: root.services
                    menuHandle: trayEntry.nativeItem ? trayEntry.nativeItem.menu : null
                    entriesOverride: trayEntry.testMenuEntries
                }
                Connections {
                    target: root
                    function onBlockedChanged() { if (root.blocked) menuPopup.close() }
                }
                PentadToolTip {
                    visible: pointer.containsMouse && !!trayEntry.nativeItem
                    text: trayEntry.nativeItem ? (trayEntry.nativeItem.tooltipTitle || trayEntry.nativeItem.title || "") : ""
                    detail: trayEntry.nativeItem ? (trayEntry.nativeItem.tooltipDescription || "") : ""
                }

                PentadIcon {
                    objectName: "tray-icon"
                    anchors.centerIn: parent
                    width: Metrics.trayIcon
                    height: Metrics.trayIcon
                    source: trayEntry.nativeItem ? trayEntry.nativeItem.icon : ""
                    pixelSize: Metrics.trayIcon
                    color: trayEntry.symbolicSource ? Qt.alpha(Theme.tokens.text, 0.8) : Theme.tokens.text
                    symbolic: trayEntry.symbolicSource || !trayEntry.showingColor
                    preserveLuminance: !trayEntry.symbolicSource
                    accessibleName: trayEntry.nativeItem ? trayEntry.nativeItem.title : ""
                }

                Keys.onPressed: function(event) {
                    if (event.isAutoRepeat) return
                    event.accepted = root.handleTrayKey(trayEntry, event.key, event.modifiers)
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    onPressed: function(mouse) {
                        trayEntry.forceActiveFocus()
                    }
                    onClicked: function(mouse) {
                        if (root.actionsBlocked() || !trayEntry.nativeItem) return
                        if (mouse.button === Qt.LeftButton) trayEntry.nativeItem.activate()
                        else if (mouse.button === Qt.RightButton) root.openItemMenu(trayEntry)
                    }
                }
            }
        }
    }
}
