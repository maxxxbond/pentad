pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/network.mjs" as NetworkLogic

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
    // The backend lists networks only while it scans, so the list shown here is a snapshot
    // that survives a stopped scan; rows are rebuilt at most every 1.2 s and only on a real change.
    property var shownAccessPoints: []
    property string shownSignature: ""
    property bool shownDirty: false
    // A connect waiting for a stopped scan to bring its network back: { name, device, secret }.
    property var queuedConnect: null
    width: parent ? parent.width : 320
    implicitHeight: card.implicitHeight

    function refreshShown() {
        shownDirty = false;
        if (adapterState.kind !== "ready" || adapterState.value.wifiEnabled !== true) {
            shownSignature = "";
            shownAccessPoints = [];
            return;
        }
        if (credentialPromptOpen) { shownDirty = true; return; }
        const next = NetworkLogic.mergeAccessPoints(shownAccessPoints, adapterState.value.accessPoints,
            adapterState.value.wifiScanEnabled);
        const signature = next.map(function(item) {
            return `${item.device}|${item.name}|${item.connected}|${item.bars}|${item.known}|${item.stale === true}`;
        }).join("\n");
        if (signature === shownSignature) return;
        shownSignature = signature;
        shownAccessPoints = next;
    }
    function scheduleRefresh() {
        if (adapterState.kind !== "ready" || adapterState.value.wifiEnabled !== true) { refreshShown(); return; }
        if (refreshThrottle.running) { shownDirty = true; return; }
        refreshShown();
        refreshThrottle.start();
    }
    readonly property bool scanning: adapterState.kind === "ready" && adapterState.value.wifiScanEnabled === true
    readonly property bool scanAvailable: networkService.active && !networkService.safeMode && wifiPresent
        && adapterState.kind === "ready" && adapterState.value.wifiEnabled === true && !pendingRequestId
    function toggleScan() {
        if (!scanAvailable) return;
        const device = adapterState.value.devices.find(function(item) {
            return item.type === "wifi" && (adapterState.value.wifiScanEnabled ? item.scannerEnabled : true);
        });
        if (!device) return;
        if (adapterState.value.wifiScanEnabled) {
            ownedScanDevice = "";
            run(networkService.stopScan(device.name));
        } else {
            ownedScanDevice = device.name;
            run(networkService.scan(device.name));
        }
    }
    function startConnect(name, device, secret) {
        if (pendingRequestId) return false;
        if (networkService.findNetwork(name, device)) return run(networkService.connectNetwork(name, device, secret));
        if (adapterState.kind !== "ready" || !adapterState.value.devices.some(function(item) { return item.name === device; }))
            return false;
        queuedConnect = { name: name, device: device, secret: secret };
        queueTimeout.restart();
        if (!adapterState.value.wifiScanEnabled) {
            ownedScanDevice = device;
            run(networkService.scan(device));
        }
        return true;
    }
    function flushQueuedConnect() {
        if (!queuedConnect || pendingRequestId) return;
        const queued = queuedConnect;
        if (!networkService.findNetwork(queued.name, queued.device)) return;
        queuedConnect = null;
        queueTimeout.stop();
        run(networkService.connectNetwork(queued.name, queued.device, queued.secret));
    }

    function run(requestId, kind) {
        if (!requestId) return false;
        pendingRequestId = requestId;
        pendingWifiToggleId = kind === "wifi-toggle" ? requestId : "";
        error = "";
        return true;
    }
    function connectAccessPoint(item) {
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
            return;
        }
        startConnect(item.name, item.device, undefined);
    }
    function submitPassword() {
        if (!password || !requestName || !requestCanUsePsk) return;
        const secret = password;
        requestUsedPsk = true;
        const started = startConnect(requestName, requestDevice, secret);
        password = "";
        if (started) credentialPromptOpen = false;
        else {
            credentialPromptOpen = true;
            error = root.services.text("Триває інша мережева дія", "Another network action is in progress");
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
            // Keep the request while a connect waits for the rescan that just finished.
            if (!queuedConnect) closeCredentialPrompt();
        } else if (result.reason === "secrets-required" && requestCanUsePsk) {
            if (!visible) { closeCredentialPrompt(); return; }
            error = requestUsedPsk ? root.services.text("Пароль не прийнято. Спробуйте ще раз.", "Password was not accepted. Try again.") : "";
            password = "";
            credentialPromptOpen = true;
        } else if (["authentication-timeout", "wifi-disconnected", "wifi-failed"].includes(result.reason)
            && requestCanUsePsk) {
            if (!visible) { closeCredentialPrompt(); return; }
            error = root.services.text("Не вдалося автентифікуватися. Перевірте пароль і спробуйте ще раз.", "Could not authenticate. Check the password and try again.");
            password = "";
            credentialPromptOpen = true;
        } else {
            error = result.reason === "secrets-required"
                ? root.services.text("Ця мережа потребує даних входу, які оболонка не може запитати", "This network needs credentials that the native API cannot prompt for")
                : root.services.text("Мережева дія не вдалася", "Network action failed") + ` (${result.reason || "failed"})`;
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
    onAdapterStateChanged: { autoScan(); flushQueuedConnect(); scheduleRefresh(); }
    onPendingRequestIdChanged: { autoScan(); flushQueuedConnect(); }
    onCredentialPromptOpenChanged: if (!credentialPromptOpen) scheduleRefresh()
    onVisibleChanged: {
        if (visible) autoScan();
        else {
            autoScanTried = false;
            queuedConnect = null;
            queueTimeout.stop();
            requestScanStop();
            closeCredentialPrompt();
        }
    }
    Component.onCompleted: { autoScan(); scheduleRefresh(); }
    Component.onDestruction: { requestScanStop(); closeCredentialPrompt(); }

    // A short scan is enough to fill the list; leaving it on keeps refreshing signal strengths.
    // It must not stop while a connect is waiting for, or using, its network.
    Timer {
        interval: 3000
        running: root.ownedScanDevice !== "" && root.visible && !root.queuedConnect
            && !root.networkService.operation
        onTriggered: root.requestScanStop()
    }
    Timer {
        id: refreshThrottle
        interval: 1200
        onTriggered: if (root.shownDirty) { root.refreshShown(); refreshThrottle.start(); }
    }
    Timer {
        id: queueTimeout
        interval: 6000
        onTriggered: {
            root.queuedConnect = null;
            root.error = root.services.text("Мережу не знайдено поруч", "The network is not in range");
            root.requestScanStop();
        }
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
                // In the details view the toggle and the scan button live in its header.
                visible: !root.selectorMode
                width: content.width
                spacing: 8
                PentadText { visible: !root.selectorMode; text: root.services.text("Мережа", "Network"); role: "section"; width: Math.max(0, parent.width - wifiToggle.width - scanButton.width - 20) }
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
                    // In the details view the card is already raised, so lift the button one step.
                    restFill: root.selectorMode ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                    text: root.adapterState.kind === "ready" && root.adapterState.value.wifiScanEnabled
                        ? root.services.text("Зупинити пошук", "Stop scan")
                        : root.services.text("Шукати мережі", "Scan networks")
                    requestedEnabled: root.networkService.active && !root.networkService.safeMode
                        && root.wifiPresent
                        && root.adapterState.kind === "ready" && root.adapterState.value.wifiEnabled && !root.pendingRequestId
                    visible: !root.selectorMode
                    onPressed: root.toggleScan()
                }
            }
            PentadText {
                visible: root.adapterState.kind !== "ready"
                text: root.networkService.preview ? root.services.text("Перегляд · лише читання", "Preview · read only")
                    : root.services.text("Мережева служба недоступна", "Network service unavailable")
                color: Theme.tokens.textMuted
                role: "caption"
            }
            PentadText {
                visible: root.networkService.safeMode
                    || root.adapterState.kind === "ready" && !root.adapterState.value.wifiHardwareEnabled
                text: root.networkService.safeMode ? root.services.text("У безпечному режимі лише читання", "Read only in safe mode")
                    : root.services.text("Wi-Fi вимкнено апаратно", "Wi-Fi is disabled by hardware")
                color: Theme.tokens.textMuted
                role: "caption"
            }
            PentadText {
                id: emptyAccessPoints
                objectName: "networkEmptyAccessPoints"
                visible: root.adapterState.kind === "ready" && root.shownAccessPoints.length === 0
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
                model: root.shownAccessPoints
                delegate: Column {
                    id: accessPointItem
                    required property var modelData
                    width: content.width
                    spacing: 6
                    SelectorOption {
                        id: accessPointRow
                        readonly property var accessPoint: accessPointItem.modelData
                        width: content.width
                        text: accessPoint.name
                        selected: accessPoint.connected
                        subtitle: accessPoint.security
                        signalLevel: accessPoint.bars
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
                    // The row above names the network, so the prompt is just the field and its actions,
                    // on a tonal card concentric with the row (14 = 8 padding + 6 field radius).
                    ContinuousSurface {
                        id: passwordPrompt
                        visible: root.credentialPromptOpen && root.requestName === accessPointRow.accessPoint.name
                            && root.requestDevice === accessPointRow.accessPoint.device
                        onVisibleChanged: if (visible) Qt.callLater(function() { passwordField.forceActiveFocus(); })
                        width: content.width
                        implicitHeight: promptRow.implicitHeight + 16
                        height: implicitHeight
                        fill: Theme.tokens.surfaceOverlay
                        extent: Metrics.radiusCard
                        Row {
                            id: promptRow
                            x: 8
                            y: 8
                            width: parent.width - 16
                            spacing: 8
                            PentadTextField {
                                id: passwordField
                                width: Math.max(0, promptRow.width - connectButton.width - cancelButton.width - 16)
                                implicitHeight: 40
                                text: root.password
                                onTextChanged: root.password = text
                                placeholderText: root.services.text("Пароль Wi-Fi", "Wi-Fi password")
                                echoMode: TextInput.Password
                                accessibleName: root.services.text("Пароль Wi-Fi", "Wi-Fi password")
                                onAccepted: root.submitPassword()
                            }
                            PentadButton {
                                id: connectButton
                                controlHeight: 40
                                text: root.services.text("Підключити", "Connect")
                                requestedEnabled: root.password !== ""
                                onPressed: root.submitPassword()
                            }
                            PentadButton {
                                id: cancelButton
                                controlHeight: 40
                                iconSource: Qt.resolvedUrl("../../assets/icons/material/close-symbolic.svg")
                                accessibleName: root.services.text("Скасувати", "Cancel")
                                onPressed: root.closeCredentialPrompt()
                            }
                        }
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
                    ? root.services.text("Увійдіть у мережу", "Sign in to the network") : root.services.text("Підключено · обмежений інтернет", "Connected · limited internet")
                color: Theme.tokens.textMuted
                role: "caption"
            }
        }
    }
}
