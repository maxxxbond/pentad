pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules

// The background worker's rows: its state, the jobs it finished, the size of its result cache with
// "Clear cache", and after how many idle minutes it stops (worker.idleExitSeconds in minutes).
Item {
    id: root
    required property var services
    readonly property var ms: services ? services.modelSettings : null
    readonly property var document: ms ? ms.document : null
    readonly property bool uk: services.text("uk", "en") === "uk"
    readonly property var stats: ms ? ms.stats : null
    readonly property var cache: stats && stats.cache ? stats.cache : null
    readonly property string workerState: {
        const capabilities = services ? services.capabilities : null;
        const state = capabilities ? capabilities.state : null;
        if (!state || state.kind !== "ready") return state && state.reason === "preview" ? "off" : "down";
        return state.value.worker;
    }
    readonly property bool writable: !!ms && ms.writableState.ok
    objectName: "settings-model-worker"
    implicitHeight: rows.height

    function t(uk, en) { return services.text(uk, en); }
    function stateText() {
        switch (workerState) {
        case "ready": return t("працює", "running");
        case "starting": return t("запуск…", "starting…");
        case "idle": return t("зупинено", "stopped");
        case "crash-loop": return t("збій", "failing");
        case "off": return t("вимкнено", "off");
        default: return t("недоступний", "unavailable");
        }
    }
    function stateInk() {
        if (workerState === "ready") return Theme.tokens.success;
        if (workerState === "crash-loop" || workerState === "down") return Theme.tokens.error;
        return Theme.tokens.textMuted;
    }
    function summary() {
        const parts = [];
        if (stats) {
            const done = (stats.completed || 0);
            parts.push(uk ? done + " " + Rules.pluralUk(done, "задача", "задачі", "задач") : done + (done === 1 ? " job" : " jobs"));
        }
        const cap = cache ? cache.maxBytes : document && document.worker ? document.worker.cacheMiB * 1024 * 1024 : 0;
        if (cache) parts.push(t("кеш ", "cache ") + Rules.binaryText(cache.bytes, uk) + t(" з ", " of ") + Rules.binaryText(cap, uk));
        else if (cap > 0) parts.push(t("кеш до ", "cache up to ") + Rules.binaryText(cap, uk));
        return parts.join(" · ");
    }

    Column {
        id: rows
        width: root.width

        Item {
            objectName: "settings-model-worker-status"
            width: rows.width
            height: Metrics.settingsRowMinHeight + Metrics.space1
            SettingsModelTag {
                id: stateTag
                objectName: "settings-model-worker-state"
                x: Metrics.space5
                anchors.verticalCenter: parent.verticalCenter
                text: root.stateText()
                ink: root.stateInk()
                dot: true
            }
            PentadText {
                objectName: "settings-model-worker-summary"
                anchors.left: stateTag.right
                anchors.leftMargin: Metrics.space3
                anchors.right: clear.left
                anchors.rightMargin: Metrics.space3
                anchors.verticalCenter: parent.verticalCenter
                text: root.summary()
                textFormat: Text.PlainText
                font.features: ({ tnum: 1 })
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
            PentadButton {
                id: clear
                objectName: "settings-model-clear-cache"
                anchors.right: parent.right
                anchors.rightMargin: Metrics.space4
                anchors.verticalCenter: parent.verticalCenter
                controlHeight: Metrics.controlSmall
                restFill: Theme.tokens.surfaceOverlay
                text: root.t("Очистити кеш", "Clear cache")
                pending: !!root.ms && root.ms.busy === "clear-cache"
                requestedEnabled: !!root.ms && root.ms.blocked !== "preview" && !!root.cache && root.cache.entries > 0
                onClicked: root.ms.clearCache()
            }
        }
        Item {
            objectName: "settings-model-worker-idle"
            width: rows.width
            height: Metrics.settingsRowMinHeight + Metrics.space1
            Rectangle {
                x: Metrics.space4
                width: parent.width - 2 * Metrics.space4
                height: 1
                color: Theme.tokens.outline
            }
            PentadText {
                x: Metrics.space5
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - idle.width - unit.width - 3 * Metrics.space3
                text: root.t("Зупинятися після простою", "Stop when idle for")
                textFormat: Text.PlainText
                font.weight: Font.Medium
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
            PentadSpinBox {
                id: idle
                objectName: "settings-model-idle-minutes"
                anchors.right: unit.left
                anchors.rightMargin: Metrics.space2
                anchors.verticalCenter: parent.verticalCenter
                accessibleName: root.t("Хвилин простою до зупинки", "Idle minutes before stopping")
                from: Rules.idleMinutesRange.min
                to: Rules.idleMinutesRange.max
                value: Rules.idleMinutes(root.document)
                enabled: root.writable && !(root.ms && root.ms.busy === "idle")
                onValueModified: {
                    root.ms.setIdleMinutes(value);
                    value = Qt.binding(function() { return Rules.idleMinutes(root.document); });
                }
            }
            PentadText {
                id: unit
                anchors.right: parent.right
                anchors.rightMargin: Metrics.space4
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("хв", "min")
                textFormat: Text.PlainText
                color: Theme.tokens.textMuted
                wrapMode: Text.NoWrap
            }
        }
    }
}
