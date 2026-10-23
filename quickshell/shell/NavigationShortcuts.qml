import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: root
    required property var services
    GlobalShortcut { appid: 'pentad'; name: 'search-release'; description: 'Search applications on bare Super release'; onReleased: { if (root.services.navigation.bareSuperTap()) root.services.spotlight.toggle(); } }
    GlobalShortcut { appid: 'pentad'; name: 'search'; description: 'Toggle application search'; onPressed: root.services.spotlight.toggle() }
    GlobalShortcut { appid: 'pentad'; name: 'overview'; description: 'Toggle workspace overview'; onPressed: root.services.navigation.toggleOverview() }
    GlobalShortcut { appid: 'pentad'; name: 'stash'; description: 'Toggle Stash'; onPressed: root.services.stash.toggle() }
    GlobalShortcut { appid: 'pentad'; name: 'window-next'; description: 'Next window'; onPressed: root.services.navigation.beginSwitcher('all', 1) }
    GlobalShortcut { appid: 'pentad'; name: 'window-previous'; description: 'Previous window'; onPressed: root.services.navigation.beginSwitcher('all', -1) }
    GlobalShortcut { appid: 'pentad'; name: 'application-next'; description: 'Next application window'; onPressed: root.services.navigation.beginSwitcher('application', 1) }
    GlobalShortcut { appid: 'pentad'; name: 'application-previous'; description: 'Previous application window'; onPressed: root.services.navigation.beginSwitcher('application', -1) }
    GlobalShortcut { appid: 'pentad'; name: 'super-left'; description: 'Observe left Super'; onPressed: root.services.navigation.modifier('Super_L', true); onReleased: root.services.navigation.modifier('Super_L', false) }
    GlobalShortcut { appid: 'pentad'; name: 'super-right'; description: 'Observe right Super'; onPressed: root.services.navigation.modifier('Super_R', true); onReleased: root.services.navigation.modifier('Super_R', false) }
    GlobalShortcut { appid: 'pentad'; name: 'alt-left'; description: 'Observe left Alt'; onPressed: root.services.navigation.modifier('Alt_L', true); onReleased: root.services.navigation.modifier('Alt_L', false) }
    GlobalShortcut { appid: 'pentad'; name: 'alt-right'; description: 'Observe right Alt'; onPressed: root.services.navigation.modifier('Alt_R', true); onReleased: root.services.navigation.modifier('Alt_R', false) }
}
