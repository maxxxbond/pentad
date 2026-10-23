pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import qs.features.system
import "../../logic/settings-devices.mjs" as Devices

// A live device panel on a settings page (`control: 'panel'`). Wi-Fi and sound reuse the control
// center's components; power and brightness lie as rows on one section card. Everything here is
// destroyed with the page, so scans and the mixer stop as soon as the page is left.
Item {
    id: root
    required property var services
    required property string panel
    implicitHeight: loader.item ? loader.item.implicitHeight : 0

    function t(uk, en) { return services.text(uk, en); }

    Loader {
        id: loader
        width: root.width
        sourceComponent: root.panel === "wifi" ? wifiPanel
            : root.panel === "sound" ? soundPanel
            : root.panel === "mixer" ? mixerPanel
            : root.panel === "power" ? powerPanel
            : root.panel === "brightness" ? brightnessPanel
            : root.panel === "bluetooth" ? bluetoothPanel
            : root.panel === "bluetooth-devices" ? bluetoothDevicesPanel
            : root.panel === "bluetooth-nearby" ? bluetoothNearbyPanel : null
    }

    // A "Wi-Fi" row with its switch, then the control center's network list on the same card.
    Component {
        id: wifiPanel
        RowCard {
            id: wifiCard
            objectName: "settings-panel-wifi"
            readonly property var network: root.services.network
            readonly property var adapter: network ? network.state : ({ kind: "unavailable" })
            readonly property bool wifiOn: adapter.kind === "ready" && adapter.value.wifiEnabled === true
            property string pendingRequest: ""
            property string toggleError: ""

            Connections {
                target: wifiCard.network
                function onCommandFinished(requestId, result) {
                    if (requestId !== wifiCard.pendingRequest) return;
                    wifiCard.pendingRequest = "";
                    wifiCard.toggleError = result.ok ? ""
                        : root.t("Не вдалося перемкнути Wi-Fi", "Could not switch Wi-Fi") + " (" + (result.reason || "failed") + ")";
                }
            }

            SettingsRow {
                width: wifiCard.width
                label: "Wi-Fi"
                pending: wifiCard.pendingRequest !== ""
                error: wifiCard.toggleError !== ""
                errorText: wifiCard.toggleError
                PentadToggle {
                    objectName: "settings-wifi-toggle"
                    implicitHeight: Metrics.controlSmall
                    accessibleName: "Wi-Fi"
                    checked: wifiCard.wifiOn
                    pending: wifiCard.pendingRequest !== ""
                    requestedEnabled: wifiCard.adapter.kind === "ready" && wifiCard.adapter.value.wifiHardwareEnabled
                        && !root.services.safeMode && wifiCard.pendingRequest === ""
                    onToggled: {
                        wifiCard.toggleError = "";
                        wifiCard.pendingRequest = wifiCard.network.setWifiEnabled(checked);
                        checked = Qt.binding(function() { return wifiCard.wifiOn; });
                    }
                }
            }
            // The list sits on the card under a separator line, inset like a row.
            Item {
                width: wifiCard.width
                implicitHeight: networkList.implicitHeight + 24
                Rectangle {
                    x: 16
                    width: parent.width - 32
                    height: 1
                    color: Theme.tokens.outline
                }
                NetworkControls {
                    id: networkList
                    objectName: "settings-wifi-list"
                    x: 16
                    y: 12
                    width: parent.width - 32
                    services: root.services
                    selectorMode: true
                }
            }
        }
    }

    Component {
        id: soundPanel
        AudioControls {
            objectName: "settings-panel-sound"
            width: root.width
            services: root.services
        }
    }

    Component {
        id: mixerPanel
        ContinuousSurface {
            objectName: "settings-panel-mixer"
            width: root.width
            implicitHeight: mixer.implicitHeight + 24
            fill: Theme.tokens.surfaceRaised
            extent: Metrics.radiusCard
            ApplicationMixer {
                id: mixer
                x: 12
                y: 12
                width: parent.width - 24
                height: implicitHeight
                services: root.services
                consumerId: "settings-mixer"
                presented: true
            }
        }
    }

    // Rows flatten onto this card exactly as they do inside a SettingsSection.
    component RowCard: ContinuousSurface {
        default property alias rows: rowColumn.data
        width: root.width
        implicitHeight: rowColumn.implicitHeight
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusCard
        Column {
            id: rowColumn
            objectName: "settings-section-fields"
            width: parent.width
        }
    }

    Component {
        id: powerPanel
        RowCard {
            id: powerCard
            objectName: "settings-panel-power"
            readonly property var power: root.services.power
            readonly property var batteryState: power ? power.batteryState : ({ kind: "unavailable" })
            readonly property var profileState: power ? power.profileState : ({ kind: "unavailable" })
            readonly property string summary: batteryState.kind === "ready"
                ? Devices.batterySummary(batteryState.value.battery, root.t) || "" : ""
            property string pendingRequest: ""
            property string profileError: ""

            Connections {
                target: powerCard.power
                function onCommandFinished(requestId, result) {
                    if (requestId !== powerCard.pendingRequest) return;
                    powerCard.pendingRequest = "";
                    powerCard.profileError = result.ok ? ""
                        : root.t("Не вдалося змінити режим", "Could not change the mode") + " (" + (result.reason || "failed") + ")";
                }
            }

            SettingsRow {
                width: powerCard.width
                label: root.t("Батарея", "Battery")
                PentadText {
                    objectName: "settings-power-battery"
                    text: powerCard.summary !== "" ? powerCard.summary : root.t("Немає батареї", "No battery")
                    color: powerCard.summary !== "" ? Theme.tokens.text : Theme.tokens.textMuted
                    font.features: { "tnum": 1 }
                }
            }
            SettingsRow {
                width: powerCard.width
                label: root.t("Режим живлення", "Power mode")
                helpText: root.t("Профілі power-profiles-daemon. Без нього режим не змінюється.",
                    "Profiles from power-profiles-daemon. Without it the mode cannot change.")
                infoAccessibleName: root.t("Про цей параметр", "About this setting")
                pending: powerCard.pendingRequest !== ""
                error: powerCard.profileError !== ""
                errorText: powerCard.profileError
                PentadSegmented {
                    objectName: "settings-power-profile"
                    visible: powerCard.profileState.kind === "ready"
                    options: powerCard.profileState.kind === "ready"
                        ? Devices.profileOptions(powerCard.profileState.value.profiles, root.t) : []
                    value: powerCard.profileState.kind === "ready"
                        ? (powerCard.profileState.value.desired || powerCard.profileState.value.actual) : ""
                    accessibleName: root.t("Режим живлення", "Power mode")
                    enabled: powerCard.pendingRequest === "" && !root.services.safeMode
                    onActivated: function(value) {
                        powerCard.profileError = "";
                        powerCard.pendingRequest = powerCard.power.setProfile(value);
                    }
                }
                PentadText {
                    visible: powerCard.profileState.kind !== "ready"
                    text: root.t("Недоступно", "Unavailable")
                    color: Theme.tokens.textMuted
                }
            }
        }
    }

    Component {
        id: brightnessPanel
        RowCard {
            id: brightnessCard
            objectName: "settings-panel-brightness"
            readonly property var outputs: Devices.brightnessOutputs(root.services.hyprland.state)
            SettingsRow {
                visible: brightnessCard.outputs.length === 0
                width: brightnessCard.width
                label: root.t("Монітори не знайдено", "No displays found")
            }
            Repeater {
                model: brightnessCard.outputs
                delegate: SettingsRow {
                    id: outputRow
                    required property string modelData
                    width: brightnessCard.width
                    label: modelData
                    // The bar window of each output owns its adapter; the page only borrows it. It is
                    // fetched once, because brightnessFor() may add an adapter and would loop a binding.
                    BrightnessControls {
                        id: outputBrightness
                        objectName: "settings-brightness-" + outputRow.modelData
                        width: parent ? parent.width : 240
                        brightness: null
                        services: root.services
                        compact: true
                        Component.onCompleted: outputBrightness.brightness = root.services.brightnessFor(outputRow.modelData)
                    }
                }
            }
        }
    }

    // Bluetooth reuses the control center's adapter service (services.quickSettings), so both places
    // switch, connect and pair through one queue of operations.
    readonly property var quick: services.quickSettings || null
    readonly property var quickValue: quick && quick.state && quick.state.value ? quick.state.value : ({})
    readonly property bool bluetoothOn: quickValue.bluetooth === true
    property string bluetoothRequest: ""
    property string bluetoothError: ""
    // The device a failed action belongs to, so its row shows the message ("" = the adapter row).
    property string bluetoothTarget: ""
    function runBluetooth(requestId, deviceId) {
        root.bluetoothError = "";
        root.bluetoothTarget = deviceId || "";
        root.bluetoothRequest = requestId || "";
    }
    Connections {
        target: root.quick
        function onCommandFinished(requestId, result) {
            if (requestId !== root.bluetoothRequest) return;
            root.bluetoothRequest = "";
            root.bluetoothError = result.ok ? "" : Devices.bluetoothError(result.reason, root.t);
        }
    }

    Component {
        id: bluetoothPanel
        RowCard {
            id: bluetoothCard
            objectName: "settings-panel-bluetooth"
            SettingsRow {
                width: bluetoothCard.width
                label: "Bluetooth"
                pending: root.bluetoothRequest !== ""
                error: root.bluetoothError !== "" && root.bluetoothTarget === ""
                errorText: error ? root.bluetoothError : ""
                PentadToggle {
                    objectName: "settings-bluetooth-toggle"
                    implicitHeight: Metrics.controlSmall
                    accessibleName: "Bluetooth"
                    checked: root.bluetoothOn
                    pending: root.bluetoothRequest !== ""
                    requestedEnabled: root.quickValue.bluetoothAvailable === true && root.bluetoothRequest === ""
                    onToggled: {
                        root.runBluetooth(root.quick.toggleBluetooth());
                        checked = Qt.binding(function() { return root.bluetoothOn; });
                    }
                }
            }
            SettingsRow {
                visible: root.quickValue.bluetoothAvailable !== true
                width: bluetoothCard.width
                label: root.t("Адаптер Bluetooth не знайдено", "No Bluetooth adapter")
            }
        }
    }

    // One device row: its name, the battery when known, and the actions that fit its state.
    component DeviceRow: SettingsRow {
        id: deviceRow
        required property var modelData
        readonly property var device: modelData
        width: parent ? parent.width : 320
        label: device.label
        pending: root.bluetoothRequest !== "" && root.bluetoothTarget === device.id
        error: root.bluetoothError !== "" && root.bluetoothTarget === device.id
        errorText: error ? root.bluetoothError : ""
        Row {
            spacing: 8
            layoutDirection: Qt.RightToLeft
            width: parent ? parent.width : 160
            PentadButton {
                objectName: "settings-bluetooth-action-" + deviceRow.device.id
                text: !deviceRow.device.paired
                    ? (deviceRow.device.pairing ? root.t("Спарювання…", "Pairing…") : root.t("Спарити", "Pair"))
                    : deviceRow.device.connected ? root.t("Відключити", "Disconnect") : root.t("Підключити", "Connect")
                requestedEnabled: root.bluetoothOn && root.bluetoothRequest === "" && !deviceRow.device.pairing
                onPressed: root.runBluetooth(deviceRow.device.paired
                    ? root.quick.toggleBluetoothDevice(deviceRow.device.id)
                    : root.quick.pairBluetoothDevice(deviceRow.device.id), deviceRow.device.id)
            }
            PentadButton {
                visible: deviceRow.device.paired
                objectName: "settings-bluetooth-forget-" + deviceRow.device.id
                text: root.t("Забути", "Forget")
                requestedEnabled: root.bluetoothRequest === ""
                onPressed: root.runBluetooth(root.quick.forgetBluetoothDevice(deviceRow.device.id), deviceRow.device.id)
            }
            PentadText {
                visible: deviceRow.device.battery !== null
                anchors.verticalCenter: parent.verticalCenter
                text: deviceRow.device.battery + " %"
                color: Theme.tokens.textMuted
                font.features: { "tnum": 1 }
            }
        }
    }

    Component {
        id: bluetoothDevicesPanel
        RowCard {
            id: pairedCard
            objectName: "settings-panel-bluetooth-devices"
            readonly property var devices: Array.isArray(root.quickValue.bluetoothDevices) ? root.quickValue.bluetoothDevices : []
            SettingsRow {
                visible: pairedCard.devices.length === 0
                width: pairedCard.width
                label: root.t("Немає спарених пристроїв", "No paired devices")
            }
            Repeater {
                model: pairedCard.devices
                delegate: DeviceRow {}
            }
        }
    }

    Component {
        id: bluetoothNearbyPanel
        RowCard {
            id: nearbyCard
            objectName: "settings-panel-bluetooth-nearby"
            readonly property var devices: Array.isArray(root.quickValue.bluetoothNearby) ? root.quickValue.bluetoothNearby : []
            // Scans only while this card exists, and only if it started the scan itself.
            property bool startedScan: false
            function syncScan() {
                if (root.bluetoothOn && !startedScan) startedScan = root.quick.setBluetoothDiscovering(true);
                else if (!root.bluetoothOn) startedScan = false;
            }
            // Deferred: starting a scan changes the adapter state this card is reading right now.
            Connections {
                target: root
                function onBluetoothOnChanged() { Qt.callLater(nearbyCard.syncScan); }
            }
            Component.onCompleted: Qt.callLater(syncScan)
            Component.onDestruction: if (startedScan) root.quick.setBluetoothDiscovering(false)
            SettingsRow {
                visible: nearbyCard.devices.length === 0
                width: nearbyCard.width
                label: !root.bluetoothOn ? root.t("Увімкніть Bluetooth, щоб шукати", "Turn on Bluetooth to search")
                    : root.quickValue.bluetoothDiscovering === true ? root.t("Пошук пристроїв…", "Searching for devices…")
                    : root.t("Пристроїв поруч не знайдено", "No devices nearby")
            }
            Repeater {
                model: nearbyCard.devices
                delegate: DeviceRow {}
            }
        }
    }
}
