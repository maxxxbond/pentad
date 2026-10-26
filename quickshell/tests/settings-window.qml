import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.features.settings
import qs.services
import qs.theme
import "../shell"
import "../logic/config.mjs" as ConfigLogic

ShellRoot {
    id: root

    property TestEvent pointer: TestEvent {}
    property var checks: []
    property var saves: []

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(c) { return c.passed; }) ? "pass" : "fail",
            checks: checks,
        }));
        Qt.quit();
    }
    function findBy(item, predicate) {
        if (!item) return null;
        if (predicate(item)) return item;
        for (const child of item.children || []) {
            const found = root.findBy(child, predicate);
            if (found) return found;
        }
        return null;
    }
    function findNamed(item, name) {
        return root.findBy(item, function(candidate) { return candidate.objectName === name; });
    }
    function lastSave() { return root.saves.length > 0 ? root.saves[root.saves.length - 1] : null; }
    function click(item) {
        root.pointer.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
    }

    QtObject {
        id: fakeConfig
        property var documents: JSON.parse(JSON.stringify(ConfigLogic.defaults))
        signal commandFinished(string requestId, var result)
        function save(name, document) {
            const requestId = "fixture-save-" + (root.saves.length + 1);
            root.saves = root.saves.concat([{ name: name, document: document, requestId: requestId }]);
            return requestId;
        }
        function checkpoint(name) { return "fixture-checkpoint-" + name; }
        function restore(name, id) { return "fixture-restore-" + name; }
    }
    QtObject {
        id: fakePlugins
        property int revision: 0
        property var catalog: ({
            "pentad.weather": { manifest: {
                id: "pentad.weather", name: "Weather", version: "1.0.0", apiVersion: 2, entry: "View.qml",
                allowedSlots: ["sidebar-left", "sidebar-right"], pentads: ["left-menu", "right-menu"],
                settingsFields: [{ key: "units", label: "Units", kind: "select",
                    options: [{ value: "celsius", label: "Celsius" }, { value: "fahrenheit", label: "Fahrenheit" }] }]
            } }
        })
    }
    property string captureBase: Quickshell.env("PENTAD_ARTIFACT_PATH") || ""
    function grab(suffix) {
        if (root.captureBase === "") return;
        const target = root.captureBase + suffix;
        scene.grabToImage(function(result) { root.check("capture" + suffix, result.saveToFile(target), target); });
    }
    function settle(requestId) {
        const entry = root.saves.find(function(candidate) { return candidate.requestId === requestId; });
        if (entry) {
            const docs = JSON.parse(JSON.stringify(fakeConfig.documents));
            docs[entry.name] = entry.document;
            fakeConfig.documents = docs;
        }
        fakeConfig.commandFinished(requestId, { ok: true });
    }
    QtObject {
        id: fakeScreenshot
        signal bindingsExported(var result)
        property int exports: 0
        function openSettings() { return true; }
        function closeSettings() { return true; }
        function exportBindings(fragment) { exports += 1; return true; }
    }
    QtObject {
        id: fakeServices
        property var config: fakeConfig
        property var screenshot: fakeScreenshot
        property var plugins: fakePlugins
        property var settings: controller
        // Device pages borrow preview adapters: no system calls, but the real state shapes.
        readonly property var network: deviceServices.network
        readonly property var audio: deviceServices.audio
        readonly property var power: deviceServices.power
        readonly property var hyprland: deviceServices.hyprland
        readonly property var popups: deviceServices.popups
        property var quickSettings: deviceServices.quickSettings
        readonly property var systemSettings: fakeSystem
        property bool safeMode: true
        function brightnessFor(outputId) { return deviceServices.brightnessFor(outputId); }
        function text(uk, en) { return en; }
    }
    property Services deviceServices: Services { preview: true; safeMode: true }
    // System facts as pentad_system.py would report them; records the reads and writes the pages ask for.
    QtObject {
        id: fakeSystem
        property var calls: []
        property var about: null
        property var time: null
        property var timezones: []
        property var defaultApps: null
        signal commandFinished(string requestId, var result)
        function record(name) { calls = calls.concat([name]); }
        function refreshAbout() {
            record("about");
            about = { ok: true, hostname: "fixture-host", os: "Arch Linux", kernel: "6.18.0", cpu: "Fixture CPU",
                memory: 32768000 * 1024, desktop: "Hyprland", uptime: 3725 };
        }
        function refreshTime() { record("time"); time = { ok: true, timezone: "Europe/Kyiv", ntp: true, canNtp: true, canSet: true }; }
        function loadTimezones() { record("timezones"); timezones = ["America/New_York", "Europe/Kyiv"]; }
        function refreshDefaultApps() {
            record("default-apps");
            defaultApps = { ok: true, categories: [
                { category: "web", current: "firefox.desktop", candidates: [{ id: "firefox.desktop", name: "Firefox" }] },
                { category: "image", current: "", candidates: [{ id: "loupe.desktop", name: "Loupe" }] }] };
        }
        function setTimezone(zone) { record("set-timezone:" + zone); return "system-1"; }
        function setNtp(on) { record("set-ntp:" + on); return "system-2"; }
        function setDefaultApp(category, id) { record("set-app:" + category + ":" + id); return "system-3"; }
    }
    // An adapter with one paired headset and one speaker nearby; records what the page asks for.
    QtObject {
        id: fakeBluetooth
        property var calls: []
        property bool discovering: false
        signal commandFinished(string requestId, var result)
        readonly property var state: ({ kind: "ready", value: {
            bluetooth: true, bluetoothAvailable: true, bluetoothDiscovering: discovering,
            bluetoothDevices: [{ id: "AA", label: "Headset", connected: true, paired: true, pairing: false, battery: 80 }],
            bluetoothNearby: [{ id: "BB", label: "Speaker", connected: false, paired: false, pairing: false, battery: null }]
        } })
        function setBluetoothDiscovering(on) { discovering = on; calls = calls.concat(["scan:" + on]); return true; }
        function toggleBluetoothDevice(id) { calls = calls.concat(["toggle:" + id]); return "bt-1"; }
        function pairBluetoothDevice(id) { calls = calls.concat(["pair:" + id]); return "bt-2"; }
        function forgetBluetoothDevice(id) { calls = calls.concat(["forget:" + id]); return "bt-3"; }
        function toggleBluetooth() { calls = calls.concat(["power"]); return "bt-4"; }
    }
    SettingsController {
        id: controller
        services: fakeServices
    }
    // The real popup manager, to exercise the screenshot capture gate with settings hosts visible.
    PopupManager {
        id: popups
    }

    FloatingWindow {
        id: win
        width: 960
        height: 640
        visible: true
        color: Theme.tokens.surface

        Item {
        id: scene
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
        SettingsSidebar {
            id: sidebar
            x: 0
            y: 0
            width: preferredWidth
            height: parent.height
            services: fakeServices
            collapsed: false
        }
        SettingsPage {
            id: page
            x: sidebar.width + 1
            width: parent.width - x
            height: parent.height
            visible: controller.query === "" && controller.widgetId === "" && !shotDialog.visible
            services: fakeServices
        }
        WidgetSettings {
            id: widgetPage
            x: sidebar.width + 1
            width: parent.width - x
            height: parent.height
            visible: controller.widgetId !== ""
            services: fakeServices
            instanceId: controller.widgetId
            onBack: controller.closeWidget()
        }
        SettingsSearchResults {
            id: results
            x: sidebar.width + 1
            width: parent.width - x
            height: parent.height
            visible: controller.query !== ""
            services: fakeServices
        }
        Loader {
            id: addSheet
            anchors.fill: parent
            z: 10
            active: controller.flow === "add-widget"
            sourceComponent: AddWidgetSheet { services: fakeServices }
        }
        // The screenshot settings dialog body, shown over the page at the end of the run.
        Rectangle {
            id: shotDialog
            visible: false
            anchors.centerIn: parent
            width: 640
            height: 600
            radius: Metrics.radiusPopover
            color: Theme.tokens.surface
            ScreenshotSettings {
                id: shots
                anchors.fill: parent
                services: fakeServices
                ownerVisible: shotDialog.visible
            }
        }

        }

        TestCase {
            id: testCase
            name: "settings-window"
            when: false
            function test_all() {
                wait(50);
                controller.openPage("bar");
                wait(50);
                root.check("open-flag", controller.open === true && controller.pageId === "bar");
                root.grab("");
                wait(300);
                sidebar.collapsed = true;
                wait(300);
                root.grab(".rail.png");
                wait(300);
                sidebar.collapsed = false;
                wait(100);
                root.check("nav-marks-bar-active",
                    root.findNamed(sidebar, "settings-nav-bar").active === true);

                const toggle = root.findBy(page, function(candidate) {
                    return candidate.accessibleName === "Seconds in clock";
                });
                root.check("seconds-toggle-rendered", toggle !== null && toggle.checked === false);
                const secondsField = root.findNamed(page, "settings-field-showSeconds");
                root.check("toggle-row-is-compact", secondsField !== null && secondsField.height === Metrics.settingsRowMinHeight,
                    secondsField ? String(secondsField.height) : "no row");
                if (toggle) toggle.click();
                const save = root.saves.length === 1 ? root.saves[0] : null;
                root.check("toggle-saves-layout", save !== null && save.name === "layout"
                    && save.document.showSeconds === true && save.document.barHeight === 40,
                    JSON.stringify(root.saves));
                root.check("pending-set", controller.pendingId === "fixture-save-1");
                root.settle("fixture-save-1");
                root.check("pending-cleared", controller.pendingId === "");
                root.check("status-saved-after-commit", controller.status === "saved" && page.status === "saved", controller.status);
                root.check("page-counts-modified", page.modifiedCount === 1, String(page.modifiedCount));
                const resetButton = root.findNamed(page, "settings-page-reset");
                root.check("reset-button-visible", resetButton !== null && resetButton.visible === true);
                page.resetRequested();
                root.check("reset-saves-default", root.saves.length === 2 && root.saves[1].document.showSeconds === false,
                    JSON.stringify(root.saves.length));
                root.settle("fixture-save-2");
                root.check("reset-clears-modified", page.modifiedCount === 0, String(page.modifiedCount));
                root.check("reset-offers-no-undo", controller.lastChange === null);
                toggle.click();
                root.settle("fixture-save-3");
                wait(1500);
                root.check("status-offers-undo-after-saved", controller.status === "undo" && page.status === "undo", controller.status);
                page.undoRequested();
                root.check("undo-saves-previous-value", root.saves.length === 4 && root.saves[3].document.showSeconds === false,
                    JSON.stringify(root.saves.length));
                root.settle("fixture-save-4");
                root.check("undo-consumed", controller.lastChange === null && page.modifiedCount === 0);

                controller.openPage("bar-tools");
                wait(100);
                root.check("legacy-bar-tools-id-opens-bar-tools-tab", controller.pageId === "bar" && controller.tabId === "tools",
                    controller.pageId + "/" + controller.tabId);
                const pageTabs = root.findNamed(page, "settings-page-tabs");
                root.check("page-tabs-follow-requested-tab", pageTabs !== null && pageTabs.visible && pageTabs.selectedIndex === 1,
                    pageTabs ? String(pageTabs.selectedIndex) : "no tabs");
                const layoutTab = root.findNamed(page, "settings-page-tab-0");
                if (layoutTab) root.click(layoutTab);
                root.check("page-tab-click-selects-layout", page.tabId === "layout" && pageTabs !== null && pageTabs.selectedIndex === 0,
                    page.tabId);
                const toolsTab = root.findNamed(page, "settings-page-tab-1");
                if (toolsTab) root.click(toolsTab);
                root.check("page-tab-click-selects-tools", page.tabId === "tools" && pageTabs !== null && pageTabs.selectedIndex === 1,
                    page.tabId);
                wait(200);
                root.grab(".tools.png");
                wait(300);
                controller.openPage("bar");
                wait(50);
                controller.openPage("widgets");
                wait(200);
                root.grab(".widgets.png");
                wait(300);
                const weatherCard = root.findNamed(page, "widgetCard_weather-main");
                const glyph = weatherCard ? root.findNamed(weatherCard, "pentadGlyph") : null;
                root.check("widget-card-shows-placement-art", glyph !== null && glyph.visible
                    && JSON.stringify(glyph.zones) === JSON.stringify(["left-menu"]), glyph ? JSON.stringify(glyph.zones) : "no glyph");
                const weatherName = weatherCard ? root.findNamed(weatherCard, "widgetName") : null;
                root.check("widget-card-uses-manifest-name", weatherName !== null && weatherName.text === "Weather", weatherName ? weatherName.text : "no name");
                const weatherModule = weatherCard ? root.findNamed(weatherCard, "widgetModule") : null;
                root.check("widget-card-keeps-module-id-as-caption", weatherModule !== null && weatherModule.visible && weatherModule.text === "pentad.weather");
                const weatherZones = weatherCard ? root.findNamed(weatherCard, "widgetZones") : null;
                root.check("widget-card-names-its-section", weatherZones !== null && weatherZones.text === "Left menu", weatherZones ? weatherZones.text : "no zones");
                const gear = weatherCard ? root.findNamed(weatherCard, "configureButton") : null;
                root.check("widget-card-with-manifest-has-gear", gear !== null && gear.visible === true);
                const plainCard = root.findNamed(page, "widgetCard_clock-main");
                const plainGear = plainCard ? root.findNamed(plainCard, "configureButton") : null;
                root.check("widget-card-without-manifest-has-no-gear", plainGear !== null && plainGear.visible === false);
                const plainName = plainCard ? root.findNamed(plainCard, "widgetName") : null;
                root.check("widget-card-without-manifest-falls-back-to-id", plainName !== null && plainName.text === "pentad.clock");
                root.check("widget-add-card-present", root.findNamed(page, "widgetAddCard") !== null);
                if (gear) gear.clicked();
                wait(100);
                root.check("gear-opens-widget-settings", controller.widgetId === "weather-main");
                controller.closeWidget();
                wait(50);
                controller.openWidget("weather-main");
                wait(100);
                root.check("widget-page-opens", controller.widgetId === "weather-main" && widgetPage.visible && widgetPage.page !== null);
                root.grab(".widget.png");
                wait(300);
                widgetPage.tabId = "placement";
                wait(200);
                const widgetTabs = root.findNamed(widgetPage, "settings-page-tabs");
                root.check("widget-page-tabs-follow-tab-id", widgetTabs !== null && widgetTabs.selectedIndex === 1,
                    widgetTabs ? String(widgetTabs.selectedIndex) : "no tabs");
                root.grab(".placement.png");
                wait(300);
                const picker = root.findBy(widgetPage, function(candidate) {
                    return candidate.accessibleName === "Sections" && typeof candidate.toggle === "function";
                });
                root.check("widget-placement-has-picker", picker !== null);
                if (picker) picker.toggle("right-menu");
                const zoneSave = root.saves.length === 5 ? root.saves[4] : null;
                root.check("picker-saves-zones-under-reserved-key", zoneSave !== null
                    && JSON.stringify(zoneSave.document.widgets[1].settings._zones) === JSON.stringify(["left-menu", "right-menu"]),
                    zoneSave ? JSON.stringify(zoneSave.document.widgets[1].settings._zones) : "no save");
                root.settle("fixture-save-5");
                widgetPage.back();
                wait(50);
                root.check("widget-back-closes", controller.widgetId === "");

                // Switching a widget off from its card writes `enabled` on that placement only.
                wait(100);
                const clockCard = root.findNamed(page, "widgetCard_clock-main");
                const clockToggle = clockCard ? root.findNamed(clockCard, "enableToggle") : null;
                root.check("widget-card-has-enable-switch", clockToggle !== null && clockToggle.checked === true);
                if (clockToggle) clockToggle.click();
                let saved = root.lastSave();
                const clockEntry = saved ? saved.document.widgets.find(function(entry) { return entry.instanceId === "clock-main"; }) : null;
                root.check("widget-switch-saves-enabled-flag", saved !== null && saved.name === "layout" && clockEntry && clockEntry.enabled === false
                    && saved.document.widgets.filter(function(entry) { return entry.enabled === false; }).length === 3,
                    saved ? JSON.stringify(saved.document.widgets.map(function(entry) { return entry.instanceId + ":" + entry.enabled; })) : "no save");
                root.settle(saved.requestId);
                wait(50);
                // The catalog rebuilds its cards from the saved document, so look the card up again.
                const clockCardAfter = root.findNamed(page, "widgetCard_clock-main");
                const clockZones = clockCardAfter ? root.findNamed(clockCardAfter, "widgetZones") : null;
                root.check("widget-card-off-shows-off-label", clockZones !== null && clockZones.text === "Off", clockZones ? clockZones.text : "none");

                // Dragging a card by its grip one column to the right swaps it with its neighbour.
                const firstCard = root.findNamed(page, "widgetCard_workspaces-main");
                const catalog = firstCard ? firstCard.parent : null;
                const grip = firstCard ? root.findNamed(firstCard, "dragHandle") : null;
                root.check("catalog-card-has-grip", grip !== null && catalog !== null && typeof catalog.cardWidth === "number");
                if (grip) {
                    const dx = catalog.cardWidth + catalog.gap;
                    root.pointer.mousePress(grip, grip.width / 2, grip.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                    root.pointer.mouseMove(grip, grip.width / 2 + dx, grip.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                    root.pointer.mouseRelease(grip, grip.width / 2 + dx, grip.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                }
                saved = root.lastSave();
                root.check("dragging-a-card-reorders-placements", saved !== null && saved.name === "layout"
                    && saved.document.widgets[0].instanceId === "weather-main" && saved.document.widgets[1].instanceId === "workspaces-main",
                    saved ? saved.document.widgets.slice(0, 2).map(function(entry) { return entry.instanceId; }).join(",") : "no save");
                root.settle(saved.requestId);
                wait(100);

                // Add a widget: one sheet, one click, then the new widget's own page.
                controller.runAction("widgets.add");
                wait(200);
                root.check("add-sheet-opens", controller.flow === "add-widget" && addSheet.item !== null);
                root.grab(".add.png");
                wait(300);
                const pick = addSheet.item ? root.findNamed(addSheet.item, "widgetPick_pentad.weather") : null;
                root.check("add-sheet-lists-installed-widgets", pick !== null);
                const countBefore = fakeConfig.documents.layout.widgets.length;
                if (pick) root.click(pick);
                saved = root.lastSave();
                const added = saved ? saved.document.widgets[saved.document.widgets.length - 1] : null;
                root.check("picking-a-card-adds-an-instance-in-its-first-section", saved !== null && saved.name === "layout"
                    && saved.document.widgets.length === countBefore + 1 && added !== null && added.instanceId === "weather-1"
                    && added.moduleId === "pentad.weather" && added.slot === "sidebar-left" && added.enabled === true,
                    saved ? JSON.stringify(added) : "no save");
                root.settle(saved.requestId);
                wait(100);
                root.check("added-widget-opens-its-own-page", controller.flow === "" && controller.widgetId === "weather-1"
                    && widgetPage.visible && widgetPage.page !== null, controller.flow + "/" + controller.widgetId);
                controller.closeWidget();
                wait(50);

                controller.setQuery("tray");
                wait(50);
                const hit = root.findNamed(results, "settings-result-bar-trayIcons");
                root.check("search-finds-tray-icons", hit !== null && results.visible && !page.visible);
                if (hit) hit.clicked();
                wait(50);
                root.check("result-opens-page-and-clears-query", controller.pageId === "bar" && controller.query === "");

                controller.setQuery("zzzzqq");
                wait(50);
                const empty = root.findNamed(results, "settings-search-empty");
                root.check("empty-result-shows-icon-only", empty !== null && empty.visible === true);
                controller.setQuery("");

                // Appearance: swatches commit the accent, the font row is a picker.
                controller.openPage("appearance");
                wait(200);
                root.grab(".appearance.png");
                wait(300);
                const fontCurrent = root.findNamed(page, "fontCurrent");
                root.check("font-row-is-a-picker-showing-current-family", fontCurrent !== null && fontCurrent.text === "Geist",
                    fontCurrent ? fontCurrent.text : "no picker");
                const swatch = root.findNamed(page, "colorSwatch_#7C9AB5");
                root.check("accent-swatches-rendered", swatch !== null);
                if (swatch) root.click(swatch);
                saved = root.lastSave();
                root.check("swatch-click-saves-accent", saved !== null && saved.name === "theme" && saved.document.accent === "#7C9AB5",
                    saved ? JSON.stringify(saved.document) : "no save");
                root.settle(saved.requestId);
                wait(50);
                const chip = root.findNamed(page, "colorChip");
                root.check("hex-chip-follows-saved-accent", chip !== null && String(chip.color).toUpperCase() === "#7C9AB5", chip ? String(chip.color) : "no chip");
                const accentField = root.findNamed(page, "settings-field-accent");
                const info = accentField ? root.findNamed(accentField, "settings-row-info") : null;
                root.check("info-button-is-an-icon-not-a-letter", info !== null && info.visible && info.height === 24
                    && root.findBy(info, function(candidate) { return String(candidate.source || "").indexOf("help-symbolic.svg") >= 0; }) !== null,
                    info ? String(info.height) + "/" + info.visible : "no info");

                // Font family: the picker opens a list of installed families; choosing one saves it.
                const fontField = fontCurrent ? fontCurrent.parent : null;
                root.check("font-field-is-a-picker", fontField !== null && typeof fontField.toggle === "function" && fontField.open === false);
                if (fontField) fontField.toggle();
                // Let the popup's enter fade finish before touching its content.
                wait(400);
                const fontList = fontField && fontField.popup ? root.findNamed(fontField.popup.contentItem, "fontList") : null;
                root.check("font-popup-lists-installed-families", fontField !== null && fontField.popup.opened === true && fontList !== null && fontList.count > 1,
                    fontList ? String(fontList.count) + "/" + fontField.popup.opened : "no list");
                const plainFamilies = fontField ? fontField.shown.filter(function(name) { return /^[A-Za-z0-9 ]+$/.test(name) && name !== fontField.value; }) : [];
                const pickFamily = plainFamilies.length > 0 ? plainFamilies[0] : "";
                const pickIndex = fontField ? fontField.shown.indexOf(pickFamily) : -1;
                if (fontList && pickIndex >= 0) { fontList.positionViewAtIndex(pickIndex, ListView.Beginning); wait(200); }
                const fontEntry = fontList && pickIndex >= 0 ? fontList.itemAtIndex(pickIndex) : null;
                root.check("font-entry-rendered", fontEntry !== null, pickFamily);
                if (fontEntry) root.click(fontEntry);
                wait(50);
                saved = root.lastSave();
                root.check("font-pick-saves-family", saved !== null && saved.name === "theme" && saved.document.fontFamily === pickFamily,
                    saved ? JSON.stringify(saved.document.fontFamily) : "no save");
                root.settle(saved.requestId);
                wait(250);
                // `opened` drops as soon as the popup starts closing; `visible` lingers through the fade.
                root.check("font-popup-closes-and-shows-pick", fontField !== null && fontField.popup.opened === false && fontCurrent.text === pickFamily,
                    fontCurrent.text + "/" + (fontField ? fontField.popup.opened : "none"));
                if (fontField) root.click(fontField);
                wait(250);
                const fontClickOpened = fontField !== null && fontField.popup.opened === true;
                if (fontField) root.click(fontField);
                wait(250);
                root.check("font-second-click-closes", fontClickOpened && fontField.popup.opened === false,
                    fontField ? fontClickOpened + "/" + fontField.popup.opened : "no field");
                const fontSettingsField = root.findNamed(page, "settings-field-fontFamily");
                if (fontSettingsField) fontSettingsField.change("Geist");
                saved = root.lastSave();
                root.settle(saved.requestId);
                wait(50);

                // Spotlight: emoji languages are chips; picking one leaves Auto, clearing it returns.
                controller.openPage("spotlight");
                wait(200);
                root.grab(".spotlight.png");
                wait(300);
                const autoChip = root.findNamed(page, "chip_auto");
                const ukChip = root.findNamed(page, "chip_uk");
                root.check("emoji-languages-render-as-chips", autoChip !== null && ukChip !== null && autoChip.checked === true && ukChip.checked === false);
                if (ukChip) root.click(ukChip);
                saved = root.lastSave();
                root.check("chip-click-saves-language-list", saved !== null && saved.name === "spotlight"
                    && JSON.stringify(saved.document.emoji.languages) === JSON.stringify(["uk"]), saved ? JSON.stringify(saved.document) : "no save");
                root.settle(saved.requestId);
                wait(50);
                root.check("chips-reflect-saved-languages", autoChip.checked === false && ukChip.checked === true);
                root.click(ukChip);
                saved = root.lastSave();
                root.check("clearing-last-chip-returns-to-auto", saved !== null && saved.document.emoji.languages === "auto", saved ? JSON.stringify(saved.document) : "no save");
                root.settle(saved.requestId);
                wait(50);

                // Spotlight results: calculator and web rows; the engine row follows the web toggle.
                const engineField = root.findNamed(page, "settings-field-webEngine");
                root.check("spotlight-result-options-render", root.findNamed(page, "settings-field-calculator") !== null
                    && engineField !== null && engineField.visible === true);
                // A second click on a dropdown closes it instead of closing and reopening it.
                const engineBox = engineField ? root.findBy(engineField, function(candidate) {
                    return candidate.accessibleName === "Search engine" && candidate.popup !== undefined;
                }) : null;
                if (engineBox) root.click(engineBox);
                wait(200);
                const engineOpened = engineBox !== null && engineBox.popup.visible === true;
                if (engineBox) root.click(engineBox);
                wait(200);
                root.check("dropdown-second-click-closes", engineOpened && engineBox.popup.visible === false,
                    engineBox ? engineOpened + "/" + engineBox.popup.visible : "no dropdown");
                const webToggle = root.findBy(page, function(candidate) { return candidate.accessibleName === "Web search"; });
                if (webToggle) webToggle.click();
                saved = root.lastSave();
                root.check("web-search-toggle-saves-spotlight", saved !== null && saved.name === "spotlight"
                    && saved.document.webSearch === false && saved.document.webEngine === "duckduckgo", saved ? JSON.stringify(saved.document) : "no save");
                root.settle(saved.requestId);
                wait(50);
                const hiddenEngine = root.findNamed(page, "settings-field-webEngine");
                root.check("engine-row-hides-without-web-search", hiddenEngine === null || hiddenEngine.visible === false);

                // Bar clock options save into the layout document.
                controller.openPage("bar");
                wait(200);
                root.grab(".bar-clock.png");
                wait(300);
                const formatField = root.findNamed(page, "settings-field-clockFormat");
                root.check("clock-options-render", formatField !== null && root.findNamed(page, "settings-field-clockDate") !== null
                    && root.findNamed(page, "settings-field-showBatteryPercent") !== null
                    && root.findNamed(page, "settings-field-workspaceCount") !== null);
                if (formatField) formatField.change("12h");
                saved = root.lastSave();
                root.check("clock-format-saves-layout", saved !== null && saved.name === "layout" && saved.document.clockFormat === "12h",
                    saved ? String(saved.document.clockFormat) : "no save");
                root.settle(saved.requestId);
                wait(50);

                // Notification popups save into the interface document.
                controller.openPage("notifications");
                wait(200);
                root.grab(".notifications.png");
                wait(300);
                const popupField = root.findNamed(page, "settings-field-notificationPopups");
                root.check("popup-options-render", popupField !== null && root.findNamed(page, "settings-field-notificationTimeout") !== null);
                if (popupField) popupField.change(1);
                saved = root.lastSave();
                root.check("popup-count-saves-interface", saved !== null && saved.name === "interface" && saved.document.notificationPopups === 1
                    && saved.document.language === "auto", saved ? JSON.stringify(saved.document) : "no save");
                root.settle(saved.requestId);
                wait(50);

                // Device pages: live panels from the control center, under a new "Devices" group.
                root.check("devices-group-in-sidebar", root.findNamed(sidebar, "settings-nav-network") !== null
                    && root.findNamed(sidebar, "settings-nav-sound") !== null && root.findNamed(sidebar, "settings-nav-power") !== null);
                controller.openPage("network");
                wait(300);
                root.grab(".network.png");
                wait(300);
                const wifiPanel = root.findNamed(page, "settings-panel-wifi");
                const wifiList = root.findNamed(page, "settings-wifi-list");
                root.check("network-page-embeds-wifi-panel", wifiPanel !== null && wifiPanel.visible && wifiPanel.height > 0
                    && root.findNamed(page, "settings-wifi-toggle") !== null && wifiList !== null && wifiList.selectorMode === true,
                    wifiPanel ? String(wifiPanel.height) : "missing");
                controller.openPage("bluetooth");
                wait(300);
                root.grab(".bluetooth.png");
                wait(300);
                const bluetoothToggle = root.findNamed(page, "settings-bluetooth-toggle");
                root.check("bluetooth-page-has-adapter-paired-and-nearby", bluetoothToggle !== null
                    && root.findNamed(page, "settings-panel-bluetooth-devices") !== null
                    && root.findNamed(page, "settings-panel-bluetooth-nearby") !== null);
                // Preview has no adapter: the switch stays off and disabled, and no scan is started.
                root.check("bluetooth-without-adapter-is-inert", bluetoothToggle !== null && bluetoothToggle.checked === false
                    && bluetoothToggle.requestedEnabled === false
                    && deviceServices.quickSettings.state.value.bluetoothDiscovering === false);
                // With an adapter: device rows, battery, actions, and a scan that ends with the page.
                fakeServices.quickSettings = fakeBluetooth;
                controller.openPage("sound");
                wait(100);
                controller.openPage("bluetooth");
                wait(300);
                root.grab(".bluetooth-devices.png");
                wait(300);
                root.check("bluetooth-page-starts-scan", fakeBluetooth.discovering === true, JSON.stringify(fakeBluetooth.calls));
                const pairButton = root.findNamed(page, "settings-bluetooth-action-BB");
                const disconnectButton = root.findNamed(page, "settings-bluetooth-action-AA");
                root.check("bluetooth-rows-offer-pair-and-disconnect", pairButton !== null && pairButton.text === "Pair"
                    && disconnectButton !== null && disconnectButton.text === "Disconnect"
                    && root.findNamed(page, "settings-bluetooth-forget-AA") !== null && root.findNamed(page, "settings-bluetooth-forget-AA").visible
                    && root.findNamed(page, "settings-bluetooth-forget-BB").visible === false,
                    (pairButton ? pairButton.text : "none") + "/" + (disconnectButton ? disconnectButton.text : "none"));
                if (pairButton) root.click(pairButton);
                root.check("bluetooth-pair-calls-service", fakeBluetooth.calls.indexOf("pair:BB") >= 0, JSON.stringify(fakeBluetooth.calls));
                fakeBluetooth.commandFinished("bt-2", { ok: false, reason: "pairing-failed" });
                wait(50);
                const bluetoothRowError = root.findBy(page, function(candidate) {
                    return candidate.objectName === "settings-row-error" && candidate.visible && candidate.text.indexOf("PIN") >= 0;
                });
                root.check("bluetooth-failure-is-explained", bluetoothRowError !== null);
                controller.openPage("sound");
                wait(300);
                root.grab(".sound.png");
                wait(300);
                root.check("bluetooth-scan-stops-with-the-page", fakeBluetooth.discovering === false, JSON.stringify(fakeBluetooth.calls));
                fakeServices.quickSettings = deviceServices.quickSettings;
                root.check("sound-page-embeds-devices-and-mixer", root.findNamed(page, "settings-panel-sound") !== null
                    && root.findNamed(page, "settings-panel-mixer") !== null);
                root.check("mixer-retained-while-shown", deviceServices.audio.mixerConsumers["settings-mixer"] === true,
                    JSON.stringify(deviceServices.audio.mixerConsumers));
                controller.openPage("power");
                wait(300);
                root.grab(".power.png");
                wait(300);
                root.check("mixer-released-after-leaving-sound", deviceServices.audio.mixerConsumers["settings-mixer"] !== true,
                    JSON.stringify(deviceServices.audio.mixerConsumers));
                const battery = root.findNamed(page, "settings-power-battery");
                root.check("power-page-shows-battery-row", root.findNamed(page, "settings-panel-power") !== null && battery !== null
                    && battery.text === "No battery", battery ? battery.text : "missing");
                const brightness = root.findNamed(page, "settings-panel-brightness");
                root.check("power-page-has-brightness-card", brightness !== null && brightness.height > 0,
                    brightness ? String(brightness.height) : "missing");

                // System pages: they read once when opened and write through the service.
                controller.openPage("datetime");
                wait(300);
                root.grab(".datetime.png");
                wait(300);
                const zoneBox = root.findNamed(page, "settings-timezone");
                const ntpToggle = root.findNamed(page, "settings-ntp");
                root.check("datetime-shows-zone-and-ntp", zoneBox !== null && zoneBox.currentText === "Europe/Kyiv"
                    && ntpToggle !== null && ntpToggle.checked === true && fakeSystem.calls.indexOf("timezones") >= 0,
                    (zoneBox ? zoneBox.currentText : "none") + " " + JSON.stringify(fakeSystem.calls));
                root.check("datetime-repeats-clock-format", root.findNamed(page, "settings-field-clockFormat") !== null
                    && root.findNamed(page, "settings-field-firstDayOfWeek") !== null);
                root.check("safe-mode-blocks-system-writes", ntpToggle !== null && ntpToggle.requestedEnabled === false);
                fakeServices.safeMode = false;
                wait(50);
                if (ntpToggle) root.click(ntpToggle);
                root.check("ntp-toggle-writes", fakeSystem.calls.indexOf("set-ntp:false") >= 0, JSON.stringify(fakeSystem.calls));
                fakeSystem.commandFinished("system-2", { ok: false, reason: "denied" });
                wait(50);
                const timeError = root.findBy(page, function(candidate) {
                    return candidate.objectName === "settings-row-error" && candidate.visible && candidate.text === "The system did not allow the change";
                });
                root.check("system-denial-is-explained", timeError !== null);
                fakeServices.safeMode = true;
                controller.openPage("default-apps");
                wait(300);
                root.grab(".default-apps.png");
                wait(300);
                const webBox = root.findNamed(page, "settings-default-app-web");
                const imageBox = root.findNamed(page, "settings-default-app-image");
                root.check("default-apps-show-current-and-unset", webBox !== null && webBox.displayText === "Firefox"
                    && imageBox !== null && imageBox.displayText === "Not set",
                    (webBox ? webBox.displayText : "none") + "/" + (imageBox ? imageBox.displayText : "none"));
                controller.openPage("about");
                wait(300);
                root.grab(".about.png");
                wait(300);
                root.check("about-lists-device-facts", root.findNamed(page, "settings-about-hostname") !== null
                    && root.findBy(page, function(candidate) { return candidate.text === "31.3 GB"; }) !== null
                    && root.findBy(page, function(candidate) { return candidate.text === "1 h 2 min"; }) !== null);

                // Bar menus: speed (built ahead of time) by default, memory on request; saved in interface.
                controller.openPage("system");
                wait(300);
                root.grab(".system.png");
                wait(300);
                const barMenusField = root.findNamed(page, "settings-field-barMenus");
                root.check("bar-menus-row-renders-with-speed-default", barMenusField !== null && barMenusField.visible
                    && fakeConfig.documents.interface.barMenus === "speed"
                    && root.findNamed(barMenusField, "settings-row-info") !== null);
                if (barMenusField) barMenusField.change("memory");
                saved = root.lastSave();
                root.check("bar-menus-saves-interface", saved !== null && saved.name === "interface"
                    && saved.document.barMenus === "memory" && saved.document.language === "auto"
                    && saved.document.notificationPopups === 1, saved ? JSON.stringify(saved.document) : "no save");
                root.settle(saved.requestId);
                wait(50);

                // The sidebar has no footer: nothing promises a theme switch that does not exist yet.
                root.check("sidebar-has-no-footer", root.findNamed(sidebar, "settings-footer") === null
                    && root.findNamed(sidebar, "settings-footer-theme") === null);

                // Capture gate: open settings windows never hold a screenshot back; menus still do.
                let captureReadyCount = 0;
                popups.captureReady.connect(function() { captureReadyCount += 1; });
                popups.hostVisibility("settings", true);
                popups.hostVisibility("screenshot-settings", true);
                popups.prepareCapture();
                wait(50);
                root.check("capture-gate-ignores-open-settings-windows", captureReadyCount === 1, String(captureReadyCount));
                popups.hostVisibility("DP-1/left", true);
                popups.prepareCapture();
                wait(50);
                root.check("capture-gate-still-waits-for-a-menu", captureReadyCount === 1, String(captureReadyCount));
                popups.hostVisibility("DP-1/left", false);
                wait(50);
                root.check("capture-gate-opens-once-the-menu-hides", captureReadyCount === 2, String(captureReadyCount));
                popups.hostVisibility("settings", false);
                popups.hostVisibility("screenshot-settings", false);

                // Screenshots dialog: sections, draft editing, compact editor keys, save.
                shotDialog.visible = true;
                wait(200);
                root.grab(".screenshots.png");
                wait(300);
                const saveButton = root.findNamed(shots, "screenshot-settings-save");
                root.check("screenshot-save-disabled-until-dirty", saveButton !== null && saveButton.enabled === false);
                const brush = root.findNamed(shots, "screenshot-local-brush");
                root.check("editor-keys-render-compact-recorders", brush !== null && brush.compact === true && brush.value === "B");
                if (brush) brush.start();
                wait(0);
                root.pointer.keyClick(Qt.Key_G, Qt.NoModifier, 0);
                root.check("editor-key-accepts-single-letter", shots.draft.localKeys.brush === "G" && brush.recording === false, shots.draft.localKeys.brush);
                const monitor = root.findNamed(shots, "screenshot-global-monitor");
                if (monitor) monitor.start();
                wait(0);
                root.pointer.keyClick(Qt.Key_P, Qt.NoModifier, 0);
                root.check("global-key-requires-modifier", monitor !== null && monitor.recording === true && monitor.errorText !== "" && shots.draft.globalKeys.monitor === "Print");
                root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                root.check("escape-cancels-recording", monitor.recording === false);
                const directory = root.findNamed(shots, "screenshot-directory");
                directory.text = "/tmp/shots";
                directory.textEdited();
                root.check("screenshot-edits-make-draft-dirty", shots.dirty === true && saveButton.enabled === true);
                saveButton.clicked();
                saved = root.lastSave();
                root.check("screenshot-save-writes-document", saved !== null && saved.name === "screenshots"
                    && saved.document.directory === "/tmp/shots" && saved.document.localKeys.brush === "G", saved ? JSON.stringify(saved.document) : "no save");
                root.settle(saved.requestId);
                wait(50);
                root.check("screenshot-save-reports-and-cleans", shots.dirty === false && shots.message === "Settings saved.", shots.message);
                shotDialog.visible = false;
                root.finish();
            }
        }
        Timer {
            interval: 300
            running: true
            repeat: false
            onTriggered: testCase.test_all()
        }
    }
}
