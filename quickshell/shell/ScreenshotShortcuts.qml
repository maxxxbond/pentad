import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: root
    required property var services
    GlobalShortcut { appid: 'pentad'; name: 'screenshot-edit'; description: 'Screenshot region and annotate'; onPressed: root.services.screenshot.open('edit', '') }
    GlobalShortcut { appid: 'pentad'; name: 'screenshot-copy'; description: 'Screenshot region to clipboard'; onPressed: root.services.screenshot.open('copy', '') }
    GlobalShortcut { appid: 'pentad'; name: 'screenshot-window'; description: 'Screenshot active window'; onPressed: root.services.screenshot.open('window', '') }
    GlobalShortcut { appid: 'pentad'; name: 'screenshot-monitor'; description: 'Screenshot current monitor'; onPressed: root.services.screenshot.open('monitor', '') }
}
