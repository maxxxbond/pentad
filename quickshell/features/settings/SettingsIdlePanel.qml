pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/settings-system.mjs" as SystemText

Item {
    id: root
    required property var services
    readonly property var system: services.systemSettings
    readonly property var idleState: system ? system.idle : null
    readonly property bool ready: !!idleState && idleState.ok === true && idleState.available === true
    property string pendingRequest: ""
    property string pendingAction: ""
    property string failure: ""
    property bool refreshing: false
    objectName: "settings-panel-idle"
    implicitHeight: rows.implicitHeight

    ContinuousSurface {
        anchors.fill: parent
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusCard
    }

    function t(uk, en) { return services.text(uk, en); }
    function refresh() {
        if (!system) return;
        refreshing = true;
        system.refreshIdle();
    }
    onVisibleChanged: if (root.visible) root.refresh()
    Component.onCompleted: if (root.visible) root.refresh()
    Connections {
        target: root.system
        function onIdleChanged() { root.refreshing = false; }
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingRequest) return;
            root.pendingRequest = "";
            root.failure = result.ok ? "" : SystemText.systemError(result.reason, root.t);
            root.refreshing = true;
        }
    }

    Column {
        id: rows
        objectName: "settings-section-fields"
        width: parent.width
        Repeater {
            model: ["display", "suspend"]
            delegate: SettingsRow {
                id: timerRow
                required property string modelData
                readonly property int seconds: root.idleState && root.idleState.ok ? root.idleState[modelData] : 0
                readonly property var choices: SystemText.idleTimeoutOptions(seconds, root.t)
                width: rows.width
                label: modelData === "display" ? root.t("Вимикати екран через", "Turn off screen after")
                    : root.t("Переводити в сон через", "Sleep after")
                helpText: modelData === "display"
                    ? root.t("Час від останньої активності. Вимикає дисплеї; рух миші або клавіша вмикає їх знову. Таймер блокування не змінюється.",
                        "Time since last activity. Turns displays off; mouse or keyboard activity wakes them. The lock timer stays unchanged.")
                    : root.t("Час від останньої активності. Наявна команда сну зберігається. Інші правила hypridle не змінюються.",
                        "Time since last activity. Keeps the existing sleep command and other hypridle rules.")
                infoAccessibleName: root.t("Про цей параметр", "About this setting")
                pending: root.pendingRequest !== "" && root.pendingAction === modelData
                error: root.failure !== "" && root.pendingAction === modelData
                errorText: error ? root.failure : ""
                PentadComboBox {
                    id: timerBox
                    objectName: "settings-idle-" + timerRow.modelData
                    width: timerBox.parent ? timerBox.parent.width : 240
                    fill: Theme.tokens.surfaceOverlay
                    model: timerRow.choices
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: timerRow.choices.findIndex(function(option) { return option.value === timerRow.seconds; })
                    displayText: root.idleState && root.idleState.ok ? timerBox.currentText : root.t("Недоступно", "Unavailable")
                    accessibleName: timerRow.label
                    enabled: root.ready && !root.services.safeMode && !root.refreshing && root.pendingRequest === ""
                    onActivated: function(index) {
                        root.failure = "";
                        root.pendingAction = timerRow.modelData;
                        root.pendingRequest = root.system.setIdleTimeout(timerRow.modelData, timerRow.choices[index].value);
                        timerBox.currentIndex = Qt.binding(function() {
                            return timerRow.choices.findIndex(function(option) { return option.value === timerRow.seconds; });
                        });
                    }
                }
            }
        }
        SettingsRow {
            visible: !root.ready || !!(root.system && root.system.idleRestartRequired)
            width: rows.width
            label: root.t("Стан", "Status")
            PentadText {
                id: statusText
                objectName: "settings-idle-status"
                width: statusText.parent ? statusText.parent.width : 240
                text: !root.idleState ? root.t("Завантаження…", "Loading…")
                    : !root.idleState.ok ? SystemText.systemError(root.idleState.reason, root.t)
                    : !root.idleState.available ? root.t("Потрібен hypridle", "Requires hypridle")
                    : root.t("Збережено. Перезапустіть hypridle або увійдіть у сеанс знову.",
                        "Saved. Restart hypridle or sign in again.")
                color: Theme.tokens.textMuted
                wrapMode: Text.WordWrap
            }
            PentadButton {
                objectName: "settings-idle-refresh"
                visible: !root.ready
                text: root.t("Оновити", "Refresh")
                enabled: !root.refreshing && root.pendingRequest === ""
                onClicked: root.refresh()
            }
        }
    }
}
