pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/network-settings.mjs" as Net

// The details of one saved connection, opened under its row on the Network page: the live
// addresses, then what can be changed (auto-connect, password, metered, IPv4, DNS, IPv6, MAC) and
// "Forget". Simple choices save at once; typed addresses wait for "Apply".
ContinuousSurface {
    id: root
    required property var services
    required property string uuid
    // ethernet, usb, wifi, hotspot, bluetooth, mobile or vpn.
    required property string kind
    // The live device of this connection from the status reply, or null when it is down.
    property var device: null
    readonly property var net: services.networkSettings
    readonly property var info: net && net.details ? net.details[uuid] || null : null
    readonly property bool loaded: !!info && info.ok === true
    readonly property bool canWrite: loaded && !services.safeMode && pendingRequest === ""
    readonly property bool hasMac: kind === "ethernet" || kind === "usb" || kind === "wifi"
    readonly property bool hasIp: kind !== "hotspot"
    property string pendingRequest: ""
    property string pendingKey: ""
    property string failure: ""
    property string failureKey: ""
    property string secret: ""
    property string secretRequest: ""
    // "manual"/"custom" while the user fills in the fields, before anything is saved.
    property string ipv4Draft: ""
    property string ipv6Draft: ""
    property string dnsDraft: ""
    // The profile is gone; the row that opened these details should close them.
    signal forgotten()
    implicitHeight: column.implicitHeight
    fill: Theme.tokens.surfaceOverlay
    extent: Metrics.radiusSmall

    function t(uk, en) { return services.text(uk, en); }
    function run(key, requestId) {
        failure = "";
        failureKey = key;
        pendingKey = key;
        pendingRequest = requestId || "";
    }
    function fail(key, reason, value) {
        failureKey = key;
        failure = Net.errorText(reason, t) + (value ? " (" + value + ")" : "");
    }
    function save(key, settings) { run(key, net.update(uuid, settings)); }
    function savedMethod(family) { return loaded && info[family] ? info[family].method : "auto"; }
    function savedList(family, field) {
        return loaded && info[family] ? Net.listOf(info[family][field]) : [];
    }
    function optionIndex(options, value) {
        return options.findIndex(function(option) { return option.value === value; });
    }
    function chooseMethod(family, value) {
        if (value === "manual") {
            if (family === "ipv4") ipv4Draft = "manual"; else ipv6Draft = "manual";
            return;
        }
        if (family === "ipv4") ipv4Draft = ""; else ipv6Draft = "";
        const settings = {};
        settings[family] = Net.ipSettings(family, { method: value }).value;
        save(family, settings);
    }
    function applyAddresses(family, addresses, gateway) {
        const parsed = Net.ipSettings(family, { method: "manual", addresses: addresses, gateway: gateway });
        if (!parsed.ok) { fail(family, parsed.error, parsed.value); return; }
        const settings = {};
        settings[family] = parsed.value;
        save(family, settings);
    }
    function applyDns(choice, text) {
        const parsed = Net.dnsSettings(choice, text);
        if (!parsed.ok) { fail("dns", parsed.error, parsed.value); return; }
        save("dns", { ipv4: parsed.ipv4, ipv6: parsed.ipv6 });
    }

    Component.onCompleted: if (net) net.loadDetails(uuid)
    Connections {
        target: root.net
        function onCommandFinished(requestId, result) {
            if (requestId === root.secretRequest) {
                root.secretRequest = "";
                if (result.ok && result.secret) root.secret = String(result.secret);
                // An empty answer means a keyring holds the key, out of NetworkManager's reach.
                else root.fail("secret", result.ok ? "secret-keyring" : result.reason);
                return;
            }
            if (requestId !== root.pendingRequest) return;
            const key = root.pendingKey;
            root.pendingRequest = "";
            root.pendingKey = "";
            if (!result.ok) {
                root.fail(key, result.reason, result.message);
                // The hold button latches after it fires; let it be held again.
                if (key === "forget") forgetButton.reset();
                return;
            }
            if (key === "forget") root.forgotten();
            if (key === "ipv4") root.ipv4Draft = "";
            if (key === "ipv6") root.ipv6Draft = "";
            if (key === "dns") root.dnsDraft = "";
        }
    }

    component Fact: SettingsRow {
        id: fact
        property string value: ""
        visible: value !== ""
        width: parent ? parent.width : 320
        PentadText {
            width: parent ? parent.width : 160
            text: fact.value
            color: Theme.tokens.textMuted
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            wrapMode: Text.NoWrap
            font.features: { "tnum": 1 }
        }
    }

    // IPv4 and IPv6 share one shape: a method menu, then address and router fields for "Manual".
    component AddressRows: Column {
        id: addressRows
        required property string family
        readonly property string draft: family === "ipv4" ? root.ipv4Draft : root.ipv6Draft
        readonly property string method: draft !== "" ? draft : root.savedMethod(family)
        readonly property var options: family === "ipv4" ? Net.ipv4MethodOptions(root.t) : Net.ipv6MethodOptions(root.t)
        function seed() {
            const saved = root.savedList(family, "addresses");
            addressField.text = saved.length > 0 ? saved.join(", ") : liveAddresses;
            gatewayField.text = root.loaded && root.info[family] && root.info[family].gateway ? root.info[family].gateway
                : root.device ? root.device[family === "ipv4" ? "gateway4" : "gateway6"] || "" : "";
        }
        onMethodChanged: if (method === "manual") seed()
        Component.onCompleted: seed()
        Connections {
            target: root
            function onLoadedChanged() { if (root.loaded) addressRows.seed(); }
        }
        readonly property string liveAddresses: root.device ? Net.joinAddresses(root.device[family]) : ""
        visible: root.loaded && root.hasIp
        width: parent ? parent.width : 320
        // Its rows lie on the details card; the 1 px spacer keeps a separator above the first one.
        objectName: "settings-section-fields"
        Item { width: 1; height: 1 }
        SettingsRow {
            width: addressRows.width
            label: addressRows.family === "ipv4" ? root.t("Налаштування IPv4", "Configure IPv4") : root.t("Налаштування IPv6", "Configure IPv6")
            pending: root.pendingKey === addressRows.family
            error: root.failure !== "" && root.failureKey === addressRows.family
            errorText: error ? root.failure : ""
            PentadComboBox {
                objectName: "network-details-" + addressRows.family + "-method"
                width: parent ? parent.width : 220
                fill: Theme.tokens.surfaceRaised
                model: addressRows.options
                textRole: "label"
                valueRole: "value"
                currentIndex: root.optionIndex(addressRows.options, addressRows.method)
                accessibleName: addressRows.family.toUpperCase()
                enabled: root.canWrite
                onActivated: function(index) {
                    root.chooseMethod(addressRows.family, addressRows.options[index].value);
                    currentIndex = Qt.binding(function() { return root.optionIndex(addressRows.options, addressRows.method); });
                }
            }
        }
        SettingsRow {
            visible: addressRows.method === "manual"
            width: addressRows.width
            label: root.t("Адреса", "Address")
            PentadTextField {
                id: addressField
                objectName: "network-details-" + addressRows.family + "-addresses"
                width: parent ? parent.width : 220
                implicitHeight: Metrics.controlMedium
                fill: Theme.tokens.surfaceRaised
                placeholderText: addressRows.family === "ipv4" ? "192.168.1.20/24" : "2001:db8::20/64"
                accessibleName: root.t("Адреса", "Address")
                enabled: root.canWrite
                onAccepted: applyButton.clicked()
            }
        }
        SettingsRow {
            visible: addressRows.method === "manual"
            width: addressRows.width
            label: root.t("Шлюз", "Router")
            PentadTextField {
                id: gatewayField
                objectName: "network-details-" + addressRows.family + "-gateway"
                width: parent ? parent.width : 220
                implicitHeight: Metrics.controlMedium
                fill: Theme.tokens.surfaceRaised
                placeholderText: addressRows.family === "ipv4" ? "192.168.1.1" : "fe80::1"
                accessibleName: root.t("Шлюз", "Router")
                enabled: root.canWrite
                onAccepted: applyButton.clicked()
            }
        }
        SettingsRow {
            visible: addressRows.method === "manual"
            width: addressRows.width
            PentadButton {
                id: applyButton
                objectName: "network-details-" + addressRows.family + "-apply"
                anchors.right: parent ? parent.right : undefined
                text: root.t("Застосувати", "Apply")
                requestedEnabled: root.canWrite
                onClicked: root.applyAddresses(addressRows.family, addressField.text, gatewayField.text)
            }
        }
    }

    Column {
        id: column
        objectName: "settings-section-fields"
        width: parent.width

        SettingsRow {
            visible: !root.loaded
            width: column.width
            label: !root.info ? root.t("Завантаження…", "Loading…") : Net.errorText(root.info.reason, root.t, root.info.message)
        }

        // What the link has right now, from the device that carries it.
        Fact {
            label: "IPv4"
            value: root.device ? Net.joinAddresses(root.device.ipv4) : ""
        }
        Fact {
            label: root.t("Шлюз", "Router")
            value: root.device ? root.device.gateway4 || "" : ""
        }
        Fact {
            label: "DNS"
            value: root.device ? Net.joinAddresses(root.device.dns) : ""
        }
        Fact {
            label: "IPv6"
            value: root.device ? Net.joinAddresses(root.device.ipv6) : ""
        }
        Fact {
            label: root.t("MAC-адреса", "MAC address")
            value: root.device && root.kind !== "vpn" ? root.device.hwaddr || "" : ""
        }

        SettingsRow {
            visible: root.loaded && root.kind !== "hotspot"
            width: column.width
            label: root.t("Підключатися автоматично", "Connect automatically")
            pending: root.pendingKey === "autoconnect"
            error: root.failure !== "" && root.failureKey === "autoconnect"
            errorText: error ? root.failure : ""
            PentadToggle {
                objectName: "network-details-autoconnect"
                implicitHeight: Metrics.controlSmall
                accessibleName: root.t("Підключатися автоматично", "Connect automatically")
                checked: root.loaded && root.info.autoconnect === true
                requestedEnabled: root.canWrite
                onToggled: {
                    root.save("autoconnect", { autoconnect: checked });
                    checked = Qt.binding(function() { return root.loaded && root.info.autoconnect === true; });
                }
            }
        }

        SettingsRow {
            visible: root.loaded && root.info.hasSecret === true
            width: column.width
            label: root.t("Пароль", "Password")
            error: root.failure !== "" && root.failureKey === "secret"
            errorText: error ? root.failure : ""
            Row {
                spacing: Metrics.space2
                layoutDirection: Qt.RightToLeft
                width: parent ? parent.width : 200
                PentadButton {
                    objectName: "network-details-reveal"
                    visible: root.info.secretInKeyring !== true
                    iconSource: Qt.resolvedUrl("../../assets/icons/" + (root.secret !== ""
                        ? "material/network/visibility-off-symbolic.svg" : "material/network/visibility-symbolic.svg"))
                    accessibleName: root.secret !== "" ? root.t("Сховати пароль", "Hide password") : root.t("Показати пароль", "Show password")
                    controlHeight: Metrics.controlSmall
                    pending: root.secretRequest !== ""
                    requestedEnabled: root.secretRequest === ""
                    onClicked: {
                        if (root.secret !== "") { root.secret = ""; return; }
                        root.failure = "";
                        root.secretRequest = root.net.revealSecret(root.uuid);
                    }
                }
                PentadText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - Metrics.controlSmall - Metrics.space2)
                    horizontalAlignment: Text.AlignRight
                    text: root.secret !== "" ? root.secret
                        : root.info.secretInKeyring === true ? root.t("У сховищі ключів", "In your keyring") : "••••••••"
                    color: root.secret !== "" ? Theme.tokens.text : Theme.tokens.textMuted
                    elide: Text.ElideMiddle
                    wrapMode: Text.NoWrap
                }
            }
        }

        SettingsRow {
            visible: root.loaded && root.kind !== "vpn" && root.kind !== "hotspot"
            width: column.width
            label: root.t("Лімітне з’єднання", "Metered connection")
            helpText: root.t("На лімітному з’єднанні застосунки економлять трафік: оновлення та синхронізація чекають на безлімітну мережу. «Авто» довіряє тому, що повідомляє мережа.",
                "On a metered connection apps save data: updates and sync wait for an unmetered network. Auto trusts what the network reports.")
            infoAccessibleName: root.t("Про цей параметр", "About this setting")
            pending: root.pendingKey === "metered"
            error: root.failure !== "" && root.failureKey === "metered"
            errorText: error ? root.failure : ""
            PentadSegmented {
                objectName: "network-details-metered"
                width: parent ? parent.width : 200
                options: Net.meteredOptions(root.t)
                value: root.loaded ? root.info.metered : "unknown"
                accessibleName: root.t("Лімітне з’єднання", "Metered connection")
                enabled: root.canWrite
                onActivated: function(value) { root.save("metered", { metered: value }); }
            }
        }

        AddressRows { family: "ipv4" }

        Column {
            id: dnsRows
            readonly property var options: Net.dnsOptions(root.t)
            readonly property string choice: root.dnsDraft !== "" ? root.dnsDraft : root.loaded ? Net.dnsChoice(root.info) : "auto"
            visible: root.loaded && root.hasIp
            width: column.width
            objectName: "settings-section-fields"
            Item { width: 1; height: 1 }
            SettingsRow {
                width: dnsRows.width
                label: root.t("DNS-сервери", "DNS servers")
                helpText: root.t("«Автоматично» бере сервери від роутера чи провайдера. Публічні сервери можуть бути швидшими або фільтрувати рекламу.",
                    "Automatic uses the servers your router or provider gives. Public servers can be faster or filter ads.")
                infoAccessibleName: root.t("Про цей параметр", "About this setting")
                pending: root.pendingKey === "dns"
                error: root.failure !== "" && root.failureKey === "dns"
                errorText: error ? root.failure : ""
                PentadComboBox {
                    objectName: "network-details-dns"
                    width: parent ? parent.width : 220
                    fill: Theme.tokens.surfaceRaised
                    model: dnsRows.options
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndex(dnsRows.options, dnsRows.choice)
                    accessibleName: "DNS"
                    enabled: root.canWrite
                    onActivated: function(index) {
                        const value = dnsRows.options[index].value;
                        if (value === "custom") root.dnsDraft = "custom";
                        else { root.dnsDraft = ""; root.applyDns(value, ""); }
                        currentIndex = Qt.binding(function() { return root.optionIndex(dnsRows.options, dnsRows.choice); });
                    }
                }
            }
            SettingsRow {
                visible: dnsRows.choice === "custom"
                width: dnsRows.width
                label: root.t("Сервери", "Servers")
                Column {
                    width: parent ? parent.width : 220
                    spacing: Metrics.space2
                    PentadTextField {
                        id: dnsField
                        objectName: "network-details-dns-servers"
                        width: parent.width
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceRaised
                        placeholderText: "192.168.1.2, 2001:db8::2"
                        function seed() { text = root.savedList("ipv4", "dns").concat(root.savedList("ipv6", "dns")).join(", "); }
                        Component.onCompleted: seed()
                        Connections {
                            target: root
                            function onLoadedChanged() { if (root.loaded) dnsField.seed(); }
                            function onDnsDraftChanged() { if (root.dnsDraft === "custom") dnsField.seed(); }
                        }
                        accessibleName: root.t("DNS-сервери", "DNS servers")
                        enabled: root.canWrite
                        onAccepted: root.applyDns("custom", text)
                    }
                    PentadButton {
                        objectName: "network-details-dns-apply"
                        anchors.right: parent.right
                        text: root.t("Застосувати", "Apply")
                        requestedEnabled: root.canWrite
                        onClicked: root.applyDns("custom", dnsField.text)
                    }
                }
            }
        }

        AddressRows { family: "ipv6" }

        SettingsRow {
            visible: root.loaded && root.hasMac
            width: column.width
            label: root.t("MAC-адреса", "MAC address")
            helpText: root.t("Приватна адреса не дає мережам стежити за пристроєм. «Справжня» потрібна, якщо роутер пускає лише відомі пристрої.",
                "A private address keeps networks from tracking this device. Use the hardware one if the router only lets in known devices.")
            infoAccessibleName: root.t("Про цей параметр", "About this setting")
            pending: root.pendingKey === "mac"
            error: root.failure !== "" && root.failureKey === "mac"
            errorText: error ? root.failure : ""
            PentadComboBox {
                id: macBox
                readonly property var options: Net.macChoices(root.info, root.t)
                objectName: "network-details-mac"
                width: parent ? parent.width : 220
                fill: Theme.tokens.surfaceRaised
                model: options
                textRole: "label"
                valueRole: "value"
                currentIndex: root.optionIndex(options, root.loaded ? root.info.mac : "")
                accessibleName: root.t("MAC-адреса", "MAC address")
                enabled: root.canWrite
                onActivated: function(index) {
                    root.save("mac", { mac: macBox.options[index].value });
                    currentIndex = Qt.binding(function() { return root.optionIndex(macBox.options, root.loaded ? root.info.mac : ""); });
                }
            }
        }

        SettingsRow {
            visible: root.loaded
            width: column.width
            pending: root.pendingKey === "forget"
            error: root.failure !== "" && root.failureKey === "forget"
            errorText: error ? root.failure : ""
            PentadHoldButton {
                id: forgetButton
                objectName: "network-details-forget"
                width: parent ? parent.width : 200
                destructive: true
                text: root.kind === "wifi" ? root.t("Забути мережу", "Forget this network") : root.t("Видалити з’єднання", "Remove connection")
                hintText: root.t("Затисніть і тримайте", "Press and hold")
                iconSource: Qt.resolvedUrl("../../assets/icons/material/network/delete-symbolic.svg")
                enabled: root.canWrite
                onConfirmed: root.run("forget", root.net.forget(root.uuid))
            }
        }
    }
}
