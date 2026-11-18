pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/quick-settings.mjs" as Rules
import "../../logic/control-model.mjs" as Controls

Item {
    id: root
    required property var services
    property var brightness: null
    // The level sliders that are on the grid right now, by definition id.
    property var levelControls: ({})
    readonly property var quickSettings: services.quickSettings
    readonly property var quickState: quickSettings ? quickSettings.state : ({ kind: "unavailable" })
    readonly property var tiles: makeTiles()
    signal detailsRequested(string section)

    // The quick settings service refreshes periodically only while a grid is on screen.
    property var heldQuickSettings: null
    function holdQuickSettings(on) {
        const service = on ? quickSettings : heldQuickSettings;
        if (!service || typeof service.acquire !== "function") return;
        if (on) service.acquire(root);
        else service.release(root);
        heldQuickSettings = on ? service : null;
    }
    onVisibleChanged: holdQuickSettings(visible)
    Component.onCompleted: holdQuickSettings(visible)
    Component.onDestruction: holdQuickSettings(false)

    property var menuLayout: services.config.documents.layout.controlCenter || Controls.defaultQuickMenu
    property string pendingSave: ""
    property string menuError: ""
    property string tailscaleRequest: ""
    property string tailscaleError: ""
    property string themeRequest: ""
    property var contextControl: null
    property var contextPlacement: null
    readonly property var contextInfo: contextPlacement
        ? tiles.find(function(tile) { return tile.key === contextPlacement.definitionId; }) || ({}) : ({})
    readonly property var contextDefinition: contextPlacement ? definitionFor(contextPlacement.definitionId) : null
    readonly property var normalizedMenu: Controls.validateMenuLayout(menuLayout)
    readonly property alias menuGrid: grid

    // Editing works on a draft: every move, resize and column change is live, and the
    // draft is saved once when editing ends, so a half-finished drag never reaches the config.
    property bool editing: false
    property var draft: null
    readonly property var savedMenu: normalizedMenu.ok ? Controls.withLevelControls(normalizedMenu.value) : Controls.defaultQuickMenu
    readonly property var activeMenu: editing && draft ? draft : savedMenu
    readonly property int chosenColumns: Controls.menuColumns(activeMenu)
    readonly property int displayColumns: width >= 280 ? chosenColumns : Math.min(2, chosenColumns)
    readonly property var quickKeys: Controls.defaultQuickMenu.items.map(function(item) { return item.definitionId; })
    readonly property var hiddenTiles: quickKeys.filter(function(key) {
        return !activeMenu.items.some(function(item) { return item.definitionId === key && item.visible !== false; });
    }).map(function(key) { return tiles.find(function(tile) { return tile.key === key; }); }).filter(Boolean)
    readonly property real editBarHeight: editing ? Metrics.controlMedium + 8 : 0
    readonly property real trayHeight: editing ? trayArea.trayImplicitHeight + 12 : 0
    implicitHeight: editBarHeight + grid.implicitHeight + trayHeight

    function makeTiles() {
        const t = function(uk, en) { return services.text(uk, en); };
        const ready = quickState.kind === "ready" ? quickState.value : ({});
        const networkState = services.network ? services.network.state : ({ kind: "unavailable" });
        const wifi = Rules.wifiTileState(networkState, t);
        const desktopState = services.desktop ? services.desktop.state : ({ value: {} });
        const notifyState = services.notifications ? services.notifications.state : ({});
        const profileState = services.power ? services.power.profileState : ({ kind: "unavailable" });
        const themeDocument = services.config.documents.theme || ({});
        const screenshot = services.screenshot || null;
        const bluetoothAvailable = ready.bluetoothAvailable === true;
        const vpnProfiles = ready.vpns || [];
        const vpn = vpnProfiles.find(function(item) { return item.active; }) || vpnProfiles[0];
        const profiles = profileState.kind === "ready" ? profileState.value.profiles : [];
        const actual = profileState.kind === "ready" ? profileState.value.actual : "";
        const overnight = services.overnight || null;
        const overnightOn = !!overnight && overnight.active === true;
        const overnightEnd = overnightOn && overnight.endsAt > 0 ? Qt.formatTime(new Date(overnight.endsAt), "HH:mm") : "";
        return [
            { key: "tailscale", title: "Tailscale", subtitle: services.desktop && services.desktop.tailscaleAvailable ? t("Відкрити Trayscale", "Open Trayscale") : t("Trayscale недоступний", "Trayscale unavailable"), icon: "shield-symbolic.svg", available: !!services.desktop && services.desktop.tailscaleAvailable === true, active: false, pending: !!tailscaleRequest, error: tailscaleError },
            { key: "network", title: "Wi-Fi", subtitle: wifi.subtitle, icon: "controls/wifi-symbolic.svg", available: wifi.available && !services.network.safeMode, active: wifi.active, pending: services.network && !!services.network.operation, section: "network" },
            { key: "bluetooth", title: "Bluetooth", subtitle: bluetoothAvailable ? (ready.bluetooth ? ((ready.bluetoothDevices || []).find(function(item) { return item.connected; })?.label || t("Не підключено", "Not connected")) : "") : t("Недоступно", "Unavailable"), icon: "controls/bluetooth-symbolic.svg", available: bluetoothAvailable, active: ready.bluetooth === true, pending: ready.busy && quickSettings.operation && (quickSettings.operation.kind === "bluetooth" || quickSettings.operation.kind === "bluetooth-device"), error: ready.errorSetting === "bluetooth" ? ready.error : "", section: "bluetooth" },
            { key: "vpn", title: "VPN", subtitle: vpn ? vpn.name : t("Немає збережених профілів VPN", "No saved VPN"), icon: "controls/vpn-key-symbolic.svg", available: vpnProfiles.length > 0, active: !!vpn && vpn.active, pending: ready.busy && quickSettings.operation && quickSettings.operation.kind === "vpn", error: ready.errorSetting === "vpn" ? ready.error : "", section: "vpn", vpns: vpnProfiles },
            { key: "airplane", title: t("У літаку", "Airplane mode"), subtitle: ready.airplaneAvailable === true ? "" : t("Недоступно", "Unavailable"), icon: "controls/flight-symbolic.svg", available: ready.airplaneAvailable === true, active: ready.airplane === true, pending: ready.busy && quickSettings.operation && quickSettings.operation.kind === "airplane", error: ready.errorSetting === "airplane" ? ready.error : "" },
            { key: "inhibit", title: t("Не засинати", "Keep awake"), subtitle: "", icon: "controls/coffee-symbolic.svg", available: !!services.desktop && !services.desktop.preview && !services.desktop.safeMode, active: !!(desktopState.value && desktopState.value.inhibited), pending: !!(services.desktop && services.desktop.inhibitRequest) },
            { key: "overnight", title: t("Нічний режим", "Overnight mode"), subtitle: !overnightOn ? "" : overnightEnd ? t("До " + overnightEnd, "Until " + overnightEnd) : t("До вимкнення", "Until turned off"), icon: "controls/bedtime-symbolic.svg", available: !!overnight && overnight.available === true, active: overnightOn, pending: !!overnight && overnight.pending === true },
            { key: "night", title: t("Нічне світло", "Night light"), subtitle: ready.nightAvailable ? "" : t("Недоступно", "Unavailable"), icon: "controls/dark-mode-symbolic.svg", available: ready.nightAvailable === true, active: ready.night === true, pending: ready.busy && quickSettings.operation && quickSettings.operation.kind === "night", error: ready.errorSetting === "night" ? ready.error : "" },
            { key: "dnd", title: t("Не турбувати", "Do not disturb"), subtitle: notifyState.status === "available" ? "" : notifyState.status === "another-server" ? t("Інша служба", "Other service") : t("Немає служби", "No service"), reason: notifyState.status === "another-server" ? t("Сповіщеннями керує інша служба", "Another service manages notifications") : t("Служба сповіщень недоступна", "Notification service unavailable"), icon: "controls/notifications-off-symbolic.svg", available: notifyState.status === "available", active: notifyState.status === "available" && notifyState.dnd === true, pending: false },
            { key: "energy", title: t("Енергія", "Energy"), subtitle: actual ? profileLabel(actual) : t("Немає служби", "No service"), icon: actual === "power-saver" || actual === "powersave" ? "controls/eco-symbolic.svg" : "controls/speed-symbolic.svg", available: profiles.length > 0, active: false, pending: profileState.kind === "ready" && profileState.value.pending, section: "energy" },
            { key: "appearance", title: t("Темна тема", "Dark theme"), subtitle: themeDocument.appearance === "light" ? t("Вимкнено", "Off") : t("Увімкнено", "On"), icon: "controls/contrast-symbolic.svg", available: !services.preview, active: themeDocument.appearance !== "light", pending: !!themeRequest },
            { key: "screenshot", title: t("Скриншот", "Screenshot"), subtitle: "", icon: "controls/screenshot-region-symbolic.svg", available: !!screenshot && !screenshot.active && !screenshot.busy, active: false, pending: false },
            { key: "brightness", title: t("Яскравість", "Brightness"), subtitle: "", icon: "controls/light-mode-symbolic.svg", available: true, active: false, pending: false },
            { key: "audio-output", title: t("Гучність", "Volume"), subtitle: "", icon: "volume-up-symbolic.svg", available: true, active: false, pending: false },
            { key: "audio-input", title: t("Мікрофон", "Microphone"), subtitle: "", icon: "media/mic-symbolic.svg", available: true, active: false, pending: false },
        ];
    }

    function openTailscale() {
        if (!services.desktop || tailscaleRequest) return;
        tailscaleError = "";
        tailscaleRequest = services.desktop.command("tailscale") || "";
    }

    function activate(tile) {
        const action = Rules.actionForTile(tile.key, tile);
        if (!action) return;
        if (action.kind === "desktop") openTailscale();
        else if (action.kind === "wifi") services.network.setWifiEnabled(action.enabled);
        else if (action.kind === "details") detailsRequested(action.section);
        else if (action.kind === "toggle" && action.setting === "bluetooth") quickSettings.toggleBluetooth();
        else if (action.kind === "toggle" && action.setting === "airplane") quickSettings.toggleAirplane();
        else if (action.kind === "toggle" && action.setting === "night") quickSettings.toggleNight();
        else if (action.kind === "vpn") quickSettings.toggleVpn(action.uuid);
        else if (action.kind === "inhibit") services.desktop.command("inhibit");
        else if (action.kind === "overnight") services.overnight.toggle();
        else if (action.kind === "dnd") services.notifications.setDnd(action.enabled);
        else if (action.kind === "appearance" && !themeRequest)
            themeRequest = services.config.save("theme", Object.assign({}, services.config.documents.theme,
                { appearance: action.appearance })) || "";
        else if (action.kind === "screenshot") {
            // Let the drawer slide away first so it is not in the captured frame.
            if (services.popups) services.popups.close();
            screenshotDelay.restart();
        }
    }

    function profileLabel(profile) {
        if (profile === "balanced") return root.services.text("Збалансований", "Balanced");
        if (profile === "performance") return root.services.text("Продуктивність", "Performance");
        if (profile === "power-saver" || profile === "powersave") return root.services.text("Енергозбереження", "Power saver");
        return profile;
    }

    function definitionFor(key) {
        const info = tiles.find(function(tile) { return tile.key === key; });
        return info ? Controls.controlDefinition(key, {
            label: info.title,
            icon: Qt.resolvedUrl("../../assets/icons/material/" + info.icon).toString()
        }) : null;
    }

    function stateFor(key) {
        const info = tiles.find(function(tile) { return tile.key === key; }) || ({});
        return { available: info.available === true, active: info.active === true,
            pending: info.pending === true, error: info.error || "", subtitle: info.subtitle || "",
            unavailableReason: info.available ? "" : info.reason || info.subtitle || "",
            choices: [], selectedId: "" };
    }

    function showContext(control, placement) {
        if (editing) return;
        const sameTrigger = contextControl === control;
        contextControl = control;
        contextPlacement = placement;
        menuError = "";
        if (contextMenu.opened && !sameTrigger) contextMenu.open();
        else contextMenu.toggle();
    }

    function saveMenu(menu) {
        const checked = Controls.validateMenuLayout(menu);
        if (!checked.ok) { menuError = checked.errors.join("; "); return false; }
        pendingSave = services.config.save("layout", Object.assign({}, services.config.documents.layout,
            { controlCenter: checked.value }));
        return true;
    }

    function savePlacement(patch) {
        if (!contextPlacement || pendingSave) return;
        saveMenu(Object.assign({}, savedMenu, { items: savedMenu.items.map(function(item) {
            return item.instanceId === contextPlacement.instanceId ? Object.assign({}, item, patch) : item;
        }) }));
    }

    function changeTemplate(template) {
        if (!Controls.supportsTemplate(contextDefinition, template)) return;
        const span = Controls.defaultSpan(template);
        if (template !== "icon") span.columnSpan = template === "row" ? chosenColumns
            : Controls.minimumTemplateColumns(template, chosenColumns);
        savePlacement(Object.assign({ template: template }, span));
    }

    function changeSize(columns, rows) {
        savePlacement({ columnSpan: columns, rowSpan: rows });
    }

    // A level slider's own menu switches between a full flat line and an upright capsule.
    function setLevelTemplate(instanceId, template) {
        const span = template === "range-vertical" ? { columnSpan: 1, rowSpan: 3 } : { columnSpan: chosenColumns, rowSpan: 1 };
        const update = function(items) {
            return items.map(function(item) {
                return item.instanceId === instanceId ? Object.assign({}, item, { template: template }, span) : item;
            });
        };
        if (editing && draft) setDraftItems(update(draft.items));
        else if (!pendingSave) saveMenu(Object.assign({}, savedMenu, { items: update(savedMenu.items) }));
    }

    function registerLevel(key, control) {
        const next = Object.assign({}, levelControls);
        next[key] = control;
        levelControls = next;
    }

    function unregisterLevel(key, control) {
        if (levelControls[key] !== control) return;
        const next = Object.assign({}, levelControls);
        delete next[key];
        levelControls = next;
    }

    function resetLayout() {
        if (pendingSave) return;
        if (editing) {
            draft = JSON.parse(JSON.stringify(Controls.defaultQuickMenu));
            return;
        }
        pendingSave = services.config.save("layout", Object.assign({}, services.config.documents.layout,
            { controlCenter: Controls.defaultQuickMenu }));
    }

    function beginEdit() {
        if (editing) return;
        contextMenu.close();
        menuError = "";
        draft = JSON.parse(JSON.stringify(Object.assign({ columns: chosenColumns }, savedMenu)));
        editing = true;
    }

    function finishEdit() {
        if (!editing) return;
        const value = draft;
        grid.draggingId = "";
        editing = false;
        draft = null;
        if (value && (value.columns !== Controls.menuColumns(savedMenu)
            || JSON.stringify(value.items) !== JSON.stringify(savedMenu.items)))
            saveMenu(value);
    }

    function setDraftItems(items) {
        if (!draft) return;
        draft = { version: 1, columns: draft.columns, items: items };
    }

    function setColumns(columns) {
        if (!editing || !draft || draft.columns === columns) return;
        draft = Controls.rescaleMenu(draft, columns);
    }

    function resizeItem(instanceId, columns, rows) {
        if (!draft) return;
        const definitions = Controls.builtinDefinitions;
        setDraftItems(draft.items.map(function(item) {
            return item.instanceId === instanceId
                ? Controls.resizePlacement(item, definitions[item.definitionId], columns, rows, draft.columns) : item;
        }));
    }

    function moveItem(instanceId, row, column) {
        if (!draft) return;
        const index = Controls.dropIndex(draft.items, grid.resolvedLayout.items, row, column, draft.columns, instanceId);
        const next = Controls.moveItem(draft.items, instanceId, index);
        if (next.map(function(item) { return item.instanceId; }).join() !== draft.items.map(function(item) { return item.instanceId; }).join())
            setDraftItems(next);
    }

    function stepItem(instanceId, delta) {
        if (!draft) return;
        const index = draft.items.findIndex(function(item) { return item.instanceId === instanceId; });
        if (index >= 0) setDraftItems(Controls.moveItem(draft.items, instanceId, index + delta));
    }

    function hideItem(instanceId) {
        if (draft) setDraftItems(Controls.setItemVisible(draft.items, instanceId, false));
    }

    function addItem(definitionId) {
        if (draft) setDraftItems(Controls.addControl(draft.items, definitionId, draft.columns));
    }

    Timer {
        id: screenshotDelay
        interval: Motion.longDuration
        onTriggered: if (root.services.screenshot) root.services.screenshot.open("edit", "")
    }

    Connections {
        target: root.services.desktop
        function onCommandFinished(requestId, result) {
            if (!root.tailscaleRequest || requestId !== root.tailscaleRequest) return;
            root.tailscaleRequest = "";
            root.tailscaleError = result.ok ? "" : root.services.text("Не вдалося відкрити Trayscale", "Could not open Trayscale");
            if (result.ok && root.services.popups) root.services.popups.close();
        }
    }

    Connections {
        target: root.services.config
        function onCommandFinished(requestId, result) {
            if (requestId === root.themeRequest) { root.themeRequest = ""; return; }
            if (requestId !== root.pendingSave) return;
            root.pendingSave = "";
            root.menuError = result.ok ? "" : result.message || result.reason;
            if (result.ok) contextMenu.close();
        }
    }

    QuickSettingsEditBar {
        id: editBar
        width: root.width
        height: Math.max(0, root.editBarHeight - 8)
        services: root.services
        editing: root.editing
        chosenColumns: root.chosenColumns
        onColumnsRequested: function(columns) { root.setColumns(columns); }
        onResetRequested: root.resetLayout()
        onDoneRequested: root.finishEdit()
    }

    MenuGrid {
        id: grid
        y: root.editBarHeight
        width: root.width
        columns: root.displayColumns
        cellHeight: 48
        spacing: 8
        editing: root.editing
        placements: root.activeMenu.items
        Behavior on y { NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
        delegate: Component {
            FocusScope {
                id: cell
                property var placement: ({ definitionId: "", template: "icon" })
                readonly property bool level: Controls.levelControlIds.indexOf(placement.definitionId) >= 0
                readonly property bool lifted: grid.draggingId === placement.instanceId || resizeArea.pressed
                objectName: "control-center-edit-cell-" + placement.instanceId
                activeFocusOnTab: root.editing
                scale: lifted ? 1.03 : root.editing ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutBack } }
                Accessible.role: root.editing ? Accessible.Grouping : Accessible.NoRole
                Accessible.name: root.editing ? tile.label : ""
                Accessible.description: root.editing ? root.services.text(
                    "Перетягніть або стрілками змініть місце; Shift зі стрілками змінює розмір; Delete ховає",
                    "Drag or use arrows to move; Shift with arrows resizes; Delete hides") : ""
                Keys.enabled: root.editing
                Keys.onPressed: function(event) {
                    const id = cell.placement.instanceId;
                    const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                    if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) root.hideItem(id);
                    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.finishEdit();
                    else if (shift && event.key === Qt.Key_Right) root.resizeItem(id, cell.placement.columnSpan + 1, cell.placement.rowSpan);
                    else if (shift && event.key === Qt.Key_Left) root.resizeItem(id, cell.placement.columnSpan - 1, cell.placement.rowSpan);
                    else if (shift && event.key === Qt.Key_Down) root.resizeItem(id, cell.placement.columnSpan, cell.placement.rowSpan + 1);
                    else if (shift && event.key === Qt.Key_Up) root.resizeItem(id, cell.placement.columnSpan, cell.placement.rowSpan - 1);
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) root.stepItem(id, 1);
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) root.stepItem(id, -1);
                    else return;
                    event.accepted = true;
                }

                PentadControl {
                    id: tile
                    readonly property var info: root.tiles.find(function(item) { return item.key === cell.placement.definitionId; }) || ({})
                    anchors.fill: parent
                    visible: !cell.level
                    popupManager: root.services.popups || null
                    contextOpened: contextMenu.opened && root.contextControl === tile
                    definition: root.definitionFor(cell.placement.definitionId)
                    controlState: {
                        const state = root.stateFor(cell.placement.definitionId);
                        if (cell.placement.template === "row" && (cell.placement.definitionId === "network" || cell.placement.definitionId === "bluetooth")
                            && state.subtitle === root.services.text("Не підключено", "Not connected"))
                            state.subtitle = root.services.text("Не з’єднано", "Not connected");
                        return state;
                    }
                    presentation: cell.placement.template
                    function setNames() {
                        primaryButton.objectName = cell.placement.definitionId === "energy" ? "control-center-tile-energy"
                            : "control-center-toggle-" + cell.placement.definitionId;
                        detailsButton.objectName = "control-center-details-" + cell.placement.definitionId;
                    }
                    Component.onCompleted: setNames()
                    Connections {
                        target: cell
                        function onPlacementChanged() { tile.setNames(); }
                    }
                    onCommandRequested: function(action, value) {
                        if (action === "toggle" || action === "tailscale.open" || action === "screenshot.capture") root.activate(info);
                    }
                    onDetailsRequested: if (info.section) root.detailsRequested(info.section)
                    onContextRequested: root.showContext(tile, cell.placement)
                }

                // Volume, microphone and brightness keep their own request logic; the cell only
                // gives them a size, and their presentation follows it.
                Loader {
                    anchors.fill: parent
                    active: cell.level
                    enabled: !root.editing
                    sourceComponent: cell.placement.definitionId === "brightness" ? brightnessLevel : audioLevel
                }
                Component {
                    id: brightnessLevel
                    BrightnessControls {
                        id: brightnessItem
                        readonly property string levelKey: cell.placement.definitionId
                        brightness: root.brightness
                        services: root.services
                        compact: true
                        layoutManaged: true
                        presentation: cell.placement.template
                        levelHeight: cell.height
                        Component.onCompleted: root.registerLevel(levelKey, brightnessItem)
                        Component.onDestruction: root.unregisterLevel(levelKey, brightnessItem)
                    }
                }
                Component {
                    id: audioLevel
                    AudioControls {
                        id: audioItem
                        readonly property string levelKey: cell.placement.definitionId
                        objectName: levelKey === "audio-input" ? "control-center-microphone-range" : "control-center-audio-range"
                        services: root.services
                        kinds: [levelKey === "audio-input" ? "input" : "output"]
                        compact: true
                        layoutManaged: true
                        presentation: cell.placement.template
                        levelHeight: cell.height
                        onDetailsRequested: function(section) { root.detailsRequested(section); }
                        onPresentationRequested: function(value) { root.setLevelTemplate(cell.placement.instanceId, value); }
                        Component.onCompleted: root.registerLevel(levelKey, audioItem)
                        Component.onDestruction: root.unregisterLevel(levelKey, audioItem)
                    }
                }

                // Editing chrome: an outline that follows the control's shape, a drag surface over
                // the whole control, a remove badge and a corner handle that resizes in whole cells.
                ContinuousSurface {
                    anchors.fill: parent
                    anchors.margins: -3
                    visible: opacity > 0 && cell.placement.template === "tile"
                    opacity: root.editing ? 1 : 0
                    fill: "transparent"
                    edge: cell.activeFocus || cell.lifted ? Theme.tokens.accent : Qt.alpha(Theme.tokens.accent, 0.55)
                    extent: Metrics.radiusLarge + 3
                    Behavior on opacity { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    visible: opacity > 0 && cell.placement.template !== "tile"
                    opacity: root.editing ? 1 : 0
                    radius: Math.min(width, height) / 2
                    color: "transparent"
                    border.width: cell.activeFocus || cell.lifted ? 2 : 1
                    border.color: cell.activeFocus || cell.lifted ? Theme.tokens.accent : Qt.alpha(Theme.tokens.accent, 0.55)
                    Behavior on opacity { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    id: dragArea
                    objectName: "control-center-edit-drag-" + cell.placement.instanceId
                    anchors.fill: parent
                    z: 20
                    enabled: root.editing
                    visible: root.editing
                    preventStealing: true
                    cursorShape: grid.draggingId !== "" ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property point grab: Qt.point(0, 0)
                    property string lastCell: ""
                    onPressed: function(mouse) {
                        grab = Qt.point(mouse.x, mouse.y);
                        lastCell = "";
                        cell.forceActiveFocus();
                    }
                    onPositionChanged: function(mouse) {
                        if (grid.draggingId === "" && Math.abs(mouse.x - grab.x) + Math.abs(mouse.y - grab.y) < 6) return;
                        const point = mapToItem(grid, mouse.x, mouse.y);
                        grid.dragPosition = Qt.point(point.x - grab.x * cell.scale, point.y - grab.y * cell.scale);
                        grid.draggingId = cell.placement.instanceId;
                        const target = grid.cellAt(point.x, point.y);
                        const key = target.row + ":" + target.column;
                        if (key === lastCell) return;
                        lastCell = key;
                        root.moveItem(cell.placement.instanceId, target.row, target.column);
                    }
                    onReleased: grid.draggingId = ""
                    onCanceled: grid.draggingId = ""
                }
                Button {
                    objectName: "control-center-edit-remove-" + cell.placement.instanceId
                    x: -6
                    y: -6
                    z: 30
                    width: 22
                    height: 22
                    padding: 0
                    visible: opacity > 0
                    opacity: root.editing && !cell.lifted ? 1 : 0
                    scale: root.editing ? (down ? 0.9 : 1) : 0.4
                    enabled: root.editing
                    focusPolicy: Qt.NoFocus
                    Accessible.name: root.services.text("Сховати ", "Hide ") + tile.label
                    Behavior on opacity { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutBack } }
                    onClicked: root.hideItem(cell.placement.instanceId)
                    background: Rectangle {
                        radius: height / 2
                        color: parent.hovered ? Theme.tokens.error : Theme.tokens.surfaceOverlay
                        border.width: 2
                        border.color: Theme.tokens.surface
                        Behavior on color { ColorAnimation { duration: Motion.state } }
                    }
                    contentItem: Item {
                        PentadIcon {
                            anchors.centerIn: parent
                            source: Qt.resolvedUrl("../../assets/icons/material/controls/remove-symbolic.svg")
                            pixelSize: Metrics.panelIcon
                            color: Theme.tokens.text
                        }
                    }
                }
                Rectangle {
                    objectName: "control-center-edit-resize-" + cell.placement.instanceId
                    x: parent.width - width + 6
                    y: parent.height - height + 6
                    z: 30
                    width: 22
                    height: 22
                    radius: height / 2
                    color: resizeArea.pressed || resizeArea.containsMouse ? Qt.lighter(Theme.tokens.accent, 1.1) : Theme.tokens.accent
                    border.width: 2
                    border.color: Theme.tokens.surface
                    visible: opacity > 0
                    opacity: root.editing && grid.draggingId === "" ? 1 : 0
                    scale: root.editing ? (resizeArea.pressed ? 1.15 : 1) : 0.4
                    Accessible.role: Accessible.Button
                    Accessible.name: root.services.text("Змінити розмір ", "Resize ") + tile.label
                    Behavior on opacity { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: Motion.reveal; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: Motion.state } }
                    PentadIcon {
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl("../../assets/icons/material/controls/open-in-full-symbolic.svg")
                        pixelSize: 12
                        color: Theme.tokens.onAccent
                        rotation: 90
                    }
                    MouseArea {
                        id: resizeArea
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: root.editing
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.SizeFDiagCursor
                        property point start: Qt.point(0, 0)
                        property real startWidth: 0
                        property real startHeight: 0
                        onPressed: function(mouse) {
                            start = mapToItem(grid, mouse.x, mouse.y);
                            startWidth = cell.placement.columnSpan * (grid.cellWidth + grid.spacing);
                            startHeight = cell.placement.rowSpan * (grid.cellHeight + grid.spacing);
                            cell.forceActiveFocus();
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return;
                            const point = mapToItem(grid, mouse.x, mouse.y);
                            const columns = Math.round((startWidth + point.x - start.x) / (grid.cellWidth + grid.spacing));
                            const rows = Math.round((startHeight + point.y - start.y) / (grid.cellHeight + grid.spacing));
                            if (columns !== cell.placement.columnSpan || rows !== cell.placement.rowSpan)
                                root.resizeItem(cell.placement.instanceId, columns, rows);
                        }
                    }
                }
            }
        }
    }

    QuickSettingsEditTray {
        id: trayArea
        y: grid.y + grid.height + 12
        width: root.width
        height: Math.max(0, root.trayHeight - 12)
        services: root.services
        editing: root.editing
        hiddenTiles: root.hiddenTiles
        onAddRequested: function(key) { root.addItem(key); }
    }

    QuickSettingsContextMenu {
        id: contextMenu
        anchorItem: root.contextControl
        services: root.services
        contextInfo: root.contextInfo
        contextDefinition: root.contextDefinition
        contextPlacement: root.contextPlacement
        pendingSave: root.pendingSave
        menuError: root.menuError
        chosenColumns: root.chosenColumns
        onDetailsRequested: function(section) { root.detailsRequested(section); }
        onEditRequested: root.beginEdit()
        onTemplateRequested: function(template) { root.changeTemplate(template); }
        onSizeRequested: function(columns, rows) { root.changeSize(columns, rows); }
        onResetRequested: root.resetLayout()
    }
}
