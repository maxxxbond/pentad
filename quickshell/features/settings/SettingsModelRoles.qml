pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules
import "../../logic/models.mjs" as Models

// The role card of the Models page: one row per role Pentad routes to, with a hue square (local
// green, cloud amber), the role's name, its model picker and, for a model a local Ollama serves,
// a "Warm" action that loads it now and then shows how long the load took.
Item {
    id: root
    required property var services
    readonly property var ms: services ? services.modelSettings : null
    readonly property var document: ms ? ms.document : null
    readonly property bool uk: services.text("uk", "en") === "uk"
    readonly property bool wide: width >= 520
    readonly property real pad: Metrics.space4
    readonly property real nameWidth: wide ? 140 : width - 2 * pad
    readonly property real actionWidth: wide ? 112 : 0
    objectName: "settings-model-roles"
    implicitHeight: card.height

    function t(uk, en) { return services.text(uk, en); }
    readonly property var roleNames: ({ chat: [t("Чат", "Chat")], fast: [t("Швидка", "Fast")], vision: [t("Зір", "Vision")],
        embed: [t("Ембединги", "Embeddings")], translate: [t("Переклад", "Translation")] })
    function warmable(role) {
        const resolved = Models.resolveRole(document, role);
        return resolved.ok && resolved.provider.kind === "ollama" && Models.providerDisclosure(resolved.provider, resolved.model).execution === "local";
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

    SettingsTintCard {
        id: card
        width: root.width
        height: rows.height + 2 * Metrics.space1
        Column {
            id: rows
            y: Metrics.space1
            width: card.width
            Repeater {
                model: Models.modelRoles
                delegate: Item {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property string hueName: Rules.roleHue(root.document, modelData)
                    readonly property var warmth: root.ms && root.ms.warmth[modelData] ? root.ms.warmth[modelData] : null
                    readonly property bool canWarm: root.warmable(modelData)
                    objectName: "settings-model-role-" + modelData
                    width: rows.width
                    height: root.wide ? Metrics.controlLarge + Metrics.space2 : Metrics.controlLarge + Metrics.controlMedium + Metrics.space2

                    Rectangle {
                        visible: row.index > 0
                        x: root.pad
                        width: row.width - 2 * root.pad
                        height: 1
                        color: Theme.tokens.outline
                    }
                    Row {
                        id: name
                        x: root.pad
                        y: root.wide ? Math.round((row.height - height) / 2) : Metrics.space3
                        width: root.nameWidth
                        spacing: Metrics.space3
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Metrics.space3 - 2
                            height: width
                            radius: Metrics.radiusTag - 1
                            color: row.hueName ? Rules.hue(Theme.config.appearance, row.hueName) : Theme.tokens.surfaceOverlay
                        }
                        PentadText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.roleNames[row.modelData] ? root.roleNames[row.modelData][0] : row.modelData
                            textFormat: Text.PlainText
                            font.weight: Font.DemiBold
                            wrapMode: Text.NoWrap
                        }
                    }
                    SettingsModelPicker {
                        x: root.wide ? root.pad + root.nameWidth : root.pad
                        y: root.wide ? Math.round((row.height - height) / 2) : name.y + name.height + Metrics.space2
                        width: root.wide ? row.width - x - root.actionWidth - root.pad - Metrics.space2 : row.width - 2 * root.pad - Metrics.space2 - warmBox.width
                        height: Metrics.controlMedium
                        services: root.services
                        role: row.modelData
                    }
                    Item {
                        id: warmBox
                        x: row.width - root.pad - width
                        y: root.wide ? Math.round((row.height - height) / 2) : name.y + name.height + Metrics.space2
                        width: root.wide ? root.actionWidth : Math.max(warmButton.implicitWidth, warmNote.implicitWidth)
                        height: Metrics.controlMedium
                        PentadButton {
                            id: warmButton
                            objectName: "settings-model-warm-" + row.modelData
                            visible: row.canWarm && !(row.warmth && row.warmth.state === "warm")
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            controlHeight: Metrics.controlSmall
                            restFill: "transparent"
                            ink: Theme.tokens.textMuted
                            text: root.t("Прогріти", "Warm up")
                            pending: !!row.warmth && row.warmth.state === "warming"
                            error: !!row.warmth && row.warmth.state === "error"
                            requestedEnabled: !!root.ms && root.ms.blocked === ""
                            onClicked: root.ms.warm(row.modelData)
                        }
                        PentadText {
                            id: warmNote
                            objectName: "settings-model-warm-note-" + row.modelData
                            visible: !warmButton.visible && text !== ""
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                const w = row.warmth;
                                if (w && w.state === "warm") return root.t("теплий · ", "warm · ") + Rules.secondsText(w.loadMs || w.wallMs, root.uk);
                                return "";
                            }
                            textFormat: Text.PlainText
                            role: "caption"
                            color: row.warmth && row.warmth.state === "warm" ? Rules.hue(Theme.config.appearance, "local") : Theme.tokens.textMuted
                            font.features: ({ tnum: 1 })
                            wrapMode: Text.NoWrap
                        }
                    }
                }
            }
        }
    }
}
