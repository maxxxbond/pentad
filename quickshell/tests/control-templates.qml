import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import QtTest
import Quickshell
import qs.components
import qs.features.system
import qs.theme
import "../logic/control-model.mjs" as ControlModel

ShellRoot {
    id: root

    property TestEvent pointer: TestEvent {}
    property var checks: []
    property var commands: []
    property int detailsCount: 0
    property int contextCount: 0
    property int comboActivations: 0
    property bool bluetoothAvailable: true
    property bool bluetoothActive: false
    property bool recording: false
    property var audioState: ({
        available: true,
        value: 0.4,
        confirmedValue: 0.4,
        selectedId: "speaker-a",
        choices: [
            { id: "speaker-a", label: "Built-in output" },
            { id: "speaker-b", label: "USB output" },
        ],
    })
    property real lastAudioRequest: -1
    property var wheelSliderRequests: []
    property var gridItems: ControlModel.defaultQuickMenu.items.slice(0, 4)
    property string pendingCapturePath: ""
    property var focusBeforePopover: null
    property int configSaveCount: 0
    property var quickCommands: []
    property var audioRequests: []

    QtObject {
        id: fakeConfig
        property var documents: ({ layout: { controlCenter: ControlModel.defaultQuickMenu, audioPresentation: "range-horizontal" } })
        signal commandFinished(string requestId, var result)
        function save(name, document) {
            const requestId = "fixture-save-" + (++root.configSaveCount);
            const next = Object.assign({}, documents, { [name]: document });
            Qt.callLater(function() {
                documents = next;
                commandFinished(requestId, { ok: true });
            });
            return requestId;
        }
    }
    QtObject {
        id: fakeQuickSettings
        property var state: ({ kind: "ready", value: {
            bluetooth: false, bluetoothAvailable: true, bluetoothDevices: [], vpns: [],
            airplane: false, airplaneAvailable: true, night: false, nightAvailable: true,
        } })
        function toggleBluetooth() {
            root.quickCommands = root.quickCommands.concat(["bluetooth"]);
            state = Object.assign({}, state, { value: Object.assign({}, state.value, { bluetooth: !state.value.bluetooth }) });
        }
    }
    QtObject {
        id: fakeNetwork
        property bool safeMode: false
        property var state: ({ kind: "ready", value: { devices: [{ type: "wifi" }], wifiHardwareEnabled: true, wifiEnabled: true, accessPoints: [] } })
        function setWifiEnabled(enabled) { root.quickCommands = root.quickCommands.concat(["wifi:" + enabled]); }
    }
    QtObject {
        id: fakeDesktop
        property bool preview: false
        property bool safeMode: false
        property var state: ({ kind: "ready", value: { inhibited: false } })
        signal commandFinished(string requestId, var result)
        function command(action) { root.quickCommands = root.quickCommands.concat([action]); }
    }
    QtObject { id: fakeNotifications; property var state: ({ status: "available", dnd: false }); function setDnd(value) { root.quickCommands = root.quickCommands.concat(["dnd:" + value]); } }
    QtObject { id: fakePower; property var profileState: ({ kind: "ready", value: { profiles: ["balanced", "power-saver"], actual: "balanced", pending: false } }) }
    QtObject {
        id: fakeAudio
        property bool active: true
        property bool safeMode: false
        property int serial: 0
        property var state: ({ kind: "ready", value: {
            output: { id: "out-default", label: "Studio output", volume: 0.35, muted: false },
            input: { id: "in-default", label: "Desk microphone", volume: 0.67, muted: false },
            outputs: [
                { id: "out-default", label: "Studio output", volume: 0.35, muted: false },
                { id: "out-usb", label: "USB headphones", volume: 0.72, muted: false },
            ],
            inputs: [{ id: "in-default", label: "Desk microphone", volume: 0.67, muted: false }],
        } })
        signal commandFinished(string requestId, var result)
        function record(kind, id, value) {
            const requestId = "audio-request-" + (++serial);
            root.audioRequests = root.audioRequests.concat([{ kind: kind, id: id, value: value }]);
            return requestId;
        }
        function setVolume(kind, value) { return record("level:" + kind, kind === "output" ? state.value.output.id : state.value.input.id, value); }
        function toggleMute(kind) { return record("mute:" + kind, kind === "output" ? state.value.output.id : state.value.input.id, null); }
        function setDefault(kind, id) { return record("select:" + kind, id, null); }
    }
    QtObject {
        id: fakeServices
        readonly property var config: fakeConfig
        readonly property var quickSettings: fakeQuickSettings
        readonly property var network: fakeNetwork
        readonly property var desktop: fakeDesktop
        readonly property var notifications: fakeNotifications
        readonly property var power: fakePower
        readonly property var audio: fakeAudio
        readonly property var popups: null
        function text(ukrainian, english) { return english; }
    }
    PentadSlider {
        id: reusableWheelSlider
        visible: false
        from: 0
        to: 1
        stepSize: 0.01
        wheelStepSize: 0.05
        value: 0.72
        onMoved: root.wheelSliderRequests = root.wheelSliderRequests.concat([value])
    }
    // Half-row level capsules, as the control-center grid places volume beside another tile.
    PentadSlider {
        id: narrowLowSlider
        visible: false
        width: 190
        height: 48
        referenceStyle: true
        trailingSlot: 44
        iconSource: Qt.resolvedUrl("../assets/icons/material/volume-up-symbolic.svg")
        label: "Volume"
        valueText: "24%"
        value: 0.24
    }
    PentadSlider {
        id: narrowHighSlider
        visible: false
        width: 190
        height: 48
        referenceStyle: true
        trailingSlot: 44
        iconSource: Qt.resolvedUrl("../assets/icons/material/volume-up-symbolic.svg")
        label: "Volume"
        valueText: "70%"
        value: 0.7
    }
    PentadSlider {
        id: settlingWheelSlider
        visible: false
        referenceStyle: true
        from: 0
        to: 1
        stepSize: 0.01
        value: 0.5
        confirmedValue: 0.5
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
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

    function findWithText(item, value) {
        if (!item) return null;
        if (item.text === value) return item;
        for (const child of item.children || []) {
            const found = findWithText(child, value);
            if (found) return found;
        }
        return null;
    }

    function captureAndFinish() {
        const path = Quickshell.env("PENTAD_ARTIFACT_PATH");
        if (!path) {
            check("panel-capture-skipped-without-artifact-path", true);
            popover.close();
            finish();
            return;
        }
        pendingCapturePath = path;
        popover.close();
        finishTimer.start();
    }

    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(item) { return item.passed; }) ? "pass" : "fail",
            checks: checks,
        }));
        Qt.quit();
    }

    Timer {
        id: finishTimer
        interval: 120
        repeat: false
        onTriggered: {
            const activeWindow = fixtureWindow.contentItem.Window.window;
            root.check("popover-close-restores-control-focus", activeWindow.activeFocusItem === root.focusBeforePopover,
                activeWindow.activeFocusItem ? activeWindow.activeFocusItem.objectName : "no active focus item");
            capturePanel.grabToImage(function(panelResult) {
                root.check("control-template-panel-captured", panelResult.saveToFile(root.pendingCapturePath));
                sliderSheet.grabToImage(function(sheetResult) {
                    root.check("slider-size-sheet-captured", sheetResult.saveToFile(root.pendingCapturePath + ".sliders.png"));
                    root.finish();
                });
            });
        }
    }

    FloatingWindow {
        id: integrationWindow
        visible: true
        implicitWidth: 720
        implicitHeight: 520
        color: "#101210"
        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            AudioControls {
                id: integrationAudio
                width: 680
                height: 160
                compact: true
                services: fakeServices
            }
            QuickSettingsGrid {
                id: integrationGrid
                width: 680
                height: 300
                services: fakeServices
            }
        }
    }

    // The three slider sizes at 0 %, low, mid and 100 %, plus muted, unknown, unconfirmed, error and
    // disabled states, for the capture only.
    FloatingWindow {
        id: sliderSheetWindow
        visible: true
        implicitWidth: 1080
        implicitHeight: 600
        color: "#101210"
        Rectangle {
            id: sliderSheet
            anchors.fill: parent
            color: "#111311"
            Column {
                x: 20
                y: 20
                spacing: 16
                Row {
                    spacing: 12
                    Repeater {
                        model: [0, 0.05, 0.5, 1]
                        PentadSlider {
                            required property real modelData
                            width: 240
                            size: "large"
                            iconSource: Qt.resolvedUrl("assets/icons/material/controls/light-mode-symbolic.svg")
                            label: "Brightness"
                            valueText: Math.round(modelData * 100) + "%"
                            value: modelData
                        }
                    }
                }
                Row {
                    spacing: 12
                    PentadSlider {
                        width: 240
                        size: "large"
                        trailingSlot: 44
                        iconSource: Qt.resolvedUrl("assets/icons/material/volume-up-symbolic.svg")
                        label: "Volume"
                        valueText: "70%"
                        value: 0.7
                    }
                    PentadSlider {
                        width: 240
                        size: "large"
                        trailingSlot: 44
                        muted: true
                        iconSource: Qt.resolvedUrl("assets/icons/material/volume-off-symbolic.svg")
                        label: "Muted"
                        valueText: "40%"
                        value: 0.4
                    }
                    PentadSlider {
                        width: 240
                        size: "large"
                        valueKnown: false
                        iconSource: Qt.resolvedUrl("assets/icons/material/controls/light-mode-symbolic.svg")
                        label: "Brightness"
                        valueText: "—"
                    }
                    PentadSlider {
                        width: 240
                        size: "large"
                        confirmedValue: 0.3
                        iconSource: Qt.resolvedUrl("assets/icons/material/volume-up-symbolic.svg")
                        label: "Unconfirmed"
                        valueText: "62%"
                        value: 0.62
                    }
                }
                Row {
                    spacing: 12
                    Repeater {
                        model: [0, 0.05, 0.5, 1]
                        PentadSlider {
                            required property real modelData
                            width: 64
                            height: 170
                            size: "large"
                            orientation: Qt.Vertical
                            trailingSlot: 44
                            iconSource: Qt.resolvedUrl("assets/icons/material/volume-up-symbolic.svg")
                            valueText: Math.round(modelData * 100) + "%"
                            value: modelData
                        }
                    }
                    Column {
                        spacing: 4
                        Repeater {
                            model: [0, 0.05, 0.5, 1]
                            PentadSlider {
                                required property real modelData
                                width: 300
                                value: modelData
                            }
                        }
                        PentadSlider { width: 300; error: true; value: 0.34 }
                        PentadSlider { width: 300; enabled: false; value: 0.6 }
                        PentadSlider { width: 300; confirmedValue: 0.3; value: 0.62 }
                    }
                    Column {
                        spacing: 4
                        Repeater {
                            model: [0, 0.05, 0.5, 1]
                            PentadSlider {
                                required property real modelData
                                width: 300
                                size: "thin"
                                value: modelData
                            }
                        }
                        PentadSlider { width: 300; size: "thin"; error: true; value: 0.34 }
                        PentadSlider { width: 300; size: "thin"; confirmedValue: 0.3; value: 0.62 }
                    }
                }
            }
        }
    }

    FloatingWindow {
        id: fixtureWindow
        PentadComboBox {
            id: pressCombo
            x: 430
            width: 150
            z: 10
            model: ["First", "Second"]
            onActivated: root.comboActivations++
        }
        visible: true
        implicitWidth: 900
        implicitHeight: 500
        color: "#101210"

        Rectangle {
            id: capturePanel
            anchors.fill: parent
            anchors.margins: 20
            radius: 24
            color: "#1b1e1b"

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                Row {
                    spacing: 18

                    Column {
                        spacing: 12

                        PentadControl {
                            id: bluetooth
                            objectName: "fixtureBluetoothControl"
                            width: 280
                            height: 128
                            definition: ControlModel.controlDefinition("bluetooth")
                            presentation: "tile"
                            controlState: ({ available: root.bluetoothAvailable, active: root.bluetoothActive,
                                subtitle: "2 paired devices", choices: [{ id: "headphones", label: "Headphones" }] })
                            onCommandRequested: function(action, value) {
                                root.commands = root.commands.concat([{ control: "bluetooth", action: action, value: value }]);
                                root.bluetoothActive = Boolean(value);
                            }
                            onDetailsRequested: root.detailsCount++
                            onContextRequested: root.contextCount++

                            PentadToolTip {
                                id: shortTooltip
                                objectName: "fixtureShortTooltip"
                                text: "Bluetooth"
                                detail: "Nearby devices"
                                delay: 0
                                visible: true
                            }

                            PentadToolTip {
                                id: longTooltip
                                objectName: "fixtureLongTooltip"
                                text: "The audio output is controlled by the selected device"
                                detail: "USB interface · 48 kHz"
                                delay: 0
                                visible: false
                            }
                        }

                        PentadControl {
                            id: audio
                            objectName: "fixtureAudioRange"
                            width: audio.presentation === "range-vertical" ? 72 : 320
                            height: audio.presentation === "range-vertical" ? 188 : 48
                            definition: ControlModel.controlDefinition("audio-output")
                            presentation: "range-horizontal"
                            controlState: root.audioState
                            onCommandRequested: function(action, value) {
                                root.commands = root.commands.concat([{ control: "audio", action: action, value: value }]);
                                root.lastAudioRequest = value;
                                root.audioState = Object.assign({}, root.audioState, { value: value });
                            }
                        }

                        PentadControl {
                            id: unsupported
                            objectName: "fixtureUnsupportedTemplate"
                            width: 180
                            height: 48
                            definition: ControlModel.controlDefinition("dnd")
                            presentation: "range-horizontal"
                            controlState: ({ available: true, active: false })
                            onCommandRequested: function(action, value) {
                                root.commands = root.commands.concat([{ control: "unsupported", action: action, value: value }]);
                            }
                        }

                        PentadControl {
                            id: recorder
                            objectName: "fixtureRecorderControl"
                            width: 180
                            height: 48
                            definition: ControlModel.controlDefinition("record")
                            presentation: "compact"
                            controlState: ({ available: true, lifecycleState: root.recording ? "recording" : "idle" })
                            onCommandRequested: function(action) {
                                root.commands = root.commands.concat([{ control: "record", action: action }]);
                            }
                        }
                    }

                    PentadControl {
                        id: verticalAudio
                        objectName: "fixtureVerticalAudioRange"
                        width: 72
                        height: 188
                        definition: ControlModel.controlDefinition("audio-output")
                        presentation: "range-vertical"
                        controlState: root.audioState
                        onCommandRequested: function(action, value) {
                            root.commands = root.commands.concat([{ control: "audio-vertical", action: action, value: value }]);
                            root.lastAudioRequest = value;
                            root.audioState = Object.assign({}, root.audioState, { value: value });
                        }
                    }

                    Column {
                        spacing: 12

                        PentadControl {
                            id: energyRow
                            objectName: "fixtureEnergyRow"
                            width: 300
                            height: 48
                            definition: ControlModel.controlDefinition("energy")
                            presentation: "row"
                            controlState: ({ available: true, subtitle: "Performance" })
                        }

                        Row {
                            spacing: 8

                            PentadControl {
                                id: uprightBluetooth
                                objectName: "fixtureUprightBluetooth"
                                width: 86
                                height: 104
                                definition: ControlModel.controlDefinition("bluetooth")
                                presentation: "vertical"
                                controlState: ({ available: true, active: root.bluetoothActive, subtitle: "Not connected" })
                                onCommandRequested: function(action, value) {
                                    root.commands = root.commands.concat([{ control: "upright", action: action, value: value }]);
                                }
                                onDetailsRequested: root.detailsCount++
                            }

                            PentadControl {
                                id: uprightAirplane
                                objectName: "fixtureUprightAirplane"
                                width: 86
                                height: 104
                                definition: ControlModel.controlDefinition("airplane")
                                presentation: "vertical"
                                controlState: ({ available: true, active: true })
                            }

                            PentadControl {
                                id: uprightEnergy
                                objectName: "fixtureUprightEnergy"
                                width: 118
                                height: 104
                                definition: ControlModel.controlDefinition("energy")
                                presentation: "vertical"
                                controlState: ({ available: true, subtitle: "Performance" })
                            }
                        }
                    }
                }

                MenuGrid {
                    id: grid
                    objectName: "fixtureMenuGrid"
                    width: 560
                    columns: 4
                    cellHeight: 54
                    spacing: 8
                    placements: root.gridItems
                    delegate: Component {
                        Item {
                            id: cellRoot
                            property var placement: null
                            objectName: placement ? "fixture-cell-" + placement.instanceId : "fixture-cell-unplaced"
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: "#252a25"
                                Text { anchors.centerIn: parent; text: cellRoot.placement ? cellRoot.placement.instanceId : "?"; color: "white" }
                            }
                        }
                    }
                }
            }
        }

        AttachedPopover {
            id: popover
            anchorItem: bluetooth.primaryButton
            grabFocus: false
            fill: "#1b1e1b"
            contentItem: Column {
                spacing: 8
                Text { width: 180; text: "Bluetooth options"; color: "white" }
                Button { width: 180; text: "Open settings" }
            }
        }

        TestCase {
            id: testCase
            name: "ControlTemplates"
            when: false

            function test_templatesAndGrid() {
                const compactWheel = findChild(integrationAudio.compactOutputSlider, "rangeWheelHandler");
                const genericWheel = findChild(audio.rangeControl, "rangeWheelHandler");
                root.check("all-range-wheel-handlers-accept-touchpads-and-mice", !!compactWheel && !!genericWheel
                    && (compactWheel.acceptedDevices & PointerDevice.TouchPad) !== 0
                    && (compactWheel.acceptedDevices & PointerDevice.Mouse) !== 0
                    && (genericWheel.acceptedDevices & PointerDevice.TouchPad) !== 0
                    && (genericWheel.acceptedDevices & PointerDevice.Mouse) !== 0);
                root.check("definitions-bind-without-issuing-commands", root.commands.length === 0);
                root.check("audio-fixture-keeps-stable-device-ids", root.audioState.selectedId === "speaker-a"
                    && root.audioState.choices.map(function(choice) { return choice.id; }).join(",") === "speaker-a,speaker-b");
                const passiveCount = root.commands.length;
                audio.presentation = "range-vertical";
                root.check("horizontal-to-vertical-switch-keeps-range-value", audio.rangeSlider.value === root.audioState.value
                    && Math.abs(audio.rangeSlider.value - 0.4) < 0.001 && root.commands.length === passiveCount);

                const highState = Object.assign({}, root.audioState, { value: 0.9, confirmedValue: 0.9 });
                root.audioState = highState;
                wait(0);
                const highY = verticalAudio.rangeSlider.handle.y;
                root.audioState = Object.assign({}, root.audioState, { value: 0.1, confirmedValue: 0.1 });
                wait(0);
                const lowY = verticalAudio.rangeSlider.handle.y;
                root.check("vertical-range-renders-high-above-low", highY < lowY, JSON.stringify({ highY: highY, lowY: lowY }));
                root.audioState = Object.assign({}, root.audioState, { value: 0.15, confirmedValue: 0.15 });
                root.lastAudioRequest = -1;
                const verticalClicked = root.pointer.mouseClick(audio.rangeSlider, audio.rangeSlider.width / 2,
                    audio.rangeSlider.height * 0.12, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("vertical-slider-pointer-selects-upper-range", verticalClicked && root.lastAudioRequest > 0.8,
                    String(root.lastAudioRequest));
                const rangeValue = root.audioState.value;
                audio.presentation = "range-horizontal";
                wait(0);
                root.check("range-value-survives-template-switch-without-command", Math.abs(audio.rangeSlider.value - rangeValue) < 0.001
                    && root.lastAudioRequest === rangeValue);
                root.audioState = Object.assign({}, root.audioState, { value: 0.4, confirmedValue: 0.4 });
                root.lastAudioRequest = 0.4;
                const wheelStart = root.audioState.value;
                const fractionalWheel = { pixelDelta: { y: 20 }, angleDelta: { y: 0 }, accepted: false };
                audio.rangeControl.handleWheel(fractionalWheel);
                root.check("fractional-wheel-handler-keeps-partial-step", root.lastAudioRequest === wheelStart
                    && Math.abs(audio.rangeControl.wheelRemainder - 0.5) < 0.001);
                audio.rangeControl.handleWheel(fractionalWheel);
                root.check("fractional-wheel-handler-accumulates-to-range-step", root.lastAudioRequest > wheelStart
                    && Math.abs(root.lastAudioRequest - (wheelStart + 0.02)) < 0.001,
                    JSON.stringify({ start: wheelStart, requested: root.lastAudioRequest }));
                const reverseWheel = { pixelDelta: { y: -20 }, angleDelta: { y: 0 }, accepted: false };
                audio.rangeControl.handleWheel(reverseWheel);
                root.check("generic-range-wheel-resets-partial-delta-on-reversal",
                    Math.abs(audio.rangeControl.wheelRemainder + 0.5) < 0.001 && reverseWheel.accepted);

                reusableWheelSlider.handleWheel({ pixelDelta: { y: 20 }, angleDelta: { y: 0 }, accepted: false });
                root.check("reusable-range-wheel-accumulates-fractional-input", root.wheelSliderRequests.length === 0
                    && Math.abs(reusableWheelSlider.wheelRemainder - 0.5) < 0.001);
                reusableWheelSlider.handleWheel({ pixelDelta: { y: 20 }, angleDelta: { y: 0 }, accepted: false });
                root.check("reusable-range-wheel-honors-adjustment-and-snap-steps",
                    root.wheelSliderRequests.length === 1 && Math.abs(root.wheelSliderRequests[0] - 0.77) < 0.001,
                    JSON.stringify(root.wheelSliderRequests));
                reusableWheelSlider.value = 0.99;
                reusableWheelSlider.handleWheel({ pixelDelta: { y: 0 }, angleDelta: { y: 1200 }, accepted: false });
                root.check("reusable-range-wheel-clamps-at-upper-bound", reusableWheelSlider.value === 1);
                const atUpperBoundCount = root.wheelSliderRequests.length;
                reusableWheelSlider.handleWheel({ pixelDelta: { y: 0 }, angleDelta: { y: 120 }, accepted: false });
                root.check("reusable-range-wheel-does-not-overshoot-bound", reusableWheelSlider.value === 1
                    && root.wheelSliderRequests.length === atUpperBoundCount);
                // A device that trails the wheel is not lagging while the wheel still turns; it is once the wheel rests.
                settlingWheelSlider.handleWheel({ pixelDelta: { y: 0 }, angleDelta: { y: 360 }, accepted: false });
                root.check("range-wheel-steering-keeps-value-ink", settlingWheelSlider.wheeling
                    && !settlingWheelSlider.settling && !settlingWheelSlider.lagging);
                settlingWheelSlider.wheeling = false;
                root.check("range-wheel-rest-shows-unconfirmed-value", settlingWheelSlider.settling);
                // Asked and real level both show: solid fill to the device's level, a translucent band on to the asked one.
                wait(1100);
                root.check("range-shows-real-level-solid-and-asked-level-as-band",
                    Math.abs(settlingWheelSlider.solidExtent - settlingWheelSlider.confirmedExtent) < 0.5
                        && Math.abs(settlingWheelSlider.bandExtent - settlingWheelSlider.fillExtent) < 0.5
                        && settlingWheelSlider.bandExtent > settlingWheelSlider.solidExtent + 1,
                    JSON.stringify({ solid: settlingWheelSlider.solidExtent, band: settlingWheelSlider.bandExtent,
                        real: settlingWheelSlider.confirmedExtent, asked: settlingWheelSlider.fillExtent }));
                // In a short capsule the value never covers the icon or the slot, and it holds its place at any level:
                // the ink changes colour at the fill edge instead of hopping around the handle.
                const lowTextLeft = narrowLowSlider.valueX + narrowLowSlider.valueWidth - narrowLowSlider.valueTextWidth;
                root.check("narrow-range-value-stays-off-icon", lowTextLeft >= narrowLowSlider.iconSlot
                    && lowTextLeft + narrowLowSlider.valueTextWidth <= narrowLowSlider.separatorAt
                    && !narrowLowSlider.labelShown,
                    JSON.stringify({ textLeft: lowTextLeft, separator: narrowLowSlider.separatorAt, label: narrowLowSlider.labelShown }));
                root.check("narrow-range-value-holds-its-place-at-any-level",
                    narrowHighSlider.valueX === narrowLowSlider.valueX && narrowHighSlider.valueOnFill && !narrowLowSlider.valueOnFill,
                    JSON.stringify({ low: narrowLowSlider.valueX, high: narrowHighSlider.valueX }));

                const audioRequestCount = root.audioRequests.length;
                if (typeof mouseWheel === "function") {
                    root.pointer.mouseMove(integrationAudio.compactOutputSlider,
                        integrationAudio.compactOutputSlider.width / 2,
                        integrationAudio.compactOutputSlider.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                    mouseWheel(integrationAudio.compactOutputSlider,
                        integrationAudio.compactOutputSlider.width / 2,
                        integrationAudio.compactOutputSlider.height / 2,
                        0, 120, Qt.NoButton, Qt.NoModifier, 0);
                    root.check("physical-wheel-event-reaches-reusable-audio-slider",
                        root.audioRequests.length === audioRequestCount + 1
                            && Math.abs(root.audioRequests[audioRequestCount].value - 0.37) < 0.001,
                        JSON.stringify(root.audioRequests.slice(audioRequestCount)));
                } else {
                    root.check("physical-wheel-api-unavailable", true, "QtTest mouseWheel is not exposed in this runtime");
                }
                const burstStart = root.audioRequests.length;
                integrationAudio.compactOutputSlider.handleWheel({ pixelDelta: { y: 0 }, angleDelta: { y: 120 }, accepted: false });
                integrationAudio.compactOutputSlider.handleWheel({ pixelDelta: { y: 0 }, angleDelta: { y: 120 }, accepted: false });
                root.check("compact-audio-wheel-preserves-latest-desired-value",
                    root.audioRequests.length === burstStart + 2
                        && Math.abs(root.audioRequests[burstStart].value - 0.39) < 0.001
                        && Math.abs(root.audioRequests[burstStart + 1].value - 0.41) < 0.001,
                    JSON.stringify(root.audioRequests.slice(burstStart)));

                const range = integrationAudio.compactOutputSlider;
                const outputPicker = root.findNamed(integrationAudio, "control-center-details-audio-output");
                root.check("reference-range-stops-before-chevron-in-same-capsule", !!outputPicker
                    && outputPicker.x >= range.x + range.span + 4 && outputPicker.x + outputPicker.width <= range.x + range.width,
                    JSON.stringify({ span: range.span, width: range.width, picker: outputPicker ? outputPicker.x : null }));
                const grabStart = root.audioRequests.length;
                const grabValue = range.value;
                const grabX = range.width * 0.7;
                root.pointer.mousePress(range, grabX, range.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("reference-range-press-does-not-jump", root.audioRequests.length === grabStart
                    && Math.abs(range.value - grabValue) < 0.001, JSON.stringify({ before: grabValue, after: range.value }));
                root.pointer.mouseMove(range, grabX + range.travel * 0.1, range.height / 2, 0, Qt.LeftButton, Qt.NoModifier);
                root.check("reference-range-drags-relative-to-press", range.grabbing && root.audioRequests.length > grabStart
                    && Math.abs(range.value - (grabValue + 0.1)) < 0.011, JSON.stringify({ before: grabValue, after: range.value }));
                root.pointer.mouseRelease(range, grabX + range.travel * 0.1, range.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("reference-range-release-keeps-dragged-value", !range.grabbing
                    && Math.abs(range.value - (grabValue + 0.1)) < 0.011, String(range.value));
                root.pointer.mouseClick(range, range.span - 2, range.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                const fullRequest = root.audioRequests[root.audioRequests.length - 1];
                root.check("reference-range-click-at-far-end-sets-full", fullRequest.value === 1 && range.value === 1,
                    JSON.stringify(fullRequest));
                // The fill edge follows the level through the whole capsule, and the capsule on its edge is gone
                // wherever it would touch the icon, the label, the value or the separator, and shown elsewhere.
                const inkClashes = [];
                [0, 0.05, 0.15, 0.5, 0.9, 1].forEach(function(level) {
                    range.value = level;
                    // The glide takes 150 ms and the capsule's fade 140 ms.
                    wait(450);
                    const aside = range.thumbOverText || range.thumbOverSeparator;
                    if (Math.abs(range.fillExtent - level * range.trackLength) > 1
                        || Math.abs(range.thumbCentre - (range.fillExtent - 5)) > 0.5
                        || aside && range.handle.opacity > 0.01
                        || !aside && range.handle.opacity < 0.1)
                        inkClashes.push({ level: level, fill: range.fillExtent, centre: range.thumbCentre,
                            aside: aside, opacity: range.handle.opacity });
                });
                root.check("reference-range-fill-follows-level-and-capsule-keeps-clear-of-ink", inkClashes.length === 0,
                    JSON.stringify(inkClashes));
                const syntheticWheelStart = root.lastAudioRequest;
                if (typeof mouseWheel === "function") {
                    root.pointer.mouseMove(audio.rangeSlider, audio.rangeSlider.width / 2,
                        audio.rangeSlider.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                    for (let tick = 0; tick < 6; ++tick)
                        mouseWheel(audio.rangeSlider, audio.rangeSlider.width / 2, audio.rangeSlider.height / 2,
                            0, 120, Qt.NoButton, Qt.NoModifier, 0);
                    root.check("synthetic-wheel-events-reach-native-range-control", root.lastAudioRequest > syntheticWheelStart,
                        JSON.stringify({ start: syntheticWheelStart, requested: root.lastAudioRequest }));
                } else {
                    root.check("synthetic-wheel-api-unavailable", true, "QtTest mouseWheel is not exposed in this runtime");
                }

                const beforeUnsupported = root.commands.length;
                unsupported.activatePrimary();
                root.check("incompatible-template-is-hidden-and-cannot-command", !unsupported.compatible && !unsupported.visible
                    && root.commands.length === beforeUnsupported);

                const beforeRecord = root.commands.length;
                recorder.activatePrimary();
                root.recording = true;
                recorder.activatePrimary();
                root.check("record-lifecycle-uses-only-supported-start-and-stop", root.commands.length === beforeRecord + 2
                    && root.commands[beforeRecord].action === "record.start"
                    && root.commands[beforeRecord + 1].action === "record.stop");

                const beforeToggle = root.commands.length;
                root.pointer.mousePress(pressCombo, 20, pressCombo.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("combo-opens-on-press", pressCombo.popup.visible);
                root.pointer.mouseRelease(pressCombo, 20, pressCombo.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("combo-release-keeps-options-open", pressCombo.popup.visible);
                // The list drops out on a spring; press a row once it is fully shown.
                for (let i = 0; i < 90 && pressCombo.listLevel < 0.99; i++)
                    wait(16);
                const comboOption = pressCombo.popup.contentItem.itemAtIndex(1);
                const releasePoint = comboOption.mapToItem(fixtureWindow.contentItem, 20, comboOption.height / 2);
                root.pointer.mousePress(comboOption, 20, comboOption.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("combo-option-activates-on-press", pressCombo.currentIndex === 1 && root.comboActivations === 1);
                root.pointer.mouseRelease(fixtureWindow.contentItem, releasePoint.x, releasePoint.y, Qt.LeftButton, Qt.NoModifier, 0);
                // The pick closes the list at once; it stays drawn only while it folds away.
                root.check("combo-option-release-does-not-repeat", root.comboActivations === 1 && !pressCombo.popup.opened);
                pressCombo.forceActiveFocus();
                root.pointer.keyClick(Qt.Key_Space, Qt.NoModifier, 0);
                root.check("combo-keeps-native-keyboard-opening", pressCombo.popup.visible);
                pressCombo.popup.close();
                // The list stays drawn, and takes presses over it, while it folds away.
                for (let i = 0; i < 90 && pressCombo.popup.visible; i++)
                    wait(16);
                const primaryClicked = root.pointer.mousePress(bluetooth.primaryButton, bluetooth.primaryButton.width / 2,
                    bluetooth.primaryButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("primary-pointer-click-issues-only-toggle", primaryClicked && root.commands.length === beforeToggle + 1
                    && root.commands[root.commands.length - 1].control === "bluetooth"
                    && root.commands[root.commands.length - 1].action === "toggle" && root.bluetoothActive);
                root.pointer.mouseRelease(bluetooth.primaryButton, bluetooth.primaryButton.width / 2,
                    bluetooth.primaryButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("primary-release-does-not-repeat-command", root.commands.length === beforeToggle + 1);

                const beforeDetails = root.commands.length;
                const detailsClicked = root.pointer.mouseClick(bluetooth.detailsButton, bluetooth.detailsButton.width / 2,
                    bluetooth.detailsButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("details-button-is-independent", detailsClicked && root.detailsCount === 1
                    && root.commands.length === beforeDetails);

                const beforeUnavailable = root.commands.length;
                root.bluetoothAvailable = false;
                wait(0);
                root.pointer.mouseClick(bluetooth.primaryButton, bluetooth.primaryButton.width / 2,
                    bluetooth.primaryButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                const detailsWhenUnavailable = root.pointer.mouseClick(bluetooth.detailsButton, bluetooth.detailsButton.width / 2,
                    bluetooth.detailsButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("unavailable-blocks-primary-and-keeps-details", root.commands.length === beforeUnavailable
                    && root.detailsCount === 2 && detailsWhenUnavailable);
                root.bluetoothAvailable = true;

                const beforeContext = root.commands.length;
                const contextClicked = root.pointer.mouseClick(bluetooth, bluetooth.width / 2, bluetooth.height / 2,
                    Qt.RightButton, Qt.NoModifier, 0);
                root.check("context-pointer-click-is-independent", contextClicked && root.contextCount === 1
                    && root.commands.length === beforeContext);
                bluetooth.forceActiveFocus();
                const keyboardContext = root.pointer.keyClick(Qt.Key_F10, Qt.ShiftModifier, 0);
                root.check("shift-f10-opens-context-without-command", keyboardContext && root.contextCount === 2
                    && root.commands.length === beforeContext);

                const shortBubble = shortTooltip.window;
                longTooltip.visible = true;
                wait(60);
                const longBubble = longTooltip.window;
                root.check("short-and-long-tooltips-size-to-content", !!shortBubble && !!longBubble
                    && shortBubble.implicitWidth >= 100 && longBubble.implicitWidth > shortBubble.implicitWidth
                    && shortBubble.implicitHeight >= 44 && longBubble.implicitHeight >= 44,
                    JSON.stringify({ short: shortBubble ? [shortBubble.implicitWidth, shortBubble.implicitHeight] : null,
                        long: longBubble ? [longBubble.implicitWidth, longBubble.implicitHeight] : null }));
                longTooltip.visible = false;

                const beforeReorder = root.commands.length;
                const originalIds = grid.resolvedLayout.items.map(function(item) { return item.instanceId; });
                root.gridItems = [root.gridItems[1], root.gridItems[0], root.gridItems[2], root.gridItems[3]];
                wait(0);
                const reordered = grid.resolvedLayout.items;
                const cell = root.findNamed(grid, "fixture-cell-" + reordered[0].instanceId);
                let noOverlap = true;
                for (let i = 0; i < reordered.length; ++i) {
                    for (let j = i + 1; j < reordered.length; ++j) {
                        const a = reordered[i];
                        const b = reordered[j];
                        if (a.column < b.column + b.columnSpan && b.column < a.column + a.columnSpan
                            && a.row < b.row + b.rowSpan && b.row < a.row + a.rowSpan) noOverlap = false;
                    }
                }
                root.check("grid-reorder-keeps-identities-and-does-not-command", reordered.map(function(item) { return item.instanceId; }).join(",")
                    === [originalIds[1], originalIds[0]].concat(originalIds.slice(2)).join(",")
                    && root.commands.length === beforeReorder);
                root.check("grid-first-fit-has-no-overlaps-and-forwards-placement", noOverlap && !!cell && cell.placement
                    && cell.placement.instanceId === reordered[0].instanceId);

                const integrationCommands = root.quickCommands.length;
                const integrationBluetoothButton = root.findNamed(integrationGrid, "control-center-toggle-bluetooth");
                const bluetoothClicked = integrationBluetoothButton
                    && root.pointer.mouseClick(integrationBluetoothButton,
                        integrationBluetoothButton.width / 2, integrationBluetoothButton.height / 2,
                        Qt.LeftButton, Qt.NoModifier, 0);
                root.check("quick-settings-routes-toggle-through-real-control", bluetoothClicked
                    && root.quickCommands[root.quickCommands.length - 1] === "bluetooth");

                const initialPlacement = integrationGrid.normalizedMenu.value.items.find(function(item) {
                    return item.definitionId === "bluetooth";
                });
                integrationGrid.showContext(integrationBluetoothButton, initialPlacement);
                integrationGrid.changeTemplate("compact");
                wait(20);
                integrationGrid.changeSize(4, 1);
                wait(20);
                const savedBluetooth = fakeConfig.documents.layout.controlCenter.items.find(function(item) {
                    return item.instanceId === initialPlacement.instanceId;
                });
                const savesBeforeInvalidSize = root.configSaveCount;
                integrationGrid.changeSize(0, 1);
                root.check("quick-settings-persists-template-and-size-by-instance", !!savedBluetooth
                    && savedBluetooth.template === "compact" && savedBluetooth.columnSpan === 4
                    && savedBluetooth.rowSpan === 1 && root.quickCommands.length === integrationCommands + 1,
                    JSON.stringify(savedBluetooth));
                root.check("quick-settings-rejects-invalid-size-without-saving", root.configSaveCount === savesBeforeInvalidSize
                    && integrationGrid.menuError !== "");

                const requestsBeforeAudio = root.audioRequests.length;
                const sliderClicked = root.pointer.mouseClick(integrationAudio.compactOutputSlider,
                    integrationAudio.compactOutputSlider.width * 0.78, integrationAudio.compactOutputSlider.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0);
                const levelRequest = root.audioRequests[root.audioRequests.length - 1];
                root.check("audio-range-routes-volume-to-stable-output-id", sliderClicked && !!levelRequest
                    && levelRequest.kind === "level:output" && levelRequest.id === "out-default"
                    && root.audioRequests.length > requestsBeforeAudio, JSON.stringify(levelRequest));
                const muteButton = root.findNamed(integrationAudio, "control-center-toggle-audio-output");
                const muteClicked = muteButton && root.pointer.mouseClick(muteButton,
                    muteButton.width / 2, muteButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                const muteRequest = root.audioRequests[root.audioRequests.length - 1];
                root.check("audio-mute-routes-to-stable-output-id", muteClicked && !!muteRequest
                    && muteRequest.kind === "mute:output" && muteRequest.id === "out-default", JSON.stringify(muteRequest));
                integrationAudio.detailsExpanded = true;
                integrationAudio.deviceSection = "audio-output";
                wait(0);
                const otherOutput = root.findWithText(integrationAudio, "USB headphones");
                const choiceClicked = otherOutput && root.pointer.mouseClick(otherOutput,
                    otherOutput.width / 2, otherOutput.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                const choiceRequest = root.audioRequests[root.audioRequests.length - 1];
                root.check("audio-choice-routes-selected-device-id", choiceClicked && !!choiceRequest
                    && choiceRequest.kind === "select:output" && choiceRequest.id === "out-usb", JSON.stringify(choiceRequest));

                // A row without its own toggle draws its disc on the button background; the icon must sit in its centre.
                const energyIcon = root.findNamed(energyRow, "controlIcon");
                const energyCenter = energyIcon ? energyIcon.mapToItem(energyRow, energyIcon.width / 2, energyIcon.height / 2) : null;
                root.check("row-disc-icon-is-centred-in-disc", !!energyCenter && energyRow.discIndicator
                    && Math.abs(energyCenter.x - (energyRow.radioInset + energyRow.radioDiameter / 2)) < 0.6
                    && Math.abs(energyCenter.y - energyRow.height / 2) < 0.6,
                    JSON.stringify({ icon: energyCenter ? [energyCenter.x, energyCenter.y] : null,
                        disc: [energyRow.radioInset + energyRow.radioDiameter / 2, energyRow.height / 2] }));

                const overlaps = function(a, b) {
                    return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
                };
                for (const upright of [uprightBluetooth, uprightAirplane, uprightEnergy]) {
                    const icon = root.findNamed(upright, "controlIcon");
                    const text = root.findNamed(upright, "controlText");
                    const iconBox = icon.mapToItem(upright, 0, 0, icon.width, icon.height);
                    const textBox = text.mapToItem(upright, 0, 0, text.width, text.height);
                    const arrow = upright.detailsButton.visible
                        ? Qt.rect(upright.detailsButton.x, upright.detailsButton.y, upright.detailsButton.width, upright.detailsButton.height) : null;
                    const detail = JSON.stringify({ icon: [iconBox.x, iconBox.y, iconBox.width, iconBox.height],
                        text: [textBox.x, textBox.y, textBox.width, textBox.height], arrow: arrow ? [arrow.x, arrow.y] : null,
                        truncated: upright.textTruncated });
                    root.check("vertical-button-stacks-readable-label-" + upright.objectName, text.visible
                        && Math.abs(iconBox.x + iconBox.width / 2 - upright.width / 2) < 0.6
                        && iconBox.y + iconBox.height <= textBox.y && textBox.x >= 0 && textBox.x + textBox.width <= upright.width
                        && textBox.y + textBox.height <= upright.height && !upright.textTruncated
                        && (!arrow || (!overlaps(arrow, iconBox) && !overlaps(arrow, textBox))), detail);
                }
                root.check("vertical-button-fills-when-active", uprightAirplane.filledActive
                    && Qt.colorEqual(uprightAirplane.ink, Theme.tokens.onAccent));

                const beforeUpright = root.commands.length;
                const uprightClicked = root.pointer.mouseClick(uprightBluetooth.primaryButton, uprightBluetooth.primaryButton.width / 2,
                    uprightBluetooth.primaryButton.height * 0.7, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("vertical-button-toggles", uprightClicked && root.commands.length === beforeUpright + 1
                    && root.commands[beforeUpright].control === "upright" && root.commands[beforeUpright].action === "toggle");
                const detailsBeforeUpright = root.detailsCount;
                const uprightDetails = root.pointer.mouseClick(uprightBluetooth.detailsButton, uprightBluetooth.detailsButton.width / 2,
                    uprightBluetooth.detailsButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("vertical-button-arrow-opens-details-only", uprightDetails && root.detailsCount === detailsBeforeUpright + 1
                    && root.commands.length === beforeUpright + 1);

                const compactPlacement = fakeConfig.documents.layout.controlCenter.items.find(function(item) {
                    return item.instanceId === initialPlacement.instanceId;
                });
                integrationGrid.showContext(integrationBluetoothButton, compactPlacement);
                integrationGrid.changeTemplate("vertical");
                // Cells glide to their new size; measure once the move has settled.
                wait(600);
                const standing = fakeConfig.documents.layout.controlCenter.items.find(function(item) {
                    return item.instanceId === initialPlacement.instanceId;
                });
                root.check("quick-settings-saves-vertical-template-at-readable-width", !!standing && standing.template === "vertical"
                    && standing.columnSpan === ControlModel.minimumTemplateColumns("vertical", 6) && standing.rowSpan === 2
                    && ControlModel.validateMenuLayout(fakeConfig.documents.layout.controlCenter).ok, JSON.stringify(standing));
                const standingButton = root.findNamed(integrationGrid, "control-center-toggle-bluetooth");
                const standingCommands = root.quickCommands.length;
                const standingClicked = !!standingButton && standingButton.height > 90 && root.pointer.mouseClick(standingButton,
                    standingButton.width / 2, standingButton.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.check("quick-settings-vertical-button-routes-toggle", standingClicked
                    && root.quickCommands.length === standingCommands + 1
                    && root.quickCommands[root.quickCommands.length - 1] === "bluetooth",
                    standingButton ? JSON.stringify([standingButton.width, standingButton.height]) : "no button");

                bluetooth.forceActiveFocus();
                wait(0);
                root.focusBeforePopover = fixtureWindow.contentItem.Window.window.activeFocusItem;
                popover.open();
                wait(60);
                const popupWindow = popover.window;
                const popupMask = popover.surface.containmentMask;
                const anchorRect = popupWindow.anchorRect;
                const cornerResults = popupMask && typeof popupMask.contains === "function" ? [
                    popupMask.contains(Qt.point(1, 1)),
                    popupMask.contains(Qt.point(popupWindow.width - 1, 1)),
                    popupMask.contains(Qt.point(1, popupWindow.height - 1)),
                    popupMask.contains(Qt.point(popupWindow.width - 1, popupWindow.height - 1)),
                ] : [];
                const cornerExcluded = cornerResults.length === 4 && cornerResults.some(function(inside) { return !inside; });
                root.check("attached-popover-opens-at-control", popover.opened && popover.anchorItem === bluetooth.primaryButton
                    && popupWindow.width > 0 && popupWindow.height > 0
                    && Number.isFinite(anchorRect.x) && Number.isFinite(anchorRect.y)
                    && anchorRect.width === bluetooth.primaryButton.width && anchorRect.height === bluetooth.primaryButton.height,
                    JSON.stringify({ opened: popover.opened, anchor: popover.anchorItem === bluetooth.primaryButton,
                        x: popupWindow.x, y: popupWindow.y, width: popupWindow.width, height: popupWindow.height,
                        anchorX: anchorRect.x, anchorY: anchorRect.y,
                        anchorWidth: anchorRect.width, anchorHeight: anchorRect.height }));
                root.check("attached-popover-excludes-transparent-corners", cornerExcluded,
                    popupMask && typeof popupMask.contains === "function" ? JSON.stringify(cornerResults) : "mask contains API unavailable");
                root.captureAndFinish();
            }
        }

        Timer {
            interval: 300
            running: true
            repeat: false
            onTriggered: testCase.test_templatesAndGrid()
        }
    }
}
