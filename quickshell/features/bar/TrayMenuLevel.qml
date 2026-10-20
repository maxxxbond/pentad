pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import qs.theme
import qs.components
import "../../logic/tray-menu-layout.mjs" as TrayMenuLayout

Item {
    id: level

    property Item anchorItem: null
    property var services: null
    property var menuHandle: null
    property var entriesOverride: null
    property var parentIntent: null
    property var parentLevel: null
    property var ownerMenu: null
    property bool grabFocus: true
    property var activeChild: null
    property var pendingRow: null
    property bool pendingClose: false
    property int hoverOpenMs: 180
    property bool keyboardFocusVisible: false
    property var submenuComponent: null
    readonly property bool opened: popup.opened
    readonly property alias surface: popup.surface
    readonly property alias window: popup.window
    readonly property alias pointerIntent: popup.pointerIntent
    readonly property alias rowRepeater: rows
    readonly property var entries: entriesOverride !== null
        ? entriesOverride : menuOpener.children.values
    readonly property real modelListHeight: TrayMenuLayout.modelListHeight(entries || [], 30, 9)
    readonly property var branchWindows: opened
        ? [popup.window].concat(activeChild ? activeChild.branchWindows : []) : []

    signal dismissed()

    function traceLayout() {
        if (!opened || !popup.pointerIntentDebug) return
        const mask = popup.window.mask
        const maskRows = mask && mask.rows ? mask.rows : []
        let maskBounds = null
        for (const row of maskRows) {
            if (!row) continue
            if (!maskBounds) maskBounds = { x: row.x, y: row.y, right: row.x + row.width, bottom: row.y + row.height }
            else {
                maskBounds.x = Math.min(maskBounds.x, row.x)
                maskBounds.y = Math.min(maskBounds.y, row.y)
                maskBounds.right = Math.max(maskBounds.right, row.x + row.width)
                maskBounds.bottom = Math.max(maskBounds.bottom, row.y + row.height)
            }
        }
        if (maskBounds) {
            maskBounds.width = maskBounds.right - maskBounds.x
            maskBounds.height = maskBounds.bottom - maskBounds.y
            delete maskBounds.right
            delete maskBounds.bottom
        }
        console.info("PENTAD_MENU_POINTER", JSON.stringify({ event: "tray-layout",
            submenu: !!parentLevel, entries: entries ? entries.length : 0, rows: rows.count,
            listHeight: list.implicitHeight, preferredHeight: popup.window.preferredHeight,
            windowHeight: popup.window.height, viewportHeight: listViewport.height,
            inputMaskRows: maskRows.length, inputMaskBounds: maskBounds,
            labels: (entries || []).map(entry => entry ? entry.text || "" : "<removed>") }))
    }

    function open(viaKeyboard) {
        if (!anchorItem || (entriesOverride === null && !menuHandle)) return
        keyboardFocusVisible = viaKeyboard === true
        popup.open()
    }

    function close(reason) {
        cancelPendingHover()
        pendingRow = null
        pendingClose = false
        closeChild()
        popup.close(reason || "tray-close")
    }

    function closeChild() {
        hoverOpenDelay.stop()
        pendingRow = null
        pendingClose = false
        const child = activeChild
        activeChild = null
        if (!child) return false
        child.close()
        child.destroy()
        return true
    }

    function finishChildDismissal(child) {
        if (activeChild !== child) return
        activeChild = null
        child.destroy()
        const nextRow = pendingRow
        const closeOnly = pendingClose
        pendingRow = null
        pendingClose = false
        if (!closeOnly && nextRow && popup.opened && rowIsCurrent(nextRow) && nextRow.pointerHovered)
            openChild(nextRow, true)
    }

    function cancelPendingHover() {
        hoverOpenDelay.stop()
        pendingRow = null
        pendingClose = false
    }

    function rowIsCurrent(row) {
        if (!row || !row.visible || !row.rowEnabled || !row.modelData || !row.modelData.hasChildren) return false
        for (let index = 0; index < rows.count; index++)
            if (rows.itemAt(index) === row) return true
        return false
    }

    function previousEntry(index) {
        for (let candidate = index - 1; candidate >= 0; candidate--) {
            const row = rows.itemAt(candidate)
            if (row && row.visible && row.rowEnabled) return row.button
        }
        return null
    }

    function nextEntry(index) {
        for (let candidate = index + 1; candidate < rows.count; candidate++) {
            const row = rows.itemAt(candidate)
            if (row && row.visible && row.rowEnabled) return row.button
        }
        return null
    }

    function ensureRowVisible(row) {
        const flickable = listViewport.contentItem
        if (!flickable || !("contentY" in flickable)) return
        const top = row.y
        const bottom = top + row.height
        if (top < flickable.contentY) flickable.contentY = top
        else if (bottom > flickable.contentY + listViewport.availableHeight)
            flickable.contentY = bottom - listViewport.availableHeight
    }

    function focusFirst() {
        for (let index = 0; index < rows.count; index++) {
            const row = rows.itemAt(index)
            if (row && row.visible && row.rowEnabled) {
                row.button.forceActiveFocus()
                return
            }
        }
    }

    function hasFocusedEntry() {
        if (activeChild && activeChild.opened) return true
        for (let index = 0; index < rows.count; index++) {
            const row = rows.itemAt(index)
            if (row && row.button.activeFocus) return true
        }
        return false
    }

    function openChild(row, skipAim) {
        if (!row || !row.rowEnabled || !row.modelData.hasChildren) return
        if (activeChild && activeChild.anchorItem === row.button) return
        if (activeChild && !skipAim) {
            pendingRow = row
            pendingClose = false
                return
        }
        closeChild()
        if (!submenuComponent)
            submenuComponent = Qt.createComponent(Qt.resolvedUrl("TrayMenuLevel.qml"))
        if (!submenuComponent || submenuComponent.status !== Component.Ready) {
            if (submenuComponent && submenuComponent.status === Component.Error)
                console.warn("Could not load tray submenu:", submenuComponent.errorString())
            return
        }
        const child = submenuComponent.createObject(level, {
            anchorItem: row.button,
            services: level.services,
            menuHandle: row.modelData,
            entriesOverride: level.entriesOverride !== null ? row.modelData.children : null,
            parentIntent: popup.pointerIntent,
            parentLevel: level,
            ownerMenu: level.ownerMenu,
            grabFocus: level.ownerMenu ? level.ownerMenu.grabFocus : level.grabFocus
        })
        if (!child) return
        activeChild = child
        child.dismissed.connect(function() { level.finishChildDismissal(child) })
        child.open(level.keyboardFocusVisible)
        Qt.callLater(child.focusFirst)
    }

    function hoverRow(row) {
        if (!row) {
            cancelPendingHover()
            if (pendingClose) {
                        pendingRow = null
                pendingClose = false
            }
            return
        }
        if (row.rowEnabled && row.modelData.hasChildren) {
            if (activeChild && activeChild.anchorItem === row.button) {
                cancelPendingHover()
                return
            }
            if (pendingRow === row && !pendingClose && hoverOpenDelay.running) return
                pendingClose = false
            pendingRow = row
            hoverOpenDelay.interval = Math.max(0, hoverOpenMs)
            hoverOpenDelay.restart()
        }
        else {
            hoverOpenDelay.stop()
            pendingRow = null
            pendingClose = false
            if (activeChild) {
                pendingRow = row
                pendingClose = true
                    }
        }
    }

    function activateEntry(entry) {
        cancelPendingHover()
        if (!entry || entry.enabled === false || entry.isSeparator) return
        if (entry.hasChildren) {
            for (let index = 0; index < rows.count; index++) {
                const row = rows.itemAt(index)
                if (row && row.modelData === entry) { openChild(row, true); return }
            }
            return
        }
        if (typeof entry.triggered === "function") entry.triggered()
        if (ownerMenu) ownerMenu.close()
    }

    function goBack() {
        if (activeChild) return closeChild()
        if (parentLevel) {
            parentLevel.closeChild()
            return true
        }
        return false
    }

    function dismissTop() {
        if (activeChild) return activeChild.dismissTop()
        if (parentLevel) return parentLevel.closeChild()
        if (ownerMenu) ownerMenu.close()
        return true
    }

    function handleRowKey(index, key) {
        cancelPendingHover()
        keyboardFocusVisible = true
        const row = rows.itemAt(index)
        if (!row || !row.rowEnabled) return false
        if (key === Qt.Key_Up || key === Qt.Key_Down) {
            const next = key === Qt.Key_Up ? previousEntry(index) : nextEntry(index)
            if (next) next.forceActiveFocus()
            return true
        }
        if (key === Qt.Key_Right && row.modelData.hasChildren) {
            openChild(row, true)
            return true
        }
        if (key === Qt.Key_Left && parentLevel) {
            goBack()
            return true
        }
        if (key === Qt.Key_Escape) {
            if (!goBack() && ownerMenu) ownerMenu.close()
            return true
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            activateEntry(row.modelData)
            return true
        }
        return false
    }

    Timer {
        id: hoverOpenDelay
        interval: level.hoverOpenMs
        repeat: false
        onTriggered: {
            const row = level.pendingRow
            level.pendingRow = null
            level.pendingClose = false
            if (popup.opened && level.rowIsCurrent(row) && row.pointerHovered)
                level.openChild(row, false)
        }
    }

    AttachedPopover {
        id: popup
        manager: null
        pointerIntentDebug: Quickshell.env("PENTAD_MENU_POINTER_DEBUG") === "1"
        anchorItem: level.anchorItem
        placement: level.parentLevel ? "right" : "below"
        pointerIntent.parentIntent: level.parentIntent
        grabFocus: level.grabFocus
        focusManagedExternally: !!(level.ownerMenu && level.ownerMenu.manager
            && level.ownerMenu.manager.hosts && level.ownerMenu.manager.hosts.length)
        contentItem: Item {
            implicitWidth: 236
            implicitHeight: Math.min(level.modelListHeight, 360)
            Column {
                id: menuContent
                width: parent.width
                spacing: 4
                PentadScrollView {
                    id: listViewport
                    width: parent.width
                    height: Math.min(level.modelListHeight, 360, popup.availableContentHeight)
                    contentWidth: availableWidth
                    contentHeight: level.modelListHeight
                    Column {
                        id: list
                        width: listViewport.availableWidth
                        onImplicitHeightChanged: Qt.callLater(level.traceLayout)
                        Repeater {
                            id: rows
                            model: level.entries || []
                            delegate: Item {
                                id: row
                                required property int index
                                required property var modelData
                                readonly property bool separator: !!modelData.isSeparator
                                readonly property bool rowEnabled: !separator && modelData.enabled !== false
                                readonly property alias button: itemButton
                                readonly property bool pointerHovered: itemPointer.hovered
                                readonly property bool focusPainted: itemButton.activeFocus && level.keyboardFocusVisible
                                property var lastInsideGlobalPoint: null
                                objectName: "tray-menu-row"
                                width: list.width
                                height: row.separator ? 9 : 30

                                PentadSeparator {
                                    anchors.fill: parent
                                    visible: row.separator
                                }
                                Button {
                                    id: itemButton
                                    objectName: row.separator ? "" : "tray-menu-item"
                                    anchors.fill: parent
                                    visible: !row.separator
                                    enabled: row.rowEnabled
                                    text: row.modelData.text || ""
                                    Accessible.name: text
                                    Accessible.role: Accessible.MenuItem
                                    Accessible.checkable: row.modelData.buttonType !== undefined
                                        && row.modelData.buttonType !== QsMenuButtonType.None
                                    Accessible.checked: row.modelData.checkState !== undefined
                                        && row.modelData.checkState !== Qt.Unchecked
                                    contentItem: RowLayout {
                                        spacing: 8
                                        Text {
                                            visible: row.modelData.buttonType !== undefined
                                                && row.modelData.buttonType !== QsMenuButtonType.None
                                            Layout.preferredWidth: visible ? 14 : 0
                                            text: row.modelData.buttonType === QsMenuButtonType.RadioButton
                                                ? (row.modelData.checkState === Qt.Unchecked ? "○" : "●")
                                                : (row.modelData.checkState === Qt.Unchecked ? "" : "✓")
                                            color: itemButton.enabled ? Theme.tokens.accent : Theme.tokens.textMuted
                                            font.family: Theme.tokens.fontFamily
                                            font.pixelSize: Metrics.textBody
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: itemButton.text
                                            textFormat: Text.PlainText
                                            color: itemButton.enabled ? (itemButton.hovered || row.focusPainted
                                                ? Theme.tokens.text : Theme.tokens.textMuted) : Theme.tokens.textMuted
                                            font.family: Theme.tokens.fontFamily
                                            font.pixelSize: Metrics.textBody
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: !!row.modelData.hasChildren
                                            text: "›"
                                            color: Theme.tokens.textMuted
                                            font.pixelSize: Metrics.textSection
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                    background: ContinuousSurface {
                                        fill: itemButton.hovered || row.focusPainted || itemButton.down
                                            ? Qt.alpha(Theme.tokens.text, 0.08) : "transparent"
                                        extent: Metrics.radiusMedium
                                        opacity: itemButton.enabled ? 1 : 0.4
                                    }
                                    Keys.onPressed: function(event) {
                                        event.accepted = level.handleRowKey(row.index, event.key)
                                    }
                                    onActiveFocusChanged: if (activeFocus) level.ensureRowVisible(row)
                                    onClicked: {
                                        level.keyboardFocusVisible = false
                                        level.activateEntry(row.modelData)
                                    }
                                }
                                HoverHandler {
                                    id: itemPointer
                                    target: null
                                    onPointChanged: if (hovered && point.position.x >= 0
                                        && point.position.y >= 0 && point.position.x <= row.width
                                        && point.position.y <= row.height)
                                        row.lastInsideGlobalPoint = popup.pointerIntent.globalPoint(row, point.position)
                                    onHoveredChanged: if (hovered) {
                                        level.keyboardFocusVisible = false
                                        level.hoverRow(row)
                                    } else {
                                        if (level.activeChild && level.activeChild.anchorItem === itemButton) {
                                        }
                                        if (level.pendingRow === row) {
                                            hoverOpenDelay.stop()
                                                                                level.pendingRow = null
                                            level.pendingClose = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        QsMenuOpener {
            id: menuOpener
            menu: popup.opened && level.entriesOverride === null ? level.menuHandle : null
        }
        Connections {
            target: popup
            function onClosed() {
                level.closeChild()
                level.dismissed()
            }
        }
        onOpenedChanged: {
            if (opened) Qt.callLater(level.focusFirst)
            else level.closeChild()
        }
    }
    Connections {
        target: level
        function onEntriesChanged() {
            level.cancelPendingHover()
            if (level.activeChild && !level.rowIsCurrent(level.activeChild.anchorItem.parent)) level.closeChild()
            Qt.callLater(level.traceLayout)
            const flickable = listViewport.contentItem
            if (flickable && ("contentY" in flickable)) flickable.contentY = 0
            if (level.opened) Qt.callLater(function() {
                if (level.opened && !level.hasFocusedEntry()) level.focusFirst()
            })
        }
    }
}
