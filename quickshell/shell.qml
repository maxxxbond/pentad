import QtQuick
import QtQml
import Quickshell
import "shell"
import "services"

ShellRoot {
    id: root
    property Services services: Services {
        safeMode: Quickshell.env("PENTAD_SAFE_MODE") === "1"
        preview: Quickshell.env("PENTAD_PREVIEW") === "1"
    }
    WallpaperHost { services: root.services }
    OutputHost { services: root.services }
    IpcBridge { services: root.services }
    NavigationHost { services: root.services }
    SpotlightHost { services: root.services }
    StashHost { services: root.services }
    CheatsheetHost { services: root.services }
    ScreenshotHost { services: root.services }
    Loader {
        active: root.services.screenshot.settingsOpen
        sourceComponent: Component {
            ScreenshotSettingsWindow { services: root.services }
        }
    }
    Loader {
        active: root.services.desktop.magnifierSource !== ""
        sourceComponent: Component {
            MagnifierWindow { services: root.services }
        }
    }
    Loader {
        active: root.services.settings.open
        sourceComponent: Component {
            SettingsWindow { services: root.services }
        }
    }
    Loader {
        active: !root.services.preview && !root.services.safeMode
        sourceComponent: Component { NavigationShortcuts { services: root.services } }
    }
    Loader {
        active: !root.services.preview && !root.services.safeMode
        sourceComponent: Component { ScreenshotShortcuts { services: root.services } }
    }
}
