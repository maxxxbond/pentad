pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

Item {
    id: root
    required property var services
    property string section: "network"
    property string headerRequestId: ""
    property string headerError: ""
    property string profileRequestId: ""
    property string profileError: ""
    readonly property var profileState: services.power.profileState
    readonly property var profileValue: profileState.kind === "ready" ? profileState.value : ({ profiles: [], actual: "", pending: false })
    readonly property var networkState: services.network.state
    readonly property var quickState: services.quickSettings.state
    readonly property var audioState: services.audio.state
    readonly property var quickValue: quickState.kind === "ready" ? quickState.value : ({})
    readonly property var audioValue: audioState.kind === "ready" ? audioState.value : ({})
    readonly property var vpnProfiles: quickValue.vpns || []
    readonly property var activeVpn: vpnProfiles.find(function(item) { return item.active; }) || vpnProfiles[0]
    readonly property string audioKind: section === "audio-input" ? "input" : "output"
    readonly property var audioDevice: audioValue[audioKind] || null
    readonly property bool actionOn: section === "network"
        ? networkState.kind === "ready" && networkState.value.wifiEnabled === true
            && (networkState.value.devices || []).some(function(device) { return device.type === "wifi"; })
        : section === "bluetooth" ? quickValue.bluetooth === true
        : section === "vpn" ? !!activeVpn && activeVpn.active === true
        : !!audioDevice && audioDevice.muted !== true
    readonly property bool actionAvailable: section === "network"
        ? networkState.kind === "ready" && !services.network.safeMode
            && (networkState.value.devices || []).some(function(device) { return device.type === "wifi"; })
            && networkState.value.wifiHardwareEnabled && typeof networkState.value.wifiEnabled === "boolean"
        : section === "bluetooth" ? quickValue.bluetoothAvailable === true && !services.quickSettings.safeMode
        : section === "vpn" ? !!activeVpn && !services.quickSettings.safeMode
        : !!audioDevice && services.audio.active && !services.audio.safeMode
    readonly property bool actionPending: !!headerRequestId
        || (section === "network" && !!services.network.operation)
        || ((section === "bluetooth" || section === "vpn") && !!services.quickSettings.operation)
    signal backRequested()
    signal trayscaleRequested()

    implicitHeight: 360

    function toggleCurrent() {
        if (!actionAvailable || actionPending) return;
        let id = "";
        if (section === "network") id = services.network.setWifiEnabled(!actionOn);
        else if (section === "bluetooth") id = services.quickSettings.toggleBluetooth();
        else if (section === "vpn") id = services.quickSettings.toggleVpn(activeVpn.uuid);
        else id = services.audio.toggleMute(audioKind);
        headerRequestId = id || "";
        headerError = "";
    }
    function finishRequest(id, result) {
        if (!headerRequestId || id !== headerRequestId) return;
        headerRequestId = "";
        headerError = result.ok ? "" : result.reason || "failed";
    }
    function profileLabel(profile) {
        if (profile === "balanced") return services.text("Збалансований", "Balanced");
        if (profile === "performance") return services.text("Продуктивність", "Performance");
        if (profile === "power-saver" || profile === "powersave") return services.text("Енергозбереження", "Power saver");
        return profile;
    }
    function selectProfile(profile) {
        if (!services.power.active || services.power.safeMode || profileState.kind !== "ready"
            || profileValue.pending || profileRequestId || profile === profileValue.actual) return;
        profileError = "";
        profileRequestId = services.power.setProfile(profile) || "";
    }
    onSectionChanged: { headerRequestId = ""; headerError = ""; }

    Connections {
        target: root.services.network
        ignoreUnknownSignals: true
        function onCommandFinished(id, result) { root.finishRequest(id, result); }
    }
    Connections {
        target: root.services.quickSettings
        ignoreUnknownSignals: true
        function onCommandFinished(id, result) { root.finishRequest(id, result); }
    }
    Connections {
        target: root.services.audio
        ignoreUnknownSignals: true
        function onCommandFinished(id, result) { root.finishRequest(id, result); }
    }
    Connections {
        target: root.services.power
        ignoreUnknownSignals: true
        function onCommandFinished(id, result) {
            if (id !== root.profileRequestId) return;
            root.profileRequestId = "";
            root.profileError = result.ok ? "" : root.services.text("Не вдалося змінити профіль", "Could not change profile");
        }
    }

    Column {
        anchors.fill: parent
        spacing: 8
        Row {
            id: header
            width: parent.width
            height: 40
            spacing: 8
            PentadButton {
                objectName: "control-center-details-back"
                chevron: "left"
                iconSize: Metrics.menuActionIcon
                width: 36
                controlHeight: 36
                accessibleName: root.services.text("Назад до швидких налаштувань", "Back to quick settings")
                requestedEnabled: root.section !== "session" || !root.services.session.pending
                onPressed: root.backRequested()
            }
            PentadText {
                width: Math.max(0, header.width - 36 - headerAction.width - 16)
                text: root.section === "network" ? "Wi-Fi"
                    : root.section === "bluetooth" ? "Bluetooth"
                    : root.section === "vpn" ? "VPN"
                    : root.section === "energy" ? root.services.text("Енергопрофіль", "Power profile")
                    : root.section === "session" ? root.services.text("Сесія та ПК", "Session and PC")
                    : root.section === "audio-input" ? root.services.text("Мікрофон", "Microphone")
                    : root.services.text("Аудіовихід", "Audio output")
                role: "section"
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
            }
            PentadToggle {
                id: headerAction
                objectName: "control-center-details-toggle"
                visible: root.section !== "energy" && root.section !== "session"
                width: visible ? implicitWidth : 0
                height: 36
                text: ""
                accessibleName: root.section === "audio-output" || root.section === "audio-input"
                    ? (root.actionOn ? root.services.text("Вимкнути звук", "Mute") : root.services.text("Увімкнути звук", "Unmute"))
                    : (root.actionOn ? root.services.text("Вимкнути", "Turn off") : root.services.text("Увімкнути", "Turn on"))
                ToolTip.visible: hovered || activeFocus
                ToolTip.delay: 500
                ToolTip.text: accessibleName
                Binding on checked {
                    value: root.actionOn
                    when: !headerAction.down && !root.actionPending
                    restoreMode: Binding.RestoreNone
                }
                requestedEnabled: root.actionAvailable && !root.actionPending
                pending: root.actionPending
                onClicked: root.toggleCurrent()
            }
        }
        Flickable {
            id: scroller
            width: parent.width
            height: Math.max(0, root.height - header.height - 8)
            clip: true
            contentWidth: width
            contentHeight: details.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: details
                width: scroller.width
                spacing: 8
                // Only the shown section exists; the others are built when they are opened.
                Loader {
                    width: details.width
                    active: root.section === "network"
                    visible: active
                    sourceComponent: Component {
                        NetworkControls {
                            services: root.services
                            selectorMode: true
                        }
                    }
                }
                Loader {
                    width: details.width
                    active: root.section === "session"
                    visible: active
                    sourceComponent: Component {
                        SessionConfirmation {
                            services: root.services
                            onBackRequested: root.backRequested()
                        }
                    }
                }
                Loader {
                    width: details.width
                    active: root.section === "audio-output" || root.section === "audio-input"
                    visible: active
                    sourceComponent: Component {
                        AudioControls {
                            services: root.services
                            compact: true
                            detailsExpanded: true
                            deviceSection: root.section
                        }
                    }
                }
                Loader {
                    width: details.width
                    active: root.section === "energy"
                    visible: active
                    sourceComponent: Component {
                        Column {
                            spacing: 6
                            Repeater {
                                model: root.profileValue.profiles
                                delegate: SelectorOption {
                                    required property string modelData
                                    objectName: "control-center-profile-" + modelData
                                    width: details.width
                                    text: root.profileLabel(modelData)
                                    selected: modelData === root.profileValue.actual
                                    subtitle: selected ? root.services.text("Поточний профіль", "Current profile") : ""
                                    enabled: root.services.power.active && !root.services.power.safeMode
                                        && !root.profileValue.pending && !root.profileRequestId
                                    onPressed: root.selectProfile(modelData)
                                }
                            }
                            PentadText {
                                width: parent.width
                                visible: root.profileState.kind !== "ready"
                                text: root.services.text("Служба енергопрофілів недоступна", "Power profile service unavailable")
                                color: Theme.tokens.textMuted
                                role: "caption"
                            }
                            PentadText {
                                width: parent.width
                                visible: root.profileError !== ""
                                text: root.profileError
                                color: Theme.tokens.error
                                role: "caption"
                            }
                        }
                    }
                }
                Loader {
                    width: details.width
                    active: root.section === "bluetooth"
                    visible: active
                    sourceComponent: Component {
                        Column {
                            spacing: 6
                            PentadText {
                                width: parent.width
                                text: root.quickValue.bluetoothAvailable
                                    ? (root.quickValue.bluetooth ? root.services.text("Спарені пристрої", "Paired devices")
                                        : root.services.text("Bluetooth вимкнено", "Bluetooth is off"))
                                    : root.services.text("Адаптер Bluetooth недоступний", "Bluetooth adapter unavailable")
                                role: "caption"
                                color: Theme.tokens.textMuted
                            }
                            Repeater {
                                model: root.quickValue.bluetoothDevices || []
                                delegate: SelectorOption {
                                    required property var modelData
                                    width: details.width
                                    text: modelData.label
                                    selected: modelData.connected
                                    accessibleName: modelData.label + (modelData.connected
                                        ? root.services.text(" · підключено", " · connected") : "")
                                    enabled: root.quickValue.bluetooth === true && !root.quickValue.busy
                                    onPressed: root.services.quickSettings.toggleBluetoothDevice(modelData.id)
                                }
                            }
                            PentadText {
                                width: parent.width
                                visible: (root.quickValue.bluetoothDevices || []).length === 0
                                text: root.services.text("Немає спарених пристроїв", "No paired devices")
                                role: "caption"
                                color: Theme.tokens.textMuted
                            }
                            PentadText {
                                width: parent.width
                                visible: root.services.quickSettings.errorSetting === "bluetooth-device"
                                    && root.services.quickSettings.error !== ""
                                text: root.services.quickSettings.error
                                role: "caption"
                                color: Theme.tokens.error
                            }
                        }
                    }
                }
                Loader {
                    width: details.width
                    active: root.section === "vpn"
                    visible: active
                    sourceComponent: Component {
                        Column {
                            spacing: 6
                            Repeater {
                                model: root.vpnProfiles
                                delegate: SelectorOption {
                                    required property var modelData
                                    width: details.width
                                    text: modelData.name
                                    subtitle: modelData.detail || ""
                                    selected: modelData.active
                                    accessibleName: root.services.text("Перемкнути VPN ", "Toggle VPN ") + modelData.name
                                    enabled: !root.quickValue.busy
                                    onPressed: root.services.quickSettings.toggleVpn(modelData.uuid)
                                }
                            }
                            PentadButton {
                                objectName: "control-center-open-trayscale"
                                width: parent.width
                                visible: !!root.services.desktop && root.services.desktop.tailscaleAvailable === true
                                text: root.services.text("Відкрити Trayscale", "Open Trayscale")
                                onPressed: root.trayscaleRequested()
                            }
                            PentadText {
                                width: parent.width
                                visible: root.vpnProfiles.length === 0
                                text: root.services.text("Немає збережених профілів VPN", "No saved VPN profiles")
                                role: "caption"
                                color: Theme.tokens.textMuted
                            }
                            PentadText {
                                width: parent.width
                                visible: root.services.quickSettings.errorSetting === "vpn"
                                    && root.services.quickSettings.error !== ""
                                text: root.services.quickSettings.error
                                role: "caption"
                                color: Theme.tokens.error
                            }
                        }
                    }
                }
                PentadText {
                    width: details.width
                    visible: root.headerError !== ""
                    text: root.headerError
                    role: "caption"
                    color: Theme.tokens.error
                }
            }
        }
    }
}
