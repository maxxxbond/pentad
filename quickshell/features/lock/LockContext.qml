pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.theme
import '../../logic/config.mjs' as Config
import '../../logic/wallpaper.mjs' as WallpaperLogic
import '../../logic/lock-screen.mjs' as LockLogic

// What every lock surface reads: theme, language, wallpaper, keyboard state and the power
// actions logind allows without asking. It reads Pentad's config documents and never writes.
Scope {
    id: root

    // A fixture sets this: no files, processes or compositor events.
    property bool preview: false
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configRoot: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/pentad"
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    readonly property string facePath: home !== "" ? home + "/.face" : ""
    property bool hasFace: false

    property string language: "auto"
    readonly property bool ukrainian: LockLogic.ukrainian(language, Qt.locale().name)
    // Dates follow the interface language, not LC_TIME, so they never mix with other text.
    readonly property var locale: Qt.locale(ukrainian ? "uk_UA" : "en_US")
    property var wallpaperDocument: WallpaperLogic.wallpaperDefaults

    property bool capsLock: false
    property string layout: ""
    // Set while a lock surface is shown: Caps Lock has no event, so its LED is re-read each second.
    property bool watchKeyboard: false
    property var ledPaths: []

    property var power: ({ suspend: false, reboot: false, poweroff: false })

    function text(uk: string, en: string): string {
        return ukrainian ? uk : en;
    }

    function wallpaperFor(output: string): string {
        return WallpaperLogic.expandHome(WallpaperLogic.wallpaperFor(wallpaperDocument, output), home);
    }

    function runPower(action: string): void {
        const command = LockLogic.powerCommand(action);
        if (!preview && command && root.power[action])
            Quickshell.execDetached(command);
    }

    function applyDocument(name: string, source: string): void {
        const parsed = Config.parseDocument(name, source);
        if (!parsed.ok)
            return;
        if (name === "theme")
            Theme.resolve(parsed.value);
        else if (name === "interface")
            root.language = ["uk", "en"].includes(parsed.value.language) ? parsed.value.language : "auto";
        else if (name === "wallpaper")
            root.wallpaperDocument = parsed.value;
    }

    function applyDevices(source: string): void {
        let keyboards;
        try {
            keyboards = JSON.parse(source).keyboards;
        } catch (error) {
            return;
        }
        if (!Array.isArray(keyboards) || keyboards.length === 0)
            return;
        const keyboard = keyboards.find(item => item.main) || keyboards[0];
        const names = String(keyboard.layout || "").split(",");
        const code = names[keyboard.active_layout_index] || "";
        root.layout = code !== "" ? code.toUpperCase() : String(keyboard.active_keymap || "");
    }

    Variants {
        model: root.preview ? [] : ["theme", "interface", "wallpaper"]
        FileView {
            required property string modelData
            path: root.configRoot + "/" + modelData + ".json"
            blockLoading: true
            printErrors: false
            onLoaded: root.applyDocument(modelData, text())
        }
    }

    FileView {
        path: root.preview || root.facePath === "" ? "" : root.facePath
        blockLoading: true
        printErrors: false
        onLoaded: root.hasFace = true
    }

    Process {
        id: devices
        running: !root.preview
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: root.applyDevices(text)
        }
    }

    Connections {
        target: root.preview ? null : Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout" && !devices.running)
                devices.running = true;
        }
    }

    Process {
        running: !root.preview
        command: ["find", "/sys/class/leds/", "-maxdepth", "1", "-name", "*::capslock"]
        stdout: StdioCollector {
            onStreamFinished: root.ledPaths = text.split("\n").filter(line => line.length > 0).map(line => line + "/brightness")
        }
    }

    Instantiator {
        id: leds
        model: root.ledPaths
        delegate: FileView {
            required property string modelData
            path: modelData
            blockLoading: true
            printErrors: false
        }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.watchKeyboard && root.ledPaths.length > 0
        onTriggered: {
            let on = false;
            for (let index = 0; index < leds.count; index++) {
                const led = leds.objectAt(index);
                if (!led)
                    continue;
                led.reload();
                const value = led.text().trim();
                if (value !== "" && value !== "0")
                    on = true;
            }
            root.capsLock = on;
        }
    }

    Variants {
        model: root.preview ? [] : LockLogic.powerActions
        Process {
            required property string modelData
            running: true
            command: LockLogic.powerCapabilityCommand(modelData)
            stdout: StdioCollector {
                onStreamFinished: {
                    const next = Object.assign({}, root.power);
                    next[modelData] = LockLogic.powerAllowed(text);
                    root.power = next;
                }
            }
        }
    }
}
