import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs.components
import qs.features.bar
import qs.shell

ShellRoot {
    id: root
    property var checks: []
    property bool ready: false
    property int step: 0
    property var entries: [
        { text: "Action", enabled: true, triggered: function() { root.actionCount++ } },
        { text: "Disabled", enabled: false },
        { text: "Submenu", enabled: true, hasChildren: true, children: [
            { text: "Nested action", enabled: true, triggered: function() { root.actionCount++ } }
        ] }
    ]
    property int actionCount: 0
    property int choiceCount: 0
    property var savedEntries: null
    property var previousFocus: null
    property bool captureSuccess: false
    property real scrollStartY: 0
    property var sideView: null
    property int panelChoiceCount: 0
    property bool nativeMenu: false
    readonly property var fixtureTray: SystemTray.items.values.find(item => item.title === "Handy fixture") || null
    Process {
        command: ["/usr/bin/python3", Qt.resolvedUrl("tests/fake-tray-menu.py").toString().replace("file://", "")]
        running: true
        stderr: SplitParser { onRead: data => console.warn("FAKE_TRAY", data) }
    }
    property TestEvent keyboard: TestEvent {}
    property PopupManager manager: PopupManager {}
    property QtObject hiddenHost: QtObject {
        property var barWindow: bar
        property bool visible: false
        property bool dragOutActive: false
    }
    Component.onCompleted: manager.registerHost(hiddenHost)
    property QtObject panelServices: QtObject {
        property var popups: root.manager
        property var config: ({ documents: { layout: { barHeight: 40 } } })
        property bool preview: false
    }
    Component {
        id: sideContent
        Item {
            id: panelContent
            implicitWidth: 390
            implicitHeight: 120
            readonly property alias trigger: panelTrigger
            readonly property alias popover: panelPopover
            readonly property alias choice: panelChoice
            Component.onCompleted: Qt.callLater(function() { root.sideView = panelContent })
            Button {
                id: panelTrigger
                x: 24; y: 24; width: 140; height: 40
                text: "Panel dropdown"
                onClicked: panelPopover.open()
            }
            AttachedPopover {
                id: panelPopover
                anchorItem: panelTrigger
                manager: root.manager
                contentItem: Button {
                    id: panelChoice
                    implicitWidth: 180; implicitHeight: 40
                    text: "Panel choice"
                    onClicked: { root.panelChoiceCount++; panelPopover.close() }
                }
            }
        }
    }
    SurfaceHost {
        id: sideHost
        services: root.panelServices
        barWindow: bar
        outputId: bar.screen.name
        surfaceName: "right"
        surfaceComponent: sideContent
        rightComponent: sideContent
        sideSurfaceHeightOverride: 180
    }
    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" })
    }
    function move(item, x, y) {
        let point = item.mapToGlobal(x, y)
        let ancestor = item
        while (ancestor) {
            if (ancestor.pointerGlobalOrigin !== undefined) {
                const local = item.mapToItem(ancestor, x, y)
                point = { x: ancestor.pointerGlobalOrigin.x + local.x, y: ancestor.pointerGlobalOrigin.y + local.y }
                break
            }
            ancestor = ancestor.parent
        }
        driver.write("move " + point.x + " " + point.y + "\n")
    }
    function snapshot() {
        return JSON.stringify({ open: menu.opened, maskRows: menu.window.mask.rows.length,
            keyboardFocus: menu.window.WlrLayershell.keyboardFocus, surface: menu.surface.pointerGlobalOrigin,
            size: [menu.surface.width, menu.surface.height],
            hovered: menu.rowRepeater.count ? menu.rowRepeater.itemAt(0).button.hovered : false })
    }
    Process {
        id: driver
        command: Quickshell.env("PENTAD_HYPRLAND_TEST_RUNTIME")
            ? [Quickshell.env("PENTAD_MENU_INPUT_DRIVER"), String(bar.screen.width), String(bar.screen.height)]
            : [Quickshell.env("PENTAD_MENU_INPUT_DRIVER")]
        stdinEnabled: true
        running: true
        stdout: SplitParser { onRead: data => { if (data === "ready") root.ready = true } }
        stderr: SplitParser { onRead: data => console.warn("NATIVE_INPUT", data) }
    }
    Process { id: nativeEscape; command: ["wtype", "-k", "Escape"] }
    Process {
        id: capture
        command: ["grim", Quickshell.env("PENTAD_MENU_CAPTURE_PATH")]
        onExited: (exitCode, exitStatus) => { root.captureSuccess = exitCode === 0 }
    }
    Process {
        id: layerState
        command: ["env", "XDG_RUNTIME_DIR=" + Quickshell.env("PENTAD_HYPRLAND_TEST_RUNTIME"),
            "/usr/bin/hyprctl", "-i", Quickshell.env("PENTAD_HYPRLAND_TEST_INSTANCE"), "-j", "layers"]
        stdout: StdioCollector { onStreamFinished: console.log("NATIVE_LAYERS", text) }
    }
    function rowPoint(index) { return menu.rowRepeater.itemAt(index).button }
    function lastRowFitsOrMenuFillsOutput(row, point) {
        return point.y >= 0 && (point.y + row.height <= menu.surface.height - 16
            || menu.surface.height >= bar.screen.height - bar.height)
    }
    PanelWindow {
        id: bar
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: 40
        exclusiveZone: 40
        color: "#111111"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Item {
            objectName: "pentad-bar-face"
            anchors.fill: parent
            Rectangle {
                id: icon
                x: 200; y: 6; width: 24; height: 28
                color: "#eeeeee"
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: menu.open() }
                TrayContextMenu {
                    id: menu
                    anchorItem: icon
                    manager: root.manager
                    entriesOverride: root.nativeMenu ? null : root.entries
                    menuHandle: root.fixtureTray ? root.fixtureTray.menu : null
                }
            }
            Rectangle {
                id: dropdownTrigger
                x: parent.width - 60; y: 6; width: 40; height: 28; color: "#cccccc"
                MouseArea { anchors.fill: parent; onClicked: dropdown.open() }
            }
            AttachedPopover {
                id: dropdown
                anchorItem: dropdownTrigger
                manager: root.manager
                contentItem: Button {
                    id: choice
                    implicitWidth: 180; implicitHeight: 40
                    text: "Choose"
                    onClicked: { root.choiceCount++; dropdown.close() }
                }
            }
            AttachedPopover {
                id: passive
                anchorItem: dropdownTrigger
                manager: root.manager
                grabFocus: false
                pointerDismissEnabled: false
                contentItem: Text { text: "Passive detail"; color: "white" }
            }
        }
    }
    Timer {
        interval: 100; running: root.ready; repeat: true
        onTriggered: {
            if (root.step === 0) root.move(icon, 12, 14)
            else if (root.step === 1) driver.write("click 273\n")
            else if (root.step === 3) {
                if (Quickshell.env("PENTAD_HYPRLAND_TEST_RUNTIME")) layerState.running = true
                root.check("native-right-click-opens-menu", menu.opened, root.snapshot())
                if (menu.opened) root.move(menu.rowRepeater.itemAt(0).button, 60, 15)
            } else if (root.step === 8) {
                if (menu.opened) {
                    if (Quickshell.env("PENTAD_HYPRLAND_TEST_RUNTIME")) capture.running = true
                    else menu.surface.grabToImage(result => { root.captureSuccess = result.saveToFile(Quickshell.env("PENTAD_MENU_CAPTURE_PATH")) })
                }
            } else if (root.step === 9) {
                root.check("native-entry-keeps-menu-open-beyond-grace", menu.opened, root.snapshot())
                root.check("native-entry-delivers-button-hover", menu.opened && menu.rowRepeater.itemAt(0).button.hovered)
                driver.write("move 500 500\n")
            } else if (root.step === 14) {
                root.check("native-outside-leave-dismisses", !menu.opened)
                root.move(icon, 12, 14)
            } else if (root.step === 15) driver.write("click 273\n")
            else if (root.step === 17) {
                if (menu.opened) root.move(root.rowPoint(1), 60, 15)
            } else if (root.step === 21) {
                root.check("disabled-row-hover-keeps-menu-open", menu.opened)
                driver.write("click 272\n")
            } else if (root.step === 23) {
                root.check("disabled-row-does-not-activate", menu.opened && root.actionCount === 0)
                if (menu.opened) root.move(root.rowPoint(2), 60, 15)
            } else if (root.step === 25) {
                root.check("native-hover-opens-submenu", !!menu.activeSubmenu && menu.activeSubmenu.opened)
                if (menu.activeSubmenu) root.move(menu.activeSubmenu.rowRepeater.itemAt(0).button, 60, 15)
            } else if (root.step === 30) {
                root.check("native-submenu-entry-keeps-entire-branch-open", menu.opened && !!menu.activeSubmenu && menu.activeSubmenu.opened)
                driver.write("click 272\n")
            } else if (root.step === 32) {
                root.check("native-leaf-click-activates-once-and-closes-branch", root.actionCount === 1 && !menu.opened)
                root.move(icon, 12, 14)
            } else if (root.step === 33) driver.write("click 273\n")
            else if (root.step === 35) {
                if (menu.opened) root.move(root.rowPoint(0), 60, 15)
            } else if (root.step === 37) {
                if (Quickshell.env("PENTAD_HYPRLAND_TEST_RUNTIME")) nativeEscape.running = true
                else if (menu.opened) root.keyboard.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)
            } else if (root.step === 39) {
                root.check("escape-closes-menu", !menu.opened)
                root.move(dropdownTrigger, 20, 14)
            } else if (root.step === 40) driver.write("click 272\n")
            else if (root.step === 42) {
                root.check("native-click-opens-general-dropdown", dropdown.opened)
                if (dropdown.opened) root.move(choice, 60, 20)
            } else if (root.step === 47) {
                root.check("general-dropdown-receives-hover-and-stays-open", dropdown.opened && choice.hovered)
                const rect = dropdown.window.placementRect
                root.check("right-edge-dropdown-stays-on-output", rect.x >= bar.screen.x && rect.x + rect.width <= bar.screen.x + bar.screen.width + 1)
                driver.write("click 272\n")
            } else if (root.step === 49) {
                root.check("general-dropdown-native-action-activates-once", root.choiceCount === 1 && !dropdown.opened)
            } else if (root.step === 50) {
                root.previousFocus = bar.contentItem.Window.window.activeFocusItem
                passive.open()
            } else if (root.step === 52) {
                root.check("passive-popover-does-not-enable-keyboard-grab", passive.opened && !root.manager.focusActive
                    && passive.window.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None
                    && bar.contentItem.Window.window.activeFocusItem === root.previousFocus,
                    JSON.stringify({ opened: passive.opened, focusActive: root.manager.focusActive,
                        keyboard: passive.window.WlrLayershell.keyboardFocus,
                        unchanged: bar.contentItem.Window.window.activeFocusItem === root.previousFocus }))
                passive.close()
                root.savedEntries = root.entries
                root.entries = []
                root.move(icon, 12, 14)
            } else if (root.step === 53) driver.write("click 273\n")
            else if (root.step === 55) {
                root.check("empty-menu-opens", menu.opened && menu.rowRepeater.count === 0)
                if (menu.opened) root.move(menu.surface, menu.surface.width / 2, 30)
                const rows = []
                for (let i = 0; i < 30; i++) rows.push({ text: "Action " + i, enabled: true, triggered: function() { root.actionCount++ } })
                root.entries = rows
            } else if (root.step === 58) {
                root.check("async-entries-update-open-menu", menu.opened && menu.rowRepeater.count === 30)
                const rect = menu.window.placementRect
                root.check("long-menu-fits-output-height", rect.y >= bar.screen.y && rect.y + menu.window.height <= bar.screen.y + bar.screen.height + 1,
                    JSON.stringify({ rect: rect, height: menu.window.height, screenHeight: bar.screen.height }))
                if (menu.opened) {
                    root.move(root.rowPoint(0), 60, 15)
                    root.scrollStartY = root.rowPoint(0).mapToItem(menu.surface, 0, 0).y
                }
            } else if (root.step === 60) driver.write("scroll 250\n")
            else if (root.step === 64) {
                root.check("wheel-scroll-keeps-long-menu-open", menu.opened)
                root.check("native-wheel-scrolls-menu-viewport", menu.opened
                    && root.rowPoint(0).mapToItem(menu.surface, 0, 0).y < root.scrollStartY)
                root.rowPoint(29).forceActiveFocus()
            } else if (root.step === 67) {
                const row = root.rowPoint(29)
                const point = row.mapToItem(menu.surface, 0, 0)
                root.check("focused-last-row-is-visible-in-scroll-viewport", menu.opened && point.y >= 0 && point.y + row.height <= menu.surface.height + 1,
                    JSON.stringify({ rowY: point.y, rowHeight: row.height, surfaceHeight: menu.surface.height }))
                menu.close()
                root.entries = root.savedEntries
                root.move(dropdownTrigger, 20, 14)
            } else if (root.step === 68) driver.write("click 272\n")
            else if (root.step === 70) {
                dropdown.pointerDismissEnabled = false
                driver.write("move 500 500\n")
            } else if (root.step === 72) driver.write("click 272\n")
            else if (root.step === 74) {
                root.check("native-compositor-screenshot-saved", root.captureSuccess)
                if (Quickshell.env("PENTAD_HYPRLAND_TEST_RUNTIME")) root.check("outside-click-dismisses-without-pointer-timer", !dropdown.opened)
                else dropdown.close()
                root.manager.open("right", bar.screen.name)
            } else if (root.step === 80) {
                root.check("production-surface-host-opens-with-preloaded-right-component", sideHost.visible
                    && !!root.sideView && !!sideHost.rightContent)
                if (root.sideView) root.move(root.sideView.trigger, 60, 20)
            } else if (root.step === 81) driver.write("click 272\n")
            else if (root.step === 83) {
                root.check("native-click-opens-dropdown-inside-panel", !!root.sideView && root.sideView.popover.opened)
                if (root.sideView && root.sideView.popover.opened) root.move(root.sideView.choice, 60, 20)
            } else if (root.step === 88) {
                root.check("panel-dropdown-hover-keeps-parent-and-child-open", sideHost.visible && root.sideView.popover.opened && root.sideView.choice.hovered)
                driver.write("click 272\n")
            } else if (root.step === 90) {
                root.check("panel-dropdown-action-closes-only-child", root.panelChoiceCount === 1 && !root.sideView.popover.opened
                    && root.manager.isOpen("right", bar.screen.name))
                root.manager.close()
            } else if (root.step === 94) {
                root.entries = []
                root.move(icon, 12, 14)
            } else if (root.step === 95) driver.write("click 273\n")
            else if (root.step === 97) root.move(menu.surface, menu.surface.width / 2, 24)
            else if (root.step === 98) {
                root.entries = [{ text: "Handy v0.9.8" }, { text: "Copy Last Transcript" }]
            } else if (root.step === 102) {
                const row = root.rowPoint(1)
                const point = row.mapToItem(menu.surface, 0, 0)
                root.check("partial-async-menu-fits-all-loaded-rows", menu.opened && point.y >= 0
                    && point.y + row.height <= menu.surface.height - 16,
                    JSON.stringify({ y: point.y, rowHeight: row.height, height: menu.surface.height }))
                root.entries = [
                    { text: "Handy v0.9.8" }, { isSeparator: true }, { text: "Copy Last Transcript" },
                    { isSeparator: true }, { text: "Parakeet TDT 0.6B v3" }, { text: "Unload Model" },
                    { isSeparator: true }, { text: "Settings..." }, { text: "Check for Updates..." },
                    { isSeparator: true }, { text: "Quit" }
                ]
            } else if (root.step === 106) {
                const row = root.rowPoint(10)
                const point = row.mapToItem(menu.surface, 0, 0)
                root.check("handy-sized-async-menu-expands-to-last-row", menu.opened && point.y >= 0
                    && root.lastRowFitsOrMenuFillsOutput(row, point),
                    JSON.stringify({ y: point.y, rowHeight: row.height, height: menu.surface.height }))
                menu.close()
                root.move(icon, 12, 14)
            } else if (root.step === 108) driver.write("click 273\n")
            else if (root.step === 110) root.move(root.rowPoint(0), 60, 15)
            else if (root.step === 112) {
                const row = root.rowPoint(10)
                const point = row.mapToItem(menu.surface, 0, 0)
                root.check("handy-sized-menu-reopens-at-full-height", menu.opened
                    && root.lastRowFitsOrMenuFillsOutput(row, point))
                menu.close()
            } else if (root.step === 114) {
                root.nativeMenu = true
                root.check("private-dbus-tray-fixture-registers", !!root.fixtureTray)
                root.move(icon, 12, 14)
            } else if ([115, 123, 131].includes(root.step)) driver.write("click 273\n")
            else if ([117, 125, 133].includes(root.step)) {
                root.check("dbus-menu-resizes-before-any-pointer-motion-" + root.step,
                    menu.opened && menu.rowRepeater.count === 11 && menu.surface.height >= Math.min(278, bar.screen.height - bar.height),
                    JSON.stringify({ open: menu.opened, rows: menu.rowRepeater.count, height: menu.surface.height,
                        requested: menu.window.implicitHeight }))
                if (root.step === 117 && menu.opened) root.move(root.rowPoint(0), 60, 15)
            } else if ([120, 128, 136].includes(root.step)) {
                const last = menu.rowRepeater.count ? root.rowPoint(menu.rowRepeater.count - 1) : null
                const point = last ? last.mapToItem(menu.surface, 0, 0) : { y: -1000 }
                root.check("dbus-handy-menu-full-height-open-" + root.step, menu.opened && menu.rowRepeater.count === 11
                    && root.lastRowFitsOrMenuFillsOutput(last, point),
                    JSON.stringify({ open: menu.opened, rows: menu.rowRepeater.count, y: point.y, height: menu.surface.height }))
                if (root.step !== 120) {
                    menu.close()
                    root.move(icon, 12, 14)
                }
            } else if (root.step === 121) {
                const row = root.rowPoint(0)
                const local = row.mapToItem(menu.window.contentItem, 60, 15)
                root.check("dbus-resized-menu-mask-delivers-hover-after-grace", menu.opened && row.hovered
                    && menu.window.mask.containsPoint(local.x, local.y),
                    JSON.stringify({ open: menu.opened, hovered: row.hovered,
                        maskContains: menu.window.mask.containsPoint(local.x, local.y), local: local }))
                menu.close()
                root.move(icon, 12, 14)
            } else if (root.step === 138) {
                driver.write("quit\n")
                stop()
                console.log("PENTAD_TEST " + JSON.stringify({ status: root.checks.every(c => c.passed) ? "pass" : "fail", checks: root.checks }))
                Qt.quit()
            }
            root.step++
        }
    }
}
