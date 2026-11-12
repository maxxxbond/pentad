import QtQuick
import Quickshell
import Quickshell.Wayland
import QtTest
import qs.theme
import qs.services
import qs.shell
import "../logic/session-actions.mjs" as SessionRules
import "../logic/organizer.mjs" as OrganizerLogic

ShellRoot {
    id: root
    property Services services: Services { preview: true; safeMode: true }
    property int reservedTopHeight: 40
    property var checks: []
    property int step: 0
    property TestEvent pointer: TestEvent {}
    property real scrollHeightBefore: 0
    property var stabilityCenter: null
    property var stabilityList: null
    property string stabilityRecordKey: ""
    property string stabilityGroupKey: ""
    property real stabilityOffset: 0
    property string stabilityAnchorKey: ""
    property var stabilityDone: null
    property QtObject fakeBrightness: QtObject {
        property bool active: true
        property bool safeMode: false
        property var state: ({ kind: "ready", value: 0.72 })
        property var operation: null
        property int serial: 0
        signal commandFinished(string requestId, var result)
        function adjust(steps) { serial++; return "fixture-brightness-" + serial; }
    }
    property QtObject fakeUiServices: QtObject {
        readonly property bool preview: false
        readonly property var plugins: root.services.plugins
        readonly property var popups: root.services.popups
        readonly property QtObject session: QtObject {
            id: fakeSession
            readonly property string userName: "max"
            readonly property string displayName: "Max"
            readonly property string hostName: "pentad-pc"
            property bool writable: true
            property int commands: 0
            property var lastCommand: []
            property var lastCompletion: null
            property var capabilities: ({ lock: "yes", logout: "yes", reboot: "yes", poweroff: "yes" })
            property var state: ({ action: "", confirmation: "", pending: "", error: "" })
            readonly property string confirmation: state.confirmation
            readonly property string pending: state.pending
            property var controller: null
            signal actionFinished(string action, bool ok)
            function canRequest(action) { return writable && !pending && capabilities[action] === "yes"; }
            function request(action) { return controller.request(action); }
            function confirm() { return controller.confirm(); }
            function cancel() { controller.cancel(); }
            Component.onCompleted: controller = SessionRules.createSessionController({
                writable: function() { return fakeSession.writable; },
                capabilities: function() { return fakeSession.capabilities; },
                sessionId: function() { return "fixture-session"; },
                changed: function(next) { fakeSession.state = next; },
                finished: function(action, ok) { fakeSession.actionFinished(action, ok); },
                execute: function(argv, done) {
                    fakeSession.commands++;
                    fakeSession.lastCommand = argv;
                    fakeSession.lastCompletion = done;
                }
            })
        }
        readonly property var config: root.services.config
        readonly property var organizer: root.services.organizer
        readonly property var notifications: root.services.notifications
        readonly property QtObject clock: QtObject {
            readonly property var locale: Qt.locale("uk_UA")
            readonly property date date: new Date(2026, 9, 12, 13, 45, 0)
        }
        readonly property QtObject audio: QtObject {
            property bool active: true
            property bool preview: false
            property bool safeMode: false
            property int serial: 0
            property var retained: ({})
            property string lastStreamId: ""
            function retainMixer(id) { retained = Object.assign({}, retained, { [id]: true }); }
            function releaseMixer(id) { const next = Object.assign({}, retained); delete next[id]; retained = next; }
            property var state: ({ kind: "ready", value: {
                streams: [{id: "fixture-player", nodeId: "41", appName: "Програвач", label: "Музика", mediaName: "Музика", icon: "", volume: 0.45, muted: false, pendingVolume: false, pendingMute: false, requestedVolume: 0.45}],
                output: { id: "speaker", label: "Built-in Audio Analog Stereo", volume: 0.64, muted: false },
                input: { id: "microphone", label: "Мікрофон", volume: 0.38, muted: false },
                outputs: [
                    { id: "speaker", label: "Built-in Audio Analog Stereo", volume: 0.64, muted: false },
                    { id: "hdmi", label: "Navi 48 HDMI/DP Audio Controller Digital Stereo", volume: 0.5, muted: false }
                ],
                inputs: [{ id: "microphone", label: "Мікрофон", volume: 0.38, muted: false }]
            } })
            signal commandFinished(string requestId, var result)
            function setStreamVolume(id, value) { lastStreamId = id; serial++; return "fixture-stream-" + serial; }
            function toggleStreamMute(id) { lastStreamId = id; serial++; return "fixture-stream-" + serial; }
            function setVolume(kind, value) { serial++; return "fixture-audio-" + serial; }
            function toggleMute(kind) {
                serial++;
                const value = Object.assign({}, state.value);
                value[kind] = Object.assign({}, value[kind], { muted: !value[kind].muted });
                state = { kind: "ready", value: value };
                return "fixture-audio-" + serial;
            }
            function setDefault(kind, id) { serial++; return "fixture-audio-" + serial; }
        }
        readonly property QtObject network: QtObject {
            id: fakeNetwork
            readonly property bool active: true
            readonly property bool preview: false
            readonly property bool safeMode: false
            readonly property var operation: null
            property int serial: 0
            // Like the native backend, the adapter lists nearby networks only while its scanner runs.
            readonly property var nearby: [
                { name: "Pentad Studio Wi-Fi", connected: true, known: true, state: "connected", security: "WPA2",
                    canUsePsk: true, signal: 82, bars: 4, device: "fixture-wifi" },
                { name: "Pentad Guest", connected: false, known: false, state: "disconnected", security: "WPA2",
                    canUsePsk: true, signal: 46, bars: 2, device: "fixture-wifi" }
            ]
            property var state: ({ kind: "ready", value: {
                label: "Pentad Studio Wi-Fi", connected: true, connectivity: "Інтернет",
                wifiEnabled: true, wifiHardwareEnabled: true, wifiScanEnabled: false,
                devices: [{ name: "fixture-wifi", type: "wifi", connected: false, scannerEnabled: false }], accessPoints: []
            } })
            signal commandFinished(string requestId, var result)
            function setScanner(deviceName, on) {
                const value = state.value || {};
                const devices = value.devices || [];
                if (state.kind !== "ready" || !devices.some(function(device) { return device.name === deviceName && device.type === "wifi"; }))
                    return "";
                const requestId = "fixture-network-" + (++serial);
                state = { kind: "ready", value: Object.assign({}, value, {
                    wifiScanEnabled: on,
                    devices: devices.map(function(device) {
                        return device.name === deviceName ? Object.assign({}, device, { scannerEnabled: on }) : device;
                    }),
                    accessPoints: on ? nearby : []
                }) };
                Qt.callLater(function() { fakeNetwork.commandFinished(requestId, { ok: true }); });
                return requestId;
            }
            function scan(deviceName) { return setScanner(deviceName, true); }
            function stopScan(deviceName) { return setScanner(deviceName, false); }
        }
        readonly property QtObject quickSettings: QtObject {
            property int bluetoothToggles: 0
            readonly property var operation: null
            readonly property string error: ""
            property var state: ({ kind: "ready", value: {
                bluetooth: true, bluetoothAvailable: true, bluetoothDiscovering: false,
                bluetoothDevices: [{ id: "fixture", label: "Навушники", connected: true, paired: true }],
                vpns: [{ uuid: "fixture", name: "Робочий VPN", active: false }],
                airplane: false, airplaneAvailable: true, night: true, nightAvailable: true,
                profile: "balanced", busy: false, errorSetting: "", error: ""
            } })
            function toggleBluetooth() { bluetoothToggles++; return "fixture-bluetooth-" + bluetoothToggles; }
            // Discovery is not an operation; like the real service it reports only whether the adapter took it.
            function setBluetoothDiscovering(on) {
                if (state.kind !== "ready" || state.value.bluetooth !== true) return false;
                if (state.value.bluetoothDiscovering !== on)
                    state = { kind: "ready", value: Object.assign({}, state.value, { bluetoothDiscovering: on }) };
                return true;
            }
            function toggleVpn(uuid) {}
            function toggleAirplane() {}
            function toggleNight() {}
        }
        readonly property QtObject desktop: QtObject {
            readonly property bool preview: false
            readonly property bool safeMode: false
            readonly property string inhibitRequest: ""
            readonly property var state: ({ kind: "ready", value: { inhibited: true } })
            signal commandFinished(string requestId, var result)
            function command(action) {}
        }
        readonly property QtObject power: QtObject {
            readonly property bool active: true
            readonly property bool safeMode: false
            property int serial: 0
            property string requestedProfile: ""
            property var profileState: ({ kind: "ready", value: {
                actual: "balanced", profiles: ["balanced", "performance"], pending: false
            } })
            signal commandFinished(string id, var result)
            function setProfile(profile) { requestedProfile = profile; return "fixture-profile-" + (++serial); }
        }
        function text(uk, en) { return uk; }
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function findCell(item) {
        let current = item;
        while (current && String(current.objectName).indexOf("control-center-edit-cell-") !== 0) current = current.parent;
        return current;
    }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const items = item.children || [];
        for (let index = 0; index < items.length; ++index) {
            const found = findNamed(items[index], name);
            if (found) return found;
        }
        return null;
    }
    function findButton(item, text) {
        if (!item) return null;
        if ((item.text === text || item.objectName === text) && typeof item.clicked === "function") return item;
        for (const child of item.children || []) {
            const found = findButton(child, text);
            if (found) return found;
        }
        return null;
    }
    function clickButton(item, text) {
        const button = findButton(item, text);
        return !!button && pointer.mouseClick(button, button.width / 2, button.height / 2,
            Qt.LeftButton, Qt.NoModifier, 0);
    }
    function revealInControls(scroll, item) {
        if (!scroll || !item) return false;
        const bounds = item.mapToItem(scroll.contentItem, 0, 0);
        const margin = 8;
        let next = scroll.contentY;
        if (bounds.y < scroll.contentY + margin) next = bounds.y - margin;
        else if (bounds.y + item.height > scroll.contentY + scroll.height - margin)
            next = bounds.y + item.height - scroll.height + margin;
        next = Math.max(0, Math.min(next, Math.max(0, scroll.contentHeight - scroll.height)));
        if (Math.abs(next - scroll.contentY) < 1) return false;
        scroll.contentY = next;
        return true;
    }
    function capture(suffix, callback) {
        const path = Quickshell.env("PENTAD_ARTIFACT_PATH");
        if (!path) { callback(false); return; }
        bar.popup.focusItem.grabToImage(function(result) {
            callback(result.saveToFile(path + suffix));
        });
    }
    function addFixtures() {
        const controller = services.notifications.controller;
        controller.setStatus("available");
        for (let index = 0; index < 5; ++index) {
            controller.notify({
                app: index < 3 ? "Calendar" : "Build monitor",
                icon: "",
                title: ["Weekly review", "Room changed", "Agenda ready", "Build passed", "Preview deployed"][index],
                body: index === 0
                    ? "A longer preview message demonstrates wrapping inside the notification card while keeping the center readable."
                    : "A realistic control-center fixture notification.",
                actions: [], hints: { urgency: 1, transient: false, resident: true },
                expireTimeout: 0, sender: "fixture"
            });
        }
        services.organizer.addTask("Переглянути план на тиждень");
        services.organizer.addTask("Підготувати нотатки до релізу");
        services.organizer.addTask("Перевірити розгортання");
        services.organizer.setTab("calendar");
        services.organizer.setCollapsed(false);
        services.organizer.setSelectedDay(OrganizerLogic.dayKey(fakeUiServices.clock.date));
        services.calendarSources = [fixtureCalendar("fixture-work", "#F2C94C", [
            { offset: 0, title: "Планування спринту", hour: 9, minutes: 75 },
            { offset: 2, title: "Демо для команди", hour: 15, minutes: 45 },
        ]), fixtureCalendar("fixture-home", "#4FA3F7", [
            { offset: 0, title: "День народження Олі", allDay: true },
            { offset: 1, title: "Тренування", hour: 19, minutes: 60 },
        ])];
    }
    function fixtureCalendar(id, color, items) {
        return {
            id: id, label: id, color: color,
            read: function(range, cancellation) {
                const now = root.fakeUiServices.clock.date;
                return items.map(function(item, index) {
                    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + item.offset);
                    if (item.allDay) {
                        const next = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
                        return { id: id + "-" + index, title: item.title, allDay: true,
                            start: OrganizerLogic.dayKey(day), end: OrganizerLogic.dayKey(next) };
                    }
                    const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), item.hour, 0);
                    return { id: id + "-" + index, title: item.title, allDay: false,
                        start: start.toISOString(), end: new Date(start.getTime() + item.minutes * 60000).toISOString() };
                });
            },
        };
    }
    function testNotificationStability(done) {
        const center = findNamed(bar.popup.focusItem, "control-center-notifications");
        const list = findNamed(center, "notification-center-list");
        if (!center || !list) {
            check("notification-model-state-stable", false, "center/list missing");
            done();
            return;
        }
        const records = [];
        for (let index = 0; index < 100; ++index) {
            records.push({
                key: "stability-" + index, app: "Fixture " + Math.floor(index / 5),
                desktopEntry: "fixture-" + Math.floor(index / 5), category: "",
                icon: "", title: "Fixture notification " + index,
                body: "A history item used to verify stable expanded content and scroll position.",
                receivedAt: 200000 - index, urgency: "normal", transient: false,
                resident: true, read: false
            });
        }
        const controller = services.notifications.controller;
        controller.restore({ schemaVersion: 1, dnd: false, records: records });
        Qt.callLater(function() {
            list.contentY = Math.max(list.originY, list.originY + list.contentHeight - list.height);
            const key = records[98].key;
            const groupKey = records[98].desktopEntry;
            center.setGroupExpanded(groupKey, true);
            center.setCardExpanded(key, true);
            scrollHeightBefore = list.contentHeight;
            stabilityCenter = center;
            stabilityList = list;
            stabilityRecordKey = key;
            stabilityGroupKey = groupKey;
            let anchorIndex = list.indexAt(1, list.contentY + 1);
            if (anchorIndex < 0) {
                for (let candidate = 0; candidate < list.count; ++candidate) {
                    const item = list.itemAtIndex(candidate);
                    if (item && item.y + item.height > list.contentY) { anchorIndex = candidate; break; }
                }
            }
            const anchorItem = anchorIndex >= 0 ? list.itemAtIndex(anchorIndex) : null;
            stabilityAnchorKey = anchorIndex >= 0 && center.renderedGroups[anchorIndex]
                ? center.renderedGroups[anchorIndex].key : "";
            stabilityOffset = anchorItem ? list.contentY - anchorItem.y : 0;
            stabilityDone = done;
            controller.setStatus("available");
            controller.notify({
                app: "Inserted at top", icon: "", title: "New notification", body: "After scroll.",
                actions: [], hints: { urgency: 1, transient: false, resident: true },
                expireTimeout: 0, sender: "fixture"
            });
            stabilityCheck.restart();
        });
    }
    function finishNotificationStability() {
        const center = stabilityCenter;
        const list = stabilityList;
        const key = stabilityRecordKey;
        const groupKey = stabilityGroupKey;
        const groupIndex = center.renderedGroups.findIndex(function(group) { return group.key === groupKey; });
        const groupItem = groupIndex >= 0 ? list.itemAtIndex(groupIndex) : null;
        const card = findNamed(groupItem, "notification-card-" + key);
        check("notification-card-expansion-survives-model-update", !!card && card.expanded,
            "card=" + !!card + ", expanded=" + (card ? card.expanded : false)
                + ", saved=" + center.expandedCards[key]);
        const anchorIndex = center.renderedGroups.findIndex(function(group) { return group.key === stabilityAnchorKey; });
        const anchorItem = anchorIndex >= 0 ? list.itemAtIndex(anchorIndex) : null;
        const restoredOffset = anchorItem ? list.contentY - anchorItem.y : NaN;
        check("notification-list-scroll-survives-model-update", !!stabilityAnchorKey && !!anchorItem
            && Math.abs(restoredOffset - stabilityOffset) <= 2,
            "anchor=" + stabilityAnchorKey + ", offset=" + stabilityOffset + ", restored=" + restoredOffset);
        stabilityDone();
    }
    function report() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks
        }));
        Qt.quit();
    }

    Component.onCompleted: {
        const appearance = Quickshell.env("PENTAD_GALLERY_APPEARANCE") === "light" ? "light" : "dark";
        const accent = Quickshell.env("PENTAD_GALLERY_ACCENT") || "#869677";
        Theme.resolve({ appearance: appearance, accent: accent, fontFamily: "Geist",
            reducedMotion: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1" });
    }

    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: root.reservedTopHeight
        exclusiveZone: root.reservedTopHeight
        color: 'transparent'
        WlrLayershell.namespace: 'pentad-control-center-test-reserved-topbar'
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }
    BarWindow {
        id: bar
        services: root.services
        screen: Quickshell.screens[0]
        Component.onCompleted: {
            exclusionMode = ExclusionMode.Normal;
            exclusiveZone = services.config.documents.layout.barHeight;
        }
    }

    Timer {
        id: stabilityCheck
        interval: 120
        repeat: false
        onTriggered: root.finishNotificationStability()
    }


    property string menuActionKey: ""
    property int menuActionHold: 0
    property var menuActionDone: null
    property var menuActionItem: null
    // holdMs 0 taps the menu entry; otherwise it is pressed for holdMs and then released.
    function sessionMenuAction(panel, key, holdMs, done) {
        const button = root.findNamed(panel.sessionHeader, "control-center-session-menu");
        if (button) root.pointer.mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
        root.menuActionKey = key;
        root.menuActionHold = holdMs;
        root.menuActionDone = done;
        menuActionProbe.start();
    }
    function finishMenuAction() {
        const done = root.menuActionDone;
        root.menuActionDone = null;
        root.menuActionItem = null;
        if (done) done();
    }
    Timer {
        id: menuActionProbe
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const menu = panel.sessionHeader.powerMenu;
            const item = root.findNamed(menu.contentItem, "control-center-session-" + root.menuActionKey);
            root.check("power-menu-opens-" + root.menuActionKey, menu.opened && !!item && item.visible);
            root.menuActionItem = item;
            if (!item) root.finishMenuAction();
            else if (root.menuActionHold <= 0) {
                root.pointer.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.finishMenuAction();
            } else {
                root.pointer.mousePress(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                menuActionRelease.interval = root.menuActionHold;
                menuActionRelease.start();
            }
        }
    }
    Timer {
        id: menuActionRelease
        onTriggered: {
            const item = root.menuActionItem;
            if (item) root.pointer.mouseRelease(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            root.finishMenuAction();
        }
    }


    property int editStep: 0
    Timer {
        id: editProbe
        interval: 320
        repeat: true
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const grid = panel.quickSettingsGrid;
            const named = function(name) { return root.findNamed(grid, name); };
            const order = function() { return grid.draft ? grid.draft.items.map(function(item) { return item.instanceId; }) : []; };
            root.editStep++;
            if (root.editStep === 1) {
                const pencil = root.findNamed(panel.sessionHeader, "control-center-session-edit");
                if (pencil) root.pointer.mouseClick(pencil, pencil.width / 2, pencil.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } else if (root.editStep === 2) {
                const handle = named("control-center-edit-resize-airplane");
                const remove = named("control-center-edit-remove-airplane");
                root.check("pencil-enters-grid-editing", grid.editing && panel.sessionHeader.editing
                    && named("control-center-edit-bar").opacity > 0.99 && !panel.audioControls.enabled);
                root.check("editing-shows-handles-and-true-sizes", !!handle && handle.opacity > 0.99 && !!remove
                    && remove.opacity > 0.99 && grid.menuGrid.resolvedLayout.free.length === 0,
                    JSON.stringify({ handle: handle ? handle.opacity : null, remove: remove ? remove.opacity : null,
                        free: grid.menuGrid.resolvedLayout.free }));
                // Each capture renders a later frame, so the next action waits for its callback.
                root.capture(".editing.png", function(saved) {
                    root.check("editing-capture", saved);
                    const four = named("control-center-grid-columns-4");
                    if (four) root.pointer.mouseClick(four, four.width / 2, four.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                });
            } else if (root.editStep === 3) {
                const wifiCell = named("control-center-edit-cell-network");
                root.check("grid-switches-to-four-columns-keeping-rows", grid.chosenColumns === 4
                    && grid.draft.items[0].columnSpan === 2 && grid.draft.items[0].template === "row"
                    && Math.abs(wifiCell.width - (grid.width - 8) / 2) < 1
                    && grid.menuGrid.resolvedLayout.free.length === 2 && !!named("menu-grid-free-cell") && named("menu-grid-free-cell").opacity > 0.5,
                    (function(f) { return f ? JSON.stringify({ o: f.opacity, x: f.x, y: f.y, w: f.width, h: f.height, v: f.visible, c: String(f.color), p: String(f.parent) }) : "none"; })(named("menu-grid-free-cell")));
                root.capture(".editing-four.png", function(saved) {
                    root.check("editing-four-capture", saved);
                    const six = named("control-center-grid-columns-6");
                    if (six) root.pointer.mouseClick(six, six.width / 2, six.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                });
            } else if (root.editStep === 4) {
                root.check("grid-returns-to-six-columns", grid.chosenColumns === 6
                    && JSON.stringify(grid.draft.items) === JSON.stringify(grid.savedMenu.items),
                    JSON.stringify(grid.draft) + " vs " + JSON.stringify(grid.savedMenu));
                const handle = named("control-center-edit-resize-airplane");
                const area = handle.children[handle.children.length - 1];
                const step = grid.menuGrid.cellWidth + 8;
                root.pointer.mousePress(area, area.width / 2, area.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(area, area.width / 2 + step * 2, area.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.pointer.mouseRelease(area, area.width / 2 + step * 2, area.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                const airplane = grid.draft.items.find(function(item) { return item.instanceId === "airplane"; });
                root.check("corner-handle-resizes-in-cells-and-picks-template", airplane.columnSpan === 3
                    && airplane.template === "row", JSON.stringify(airplane));
            } else if (root.editStep === 5) {
                const drag = named("control-center-edit-drag-airplane");
                const target = named("control-center-edit-cell-screenshot");
                const point = target.mapToItem(drag, target.width / 2, target.height / 2);
                root.pointer.mousePress(drag, drag.width / 2, drag.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(drag, drag.width / 2 + 10, drag.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.pointer.mouseMove(drag, point.x, point.y, 0, Qt.LeftButton, Qt.NoModifier);
                root.check("drag-lifts-control-and-follows-pointer", grid.menuGrid.draggingId === "airplane");
                root.pointer.mouseRelease(drag, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 0);
                const ids = order();
                root.check("drag-drop-reorders-draft-only", ids.indexOf("airplane") > ids.indexOf("screenshot")
                    && grid.menuGrid.draggingId === "" && grid.pendingSave === "", ids.join(","));
                const remove = named("control-center-edit-remove-dnd");
                if (remove) root.pointer.mouseClick(remove, remove.width / 2, remove.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            } else if (root.editStep === 6) {
                const add = named("control-center-edit-add-dnd");
                root.check("remove-hides-control-and-offers-it-in-tray", !!add && add.visible
                    && grid.hiddenTiles.some(function(tile) { return tile.key === "dnd"; })
                    && !grid.menuGrid.resolvedLayout.items.some(function(item) { return item.instanceId === "dnd"; }));
                root.capture(".editing-changed.png", function(saved) {
                    root.check("editing-changed-capture", saved);
                    if (add) root.pointer.mouseClick(add, add.width / 2, add.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                });
            } else if (root.editStep === 7) {
                // Overnight mode stays in the tray: the default grid lists it hidden.
                root.check("tray-adds-control-back", grid.hiddenTiles.map(function(tile) { return tile.key; }).join(",") === "overnight"
                    && grid.menuGrid.resolvedLayout.items.some(function(item) { return item.instanceId === "dnd"; }),
                    JSON.stringify({ editing: grid.editing, hidden: grid.hiddenTiles.map(function(tile) { return tile.key; }) }));
                // The level sliders are grid controls too: the corner handle stands volume up into a capsule.
                root.check("level-sliders-have-edit-handles", ["brightness", "audio-output", "audio-input"].every(function(id) {
                    return !!named("control-center-edit-drag-" + id) && !!named("control-center-edit-remove-" + id)
                        && !!named("control-center-edit-resize-" + id);
                }));
                const levelHandle = named("control-center-edit-resize-audio-output");
                const levelArea = levelHandle.children[levelHandle.children.length - 1];
                const across = grid.menuGrid.cellWidth + 8;
                const down = grid.menuGrid.cellHeight + 8;
                root.pointer.mousePress(levelArea, levelArea.width / 2, levelArea.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.pointer.mouseMove(levelArea, levelArea.width / 2 - across * 5, levelArea.height / 2 + down * 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.pointer.mouseRelease(levelArea, levelArea.width / 2 - across * 5, levelArea.height / 2 + down * 2, Qt.LeftButton, Qt.NoModifier, 0);
                const volume = grid.draft.items.find(function(item) { return item.instanceId === "audio-output"; });
                root.check("level-handle-stands-volume-up", volume.template === "range-vertical" && volume.columnSpan === 1
                    && volume.rowSpan === 3 && panel.audioControls.presentation === "range-vertical"
                    && panel.audioControls.compactOutputSlider.orientation === Qt.Vertical,
                    JSON.stringify({ volume: volume, presentation: panel.audioControls.presentation,
                        orientation: panel.audioControls.compactOutputSlider.orientation }));
            } else if (root.editStep === 8) {
                // By now the cell has finished growing to three rows; the capsule follows its height
                // and keeps the device chevron in its top slot.
                const volumeCell = named("control-center-edit-cell-audio-output");
                const volumeSlider = panel.audioControls.compactOutputSlider;
                root.check("vertical-volume-fills-its-cell", volumeCell.height > 150
                    && Math.abs(volumeSlider.height - volumeCell.height) < 1 && volumeSlider.trailingSlot === 44,
                    JSON.stringify({ slider: volumeSlider.height, cell: volumeCell.height, slot: volumeSlider.trailingSlot }));
                root.capture(".editing-vertical-volume.png", function(saved) {
                    root.check("editing-vertical-volume-capture", saved);
                    const reset = named("control-center-edit-reset");
                    if (reset) root.pointer.mouseClick(reset, reset.width / 2, reset.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                    root.check("reset-restores-default-draft", JSON.stringify(grid.draft) === JSON.stringify(grid.savedMenu));
                    const done = named("control-center-edit-done");
                    if (done) root.pointer.mouseClick(done, done.width / 2, done.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                });
            } else if (root.editStep === 9) {
                root.check("done-leaves-editing-without-saving-unchanged-layout", !grid.editing && grid.pendingSave === ""
                    && !panel.sessionHeader.editing && panel.audioControls.enabled
                    && grid.menuGrid.resolvedLayout.items.length === 13);
                stop();
                mainSequence.start();
                hoverProbe.start();
            }
        }
    }
    Timer {
        id: hoverProbe
        interval: 40
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const toggle = root.findNamed(panel.quickSettingsGrid, "control-center-toggle-network");
            if (toggle) root.pointer.mouseMove(toggle, toggle.width / 2, toggle.height / 2, 0, Qt.NoButton, Qt.NoModifier);
            root.check("wifi-toggle-receives-hover", !!toggle && toggle.hovered);
            root.capture(".wifi-hover.png", function(saved) {
                root.check("wifi-hover-capture", saved);
                inputProbe.start();
            });
        }
    }

    Timer {
        id: inputProbe
        interval: 100
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const slider = panel.audioControls.compactOutputSlider;
            const scroll = root.findNamed(panel, "control-center-controls-scroll");
            const scrollBefore = scroll.contentY;
            const mute = root.findNamed(panel.audioControls, "control-center-toggle-audio-output");
            const picker = root.findNamed(panel.audioControls, "control-center-details-audio-output");
            const wheelTargets = [slider, mute, picker, panel.microphoneControls.compactInputSlider];
            for (let index = 0; index < wheelTargets.length; index++) {
                const target = wheelTargets[index];
                const previous = root.fakeUiServices.audio.serial;
                root.pointer.mouseWheel(target, target.width / 2, target.height / 2,
                    Qt.NoButton, Qt.NoModifier, 0, 120, 0);
                root.check("menu-wheel-adjusts-audio-zone-" + index,
                    root.fakeUiServices.audio.serial === previous + 1 && scroll.contentY === scrollBefore);
                root.fakeUiServices.audio.commandFinished(index === 3
                    ? panel.microphoneControls.inputVolumeRequest : panel.audioControls.outputVolumeRequest, { ok: true });
            }
            const brightness = panel.brightnessControl.brightnessSlider;
            const brightnessBefore = root.fakeBrightness.serial;
            root.pointer.mouseWheel(brightness, brightness.width / 2, brightness.height / 2,
                Qt.NoButton, Qt.NoModifier, 0, 120, 0);
            root.check("menu-wheel-adjusts-brightness-without-scrolling-panel",
                root.fakeBrightness.serial === brightnessBefore + 1 && scroll.contentY === scrollBefore);
            root.fakeBrightness.commandFinished(panel.brightnessControl.pendingRequestId, { ok: true, value: 0.77 });
            const before = root.fakeUiServices.audio.serial;
            root.pointer.mouseClick(slider, slider.width * 0.25, slider.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("volume-range-responds-to-pointer", root.fakeUiServices.audio.serial > before);
            root.fakeUiServices.audio.commandFinished(panel.audioControls.outputVolumeRequest, { ok: true });
            const outputMute = root.findNamed(panel.audioControls, "control-center-toggle-audio-output");
            if (outputMute) root.pointer.mouseClick(outputMute, outputMute.width / 2, outputMute.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("output-mute-keeps-volume-and-shows-muted-state", slider.muted
                && slider.iconSource.endsWith("volume-off-symbolic.svg") && Math.abs(slider.value - 0.64) < 0.01);
            root.fakeUiServices.audio.commandFinished(panel.audioControls.outputMuteRequest, { ok: true });
            microphoneMuteProbe.start();
        }
    }
    Timer {
        id: microphoneMuteProbe
        interval: 80
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const scroll = root.findNamed(panel, "control-center-controls-scroll");
            const microphone = panel.microphoneControls.compactInputSlider;
            if (root.revealInControls(scroll, microphone)) {
                root.check("microphone-controls-revealed-before-input", microphone.mapToItem(scroll, 0, 0).y >= 0
                    && microphone.mapToItem(scroll, 0, microphone.height).y <= scroll.height,
                    JSON.stringify({ contentY: scroll.contentY, viewport: scroll.height }));
                Qt.callLater(function() { microphoneMuteProbe.start(); });
                return;
            }
            // The fill runs the whole capsule while dragged: near the top it passes under the device chevron
            // without a step, the grip fades before the separator, and at 100 % the chevron ink is `onAccent`.
            const inputPicker = root.findNamed(panel.microphoneControls, "control-center-details-audio-input");
            const dragY = microphone.height / 2;
            const dragFrom = microphone.width * 0.3;
            const startPosition = microphone.position;
            root.pointer.mousePress(microphone, dragFrom, dragY, Qt.LeftButton, Qt.NoModifier, 0);
            root.pointer.mouseMove(microphone, dragFrom + 20, dragY, 0, Qt.LeftButton, Qt.NoModifier);
            root.pointer.mouseMove(microphone, dragFrom + (0.95 - startPosition) * microphone.travel, dragY, 0, Qt.LeftButton, Qt.NoModifier);
            root.check("near-full-level-passes-under-chevron-continuously", microphone.grabbing
                && Math.abs(microphone.position - 0.95) < 0.011
                && microphone.fillExtent > microphone.separatorAt && microphone.fillExtent < microphone.availableWidth
                && microphone.handle.opacity === 0,
                JSON.stringify({ position: microphone.position, fill: microphone.fillExtent, separator: microphone.separatorAt }));
            root.pointer.mouseMove(microphone, microphone.width - 2, dragY, 0, Qt.LeftButton, Qt.NoModifier);
            root.check("full-level-fills-capsule-under-chevron", microphone.position === 1
                && Math.abs(microphone.fillExtent - microphone.availableWidth) < 0.5 && microphone.separatorOnFill,
                JSON.stringify({ fill: microphone.fillExtent, width: microphone.availableWidth }));
            root.check("full-level-chevron-uses-on-accent-ink", microphone.endOnFill
                && !!inputPicker && Qt.colorEqual(inputPicker.ink, Theme.tokens.onAccent));
            root.pointer.mouseRelease(microphone, microphone.width - 2, dragY, Qt.LeftButton, Qt.NoModifier, 0);
            root.check("full-level-drag-keeps-device-picker-closed", panel.detailsSection === "");
            root.fakeUiServices.audio.commandFinished(panel.microphoneControls.inputVolumeRequest, { ok: true });
            const inputMute = root.findNamed(panel.microphoneControls, "control-center-toggle-audio-input");
            if (inputMute) root.pointer.mouseClick(inputMute, inputMute.width / 2, inputMute.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("microphone-mute-keeps-level-and-shows-muted-state", microphone.muted
                && microphone.iconSource.endsWith("mic-off-symbolic.svg") && Math.abs(microphone.value - 0.38) < 0.01);
            root.fakeUiServices.audio.commandFinished(panel.microphoneControls.inputMuteRequest, { ok: true });
            scroll.contentY = 0;
            const organizer = root.findNamed(bar.popup.focusItem, "panel-organizer");
            root.clickButton(organizer, "13");
            root.check("calendar-date-responds-to-pointer", root.services.organizer.selectedDayKey.endsWith("-13"));
            root.clickButton(organizer, "calendar-today");
            const bluetoothDetails = root.findNamed(panel.quickSettingsGrid, "control-center-details-bluetooth");
            const bluetoothToggle = root.findNamed(panel.quickSettingsGrid, "control-center-toggle-bluetooth");
            const beforeToggle = root.fakeUiServices.quickSettings.bluetoothToggles;
            if (bluetoothToggle) root.pointer.mouseClick(bluetoothToggle, bluetoothToggle.width / 2, bluetoothToggle.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("bluetooth-icon-toggles-without-opening-selector",
                root.fakeUiServices.quickSettings.bluetoothToggles === beforeToggle + 1 && panel.detailsSection === "");
            root.check("quick-settings-pointer-click-dispatched", !!bluetoothDetails && root.pointer.mouseClick(
                bluetoothDetails, bluetoothDetails.width * 0.65, bluetoothDetails.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0));
            root.check("bluetooth-card-opens-details-without-toggling", panel.detailsSection === "bluetooth"
                && root.fakeUiServices.quickSettings.bluetoothToggles === beforeToggle + 1);
        }
    }

    Timer {
        id: vpnProbe
        interval: 80
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const details = root.findNamed(panel.quickSettingsGrid, "control-center-details-vpn");
            if (details) root.pointer.mouseClick(details, details.width / 2, details.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("vpn-details-respond-to-pointer", panel.detailsSection === "vpn");
            vpnReturn.start();
        }
    }
    Timer {
        id: selectorReturnCapture
        interval: 280
        onTriggered: {
            const calendar = root.findNamed(root.findNamed(bar.popup.focusItem, "panel-organizer"), "panel-calendar");
            root.check("calendar-marks-events-in-source-colours", !!calendar
                && JSON.stringify(calendar.marks[calendar.todayKey]) === JSON.stringify(["#4FA3F7", "#F2C94C"]),
                calendar ? JSON.stringify(calendar.marks) : "calendar missing");
            root.capture(".right.png", function(saved) {
                root.check("control-center-capture", saved);
                const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
                const mixer = root.findNamed(panel, "mixer-volume-fixture-player");
                root.check("right-menu-loads-mixer-through-plugin-host", !!mixer && Object.keys(root.fakeUiServices.audio.retained).length === 1);
                root.check("mixer-fits-controls-scroll-without-covering-notifications", !!mixer
                    && panel.topHeight <= panel.topPreferredHeight + 0.5
                    && root.findNamed(panel, "control-center-notifications").height > 0
                    && root.findNamed(panel, "control-center-notifications").y >= root.findNamed(panel, "control-center-controls-scroll").y + root.findNamed(panel, "control-center-controls-scroll").height,
                    JSON.stringify({ preferred: panel.topPreferredHeight, top: panel.topHeight,
                        notifications: root.findNamed(panel, "control-center-notifications").height, panel: panel.height }));
                const scroll = root.findNamed(panel, "control-center-controls-scroll");
                if (mixer) root.revealInControls(scroll, mixer);
                Qt.callLater(function() {
                    if (mixer) root.pointer.mouseClick(mixer.slider, mixer.slider.width * 0.55,
                        mixer.slider.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                    root.check("right-menu-mixer-is-reachable-and-targets-its-stream", !!mixer
                        && mixer.mapToItem(scroll, 0, mixer.height).y <= scroll.height
                        && root.fakeUiServices.audio.lastStreamId === "fixture-player");
                    root.capture(".mixer.png", function(mixerSaved) {
                        root.check("right-menu-mixer-capture", mixerSaved);
                        scroll.contentY = 0;
                        const organizer = root.findNamed(bar.popup.focusItem, "panel-organizer");
                        const tasksTab = root.findNamed(organizer, "organizer-tab-1");
                        if (tasksTab) root.pointer.mouseClick(tasksTab, tasksTab.width / 2, tasksTab.height / 2,
                            Qt.LeftButton, Qt.NoModifier, 0);
                        root.check("organizer-tab-responds-to-pointer", root.services.organizer.document.tab === "tasks");
                        vpnProbe.start();
                    });
                });
            });
        }
    }
    Timer {
        id: audioOutputProbe
        interval: 120
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const picker = root.findNamed(panel.audioControls, "control-center-details-audio-output");
            if (picker) root.pointer.mouseClick(picker, picker.width / 2, picker.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("output-picker-opens-own-selector", !!picker && panel.detailsSection === "audio-output");
            audioOutputCapture.start();
        }
    }
    Timer {
        id: audioOutputCapture
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            root.capture(".audio-output.png", function(saved) {
                root.check("output-selector-capture", saved);
                const headerAction = root.findNamed(panel.quickSettingsDetails, "control-center-details-toggle");
                const before = root.fakeUiServices.audio.serial;
                const beforeMuted = root.fakeUiServices.audio.state.value.output.muted;
                if (headerAction) root.pointer.mouseClick(headerAction, headerAction.width / 2, headerAction.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0);
                root.check("output-header-toggle-uses-mute", !!headerAction && root.fakeUiServices.audio.serial === before + 1);
                root.pointer.mouseClick(headerAction, headerAction.width / 2, headerAction.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0);
                root.check("output-switch-blocks-duplicate-pending-command", headerAction.pending
                    && root.fakeUiServices.audio.serial === before + 1);
                const state = root.fakeUiServices.audio.state;
                root.fakeUiServices.audio.state = { kind: "ready", value: Object.assign({}, state.value, {
                    output: Object.assign({}, state.value.output, { muted: beforeMuted })
                }) };
                root.fakeUiServices.audio.commandFinished(panel.quickSettingsDetails.headerRequestId, { ok: false, reason: "fixture-denied" });
                root.check("output-switch-restores-confirmed-state-on-failure", !headerAction.pending
                    && headerAction.checked === !beforeMuted && panel.quickSettingsDetails.headerError === "fixture-denied");
                root.clickButton(panel.quickSettingsDetails, "control-center-details-back");
                audioInputProbe.start();
            });
        }
    }
    Timer {
        id: audioInputProbe
        interval: 280
        property bool prepared: false
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const picker = root.findNamed(panel.microphoneControls, "control-center-details-audio-input");
            const scroll = root.findNamed(panel, "control-center-controls-scroll");
            if (!prepared) {
                prepared = true;
                if (root.revealInControls(scroll, picker)) {
                    Qt.callLater(function() { audioInputProbe.start(); });
                    return;
                }
            }
            if (picker) root.pointer.mouseClick(picker, picker.width / 2, picker.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("microphone-picker-opens-own-selector", !!picker && panel.detailsSection === "audio-input");
            audioInputCapture.start();
        }
    }
    Timer {
        id: audioInputCapture
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            root.capture(".audio-input.png", function(saved) {
                root.check("microphone-selector-capture", saved);
                root.clickButton(panel.quickSettingsDetails, "control-center-details-back");
                const scroll = root.findNamed(panel, "control-center-controls-scroll");
                if (scroll) scroll.contentY = 0;
                audioInputProbe.prepared = false;
                networkPickerProbe.start();
            });
        }
    }
    Timer {
        id: networkPickerProbe
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const picker = root.findNamed(panel.quickSettingsGrid, "control-center-details-network");
            if (picker) root.pointer.mouseClick(picker, picker.width * 0.65, picker.height / 2,
                Qt.LeftButton, Qt.NoModifier, 0);
            root.check("wifi-card-opens-selector", !!picker && panel.detailsSection === "network");
            networkPickerCapture.start();
        }
    }
    Timer {
        id: networkPickerCapture
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const network = root.findNamed(panel.quickSettingsDetails, "network-controls-selector");
            const networkCard = root.findNamed(network, "network-selector-card");
            const networkContent = root.findNamed(network, "network-selector-content");
            root.check("wifi-selector-content-has-height", !!network && network.visible && network.height > 50,
                network ? JSON.stringify({ height: network.height, implicitHeight: network.implicitHeight,
                    cardHeight: networkCard ? networkCard.height : null,
                    cardImplicit: networkCard ? networkCard.implicitHeight : null,
                    contentHeight: networkContent ? networkContent.height : null,
                    contentImplicit: networkContent ? networkContent.implicitHeight : null,
                    visible: network.visible }) : "missing");
            root.capture(".wifi.png", function(saved) {
                root.check("wifi-selector-capture", saved);
                root.clickButton(panel.quickSettingsDetails, "control-center-details-back");
                profilePickerProbe.start();
            });
        }
    }
    Timer {
        id: profilePickerProbe
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const tile = root.findNamed(panel.quickSettingsGrid, "control-center-tile-energy");
            if (tile) root.pointer.mouseClick(tile, tile.width / 2, tile.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            root.check("energy-card-opens-picker-without-changing-profile",
                panel.detailsSection === "energy" && root.fakeUiServices.power.serial === 0);
            profilePickerCapture.start();
        }
    }
    Timer {
        id: profilePickerCapture
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const option = root.findNamed(panel.quickSettingsDetails, "control-center-profile-performance");
            if (option) root.pointer.mouseClick(option, option.width / 2, option.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            root.check("profile-choice-waits-for-confirmed-state", root.fakeUiServices.power.requestedProfile === "performance"
                && panel.quickSettingsDetails.profileValue.actual === "balanced");
            root.fakeUiServices.power.profileState = { kind: "ready", value: {
                actual: "performance", profiles: ["balanced", "performance"], pending: false
            } };
            root.fakeUiServices.power.commandFinished(panel.quickSettingsDetails.profileRequestId, { ok: true });
            root.check("profile-choice-shows-confirmed-state", panel.quickSettingsDetails.profileValue.actual === "performance"
                && panel.quickSettingsDetails.profileRequestId === "");
            root.capture(".energy.png", function(saved) {
                root.check("energy-selector-capture", saved);
                root.clickButton(panel.quickSettingsDetails, "control-center-details-back");
                unavailableProbe.start();
            });
        }
    }
    Timer {
        id: unavailableProbe
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            root.fakeUiServices.network.state = { kind: "ready", value: {
                label: "Ethernet", connected: true, wifiEnabled: true, wifiHardwareEnabled: true,
                devices: [{ name: "ethernet", type: "wired", connected: true }], accessPoints: []
            } };
            const ready = Object.assign({}, root.fakeUiServices.quickSettings.state.value,
                { bluetoothDevices: [], vpns: [] });
            root.fakeUiServices.quickSettings.state = { kind: "ready", value: ready };
            root.services.notifications.controller.setStatus("another-server");
            const tileByKey = function(key) {
                return panel.quickSettingsGrid.tiles.find(function(tile) { return tile.key === key; }) || ({});
            };
            const wifiTile = tileByKey("network");
            const bluetoothTile = tileByKey("bluetooth");
            const dndTile = tileByKey("dnd");
            root.check("wifi-without-adapter-is-unavailable", !wifiTile.available
                && !wifiTile.active && wifiTile.subtitle === "Немає адаптера");
            root.check("bluetooth-enabled-without-device-is-explicit", bluetoothTile.active
                && bluetoothTile.subtitle === "Не підключено");
            root.check("dnd-explains-competing-service", !dndTile.available
                && dndTile.subtitle === "Інша служба");
            root.capture(".unavailable.png", function(saved) {
                root.check("unavailable-state-capture", saved);
                const vpn = root.findNamed(panel.quickSettingsGrid, "control-center-details-vpn");
                if (vpn) root.pointer.mouseClick(vpn, vpn.width / 2, vpn.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("empty-vpn-keeps-picker-and-disables-toggle", panel.detailsSection === "vpn"
                    && !panel.quickSettingsDetails.actionAvailable);
                root.sessionMenuAction(panel, "poweroff", 0, function() {
                    const menu = panel.sessionHeader.powerMenu;
                    const item = root.findNamed(menu.contentItem, "control-center-session-poweroff");
                    root.check("power-tap-only-hints-without-dispatch", menu.opened && !!item && item.holdHint
                        && panel.detailsSection !== "session" && root.fakeUiServices.session.confirmation === ""
                        && root.fakeUiServices.session.commands === 0, JSON.stringify({ opened: menu.opened,
                            hint: !!item && item.holdHint, section: panel.detailsSection,
                            confirmation: root.fakeUiServices.session.confirmation,
                            commands: root.fakeUiServices.session.commands }));
                    sessionShortHoldProbe.start();
                });
            });
        }
    }
    Timer {
        id: sessionShortHoldProbe
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const menu = panel.sessionHeader.powerMenu;
            const item = root.findNamed(menu.contentItem, "control-center-session-poweroff");
            if (item) root.pointer.mousePress(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
            sessionShortHoldRelease.start();
        }
    }
    Timer {
        id: sessionShortHoldRelease
        interval: 400
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            const menu = panel.sessionHeader.powerMenu;
            const item = root.findNamed(menu.contentItem, "control-center-session-poweroff");
            root.check("power-hold-fills-while-pressed", !!item && item.holdProgress > 0 && item.holdProgress < 1);
            root.capture(".session-hold.png", function(saved) {
                root.check("session-hold-capture", saved);
                if (item) root.pointer.mouseRelease(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("power-early-release-does-not-dispatch", menu.opened && root.fakeUiServices.session.commands === 0);
                menu.close();
                sessionRebootProbe.start();
            });
        }
    }
    Timer {
        id: sessionRebootProbe
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            root.sessionMenuAction(panel, "reboot", 1300, function() {
                const menu = panel.sessionHeader.powerMenu;
                root.check("restart-hold-dispatches-once-to-fake-port", root.fakeUiServices.session.commands === 1
                    && root.fakeUiServices.session.lastCommand.slice(-3).join(":") === "Reboot:b:true"
                    && (!menu.opened || menu.closeReason !== ""));
                if (root.fakeUiServices.session.lastCompletion) root.fakeUiServices.session.lastCompletion(false, "failed");
                root.check("session-failure-is-visible-and-clears-pending", root.fakeUiServices.session.pending === ""
                    && root.fakeUiServices.session.state.error === "failed" && panel.detailsSection === "session");
                sessionErrorProbe.start();
            });
        }
    }
    Timer {
        id: sessionErrorProbe
        interval: 280
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            root.check("session-error-page-has-no-confirm-step",
                !root.findNamed(panel.quickSettingsDetails, "control-center-session-confirm")
                && !root.findNamed(panel.quickSettingsDetails, "control-center-session-cancel"));
            root.capture(".session-error.png", function(saved) {
                root.check("session-error-capture", saved);
                root.report();
            });
        }
    }
    Timer {
        id: vpnReturn
        interval: 80
        onTriggered: {
            const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
            root.clickButton(panel.quickSettingsDetails, "control-center-details-back");
            root.check("vpn-details-return-to-controls", panel.detailsSection === "");
        }
    }
    Timer {
        id: shortCalendarProbe
        interval: 80
        onTriggered: {
            const organizer = root.findNamed(bar.popup.focusItem, "panel-organizer");
            const calendar = root.findNamed(organizer, "panel-calendar");
            const dates = root.findNamed(calendar, "panel-calendar-dates");
            root.check("short-calendar-dates-fit", !!dates && dates.mapToItem(calendar, 0, dates.height).y <= calendar.height);
            root.capture(".short-calendar.png", function(saved) {
                root.check("short-calendar-capture", saved);
                root.clickButton(organizer, "organizer-collapse");
                root.check("organizer-collapse-responds-to-pointer", root.services.organizer.document.collapsed);
            });
        }
    }

    Timer {
        id: mainSequence
        interval: 600
        repeat: true
        running: true
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                root.check("preview-organizer-initialized", root.services.organizer.initialized);
                root.services.session.request("poweroff");
                root.services.session.confirm();
                root.check("native-session-preview-does-not-launch-commands", root.services.session.workers.length === 0
                    && root.services.session.confirmation === "" && root.services.session.state.error === "read-only");
                root.services.session.cancel();
                root.services.popups.open("right", bar.outputId);
            } else if (root.step === 2) {
                root.addFixtures();
            } else if (root.step === 3) {
                const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
                if (panel) {
                    panel.services = root.fakeUiServices;
                    panel.brightness = root.fakeBrightness;
                }
                const center = root.findNamed(bar.popup.focusItem, "control-center-notifications");
                if (center) {
                    center.setGroupExpanded("calendar", true);
                    center.setGroupExpanded("build monitor", true);
                }
                root.check("right-drawer-attached-to-bar", bar.popup.visible
                    && bar.popup.shownSurface === "right" && bar.popup.attachedSurface.cornerGeometry.shoulder > 0);
                const reservedTop = root.reservedTopHeight + root.services.config.documents.layout.barHeight;
                root.check("right-drawer-uses-compositor-allocated-remaining-height",
                    bar.popup.exclusionMode === ExclusionMode.Normal && bar.popup.anchors.bottom
                        && bar.popup.margins.top === 0
                        && Math.abs(bar.popup.height + reservedTop - bar.screen.height) <= 1,
                    JSON.stringify({ topReserved: root.reservedTopHeight, pentadBar: root.services.config.documents.layout.barHeight,
                        drawerHeight: bar.popup.height, expectedTop: reservedTop, screenHeight: bar.screen.height }));
                root.check("control-center-loaded", !!panel && !!center);
                const userName = root.findNamed(panel.sessionHeader, "control-center-user-name");
                const hostName = root.findNamed(panel.sessionHeader, "control-center-host-name");
                root.check("header-shows-user-and-pc", !!userName && userName.text === "Max"
                    && !!hostName && hostName.text === "pentad-pc");
                root.check("notification-center-filled", root.services.notifications.state.history.length === 5
                    && center.groups.length === 2
                    && center.groups.some(function(group) { return group.records.length === 3; }));
                root.check("organizer-tasks-filled", root.services.organizer.document.tasks.length === 3);
                root.check("quick-controls-use-shared-grid", Math.abs(panel.quickSettingsGrid.width - panel.audioControls.width) < 1
                    && Math.abs(panel.audioControls.width - panel.brightnessControl.width) < 1);
                root.check("volume-and-microphone-are-separate-components", panel.audioControls !== panel.microphoneControls
                    && panel.audioControls.compactOutputSlider.visible && !panel.audioControls.compactInputSlider.visible
                    && panel.microphoneControls.compactInputSlider.visible && !panel.microphoneControls.compactOutputSlider.visible
                    && Math.abs(panel.microphoneControls.width - panel.audioControls.width) < 1);
                const grid = panel.quickSettingsGrid;
                const wifi = root.findNamed(grid, "control-center-toggle-network");
                const bluetooth = root.findNamed(grid, "control-center-toggle-bluetooth");
                const vpn = root.findNamed(grid, "control-center-toggle-vpn");
                const energy = root.findNamed(grid, "control-center-tile-energy");
                const airplane = root.findNamed(grid, "control-center-toggle-airplane");
                const inhibit = root.findNamed(grid, "control-center-toggle-inhibit");
                const night = root.findNamed(grid, "control-center-toggle-night");
                const dnd = root.findNamed(grid, "control-center-toggle-dnd");
                const wifiBounds = wifi.parent.mapToItem(grid, 0, 0);
                const bluetoothBounds = bluetooth.parent.mapToItem(grid, 0, 0);
                const vpnBounds = vpn.parent.mapToItem(grid, 0, 0);
                root.check("connections-occupy-equal-neighboring-cells", Math.abs(wifiBounds.y - bluetoothBounds.y) < 1
                    && Math.abs(wifi.parent.width - bluetooth.parent.width) < 1 && Math.abs(wifi.height - bluetooth.height) < 1
                    && bluetoothBounds.x > wifiBounds.x + wifi.parent.width && wifi.height <= 56);
                const pairs = [[wifi, bluetooth], [vpn, energy]];
                const cell = function(item) { return root.findCell(item); };
                root.check("default-grid-pairs-fill-each-line", pairs.every(function(pair) {
                    const left = cell(pair[0]).mapToItem(grid, 0, 0);
                    const right = cell(pair[1]).mapToItem(grid, 0, 0);
                    return Math.abs(left.y - right.y) < 1 && Math.abs(left.x) < 1
                        && Math.abs(cell(pair[0]).width - cell(pair[1]).width) < 1
                        && Math.abs(right.x + cell(pair[1]).width - grid.width) < 1;
                }));
                const toggles = ["airplane", "dnd", "night", "inhibit", "appearance", "screenshot"].map(function(key) {
                    return root.findNamed(grid, "control-center-edit-cell-" + key);
                });
                root.check("default-grid-toggles-fill-one-line-of-six", grid.chosenColumns === 6
                    && toggles.every(function(item, index) {
                        const point = item.mapToItem(grid, 0, 0);
                        return Math.abs(point.y - 2 * (cell(wifi).height + 8)) < 1
                            && Math.abs(item.width - toggles[0].width) < 1 && Math.abs(item.height - cell(wifi).height) < 1
                            && Math.abs(point.x - index * (toggles[0].width + 8)) < 1;
                    }) && Math.abs(toggles[5].mapToItem(grid, 0, 0).x + toggles[5].width - grid.width) < 1);
                root.check("round-toggle-fills-its-cell", Math.abs(airplane.width - toggles[0].width) < 1
                    && Math.abs(airplane.height - toggles[0].height) < 1);
                root.check("default-grid-rows-share-height-and-rhythm", pairs.every(function(pair, index) {
                    const y = cell(pair[0]).mapToItem(grid, 0, 0).y;
                    return Math.abs(cell(pair[0]).height - cell(wifi).height) < 1
                        && Math.abs(y - index * (cell(wifi).height + 8)) < 1;
                }));
                const logo = root.findNamed(panel.sessionHeader, "control-center-logo");
                root.check("header-logo-sits-on-brand-fill", !!logo && Qt.colorEqual(logo.color, Theme.tokens.accent));
                root.check("tailscale-has-no-tile-of-its-own", !root.findNamed(grid, "control-center-toggle-tailscale"));
                root.check("range-controls-show-confirmed-values", panel.audioControls.compactOutputSlider.valueKnown
                    && Math.abs(panel.audioControls.compactOutputSlider.confirmedValue - 0.64) < 0.01
                    && Math.abs(panel.brightnessControl.brightnessSlider.confirmedValue - 0.72) < 0.01);
                const requestedScale = Number(Quickshell.env("PENTAD_GALLERY_SCALE") || "1");
                root.check("gallery-scale-applied", Math.abs(bar.screen.devicePixelRatio - requestedScale) < 0.01,
                    `screen DPR ${bar.screen.devicePixelRatio}, requested ${requestedScale}`);
                // The editing walk-through takes several frames; hold the main sequence until it ends.
                mainSequence.stop();
                editProbe.start();
            } else if (root.step === 4) {
                const panel = root.findNamed(bar.popup.focusItem, "right-control-center");
                root.check("quick-settings-detail-opens", !!panel && panel.quickSettingsDetails.visible
                    && panel.quickSettingsDetails.section === "bluetooth");
                root.capture(".bluetooth.png", function(saved) {
                    root.check("bluetooth-selector-capture", saved);
                    if (panel) root.clickButton(panel.quickSettingsDetails, "control-center-details-back");
                    root.check("quick-settings-detail-reopens-grid", !!panel && panel.detailsSection === "");
                    selectorReturnCapture.start();
                });
            } else if (root.step === 5) {
                root.capture(".tasks.png", function(saved) {
                    root.check("tasks-capture", saved);
                    const todo = root.findNamed(bar.popup.focusItem, "organizer-todo-list");
                    if (todo) {
                        todo.draftField.text = "Тимчасове завдання";
                        root.services.organizer.setDraftText(todo.draftField.text);
                        root.clickButton(todo, "todo-add");
                    }
                        bar.popup.sideSurfaceHeightOverride = 600;
                });
            } else if (root.step === 6) {
                root.check("short-drawer-height", bar.popup.attachedSurface.height <= 600
                    && bar.popup.height <= 600 + Metrics.overlayShadowRoom);
                const todo = root.findNamed(bar.popup.focusItem, "organizer-todo-list");
                root.check("task-add-clears-draft", !!todo && todo.draftField.text === ""
                    && root.services.organizer.document.tasks.length === 4);
                const temporary = root.services.organizer.document.tasks.find(function(task) { return task.text === "Тимчасове завдання"; });
                if (temporary) root.services.organizer.removeTask(temporary.id);
                root.capture(".short.png", function(saved) {
                    root.check("short-control-center-capture", saved);
                    root.services.organizer.setTab("calendar");
                    shortCalendarProbe.start();
                });
            } else if (root.step === 7) {
                const organizer = root.findNamed(bar.popup.focusItem, "panel-organizer");
                root.check("collapsed-organizer-fits-bottom", !!organizer && organizer.height <= 42
                    && root.services.organizer.document.tasks.length === 3);
                const calendarTabs = root.findNamed(organizer, "organizer-tabs");
                root.check("organizer-tabs-follow-calendar", !!calendarTabs && calendarTabs.selectedIndex === 0);
                root.capture(".collapsed.png", function(saved) {
                    root.check("collapsed-organizer-capture", saved);
                    root.services.organizer.setCollapsed(false);
                    root.services.organizer.setTab("tasks");
                    root.services.organizer.document.tasks.slice().forEach(function(task) {
                        root.services.organizer.removeTask(task.id);
                    });
                });
            } else if (root.step === 8) {
                const tasks = root.findNamed(bar.popup.focusItem, "panel-organizer");
                root.check("organizer-empty-state", root.services.organizer.document.tasks.length === 0
                    && !!tasks);
                const taskTabs = root.findNamed(tasks, "organizer-tabs");
                root.check("organizer-tabs-follow-tasks", !!taskTabs && taskTabs.selectedIndex === 1);
                root.capture(".empty.png", function(saved) {
                    root.check("empty-organizer-capture", saved);
                    root.testNotificationStability(function() {
                        bar.popup.sideSurfaceHeightOverride = 0;
                        audioOutputProbe.start();
                    });
                });
                stop();
            }
        }
    }
}
