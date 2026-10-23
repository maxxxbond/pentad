pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme

Item {
    id: root
    objectName: "network-controls-selector"
    required property var services
    property bool selectorMode: false
    readonly property var networkService: services.network
    readonly property var adapterState: networkService.state
    readonly property bool wifiPresent: adapterState.kind === "ready"
        && (adapterState.value.devices || []).some(function(device) { return device.type === "wifi"; })
    property string pendingRequestId: ""
    property string pendingWifiToggleId: ""
    property string error: ""
    property string ownedScanDevice: ""
    property string requestName: ""
    property string requestDevice: ""
    property bool requestCanUsePsk: false
    property bool requestUsedPsk: false
    property bool credentialPromptOpen: false
    property string password: ""
    width: parent ? parent.width : 320
    implicitHeight: card.implicitHeight

    function run(requestId, kind) {
        if (!requestId) return false;
        pendingRequestId = requestId;
        pendingWifiToggleId = kind === "wifi-toggle" ? requestId : "";
        error = "";
        return true;
    }
    function connectAccessPoint(item) {
        requestScanStop();
        requestName = item.name;
        requestDevice = item.device;
        requestCanUsePsk = item.canUsePsk;
        requestUsedPsk = false;
        // An unknown secured network cannot connect without a password; ask up front
        // instead of waiting for the backend to report missing secrets.
        if (!item.known && item.canUsePsk) {
            error = "";
            password = "";
            credentialPromptOpen = true;
            Qt.callLater(function() { passwordField.forceActiveFocus(); });
            return;
        }
        run(networkService.connectNetwork(item.name, item.device));
    }
    function submitPassword() {
        if (!password || !requestName || !requestCanUsePsk) return;
        const secret = password;
        requestUsedPsk = true;
        const requestId = networkService.connectNetwork(requestName, requestDevice, secret);
        password = "";
        if (run(requestId)) credentialPromptOpen = false;
        else {
            credentialPromptOpen = true;
            error = "Another network action is in progress";
        }
    }
    function closeCredentialPrompt() {
        password = "";
        credentialPromptOpen = false;
        requestName = "";
        requestDevice = "";
        requestCanUsePsk = false;
    }
    function finish(requestId, result) {
        if (requestId !== pendingRequestId) return;
        pendingRequestId = "";
        pendingWifiToggleId = "";
        if (result.ok) {
            error = "";
            closeCredentialPrompt();
        } else if (result.reason === "secrets-required" && requestCanUsePsk) {
            if (!visible) { closeCredentialPrompt(); return; }
            error = requestUsedPsk ? "Password was not accepted. Try again." : "";
            password = "";
            credentialPromptOpen = true;
            Qt.callLater(function() { passwordField.forceActiveFocus(); });
        } else if (["authentication-timeout", "wifi-disconnected", "wifi-failed"].includes(result.reason)
            && requestCanUsePsk) {
            if (!visible) { closeCredentialPrompt(); return; }
            error = "Could not authenticate. Check the password and try again.";
            password = "";
            credentialPromptOpen = true;
            Qt.callLater(function() { passwordField.forceActiveFocus(); });
        } else {
            error = result.reason === "secrets-required"
                ? "This network needs credentials that the native API cannot prompt for"
                : `Network action failed (${result.reason || "failed"})`;
            closeCredentialPrompt();
        }
    }
    function requestScanStop() {
        if (!ownedScanDevice) return;
        const deviceName = ownedScanDevice;
        ownedScanDevice = "";
        networkService.stopScan(deviceName);
    }
    // Scan once per opening so the list is populated instead of an empty "no networks" state.
    property bool autoScanOnOpen: true
    property bool autoScanTried: false
    function autoScan() {
        if (!autoScanOnOpen || autoScanTried ||!visible || !networkService.active || networkService.safeMode) return;
        if (adapterState.kind !== "ready" || !adapterState.value.wifiHardwareEnabled
            || adapterState.value.wifiEnabled !== true || pendingRequestId) return;
        const device = adapterState.value.devices.find(function(item) { return item.type === "wifi"; });
        if (!device) return;
        autoScanTried = true;
        if (adapterState.value.wifiScanEnabled) return;
        ownedScanDevice = device.name;
        run(networkService.scan(device.name));
    }
    onAdapterStateChanged: autoScan()
    onPendingRequestIdChanged: autoScan()
    onVisibleChanged: {
        if (visible) autoScan();
        else { autoScanTried = false; requestScanStop(); closeCredentialPrompt(); }
    }
    Component.onCompleted: autoScan()
    Component.onDestruction: { requestScanStop(); closeCredentialPrompt(); }

    // A running scan keeps refreshing signal strengths, which rebuilds the list under the cursor.
    Timer {
        interval: 6000
        running: root.ownedScanDevice !== "" && root.visible
        onTriggered: root.requestScanStop()
    }

    Connections {
        target: root.networkService
        function onCommandFinished(requestId, result) { root.finish(requestId, result); }
    }

    PentadCard {
        id: card
        objectName: "network-selector-card"
        width: root.width
        fill: root.selectorMode ? "transparent" : Theme.tokens.surfaceRaised
        extent: root.selectorMode ? 0 : Metrics.radiusLarge
        clipContent: !root.selectorMode
        implicitHeight: content.implicitHeight + (root.selectorMode ? 0 : 24)
        Column {
            id: content
            objectName: "network-selector-content"
            anchors.fill: parent
            anchors.margins: root.selectorMode ? 0 : 12
            spacing: 8

            Row {
                width: content.width
                spacing: 8
                PentadText { visible: !root.selectorMode; text: "Network"; role: "section"; width: Math.max(0, parent.width - wifiToggle.width - scanButton.width - 20) }
                PentadToggle {
                    id: wifiToggle
                    visible: !root.selectorMode
                    objectName: "networkWifiToggle"
                    text: "Wi-Fi"
                    accessibleName: "Wi-Fi"
                    checkable: false
                    pending: !!root.pendingWifiToggleId
                    Binding on checked {
                        value: root.adapterState.kind === "ready" && root.adapterState.value.wifiEnabled
                        when: !wifiToggle.down && !root.pendingWifiToggleId
                        restoreMode: Binding.RestoreNone
                    }
                    enabled: root.networkService.active && !root.networkService.safeMode
                        && root.wifiPresent
                        && root.adapterState.kind === "ready" && root.adapterState.value.wifiHardwareEnabled
                        && (root.adapterState.value.wifiEnabled === true || root.adapterState.value.wifiEnabled === false)
                        && !root.pendingRequestId
                    onClicked: root.run(root.networkService.setWifiEnabled(!checked), "wifi-toggle")
                }
                PentadButton {
                    id: scanButton
                    text: root.adapterState.kind === "ready" && root.adapterState.value.wifiScanEnabled
                        ? root.services.text("Зупинити пошук", "Stop scan")
                        : root.services.text("Шукати мережі", "Scan networks")
                    requestedEnabled: root.networkService.active && !root.networkService.safeMode
                        && root.wifiPresent
                        && root.adapterState.kind === "ready" && root.adapterState.value.wifiEnabled && !root.pendingRequestId
                    onPressed: {
                        const device = root.adapterState.value.devices.find(function(item) {
                            return item.type === "wifi" && (root.adapterState.value.wifiScanEnabled ? item.scannerEnabled : true);
                        });
                        if (device) {
                            if (root.adapterState.value.wifiScanEnabled) {
                                root.ownedScanDevice = "";
                                root.run(root.networkService.stopScan(device.name));
                            } else {
                                root.ownedScanDevice = device.name;
                                root.run(root.networkService.scan(device.name));
                            }
                        }
                    }
                }
            }
            PentadText {
                visible: root.adapterState.kind !== "ready"
                text: root.networkService.preview ? "Preview · read only" : "Network service unavailable"
                color: Theme.tokens.textMuted
                role: "caption"
            }
            PentadText {
                visible: root.networkService.safeMode
                    || root.adapterState.kind === "ready" && !root.adapterState.value.wifiHardwareEnabled
                text: root.networkService.safeMode ? "Read only in safe mode" : "Wi-Fi is disabled by hardware"
                color: Theme.tokens.textMuted
                role: "caption"
            }
            PentadText {
                id: emptyAccessPoints
                objectName: "networkEmptyAccessPoints"
                visible: root.adapterState.kind === "ready" && root.adapterState.value.accessPoints.length === 0
                text: !root.wifiPresent ? root.services.text("Немає адаптера Wi-Fi", "No Wi-Fi adapter")
                    : root.adapterState.kind === "ready" && root.adapterState.value.wifiEnabled === null
                    ? root.services.text("Стан Wi-Fi невідомий", "Wi-Fi state unavailable")
                    : root.adapterState.kind === "ready" && root.adapterState.value.wifiEnabled === false
                    ? root.services.text("Wi-Fi вимкнено", "Wi-Fi is off")
                    : root.adapterState.kind === "ready" && root.adapterState.value.wifiScanEnabled
                    ? root.services.text("Триває пошук мереж", "Scanning for networks")
                    : root.services.text("Мереж не знайдено", "No networks found")
                color: Theme.tokens.textMuted
                role: "caption"
            }
            Repeater {
                model: root.adapterState.kind === "ready" ? root.adapterState.value.accessPoints : []
                delegate: SelectorOption {
                    id: accessPointRow
                    required property var modelData
                    readonly property var accessPoint: modelData
                    width: content.width
                    text: accessPoint.name
                    selected: accessPoint.connected
                    subtitle: accessPoint.security + " · " + accessPoint.signal + "%"
                    accessibleName: accessPoint.name + (accessPoint.connected
                        ? root.services.text(" · підключено", " · connected") : "")
                    enabled: root.networkService.active && !root.networkService.safeMode
                        && root.adapterState.kind === "ready" && root.adapterState.value.wifiEnabled && !root.pendingRequestId
                    onPressed: {
                        if (accessPoint.connected)
                            root.run(root.networkService.disconnectNetwork(accessPoint.name, accessPoint.device));
                        else root.connectAccessPoint(accessPoint);
                    }
                }
            }
            Column {
                visible: root.credentialPromptOpen
                width: content.width
                spacing: 6
                Column {
                    width: parent.width
                    PentadText {
                        width: parent.width
                        text: `Password for ${root.requestName}`
                        role: "section"
                        solid: true
                    }
                    PentadText {
                        width: parent.width
                        text: "NetworkManager may remember this password."
                        color: Theme.tokens.textMuted
                        role: "caption"
                        solid: true
                    }
                }
                Row {
                    width: parent.width
                    spacing: 8
                    PentadTextField {
                        id: passwordField
                        width: Math.max(0, parent.width - passwordActions.width - 8)
                        text: root.password
                        onTextChanged: root.password = text
                        placeholderText: "Wi-Fi password"
                        echoMode: TextInput.Password
                        accessibleName: "Wi-Fi password"
                        onAccepted: root.submitPassword()
                    }
                    Row {
                        id: passwordActions
                        spacing: 6
                        PentadButton { text: "Connect"; onPressed: root.submitPassword() }
                        PentadButton { text: "Cancel"; onPressed: root.closeCredentialPrompt() }
                    }
                }
            }
            PentadText {
                visible: root.error !== ""
                text: root.error
                color: Theme.tokens.error
                role: "caption"
            }
            PentadText {
                visible: root.adapterState.kind === "ready"
                    && (root.adapterState.value.connectivity === "portal" || root.adapterState.value.connectivity === "limited")
                text: root.adapterState.kind === "ready" && root.adapterState.value.connectivity === "portal"
                    ? "Sign in to the network" : "Connected · limited internet"
                color: Theme.tokens.textMuted
                role: "caption"
            }
        }
    }
}
