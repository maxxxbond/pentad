import QtQuick
import QtQml
import Quickshell
import qs.theme
import '../shell' as Shell

QtObject {
    id: container
    property bool safeMode: false
    property bool preview: false
    readonly property string apiVersion: "1"
    readonly property var state: ({ kind: "ready", phase: "Q05" })
    property var calendarSources: []
    function text(uk, en) {
        const language = container.config.documents.interface.language;
        if (language === "uk") return uk;
        if (language === "en") return en;
        return Qt.locale().name.toLowerCase().indexOf("uk") === 0 ? uk : en;
    }
    readonly property Hyprland hyprland: Hyprland {
        preview: container.preview
        safeMode: container.safeMode
        overviewDemanded: !!container.navigation && container.navigation.active
    }
    readonly property Audio audio: Audio { preview: container.preview; safeMode: container.safeMode }
    readonly property Power power: Power { preview: container.preview; safeMode: container.safeMode }
    readonly property Network network: Network { preview: container.preview; safeMode: container.safeMode }
    readonly property Session session: Session { preview: container.preview; safeMode: container.safeMode }
    readonly property Weather weather: Weather { preview: container.preview; safeMode: container.safeMode }
    readonly property Chat chat: Chat { preview: container.preview; safeMode: container.safeMode }
    readonly property Tray tray: Tray { services: container }
    readonly property SettingsController settings: SettingsController { services: container }
    readonly property Media media: Media { preview: container.preview; safeMode: container.safeMode }
    readonly property Artwork artwork: Artwork { helperPath: container.config.helperPath; preview: container.preview; safeMode: container.safeMode }
    readonly property Lyrics lyrics: Lyrics { media: container.media; helperPath: container.config.helperPath; preview: container.preview; safeMode: container.safeMode }
    readonly property Visualizer visualizer: Visualizer { preview: container.preview; safeMode: container.safeMode }
    property var brightnessAdapters: ({})
    function brightnessFor(outputId) {
        if (!outputId) return null;
        if (!brightnessAdapters[outputId]) {
            var component = Qt.createComponent('Brightness.qml');
            if (component.status !== Component.Ready) return null;
            var adapter = component.createObject(container, {
                outputId: outputId, preview: container.preview, safeMode: container.safeMode
            });
            if (!adapter) return null;
            brightnessAdapters = Object.assign({}, brightnessAdapters, { [outputId]: adapter });
        }
        return brightnessAdapters[outputId];
    }
    function releaseBrightness(outputId) {
        var adapter = brightnessAdapters[outputId];
        if (!adapter) return;
        var next = Object.assign({}, brightnessAdapters);
        delete next[outputId];
        brightnessAdapters = next;
        adapter.destroy();
    }
    readonly property Desktop desktop: Desktop {
        preview: container.preview
        safeMode: container.safeMode
        screenshotController: container.screenshot
        barTools: container.config.documents.layout.barTools || null
        telemetryEnabled: container.config.documents.layout.widgets.some(function(widget) {
            return widget.enabled && widget.moduleId === 'pentad.telemetry';
        })
    }
    readonly property Shell.PopupManager popups: Shell.PopupManager {}
    readonly property WindowNavigation navigation: WindowNavigation { services: container }
    readonly property Spotlight spotlight: Spotlight { services: container }
    readonly property Screenshot screenshot: Screenshot { services: container }
    property bool workspaceHeld: false
    readonly property QtObject activity: QtObject { property bool karaoke: false }
    readonly property QtObject clock: QtObject {
        readonly property var locale: container.config.documents.interface.language === 'uk' ? Qt.locale('uk_UA')
            : container.config.documents.interface.language === 'en' ? Qt.locale('en_US') : Qt.locale()
        readonly property date date: systemClock.date
        readonly property var state: ({ kind: 'ready', value: { date: systemClock.date } })
        property SystemClock systemClock: SystemClock {
            enabled: !container.preview
            precision: SystemClock.Minutes
        }
    }
    readonly property Config config: Config {
        preview: container.preview || container.safeMode
        onDocumentChanged: function(name) {
            if (name === 'theme') Theme.resolve(documents.theme);
            if (name === 'layout') container.plugins.reconcile(documents.layout.widgets || []);
        }
    }
    readonly property Organizer organizer: Organizer {
        config: container.config
        calendarSources: container.calendarSources
    }
    readonly property Notifications notifications: Notifications {
        config: container.config
        preview: container.preview
        safeMode: container.safeMode
    }
    readonly property Overnight overnight: Overnight {
        services: container
        preview: container.preview
        safeMode: container.safeMode
    }
    readonly property QuickSettings quickSettings: QuickSettings {
        preview: container.preview
        safeMode: container.safeMode
    }
    readonly property SystemSettings systemSettings: SystemSettings {
        config: container.config
        preview: container.preview
        safeMode: container.safeMode
    }
    readonly property Shelf shelf: Shelf {
        config: container.config
        preview: container.preview
        safeMode: container.safeMode
    }
    readonly property StashController stash: StashController {
        config: container.config
        preview: container.preview
        safeMode: container.safeMode
    }
    readonly property CheatsheetController cheatsheet: CheatsheetController {}
    readonly property Keybinds keybinds: Keybinds {
        preview: container.preview
        safeMode: container.safeMode
        active: container.cheatsheet.open
    }
    readonly property ToolWorkspace toolWorkspace: ToolWorkspace {}
    readonly property FileInput fileInput: FileInput {
        helperPath: container.config.helperPath.replace(/pentad-files\.py$/, 'pentad_read_input.py')
    }
    readonly property FileTools fileTools: FileTools {
        helperPath: container.config.helperPath.replace(/pentad-files\.py$/, 'pentad_file_tool.py')
    }
    readonly property FilePicker filePicker: FilePicker {
        helperPath: container.config.helperPath.replace(/pentad-files\.py$/, 'pentad_pick_files.py')
        popups: container.popups
        workspace: container.toolWorkspace
    }
    readonly property Wallpaper wallpaper: Wallpaper {
        config: container.config
        preview: container.preview
        safeMode: container.safeMode
        filePicker: container.filePicker
        helperPath: container.config.helperPath.replace(/pentad-files\.py$/, 'pentad_recolor_wallpaper.py')
    }
    readonly property ToolPreviews toolPreviews: ToolPreviews {
        helperPath: container.config.helperPath.replace(/pentad-files\.py$/, 'pentad_shelf_preview.py')
    }
    readonly property Plugins plugins: Plugins {
        safeMode: container.safeMode
        services: container
        onChanged: reconcile(container.config.documents.layout.widgets || [])
    }
}
