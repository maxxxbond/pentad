import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.features.bar
import qs.shell

ShellRoot {
    id: root
    property bool previewBlocked: true
    property bool safeModeBlocked: false
    property var activated: []
    property var entries: [
        { text: 'Open', enabled: true, isSeparator: false, hasChildren: false,
            buttonType: QsMenuButtonType.None, checkState: Qt.Unchecked,
            triggered: function() { root.activated = root.activated.concat(['open']); } },
        { text: 'Disabled', enabled: false, isSeparator: false, hasChildren: false,
            buttonType: QsMenuButtonType.None, checkState: Qt.Unchecked,
            triggered: function() { root.activated = root.activated.concat(['disabled']); } },
        { text: 'Checked', enabled: true, isSeparator: false, hasChildren: false,
            buttonType: QsMenuButtonType.CheckBox, checkState: Qt.Checked,
            triggered: function() { root.activated = root.activated.concat(['checked']); } },
        { text: '', enabled: false, isSeparator: true, hasChildren: false,
            buttonType: QsMenuButtonType.None, checkState: Qt.Unchecked },
        { text: 'More', enabled: true, isSeparator: false, hasChildren: true,
            buttonType: QsMenuButtonType.None, checkState: Qt.Unchecked, children: [
                { text: 'Nested action', enabled: true, isSeparator: false, hasChildren: false,
                    buttonType: QsMenuButtonType.RadioButton, checkState: Qt.Checked,
                    triggered: function() { root.activated = root.activated.concat(['nested']); } },
                { text: 'Submore', enabled: true, isSeparator: false, hasChildren: true,
                    buttonType: QsMenuButtonType.None, checkState: Qt.Unchecked, children: [
                        { text: 'Third-level action', enabled: true, isSeparator: false, hasChildren: false,
                            buttonType: QsMenuButtonType.None, checkState: Qt.Unchecked,
                            triggered: function() { root.activated = root.activated.concat(['third']); } }
                    ] }
            ] }
    ]
    property var checks: []
    property TestEvent pointer: TestEvent {}
    property QtObject nativeItem: QtObject {
        readonly property string title: 'Fixture tray item'
        readonly property url icon: Qt.resolvedUrl('assets/icons/material/network-wired-symbolic.svg')
        readonly property bool hasMenu: true
        readonly property var menu: null
        function activate() {}
    }
    property QtObject secondNativeItem: QtObject {
        readonly property string title: 'Second fixture tray item'
        readonly property url icon: Qt.resolvedUrl('assets/icons/material/network-wired-symbolic.svg')
        readonly property bool hasMenu: true
        readonly property var menu: null
        function activate() {}
    }
    property QtObject tray: QtObject {
        readonly property var state: ({ kind: 'ready', value: { items: [{ id: 'fixture-tray' }, { id: 'second-tray' }] } })
        function nativeItemFor(id) {
            return id === 'fixture-tray' ? root.nativeItem : id === 'second-tray' ? root.secondNativeItem : null;
        }
    }
    property QtObject services: QtObject {
        readonly property bool preview: root.previewBlocked
        readonly property bool safeMode: root.safeModeBlocked
        readonly property var tray: root.tray
        readonly property PopupManager popups: PopupManager {}
        function text(uk, en) { return uk; }
    }
    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || '' });
    }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    function findAllNamed(item, name, found) {
        found = found || [];
        if (!item) return found;
        if (item.objectName === name) found.push(item);
        for (const child of item.children || []) findAllNamed(child, name, found);
        return found;
    }
    function report() {
        const passed = checks.every(function(result) { return result.passed; });
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }

    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: 48
        exclusiveZone: 0
        color: 'transparent'
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Item {
            objectName: 'pentad-bar-face'
            anchors.fill: parent
            TrayWidget {
                id: trayWidget
                services: root.services
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int step: 0
        onTriggered: {
            const cell = root.findNamed(trayWidget, 'tray-icon-cell')
            if (step === 0) {
                root.pointer.mouseClick(cell, cell.width / 2, cell.height / 2,
                    Qt.RightButton, Qt.NoModifier, 0)
                root.check('preview-blocks-tray-context-menu', !cell.contextMenu.opened)
                cell.testMenuEntries = root.entries
                root.previewBlocked = false
                root.safeModeBlocked = true
            } else if (step === 1) {
                root.pointer.mouseClick(cell, cell.width / 2, cell.height / 2,
                    Qt.RightButton, Qt.NoModifier, 0)
                root.check('safe-mode-blocks-tray-context-menu', !cell.contextMenu.opened)
                root.safeModeBlocked = false
                cell.testMenuEntries = []
                root.pointer.mouseClick(cell, cell.width / 2, cell.height / 2,
                    Qt.RightButton, Qt.NoModifier, 0)
            } else if (step === 2) {
                const menu = cell.contextMenu
                root.check('right-click-opens-tray-context-menu', menu.opened)
                root.check('native-menu-can-open-before-async-entries-arrive',
                    menu.opened && menu.rowRepeater.count === 0)
                cell.testMenuEntries = root.entries
            } else if (step === 3) {
                const menu = cell.contextMenu
                root.check('async-menu-entries-focus-first-item', menu.opened
                    && menu.rowRepeater.count === 5 && menu.rowRepeater.itemAt(0).button.activeFocus)
                root.check('menu-keeps-disabled-checkable-separator-and-submenu-rows',
                    menu.rowRepeater.count === 5 && !menu.rowRepeater.itemAt(1).button.enabled
                        && menu.rowRepeater.itemAt(2).modelData.checkState === Qt.Checked
                        && menu.rowRepeater.itemAt(3).separator && menu.rowRepeater.itemAt(4).modelData.hasChildren)
                menu.handleRowKey(0, Qt.Key_Down)
                menu.handleRowKey(2, Qt.Key_Down)
                root.check('arrow-navigation-skips-disabled-and-separator-rows',
                    menu.rowRepeater.itemAt(4).button.focus)
                menu.handleRowKey(4, Qt.Key_Right)
            } else if (step === 4) {
                const menu = cell.contextMenu
                const child = menu.activeSubmenu
                root.check('right-arrow-opens-side-submenu', menu.opened && child && child.opened
                    && child.surface !== menu.surface && child.rowRepeater.count === 2
                    && child.rowRepeater.itemAt(0).modelData.text === 'Nested action')
                child.handleRowKey(1, Qt.Key_Right)
            } else if (step === 5) {
                const menu = cell.contextMenu
                const child = menu.activeSubmenu
                root.check('recursive-side-submenu-opens', child && child.activeChild
                    && child.activeChild.opened && child.activeChild.surface !== child.surface
                    && child.activeChild.rowRepeater.count === 1)
                root.services.popups.dismissTop()
            } else if (step === 6) {
                const menu = cell.contextMenu
                root.check('manager-escape-closes-deepest-level-first', menu.opened && menu.activeSubmenu
                    && !menu.activeSubmenu.activeChild && menu.activeSubmenu.opened)
                root.services.popups.dismissTop()
            } else if (step === 7) {
                const menu = cell.contextMenu
                root.check('escape-backs-to-root-panel', menu.opened && !menu.activeSubmenu
                    && menu.rowRepeater.count === 5)
                root.services.popups.closeChild()
            } else if (step === 8) {
                const menu = cell.contextMenu
                root.check('popup-manager-dismissal-closes-entire-branch', !menu.opened
                    && !menu.focusWindows.length && !root.services.popups.childSurface)
                trayWidget.handleTrayKey(cell, Qt.Key_Menu, Qt.NoModifier)
            } else if (step === 9) {
                const menu = cell.contextMenu
                root.check('menu-key-opens-tray-context-menu', menu.opened)
                if (menu.opened) menu.handleRowKey(0, Qt.Key_Escape)
            } else if (step === 10) {
                const menu = cell.contextMenu
                root.check('escape-closes-root-menu', !menu.opened)
                trayWidget.handleTrayKey(cell, Qt.Key_F10, Qt.ShiftModifier)
            } else if (step === 11) {
                const menu = cell.contextMenu
                root.check('shift-f10-opens-tray-context-menu', menu.opened)
                if (!menu.opened || !menu.rowRepeater.itemAt(4)) { root.check('shift-f10-fixture-open', false); stop(); root.report(); return; }
                menu.activateEntry(menu.rowRepeater.itemAt(4).modelData)
            } else if (step === 12) {
                const menu = cell.contextMenu
                root.check('submenu-opens-as-side-panel', menu.opened && menu.activeSubmenu
                    && menu.activeSubmenu.opened && menu.activeSubmenu.rowRepeater.count === 2)
                menu.activeSubmenu.activateEntry(menu.activeSubmenu.rowRepeater.itemAt(0).modelData)
            } else if (step === 13) {
                const menu = cell.contextMenu
                root.check('nested-leaf-triggers-and-closes', root.activated.join(',') === 'nested'
                    && !menu.opened && !menu.activeSubmenu)
                cell.testMenuEntries = root.entries
                root.pointer.mouseClick(cell, cell.width / 2, cell.height / 2,
                    Qt.RightButton, Qt.NoModifier, 0)
            } else if (step === 14) {
                const second = root.findAllNamed(trayWidget, 'tray-icon-cell')[1]
                root.check('first-tray-menu-open-before-sibling', cell.contextMenu.opened)
                second.testMenuEntries = root.entries
                root.pointer.mouseClick(second, second.width / 2, second.height / 2,
                    Qt.RightButton, Qt.NoModifier, 0)
            } else if (step === 15) {
                const second = root.findAllNamed(trayWidget, 'tray-icon-cell')[1]
                root.check('right-click-on-sibling-closes-previous-tray-menu',
                    !cell.contextMenu.opened && second.contextMenu.opened)
                root.check('only-sibling-menu-registered-with-popup-manager',
                    root.services.popups.children.length === 1
                        && root.services.popups.childSurface === second.contextMenu)
                second.contextMenu.close()
                stop()
                root.report()
            }
            step++
        }
    }
}
