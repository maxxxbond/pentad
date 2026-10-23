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
            : root.panel === "brightness" ? brightnessPanel : null
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
            Repeater {
                // An empty name stands for "no displays", so the card always keeps one first row.
                model: brightnessCard.outputs.length > 0 ? brightnessCard.outputs : [""]
                // Each row is alone in its own flat host, so it never draws the separator; repeated
                // rows would otherwise depend on the order the Repeater stacks them in.
                delegate: Item {
                    id: outputHost
                    required property string modelData
                    required property int index
                    objectName: "settings-section-fields"
                    width: brightnessCard.width
                    implicitHeight: outputRow.implicitHeight
                    SettingsRow {
                        id: outputRow
                        readonly property string modelData: outputHost.modelData
                        width: brightnessCard.width
                        label: modelData !== "" ? modelData : root.t("Монітори не знайдено", "No displays found")
                        // The bar window of each output owns its adapter; the page only borrows it. It is
                        // fetched once, because brightnessFor() may add an adapter and would loop a binding.
                        BrightnessControls {
                            id: outputBrightness
                            visible: outputRow.modelData !== ""
                            objectName: "settings-brightness-" + outputRow.modelData
                            width: parent ? parent.width : 240
                            brightness: null
                            services: root.services
                            compact: true
                            Component.onCompleted: if (outputRow.modelData !== "")
                                outputBrightness.brightness = root.services.brightnessFor(outputRow.modelData)
                        }
                    }
                    // Drawn after the row: the row must stay the host's first child to skip its own line.
                    Rectangle {
                        visible: outputHost.index > 0
                        x: 16
                        z: 1
                        width: parent.width - 32
                        height: 1
                        color: Theme.tokens.outline
                    }
                }
            }
        }
    }
}
