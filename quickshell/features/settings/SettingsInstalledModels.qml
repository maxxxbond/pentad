pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules

// "Installed models": one card per model a local Ollama lists, with its size in large tabular
// figures, its capability chips and, while it is in memory, a pulsing dot and a local tint. A model
// larger than the graphics memory is marked; a relayed cloud model shows "cloud" instead of a size.
Item {
    id: root
    required property var services
    readonly property var ms: services ? services.modelSettings : null
    readonly property var document: ms ? ms.document : null
    readonly property bool uk: services.text("uk", "en") === "uk"
    readonly property var cards: ms ? Rules.installedModels(document, ms.lists, ms.loaded, ms.vram) : []
    readonly property var locals: Rules.localOllamaProviders(document)
    readonly property string view: {
        if (!locals.length) return "none";
        if (cards.length) return "ready";
        const entries = locals.map(function(provider) { return root.ms ? root.ms.lists[provider.id] : null; });
        if (entries.some(function(entry) { return !entry || entry.state === "loading"; })) return "loading";
        if (entries.every(function(entry) { return entry && (entry.reason === "safe-mode" || entry.reason === "preview"); })) return "off";
        if (entries.every(function(entry) { return entry && entry.state === "error"; })) return "error";
        return "empty";
    }
    readonly property int columns: width >= 600 ? 3 : width >= 380 ? 2 : 1
    readonly property real gap: Metrics.space3
    readonly property real cardWidth: Math.floor((width - gap * (columns - 1)) / columns)
    readonly property real pad: Metrics.space4
    readonly property real cardHeight: 116
    readonly property color localInk: Rules.hue(Theme.config.appearance, "local")
    objectName: "settings-installed-models"
    implicitHeight: root.view === "ready" ? grid.height : note.implicitHeight + 2 * Metrics.space3

    function t(uk, en) { return services.text(uk, en); }
    function chipLabel(chip) { return chip === "vision" ? t("зір", "vision") : chip; }
    function chipInk(chip) {
        if (chip === "vision") return Rules.hue(Theme.config.appearance, "vision");
        if (chip === "embedding") return Rules.hue(Theme.config.appearance, "embed");
        return Theme.tokens.textMuted;
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

    ContinuousSurface {
        visible: root.view !== "ready"
        width: root.width
        height: root.implicitHeight
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusCard
        PentadText {
            id: note
            objectName: "settings-installed-models-note"
            x: Metrics.space4
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 2 * Metrics.space4
            text: root.view === "none" ? root.t("Локальний Ollama не підключено.", "No local Ollama is connected.")
                : root.view === "loading" ? root.t("Завантаження списку…", "Loading the list…")
                : root.view === "error" ? root.t("Ollama не відповідає.", "Ollama does not answer.")
                : root.view === "off" ? root.t("У безпечному режимі моделі не читаються.", "Safe mode does not read the models.")
                : root.t("Ollama ще не має моделей.", "Ollama has no models yet.")
            textFormat: Text.PlainText
            color: Theme.tokens.textMuted
        }
    }

    Grid {
        id: grid
        visible: root.view === "ready"
        width: root.width
        columns: root.columns
        columnSpacing: root.gap
        rowSpacing: root.gap
        Repeater {
            model: root.cards
            delegate: SettingsTintCard {
                id: card
                required property var modelData
                objectName: "settings-installed-model-" + modelData.name
                width: root.cardWidth
                height: root.cardHeight
                hue: modelData.loaded ? root.localInk : "transparent"
                tint: 0.12
                raised: modelData.loaded

                Column {
                    id: content
                    x: root.pad
                    y: root.pad
                    width: card.width - 2 * root.pad
                    spacing: Metrics.space2
                    Item {
                        width: parent.width
                        height: Metrics.space5
                        Item {
                            id: pulse
                            visible: card.modelData.loaded
                            width: visible ? Metrics.space2 : 0
                            height: Metrics.space2
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                id: halo
                                anchors.centerIn: parent
                                width: Metrics.space4
                                height: width
                                radius: width / 2
                                color: Qt.alpha(Theme.tokens.success, 0.18)
                                SequentialAnimation on scale {
                                    running: card.modelData.loaded && !Theme.tokens.reducedMotion && root.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.6; to: 1.15; duration: Motion.long * 3; easing.type: Easing.OutCubic }
                                    NumberAnimation { from: 1.15; to: 0.6; duration: Motion.long * 3; easing.type: Easing.InOutQuad }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.tokens.success
                            }
                        }
                        PentadText {
                            id: title
                            anchors.left: pulse.right
                            anchors.leftMargin: pulse.visible ? Metrics.space2 : 0
                            anchors.right: badge.left
                            anchors.rightMargin: Metrics.space2
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.modelData.title
                            textFormat: Text.PlainText
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        Item {
                            id: badge
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: inMemory.visible ? inMemory.implicitWidth : tooBig.visible ? tooBig.implicitWidth : 0
                            height: Metrics.space5
                            PentadText {
                                id: inMemory
                                visible: card.modelData.loaded
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.t("у пам’яті", "in memory")
                                textFormat: Text.PlainText
                                role: "caption"
                                color: Theme.tokens.textMuted
                            }
                            SettingsModelTag {
                                id: tooBig
                                visible: !card.modelData.loaded && card.modelData.tooBig
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.t("не влазить у VRAM", "larger than VRAM")
                                ink: Rules.hue(Theme.config.appearance, "cloud")
                            }
                        }
                    }
                    Row {
                        spacing: Metrics.space1
                        PentadText {
                            id: sizeValue
                            objectName: "settings-installed-size-" + card.modelData.name
                            text: card.modelData.cloud ? root.t("хмара", "cloud") : Rules.formatBytes(card.modelData.sizeBytes, root.uk).value
                            textFormat: Text.PlainText
                            role: "title"
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                            color: card.modelData.cloud ? Rules.hue(Theme.config.appearance, "cloud") : Theme.tokens.text
                            wrapMode: Text.NoWrap
                        }
                        PentadText {
                            visible: !card.modelData.cloud
                            anchors.baseline: sizeValue.baseline
                            text: Rules.formatBytes(card.modelData.sizeBytes, root.uk).unit
                            textFormat: Text.PlainText
                            color: Theme.tokens.textMuted
                            font.weight: Font.Medium
                            wrapMode: Text.NoWrap
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: Metrics.space1
                        Repeater {
                            id: chips
                            model: card.modelData.chips
                            delegate: SettingsModelTag {
                                required property string modelData
                                text: root.chipLabel(modelData)
                                ink: root.chipInk(modelData)
                            }
                        }
                        SettingsModelTag {
                            visible: card.modelData.parameterSize !== ""
                            text: card.modelData.parameterSize
                        }
                    }
                }
            }
        }
    }
}
