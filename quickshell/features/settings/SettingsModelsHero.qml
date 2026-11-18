pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules

// The poster strip at the top of the Models page: where the models run ("Усе локально." or the
// cloud providers in use), and live numbers while the page is open: memory held by loaded models,
// the last warm-up time, the OCR cache. A capsule meter splits the VRAM into the loaded models,
// the rest of the used memory and what is free. A broken models.json, safe mode and preview are
// stated here, since every edit on the page waits for them.
Item {
    id: root
    required property var services
    readonly property var ms: services ? services.modelSettings : null
    readonly property var document: ms ? ms.document : null
    readonly property bool uk: services.text("uk", "en") === "uk"
    readonly property var summary: Rules.heroSummary(document)
    readonly property var meter: ms ? Rules.vramMeter(ms.vram, ms.loaded) : ({ available: false })
    readonly property var writable: ms ? ms.writableState : ({ ok: false, reason: "service-missing" })
    readonly property bool broken: !writable.ok && (writable.reason === "document-invalid" || writable.reason === "document-unreadable")
    readonly property string hueName: broken ? "" : summary.state === "mixed" ? "cloud" : "local"
    readonly property color hueColor: broken ? Theme.tokens.error : Rules.hue(Theme.config.appearance, hueName)
    readonly property int modelCount: {
        if (!ms) return 0;
        let count = 0;
        for (const provider of Rules.localOllamaProviders(document)) {
            const entry = ms.lists[provider.id];
            count += entry && Array.isArray(entry.models) ? entry.models.length : 0;
        }
        return count;
    }
    readonly property var lastWarm: {
        const warmth = ms ? ms.warmth : ({});
        let best = null;
        for (const role of Object.keys(warmth)) {
            const entry = warmth[role];
            if (entry && entry.state === "warm" && (!best || role === "translate")) best = { role: role, ms: entry.loadMs || entry.wallMs || 0 };
        }
        return best;
    }
    readonly property bool wide: width >= 560
    readonly property real padding: Metrics.space5 - Metrics.space1
    objectName: "settings-models-hero"
    implicitHeight: card.height

    function t(uk, en) { return services.text(uk, en); }
    function roleName(role) {
        const names = { chat: ["Чат", "Chat"], fast: ["Швидка", "Fast"], vision: ["Зір", "Vision"], embed: ["Ембединги", "Embeddings"],
            translate: ["Переклад", "Translation"] };
        const pair = names[role] || [role, role];
        return t(pair[0], pair[1]);
    }

    property var held: null
    function hold() {
        if (visible && ms && !held) {
            held = ms;
            held.acquire();
        } else if ((!visible || !ms) && held) {
            held.release();
            held = null;
        }
    }
    onVisibleChanged: hold()
    Component.onCompleted: hold()
    Component.onDestruction: if (held) held.release()

    readonly property var headline: {
        if (broken) return [t("Файл моделей", "The models file"), t("містить помилку.", "has an error.")];
        if (summary.state === "empty") return [t("Моделей", "No models"), t("ще немає.", "yet.")];
        if (summary.state === "unbound") return [t("Ролі ще", "No roles"), t("не вибрано.", "chosen yet.")];
        if (summary.state === "mixed") return [t("Є", "Cloud"), t("хмарні провайдери.", "providers in use.")];
        return [t("Усе", "All"), t("локально.", "local.")];
    }
    readonly property string subline: {
        if (broken) return writable.reason === "document-unreadable"
            ? t("Перевірте models.json: його не вдалося прочитати. Доти тут нічого не змінюється.", "Check models.json: it could not be read. Until then nothing here changes.")
            : t("Виправте models.json. Доти тут нічого не змінюється.", "Fix models.json. Until then nothing here changes.");
        const parts = [];
        if (summary.state === "mixed") parts.push(summary.cloud.join(", "));
        else if (summary.local.length) parts.push(summary.local.join(", "));
        else if (summary.state !== "empty") parts.push(t("Провайдерів: ", "Providers: ") + (document && document.providers ? document.providers.length : 0));
        if (modelCount > 0) parts.push(uk ? modelCount + " " + Rules.pluralUk(modelCount, "модель", "моделі", "моделей")
            : modelCount + (modelCount === 1 ? " model" : " models"));
        if (summary.state === "local") parts.push(t("жоден віджет не відправляє дані в хмару", "no widget sends data to the cloud"));
        if (summary.state === "empty") parts.push(t("додайте провайдера нижче", "add a provider below"));
        return parts.join(" · ");
    }
    readonly property string modeNote: !ms ? "" : ms.blocked === "preview" ? t("Попередній перегляд: нічого не запускається.", "Preview: nothing runs.")
        : ms.blocked === "safe-mode" ? t("Безпечний режим: мережа й сховище ключів вимкнені.", "Safe mode: network and the keyring are off.") : ""

    SettingsTintCard {
        id: card
        width: root.width
        height: body.height + 2 * root.padding
        hue: root.hueColor
        tint: 0.16
        diagonal: true

        Item {
            id: body
            x: root.padding
            y: root.padding
            width: card.width - 2 * root.padding
            height: root.wide ? Math.max(leftColumn.height, rightColumn.height) : leftColumn.height + (rightColumn.visible ? Metrics.space4 + rightColumn.height : 0)

            Column {
                id: leftColumn
                width: root.wide ? Math.round(body.width * 0.52) : body.width
                anchors.bottom: root.wide ? parent.bottom : undefined
                spacing: Metrics.space1
                Row {
                    spacing: Metrics.space2
                    width: parent.width
                    PentadText {
                        id: headFirst
                        objectName: "settings-models-headline"
                        text: root.headline[0]
                        textFormat: Text.PlainText
                        role: "title"
                        wrapMode: Text.NoWrap
                        font.weight: Font.Black
                        font.letterSpacing: -0.4
                        solid: true
                    }
                    PentadText {
                        objectName: "settings-models-headline-accent"
                        width: Math.min(implicitWidth, parent.width - headFirst.width - parent.spacing)
                        text: root.headline[1]
                        textFormat: Text.PlainText
                        role: "title"
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        font.weight: Font.Black
                        font.letterSpacing: -0.4
                        color: root.hueColor
                        solid: true
                    }
                }
                PentadText {
                    objectName: "settings-models-subline"
                    width: parent.width
                    text: root.subline
                    textFormat: Text.PlainText
                    color: Theme.tokens.textMuted
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }
                SettingsModelTag {
                    objectName: "settings-models-mode"
                    visible: root.modeNote !== ""
                    text: root.modeNote
                    ink: Theme.tokens.warning
                    dot: true
                }
            }

            Column {
                id: rightColumn
                objectName: "settings-models-stats"
                visible: !root.broken && root.summary.state !== "empty"
                x: root.wide ? body.width - width : 0
                y: root.wide ? body.height - height : leftColumn.height + Metrics.space4
                width: root.wide ? Math.round(body.width * 0.42) : body.width
                spacing: Metrics.space3

                Row {
                    id: stats
                    width: parent.width
                    spacing: Metrics.space3
                    readonly property var entries: {
                        const list = [];
                        const resident = root.meter.available ? root.meter.residentBytes : 0;
                        const loadedBytes = resident > 0 ? resident : (function() {
                            let sum = 0;
                            const loaded = root.ms ? root.ms.loaded : ({});
                            for (const key of Object.keys(loaded))
                                for (const model of loaded[key].models || []) sum += model.sizeBytes || 0;
                            return sum;
                        })();
                        const memory = Rules.formatBytes(loadedBytes, root.uk);
                        list.push({ id: "memory", value: memory.value + " " + memory.unit,
                            label: root.meter.available ? root.t("у відеопам’яті", "in VRAM") : root.t("у пам’яті", "in memory") });
                        if (root.lastWarm)
                            list.push({ id: "warm", value: Rules.secondsText(root.lastWarm.ms, root.uk),
                                label: root.t("прогрів: ", "warm-up: ") + root.roleName(root.lastWarm.role).toLowerCase() });
                        const cache = root.ms && root.ms.stats && root.ms.stats.cache ? root.ms.stats.cache : null;
                        list.push({ id: "cache", value: cache ? Rules.binaryText(cache.bytes, root.uk) : "—",
                            label: root.t("кеш OCR", "OCR cache") });
                        return list;
                    }
                    Repeater {
                        model: stats.entries
                        delegate: Column {
                            required property var modelData
                            objectName: "settings-models-stat-" + modelData.id
                            width: (stats.width - stats.spacing * (stats.entries.length - 1)) / stats.entries.length
                            PentadText {
                                width: parent.width
                                text: parent.modelData.value
                                textFormat: Text.PlainText
                                role: "title"
                                font.weight: Font.Bold
                                font.features: ({ tnum: 1 })
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                solid: true
                            }
                            PentadText {
                                width: parent.width
                                text: parent.modelData.label
                                textFormat: Text.PlainText
                                role: "caption"
                                color: Theme.tokens.textMuted
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                solid: true
                            }
                        }
                    }
                }

                SettingsVramMeter {
                    id: vramMeter
                    width: parent.width
                    visible: root.meter.available
                    meter: root.meter
                    hue: Rules.hue(Theme.config.appearance, "local")
                    uk: root.uk
                    services: root.services
                    legend: true
                }
            }
        }
    }
}
