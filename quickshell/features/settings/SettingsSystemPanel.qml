pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/settings-system.mjs" as SystemText

// System panels on a settings page (`control: 'panel'`): date and time, default applications and
// about. They ask services.systemSettings for fresh data when created and do nothing afterwards.
Item {
    id: root
    required property var services
    required property string panel
    readonly property var system: services.systemSettings || null
    property string pendingRequest: ""
    property string pendingKey: ""
    property string failure: ""
    property string failureKey: ""
    implicitHeight: loader.item ? loader.item.implicitHeight : 0

    function t(uk, en) { return services.text(uk, en); }
    // Runs one write and remembers which row asked, so that row shows its progress and error.
    function run(key, requestId) {
        failure = "";
        failureKey = key;
        pendingKey = key;
        pendingRequest = requestId || "";
    }
    Connections {
        target: root.system
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingRequest) return;
            root.pendingRequest = "";
            root.pendingKey = "";
            root.failure = result.ok ? "" : SystemText.systemError(result.reason, root.t);
        }
    }

    Loader {
        id: loader
        width: root.width
        sourceComponent: root.panel === "datetime" ? datetimePanel
            : root.panel === "default-apps" ? appsPanel
            : root.panel === "about" ? aboutPanel : null
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
    component ValueRow: SettingsRow {
        id: valueRow
        property string value: ""
        width: parent ? parent.width : 320
        PentadText {
            width: parent ? parent.width : 160
            text: valueRow.value !== "" ? valueRow.value : root.t("Невідомо", "Unknown")
            color: valueRow.value !== "" ? Theme.tokens.text : Theme.tokens.textMuted
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    Component {
        id: datetimePanel
        RowCard {
            id: timeCard
            objectName: "settings-panel-datetime"
            readonly property var time: root.system ? root.system.time : null
            readonly property bool canSet: !!time && time.canSet === true && !root.services.safeMode
            readonly property var zones: SystemText.timezoneOptions(root.system ? root.system.timezones : [], time ? time.timezone : "")
            readonly property int zoneIndex: zones.findIndex(function(zone) { return !!time && zone.value === time.timezone; })
            Component.onCompleted: if (root.system) { root.system.refreshTime(); root.system.loadTimezones(); }

            SettingsRow {
                width: timeCard.width
                label: root.t("Часовий пояс", "Time zone")
                pending: root.pendingKey === "timezone"
                error: root.failure !== "" && root.failureKey === "timezone"
                errorText: error ? root.failure : ""
                PentadComboBox {
                    objectName: "settings-timezone"
                    width: parent ? parent.width : 240
                    implicitHeight: Metrics.controlSmall
                    fitContent: true
                    fill: Theme.tokens.surfaceOverlay
                    model: timeCard.zones
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: timeCard.zoneIndex
                    displayText: currentIndex >= 0 ? currentText : root.t("Невідомо", "Unknown")
                    accessibleName: root.t("Часовий пояс", "Time zone")
                    enabled: timeCard.canSet && root.pendingRequest === "" && timeCard.zones.length > 0
                    onActivated: function(index) {
                        root.run("timezone", root.system.setTimezone(timeCard.zones[index].value));
                        // The box shows the confirmed zone until the system reports the change.
                        currentIndex = Qt.binding(function() { return timeCard.zoneIndex; });
                    }
                }
            }
            SettingsRow {
                width: timeCard.width
                label: root.t("Автоматичний час", "Automatic time")
                helpText: root.t("Синхронізує годинник з мережевими серверами часу (NTP). Зміна може запитати пароль.",
                    "Keeps the clock in sync with network time servers (NTP). Changing it may ask for a password.")
                infoAccessibleName: root.t("Про цей параметр", "About this setting")
                pending: root.pendingKey === "ntp"
                error: root.failure !== "" && root.failureKey === "ntp"
                errorText: error ? root.failure : ""
                PentadToggle {
                    objectName: "settings-ntp"
                    implicitHeight: Metrics.controlSmall
                    accessibleName: root.t("Автоматичний час", "Automatic time")
                    checked: !!timeCard.time && timeCard.time.ntp === true
                    pending: root.pendingKey === "ntp"
                    requestedEnabled: timeCard.canSet && !!timeCard.time && timeCard.time.canNtp === true && root.pendingRequest === ""
                    onToggled: {
                        root.run("ntp", root.system.setNtp(checked));
                        checked = Qt.binding(function() { return !!timeCard.time && timeCard.time.ntp === true; });
                    }
                }
            }
        }
    }

    Component {
        id: appsPanel
        RowCard {
            id: appsCard
            objectName: "settings-panel-default-apps"
            readonly property var reply: root.system ? root.system.defaultApps : null
            readonly property var categories: reply && reply.ok && Array.isArray(reply.categories) ? reply.categories : []
            Component.onCompleted: if (root.system) root.system.refreshDefaultApps()

            ValueRow {
                visible: appsCard.categories.length === 0
                label: root.t("Застосунки", "Applications")
                value: !appsCard.reply ? root.t("Завантаження…", "Loading…") : SystemText.systemError(appsCard.reply.reason, root.t)
            }
            Repeater {
                model: appsCard.categories
                delegate: SettingsRow {
                    id: appRow
                    required property int index
                    // Read from the JS array: a model role would turn nested lists into Qt lists.
                    readonly property var modelData: appsCard.categories[index]
                    readonly property var options: SystemText.appOptions(modelData)
                    readonly property int selected: options.findIndex(function(option) { return option.value === modelData.current; })
                    width: appsCard.width
                    label: SystemText.categoryLabel(modelData.category, root.t)
                    pending: root.pendingKey === modelData.category
                    error: root.failure !== "" && root.failureKey === modelData.category
                    errorText: error ? root.failure : ""
                    PentadComboBox {
                        objectName: "settings-default-app-" + appRow.modelData.category
                        width: parent ? parent.width : 240
                        implicitHeight: Metrics.controlSmall
                        fitContent: true
                        fill: Theme.tokens.surfaceOverlay
                        model: appRow.options
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: appRow.selected
                        displayText: appRow.options.length === 0 ? root.t("Немає застосунків", "No applications")
                            : currentIndex >= 0 ? currentText : root.t("Не вибрано", "Not set")
                        accessibleName: appRow.label
                        enabled: appRow.options.length > 0 && root.pendingRequest === "" && !root.services.safeMode
                        onActivated: function(index) {
                            root.run(appRow.modelData.category,
                                root.system.setDefaultApp(appRow.modelData.category, appRow.options[index].value));
                        currentIndex = Qt.binding(function() { return appRow.selected; });
                    }
                    }
                }
            }
        }
    }

    Component {
        id: aboutPanel
        RowCard {
            id: aboutCard
            objectName: "settings-panel-about"
            readonly property var info: root.system ? root.system.about : null
            Component.onCompleted: if (root.system) root.system.refreshAbout()
            ValueRow {
                objectName: "settings-about-hostname"
                label: root.t("Назва пристрою", "Device name")
                value: aboutCard.info ? aboutCard.info.hostname : ""
            }
            ValueRow {
                label: root.t("Система", "System")
                value: aboutCard.info ? aboutCard.info.os : ""
            }
            ValueRow {
                label: root.t("Ядро", "Kernel")
                value: aboutCard.info ? aboutCard.info.kernel : ""
            }
            ValueRow {
                label: root.t("Процесор", "Processor")
                value: aboutCard.info ? aboutCard.info.cpu : ""
            }
            ValueRow {
                label: root.t("Пам’ять", "Memory")
                value: aboutCard.info && aboutCard.info.memory ? SystemText.formatBytes(aboutCard.info.memory, root.t) : ""
            }
            ValueRow {
                label: root.t("Сеанс", "Session")
                value: aboutCard.info ? aboutCard.info.desktop : ""
            }
            ValueRow {
                label: root.t("Час роботи", "Uptime")
                value: aboutCard.info && aboutCard.info.uptime !== null ? SystemText.formatUptime(aboutCard.info.uptime, root.t) : ""
            }
        }
    }
}
