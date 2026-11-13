pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components
import qs.theme
import "../../logic/network-settings.mjs" as Net

// The NetworkManager panels of the Network page (`panel: 'network-…'`): status, saved Wi-Fi,
// Ethernet, internet from a phone (USB, Bluetooth, mobile modem), hotspot and VPN. Each panel
// holds services.networkSettings while it exists, so `nmcli monitor` runs only with the page open.
// A row opens its connection's details (SettingsNetworkDetails) in place.
Item {
    id: root
    required property var services
    required property string panel
    readonly property var net: services.networkSettings || null
    readonly property var status: net ? net.status : null
    readonly property bool ready: !!status && status.ok === true && status.available === true
    readonly property bool canWrite: ready && !services.safeMode && pendingRequest === ""
    property string pendingRequest: ""
    property string pendingKey: ""
    property string failure: ""
    property string failureKey: ""
    // The row whose details are open; one at a time per panel.
    property string expandedKey: ""
    // Open forms. They close only when their request succeeds, so a failure stays readable under them.
    property bool joiningHidden: false
    property bool addingApn: false
    property bool editingHotspot: false
    readonly property var closesForm: ({ "hidden-join": "joiningHidden", "apn": "addingApn", "hotspot-save": "editingHotspot" })
    implicitHeight: loader.item ? loader.item.implicitHeight : 0

    function t(uk, en) { return services.text(uk, en); }
    function icon(path) { return Qt.resolvedUrl("../../assets/icons/" + path); }
    function run(key, requestId) {
        failure = "";
        failureKey = key;
        pendingKey = key;
        pendingRequest = requestId || "";
    }
    function fail(key, reason) {
        failureKey = key;
        failure = Net.errorText(reason, t);
    }
    // Rows are keyed by uuid or device id, so a status refresh updates them in place instead of
    // rebuilding them (which would close open details and drop what the user typed).
    function keys(list, key) {
        return Net.listOf(list).map(function(item) { return String(item[key]); });
    }
    function findIn(list, key, value) {
        return Net.listOf(list).find(function(item) { return item[key] === value; }) || ({});
    }
    function deviceById(id) { return findIn(ready ? status.devices : [], "id", id); }
    function deviceFor(uuid) {
        const devices = ready && Array.isArray(status.devices) ? status.devices : [];
        return devices.find(function(device) { return device.uuid === uuid; }) || null;
    }
    // The service this panel holds. Bindings to `services` may already read null while the page
    // tears down, so the release goes to the object that was acquired, not to `net`.
    property var held: null
    Component.onCompleted: {
        held = net;
        if (held) held.acquire();
    }
    Component.onDestruction: if (held) held.release()
    Connections {
        target: root.net
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingRequest) return;
            const key = root.pendingKey;
            root.pendingRequest = "";
            root.pendingKey = "";
            if (!result.ok) {
                root.failureKey = key;
                root.failure = Net.errorText(result.reason, root.t, result.message);
            } else if (root.closesForm[key]) root[root.closesForm[key]] = false;
        }
    }

    Loader {
        id: loader
        width: root.width
        sourceComponent: root.panel === "network-overview" ? overviewPanel
            : root.panel === "network-known-wifi" ? knownPanel
            : root.panel === "network-wired" ? wiredPanel
            : root.panel === "network-tethering" ? tetheringPanel
            : root.panel === "network-hotspot" ? hotspotPanel
            : root.panel === "network-vpn" ? vpnPanel : null
    }

    // Rows flatten onto this card exactly as they do inside a SettingsSection.
    component Card: ContinuousSurface {
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

    // A status line for an empty or unavailable list, with an optional explanation and action.
    // It reads like a connection row (icon, name over state) so empty cards keep the same rhythm.
    component Notice: Entry {
        id: notice
        property string label: ""
        property string value: ""
        property string helpText: ""
        property string actionText: ""
        signal action()
        entryKey: "notice:" + label
        title: label
        subtitle: value
        PentadInfoButton {
            visible: notice.helpText !== ""
            helpText: notice.helpText
            accessibleName: root.t("Докладніше", "Learn more")
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        }
        PentadButton {
            visible: notice.actionText !== ""
            text: notice.actionText
            controlHeight: Metrics.controlSmall
            onClicked: notice.action()
        }
    }

    // One connection or device: icon, name over state, trailing controls, and its details on demand.
    component Entry: Item {
        id: entry
        property string entryKey: ""
        property url iconSource: ""
        property string title: ""
        property string subtitle: ""
        property string uuid: ""
        property string kind: "ethernet"
        property var device: null
        readonly property bool expandable: uuid !== ""
        readonly property bool expanded: expandable && root.expandedKey === entryKey
        readonly property bool hasError: root.failure !== "" && root.failureKey === entryKey
        default property alias trailing: trailingRow.data
        width: parent ? parent.width : 320
        implicitHeight: listRow.height + Metrics.space2 + (errorLabel.visible ? errorLabel.height + Metrics.space2 : 0)
            + (detailLoader.item ? detailLoader.item.implicitHeight + Metrics.space2 : 0)
        Accessible.role: Accessible.Grouping
        Accessible.name: title

        Rectangle {
            visible: entry.y >= 1
            x: 16
            width: parent.width - 32
            height: 1
            color: Theme.tokens.outline
        }
        PentadListRow {
            id: listRow
            objectName: "network-entry-" + entry.entryKey
            x: Metrics.space1
            y: Metrics.space1
            width: parent.width - 2 * Metrics.space1
            iconSource: entry.iconSource
            title: entry.title
            subtitle: entry.subtitle
            onActivated: if (entry.expandable) root.expandedKey = entry.expanded ? "" : entry.entryKey
            Row {
                id: trailingRow
                spacing: Metrics.space2
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            }
            PentadChevron {
                visible: entry.expandable
                direction: entry.expanded ? "down" : "right"
                engaged: listRow.hovered
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            }
        }
        PentadText {
            id: errorLabel
            visible: entry.hasError
            x: Metrics.space4 + Metrics.statusIcon + Metrics.space3
            y: listRow.y + listRow.height
            width: parent.width - x - Metrics.space4
            text: root.failure
            role: "caption"
            color: Theme.tokens.error
        }
        Loader {
            id: detailLoader
            active: entry.expanded
            x: Metrics.space2
            y: listRow.y + listRow.height + (errorLabel.visible ? errorLabel.height + Metrics.space2 : 0)
            width: parent.width - 2 * Metrics.space2
            sourceComponent: SettingsNetworkDetails {
                services: root.services
                uuid: entry.uuid
                kind: entry.kind
                device: entry.device
                onForgotten: if (root.expandedKey === entry.entryKey) root.expandedKey = ""
            }
        }
    }

    // --- Status ---------------------------------------------------------------------------------
    Component {
        id: overviewPanel
        Card {
            id: overviewCard
            objectName: "settings-panel-network-overview"
            readonly property var view: Net.overview(root.status, root.t)
            readonly property color toneColor: view.tone === "online" ? Theme.tokens.accent
                : view.tone === "limited" ? Theme.tokens.warning : Theme.tokens.textMuted
            property bool open: false

            Item {
                width: overviewCard.width
                implicitHeight: 72
                Rectangle {
                    id: badge
                    x: Metrics.space4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: Metrics.radiusPill
                    color: Theme.tokens.surfaceOverlay
                    PentadIcon {
                        anchors.centerIn: parent
                        source: root.icon(overviewCard.view.icon)
                        pixelSize: Metrics.menuActionIcon
                        color: overviewCard.toneColor
                    }
                }
                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: Metrics.space3
                    anchors.right: overviewTrailing.left
                    anchors.rightMargin: Metrics.space3
                    anchors.verticalCenter: parent.verticalCenter
                    PentadText {
                        objectName: "network-overview-title"
                        width: parent.width
                        text: overviewCard.view.title
                        role: "section"
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        solid: overviewCard.view.subtitle !== ""
                    }
                    PentadText {
                        objectName: "network-overview-subtitle"
                        visible: text !== ""
                        width: parent.width
                        text: overviewCard.view.subtitle
                        role: "caption"
                        color: Theme.tokens.textMuted
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        solid: true
                        font.features: { "tnum": 1 }
                    }
                }
                Row {
                    id: overviewTrailing
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.space4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.space2
                    // An active VPN is a quiet tag: icon and name, no fill flood.
                    Repeater {
                        model: overviewCard.view.vpns
                        delegate: Rectangle {
                            id: vpnTag
                            required property string modelData
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            height: Metrics.controlSmall
                            width: vpnRow.implicitWidth + 2 * Metrics.space3
                            radius: Metrics.radiusPill
                            color: Theme.tokens.surfaceOverlay
                            Row {
                                id: vpnRow
                                anchors.centerIn: parent
                                spacing: Metrics.space1
                                PentadIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: root.icon("material/network/vpn-lock-symbolic.svg")
                                    pixelSize: Metrics.panelIcon
                                    color: Theme.tokens.accent
                                }
                                PentadText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: vpnTag.modelData
                                    role: "caption"
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 120)
                                }
                            }
                        }
                    }
                    PentadButton {
                        objectName: "network-overview-details"
                        visible: !!overviewCard.view.device
                        text: overviewCard.open ? root.t("Сховати", "Hide") : root.t("Деталі", "Details")
                        controlHeight: Metrics.controlSmall
                        onClicked: overviewCard.open = !overviewCard.open
                    }
                }
            }
            Loader {
                active: overviewCard.open && !!overviewCard.view.device
                width: overviewCard.width
                visible: active
                sourceComponent: Column {
                    id: facts
                    readonly property var device: overviewCard.view.device
                    objectName: "settings-section-fields"
                    width: overviewCard.width
                    component Fact: SettingsRow {
                        id: fact
                        property string value: ""
                        visible: value !== ""
                        width: facts.width
                        PentadText {
                            width: parent ? parent.width : 160
                            text: fact.value
                            horizontalAlignment: Text.AlignRight
                            color: Theme.tokens.textMuted
                            elide: Text.ElideMiddle
                            wrapMode: Text.NoWrap
                            font.features: { "tnum": 1 }
                        }
                    }
                    Fact { label: root.t("З’єднання", "Connection"); value: facts.device.connection || "" }
                    Fact { label: root.t("Інтерфейс", "Interface"); value: facts.device.id || "" }
                    Fact { label: root.t("Швидкість", "Speed"); value: Net.formatSpeed(facts.device.speed, root.t) }
                    Fact { label: "IPv4"; value: Net.joinAddresses(facts.device.ipv4) }
                    Fact { label: root.t("Шлюз", "Router"); value: facts.device.gateway4 || "" }
                    Fact { label: "DNS"; value: Net.joinAddresses(facts.device.dns) }
                    Fact {
                        label: "IPv6"
                        value: Net.joinAddresses(facts.device.ipv6)
                    }
                    Fact { label: root.t("MAC-адреса", "MAC address"); value: facts.device.hwaddr || "" }
                }
            }
        }
    }

    // --- Saved Wi-Fi and hidden networks --------------------------------------------------------
    Component {
        id: knownPanel
        Card {
            id: knownCard
            objectName: "settings-panel-network-known-wifi"
            readonly property var saved: Net.savedWifi(root.status)
            property string security: "wpa-psk"

            Notice {
                visible: root.ready && knownCard.saved.length === 0
                label: root.t("Збережених мереж немає", "No saved networks")
            }
            Repeater {
                model: ScriptModel { values: root.keys(knownCard.saved, "uuid") }
                delegate: Entry {
                    id: savedEntry
                    required property string modelData
                    readonly property var rec: root.findIn(knownCard.saved, "uuid", modelData)
                    entryKey: rec.uuid
                    uuid: rec.uuid
                    kind: "wifi"
                    device: rec.active ? root.deviceFor(rec.uuid) : null
                    iconSource: root.icon("material/network/wifi-symbolic.svg")
                    title: rec.name
                    subtitle: rec.active ? root.t("Підключено", "Connected")
                        : rec.autoconnect === false ? root.t("Без автопідключення", "Auto-join off") : ""
                    PentadButton {
                        visible: !savedEntry.rec.active
                        objectName: "network-known-join-" + savedEntry.rec.uuid
                        text: root.t("Підключити", "Join")
                        controlHeight: Metrics.controlSmall
                        pending: root.pendingKey === savedEntry.entryKey
                        requestedEnabled: root.canWrite && root.status.radios && root.status.radios.wifi === true
                        onClicked: root.run(savedEntry.entryKey, root.net.activate(savedEntry.rec.uuid))
                    }
                }
            }
            Entry {
                entryKey: "hidden"
                iconSource: root.icon("material/network/wifi-lock-symbolic.svg")
                title: root.t("Прихована мережа…", "Hidden network…")
                visible: root.ready && Net.hasWifiDevice(root.status)
                PentadButton {
                    objectName: "network-hidden-open"
                    text: root.joiningHidden ? root.t("Скасувати", "Cancel") : root.t("Додати", "Add")
                    controlHeight: Metrics.controlSmall
                    requestedEnabled: root.canWrite || root.joiningHidden
                    onClicked: root.joiningHidden = !root.joiningHidden
                }
            }
            Column {
                id: hiddenForm
                visible: root.joiningHidden
                objectName: "settings-section-fields"
                width: knownCard.width
                SettingsRow {
                    width: hiddenForm.width
                    label: root.t("Назва мережі (SSID)", "Network name (SSID)")
                    PentadTextField {
                        id: ssidField
                        objectName: "network-hidden-ssid"
                        width: parent ? parent.width : 220
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        accessibleName: root.t("Назва мережі", "Network name")
                    }
                }
                SettingsRow {
                    width: hiddenForm.width
                    label: root.t("Захист", "Security")
                    PentadSegmented {
                        objectName: "network-hidden-security"
                        width: parent ? parent.width : 220
                        options: Net.securityOptions(root.t)
                        value: knownCard.security
                        accessibleName: root.t("Захист", "Security")
                        onActivated: function(value) { knownCard.security = value; }
                    }
                }
                SettingsRow {
                    visible: knownCard.security !== "none"
                    width: hiddenForm.width
                    label: root.t("Пароль", "Password")
                    PentadTextField {
                        id: hiddenPassword
                        objectName: "network-hidden-password"
                        width: parent ? parent.width : 220
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        echoMode: TextInput.Password
                        accessibleName: root.t("Пароль", "Password")
                        onAccepted: joinButton.clicked()
                    }
                }
                SettingsRow {
                    width: hiddenForm.width
                    pending: root.pendingKey === "hidden-join"
                    error: root.failure !== "" && root.failureKey === "hidden-join"
                    errorText: error ? root.failure : ""
                    PentadButton {
                        id: joinButton
                        objectName: "network-hidden-join"
                        anchors.right: parent ? parent.right : undefined
                        text: root.t("Підключитися", "Join")
                        requestedEnabled: root.canWrite
                        onClicked: {
                            const problem = Net.ssidProblem(ssidField.text) || Net.passwordProblem(hiddenPassword.text, knownCard.security);
                            if (problem) { root.fail("hidden-join", problem); return; }
                            root.run("hidden-join", root.net.joinHidden(ssidField.text, knownCard.security,
                                knownCard.security === "none" ? "" : hiddenPassword.text));
                            hiddenPassword.text = "";
                        }
                    }
                }
            }
        }
    }

    // --- Ethernet -------------------------------------------------------------------------------
    Component {
        id: wiredPanel
        Card {
            id: wiredCard
            objectName: "settings-panel-network-wired"
            readonly property var devices: Net.devicesOfKind(root.status, "ethernet")
            Notice {
                visible: !root.ready
                label: Net.overview(root.status, root.t).title
            }
            Notice {
                visible: root.ready && wiredCard.devices.length === 0
                label: root.t("Немає Ethernet-адаптера", "No Ethernet adapter")
            }
            Repeater {
                model: ScriptModel { values: root.keys(wiredCard.devices, "id") }
                delegate: DeviceEntry {}
            }
        }
    }

    // A wired-like device (Ethernet, a phone on USB): connect or disconnect, details of its profile.
    component DeviceEntry: Entry {
        id: deviceEntry
        required property string modelData
        readonly property var rec: root.deviceById(modelData)
        entryKey: "device:" + rec.id
        uuid: rec.uuid || ""
        kind: rec.kind
        device: rec
        iconSource: root.icon(Net.kindIcon(rec.kind))
        title: rec.kind === "usb" ? (rec.label && rec.label !== rec.id ? rec.label : root.t("Телефон через USB", "Phone over USB"))
            : rec.label && rec.label !== rec.id ? rec.label + " · " + rec.id : rec.id
        subtitle: Net.deviceSubtitle(rec, root.t)
        PentadButton {
            visible: deviceEntry.rec.state !== "unavailable" && deviceEntry.rec.state !== "unmanaged"
            objectName: "network-device-action-" + deviceEntry.rec.id
            text: deviceEntry.rec.state === "connected" || deviceEntry.rec.state === "connecting"
                ? root.t("Відключити", "Disconnect") : root.t("Підключити", "Connect")
            controlHeight: Metrics.controlSmall
            pending: root.pendingKey === deviceEntry.entryKey
            requestedEnabled: root.canWrite
            onClicked: root.run(deviceEntry.entryKey, deviceEntry.rec.state === "connected" || deviceEntry.rec.state === "connecting"
                ? root.net.disconnectDevice(deviceEntry.rec.id) : root.net.connectDevice(deviceEntry.rec.id))
        }
    }

    // --- Internet from a phone: USB, Bluetooth, mobile modem ------------------------------------
    Component {
        id: tetheringPanel
        Card {
            id: tetherCard
            objectName: "settings-panel-network-tethering"
            readonly property var usb: Net.devicesOfKind(root.status, "usb")
            readonly property var phones: Net.bluetoothTethers(root.status, root.t)
            readonly property var modems: Net.devicesOfKind(root.status, "mobile")
            readonly property var mobileProfiles: Net.mobileProfiles(root.status)
            readonly property bool wwanAvailable: root.ready && !!root.status.radios && root.status.radios.wwanHardware === true

            Notice {
                visible: !root.ready
                label: Net.overview(root.status, root.t).title
            }

            // USB: a phone with USB tethering on shows up as a wired device by itself.
            Notice {
                visible: root.ready && tetherCard.usb.length === 0
                iconSource: root.icon("material/network/usb-symbolic.svg")
                label: root.t("USB-модем", "USB tethering")
                value: root.t("Телефон не під’єднано", "No phone connected")
                helpText: root.t("Під’єднайте телефон кабелем і ввімкніть на ньому «USB-модем» (Android) або «Режим модема» (iPhone). Він з’явиться тут сам. Для iPhone потрібен usbmuxd.",
                    "Connect the phone with a cable and turn on USB tethering (Android) or Personal Hotspot (iPhone). It appears here by itself. iPhone needs usbmuxd.")
            }
            Repeater {
                model: ScriptModel { values: root.keys(tetherCard.usb, "id") }
                delegate: DeviceEntry {}
            }

            // Bluetooth: paired phones that offer a network (PAN).
            Notice {
                visible: root.ready && tetherCard.phones.length === 0
                iconSource: root.icon("material/network/bluetooth-symbolic.svg")
                label: root.t("Bluetooth-модем", "Bluetooth tethering")
                actionText: root.t("Спарити телефон", "Pair a phone")
                helpText: root.t("Увімкніть на телефоні «Bluetooth-модем» і спарте його на сторінці Bluetooth. Телефони, що роздають інтернет, з’являться тут.",
                    "Turn on Bluetooth tethering on the phone and pair it on the Bluetooth page. Phones that share internet appear here.")
                onAction: if (root.services.settings) root.services.settings.openPage("bluetooth")
            }
            Repeater {
                model: ScriptModel { values: root.keys(tetherCard.phones, "id") }
                delegate: Entry {
                    id: phoneEntry
                    required property string modelData
                    readonly property var rec: root.findIn(tetherCard.phones, "id", modelData)
                    entryKey: "bt:" + rec.id
                    kind: "bluetooth"
                    iconSource: root.icon("material/network/smartphone-symbolic.svg")
                    title: rec.label
                    subtitle: root.t("Bluetooth-модем", "Bluetooth tethering") + (rec.active ? " · " + rec.subtitle : "")
                    PentadToggle {
                        objectName: "network-bluetooth-tether-" + phoneEntry.rec.id
                        implicitHeight: Metrics.controlSmall
                        accessibleName: phoneEntry.rec.label
                        checked: phoneEntry.rec.active
                        pending: root.pendingKey === phoneEntry.entryKey || phoneEntry.rec.busy
                        requestedEnabled: root.canWrite && !phoneEntry.rec.busy
                        onToggled: {
                            root.run(phoneEntry.entryKey, root.net.setBluetoothTether(phoneEntry.rec.id, checked));
                            checked = Qt.binding(function() { return phoneEntry.rec.active; });
                        }
                    }
                }
            }

            // Mobile broadband: a modem or SIM through ModemManager.
            Notice {
                visible: root.ready && tetherCard.modems.length === 0
                iconSource: root.icon("material/network/signal-cellular-alt-symbolic.svg")
                label: root.t("Мобільний модем", "Mobile modem")
                value: root.status && root.status.modemManager === false ? root.t("ModemManager не запущено", "ModemManager is not running")
                    : root.t("Не знайдено", "Not found")
                helpText: root.t("Вбудований LTE/5G-модем, USB-модем або телефон у режимі DUN. Потрібен запущений ModemManager.",
                    "A built-in LTE/5G modem, a USB modem or a phone in DUN mode. ModemManager must be running.")
            }
            Entry {
                visible: tetherCard.modems.length > 0
                entryKey: "wwan"
                iconSource: root.icon("material/network/signal-cellular-alt-symbolic.svg")
                title: root.t("Мобільні дані", "Mobile data")
                PentadToggle {
                    objectName: "network-wwan-toggle"
                    implicitHeight: Metrics.controlSmall
                    accessibleName: root.t("Мобільні дані", "Mobile data")
                    checked: root.ready && root.status.radios && root.status.radios.wwan === true
                    pending: root.pendingKey === "wwan"
                    requestedEnabled: root.canWrite && tetherCard.wwanAvailable
                    onToggled: {
                        root.run("wwan", root.net.setRadio("wwan", checked));
                        checked = Qt.binding(function() { return root.ready && root.status.radios && root.status.radios.wwan === true; });
                    }
                }
            }
            Repeater {
                model: ScriptModel { values: root.keys(tetherCard.modems, "id") }
                delegate: Entry {
                    id: modemEntry
                    required property string modelData
                    readonly property var rec: root.deviceById(modelData)
                    entryKey: "modem:" + rec.id
                    uuid: rec.uuid || ""
                    kind: "mobile"
                    device: rec
                    iconSource: root.icon("material/network/signal-cellular-alt-symbolic.svg")
                    title: rec.mobile && rec.mobile.operator ? rec.mobile.operator : rec.label
                    subtitle: [Net.stateLabel(rec.state, root.t),
                        rec.mobile && rec.mobile.technology ? rec.mobile.technology : "",
                        rec.mobile && rec.mobile.signal !== null && rec.mobile.signal !== undefined ? rec.mobile.signal + " %" : ""]
                        .filter(function(part) { return part !== ""; }).join(" · ")
                    PentadButton {
                        visible: tetherCard.mobileProfiles.length > 0 && modemEntry.rec.state !== "unavailable"
                        text: modemEntry.rec.state === "connected" ? root.t("Відключити", "Disconnect") : root.t("Підключити", "Connect")
                        controlHeight: Metrics.controlSmall
                        pending: root.pendingKey === modemEntry.entryKey
                        requestedEnabled: root.canWrite
                        onClicked: root.run(modemEntry.entryKey, modemEntry.rec.state === "connected"
                            ? root.net.disconnectDevice(modemEntry.rec.id) : root.net.activate(tetherCard.mobileProfiles[0].uuid))
                    }
                }
            }
            Repeater {
                model: ScriptModel { values: tetherCard.modems.length > 0 ? root.keys(tetherCard.mobileProfiles, "uuid") : [] }
                delegate: Entry {
                    required property string modelData
                    readonly property var rec: root.findIn(tetherCard.mobileProfiles, "uuid", modelData)
                    entryKey: rec.uuid
                    uuid: rec.uuid
                    kind: "mobile"
                    device: rec.active ? root.deviceFor(rec.uuid) : null
                    iconSource: root.icon("material/network/public-symbolic.svg")
                    title: rec.name
                    subtitle: rec.active ? root.t("Підключено", "Connected") : root.t("Профіль оператора", "Carrier profile")
                }
            }
            Entry {
                visible: tetherCard.modems.length > 0
                entryKey: "apn"
                iconSource: root.icon("material/network/add-symbolic.svg")
                title: root.t("Додати точку доступу (APN)…", "Add an access point (APN)…")
                PentadButton {
                    text: root.addingApn ? root.t("Скасувати", "Cancel") : root.t("Додати", "Add")
                    controlHeight: Metrics.controlSmall
                    requestedEnabled: root.canWrite || root.addingApn
                    onClicked: root.addingApn = !root.addingApn
                }
            }
            Column {
                id: apnForm
                visible: root.addingApn
                objectName: "settings-section-fields"
                width: tetherCard.width
                SettingsRow {
                    width: apnForm.width
                    label: "APN"
                    helpText: root.t("Назву APN дає оператор. Для більшості SIM-карт достатньо «internet».",
                        "Your carrier gives the APN name. For most SIM cards “internet” is enough.")
                    infoAccessibleName: root.t("Про цей параметр", "About this setting")
                    PentadTextField {
                        id: apnField
                        objectName: "network-apn"
                        width: parent ? parent.width : 220
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        placeholderText: "internet"
                        accessibleName: "APN"
                    }
                }
                SettingsRow {
                    width: apnForm.width
                    label: root.t("Користувач", "Username")
                    PentadTextField {
                        id: apnUser
                        width: parent ? parent.width : 220
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        placeholderText: root.t("Необов’язково", "Optional")
                        accessibleName: root.t("Користувач", "Username")
                    }
                }
                SettingsRow {
                    width: apnForm.width
                    label: root.t("Пароль", "Password")
                    PentadTextField {
                        id: apnPassword
                        width: parent ? parent.width : 220
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        echoMode: TextInput.Password
                        placeholderText: root.t("Необов’язково", "Optional")
                        accessibleName: root.t("Пароль", "Password")
                    }
                }
                SettingsRow {
                    width: apnForm.width
                    pending: root.pendingKey === "apn"
                    error: root.failure !== "" && root.failureKey === "apn"
                    errorText: error ? root.failure : ""
                    PentadButton {
                        anchors.right: parent ? parent.right : undefined
                        text: root.t("Зберегти й підключити", "Save and connect")
                        requestedEnabled: root.canWrite
                        onClicked: {
                            const apn = apnField.text.trim() || "internet";
                            const problem = Net.apnProblem(apn) || Net.secretProblem(apnPassword.text);
                            if (problem) { root.fail("apn", problem); return; }
                            root.run("apn", root.net.addMobile(apn, apnUser.text.trim(), apnPassword.text));
                            apnPassword.text = "";
                        }
                    }
                }
            }
        }
    }

    // --- Hotspot --------------------------------------------------------------------------------
    Component {
        id: hotspotPanel
        Card {
            id: hotspotCard
            objectName: "settings-panel-network-hotspot"
            readonly property var hotspot: Net.hotspotState(root.status)
            readonly property bool active: !!hotspot && hotspot.active === true
            readonly property bool hasWifi: Net.hasWifiDevice(root.status)

            Notice {
                visible: root.ready && !hotspotCard.hasWifi
                label: root.t("Немає адаптера Wi-Fi", "No Wi-Fi adapter")
            }
            Entry {
                visible: root.ready && hotspotCard.hasWifi
                entryKey: "hotspot"
                iconSource: root.icon("material/network/wifi-tethering-symbolic.svg")
                title: root.t("Точка доступу Wi-Fi", "Wi-Fi hotspot")
                subtitle: hotspotCard.active && hotspotCard.hotspot.ssid
                    ? root.t("Роздає «%1»", "Sharing “%1”").replace("%1", hotspotCard.hotspot.ssid) : ""
                PentadInfoButton {
                    helpText: root.t("Комп’ютер роздає своє з’єднання (наприклад, Ethernet) через Wi-Fi. Поки точка доступу ввімкнена, цей адаптер Wi-Fi не підключається до інших мереж.",
                        "This computer shares its connection (for example Ethernet) over Wi-Fi. While the hotspot is on, this Wi-Fi adapter does not join other networks.")
                    accessibleName: root.t("Про цей параметр", "About this setting")
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                }
                PentadToggle {
                    objectName: "network-hotspot-toggle"
                    implicitHeight: Metrics.controlSmall
                    accessibleName: root.t("Точка доступу", "Hotspot")
                    checked: hotspotCard.active
                    pending: root.pendingKey === "hotspot"
                    requestedEnabled: root.canWrite
                    onToggled: {
                        // The first start needs a name and a password; ask for them instead of guessing.
                        if (checked && !hotspotCard.hotspot) root.editingHotspot = true;
                        else root.run("hotspot", root.net.setHotspot(checked, "", ""));
                        checked = Qt.binding(function() { return hotspotCard.active; });
                    }
                }
            }
            Entry {
                visible: root.ready && hotspotCard.hasWifi
                entryKey: "hotspot-settings"
                iconSource: root.icon("material/network/tune-symbolic.svg")
                title: root.t("Назва й пароль", "Name and password")
                subtitle: hotspotCard.hotspot && hotspotCard.hotspot.ssid ? hotspotCard.hotspot.ssid : root.t("Ще не налаштовано", "Not set up yet")
                PentadButton {
                    objectName: "network-hotspot-edit"
                    text: root.editingHotspot ? root.t("Скасувати", "Cancel") : root.t("Змінити", "Change")
                    controlHeight: Metrics.controlSmall
                    requestedEnabled: root.canWrite || root.editingHotspot
                    onClicked: root.editingHotspot = !root.editingHotspot
                }
            }
            Column {
                id: hotspotForm
                visible: root.editingHotspot
                objectName: "settings-section-fields"
                width: hotspotCard.width
                SettingsRow {
                    width: hotspotForm.width
                    label: root.t("Назва мережі", "Network name")
                    PentadTextField {
                        id: hotspotSsid
                        objectName: "network-hotspot-ssid"
                        width: parent ? parent.width : 220
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        // Filled when the form opens, never bound: a refresh must not overwrite typing.
                        function seed() { text = hotspotCard.hotspot && hotspotCard.hotspot.ssid ? hotspotCard.hotspot.ssid : "Pentad"; }
                        Component.onCompleted: seed()
                        Connections {
                            target: root
                            function onEditingHotspotChanged() { if (root.editingHotspot) hotspotSsid.seed(); }
                        }
                        accessibleName: root.t("Назва мережі", "Network name")
                    }
                }
                SettingsRow {
                    width: hotspotForm.width
                    label: root.t("Пароль", "Password")
                    PentadTextField {
                        id: hotspotPassword
                        objectName: "network-hotspot-password"
                        width: parent ? parent.width : 220
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        echoMode: TextInput.Password
                        placeholderText: hotspotCard.hotspot ? root.t("Без змін", "Unchanged") : root.t("Щонайменше 8 символів", "At least 8 characters")
                        accessibleName: root.t("Пароль", "Password")
                    }
                }
                SettingsRow {
                    width: hotspotForm.width
                    pending: root.pendingKey === "hotspot-save"
                    error: root.failure !== "" && root.failureKey === "hotspot-save"
                    errorText: error ? root.failure : ""
                    PentadButton {
                        objectName: "network-hotspot-start"
                        anchors.right: parent ? parent.right : undefined
                        text: root.t("Зберегти й увімкнути", "Save and turn on")
                        requestedEnabled: root.canWrite
                        onClicked: {
                            const keep = !!hotspotCard.hotspot && hotspotPassword.text === "";
                            const problem = Net.ssidProblem(hotspotSsid.text) || (keep ? "" : Net.passwordProblem(hotspotPassword.text, "wpa-psk"));
                            if (problem) { root.fail("hotspot-save", problem); return; }
                            root.run("hotspot-save", root.net.setHotspot(true, hotspotSsid.text, hotspotPassword.text));
                            hotspotPassword.text = "";
                        }
                    }
                }
            }
        }
    }

    // --- VPN ------------------------------------------------------------------------------------
    Component {
        id: vpnPanel
        Card {
            id: vpnCard
            objectName: "settings-panel-network-vpn"
            readonly property var managed: Net.vpnConnections(root.status)
            readonly property var external: Net.externalVpns(root.status)
            property bool dropHover: false
            // The chooser may answer after the page closed; its callback checks this before touching the card.
            property var life: ({ alive: true })
            Component.onDestruction: life.alive = false
            function importUrl(url) {
                const text = String(url);
                let path = "";
                try { path = text.indexOf("file://") === 0 ? decodeURIComponent(text.slice(7)) : ""; } catch (error) { path = ""; }
                if (path === "") { root.fail("import", "invalid-file"); return; }
                root.run("import", root.net.importVpn(path));
            }
            function isProfile(url) { return /\.(conf|ovpn)$/i.test(String(url)); }

            Notice {
                visible: root.ready && vpnCard.managed.length === 0 && vpnCard.external.length === 0
                label: root.t("VPN ще немає", "No VPN yet")
            }
            Repeater {
                model: ScriptModel { values: root.keys(vpnCard.managed, "uuid") }
                delegate: Entry {
                    id: vpnEntry
                    required property string modelData
                    readonly property var rec: root.findIn(vpnCard.managed, "uuid", modelData)
                    readonly property bool busy: rec.state === "activating" || rec.state === "deactivating"
                    entryKey: rec.uuid
                    uuid: rec.uuid
                    kind: "vpn"
                    device: rec.active ? root.deviceFor(rec.uuid) : null
                    iconSource: root.icon("material/network/vpn-lock-symbolic.svg")
                    title: rec.name
                    subtitle: Net.vpnTypeLabel(rec.vpnType) + (rec.active ? " · " + root.t("Підключено", "Connected")
                        : busy ? " · " + Net.stateLabel(rec.state, root.t) : "")
                    PentadToggle {
                        objectName: "network-vpn-toggle-" + vpnEntry.rec.uuid
                        implicitHeight: Metrics.controlSmall
                        accessibleName: vpnEntry.rec.name
                        checked: vpnEntry.rec.active || vpnEntry.rec.state === "activating"
                        pending: root.pendingKey === vpnEntry.entryKey || vpnEntry.busy
                        requestedEnabled: root.canWrite
                        onToggled: {
                            root.run(vpnEntry.entryKey, checked ? root.net.activate(vpnEntry.rec.uuid) : root.net.deactivate(vpnEntry.rec.uuid));
                            checked = Qt.binding(function() { return vpnEntry.rec.active || vpnEntry.rec.state === "activating"; });
                        }
                    }
                }
            }
            Repeater {
                model: ScriptModel { values: root.keys(vpnCard.external, "id") }
                delegate: Entry {
                    required property string modelData
                    readonly property var rec: root.deviceById(modelData)
                    entryKey: "external:" + rec.id
                    iconSource: root.icon("material/network/vpn-lock-symbolic.svg")
                    title: rec.label || rec.id
                    subtitle: Net.deviceSubtitle(rec, root.t)
                }
            }
            Entry {
                visible: root.ready
                entryKey: "import"
                iconSource: root.icon("material/network/upload-file-symbolic.svg")
                title: root.t("Імпортувати з файлу", "Import from a file")
                subtitle: vpnCard.dropHover ? root.t("Відпустіть, щоб додати", "Drop to add")
                    : "WireGuard .conf" + (Net.listOf(root.status ? root.status.vpnPlugins : null).indexOf("openvpn") >= 0 ? " · OpenVPN .ovpn" : "")
                PentadButton {
                    objectName: "network-vpn-import"
                    text: root.t("Вибрати…", "Choose…")
                    controlHeight: Metrics.controlSmall
                    pending: root.pendingKey === "import"
                    requestedEnabled: root.canWrite && !!root.services.filePicker && !root.services.filePicker.busy
                    onClicked: {
                        const life = vpnCard.life;
                        const card = vpnCard;
                        root.services.filePicker.pick({
                            title: root.t("Профіль VPN", "VPN profile"),
                            multiple: false,
                            filters: [root.t("Профілі VPN (*.conf *.ovpn)", "VPN profiles (*.conf *.ovpn)")],
                            done: function(result) {
                                if (life.alive && result && result.ok && result.uris && result.uris.length) card.importUrl(result.uris[0]);
                            }
                        });
                    }
                }
            }
            // A profile dragged from a file manager imports on drop.
            DropArea {
                parent: vpnCard
                anchors.fill: parent
                onEntered: function(drag) {
                    drag.accepted = root.canWrite && drag.hasUrls && drag.urls.length === 1 && vpnCard.isProfile(drag.urls[0]);
                    vpnCard.dropHover = drag.accepted;
                }
                onExited: vpnCard.dropHover = false
                onDropped: function(drop) {
                    vpnCard.dropHover = false;
                    if (drop.hasUrls && drop.urls.length === 1 && vpnCard.isProfile(drop.urls[0])) {
                        drop.accept(Qt.CopyAction);
                        vpnCard.importUrl(drop.urls[0]);
                    }
                }
            }
            DropOutline {
                parent: vpnCard
                x: 4
                y: 4
                width: vpnCard.width - 8
                height: vpnCard.height - 8
                extent: Math.max(Metrics.radiusTag, Metrics.radiusCard - 4)
                visible: vpnCard.dropHover
                active: vpnCard.dropHover
            }
        }
    }
}
