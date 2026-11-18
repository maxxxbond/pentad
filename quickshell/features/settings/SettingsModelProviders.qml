pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules
import "../../logic/models.mjs" as Models

// The provider cards of the Models page: one raised card per provider, tinted with its group hue
// (local green, cloud amber), a badge, the endpoint, a live status chip and its actions, then a
// quiet card that adds one. A local Ollama shows its VRAM meter and what it holds in memory; a
// remote provider shows where its key comes from and which roles use it. Removing a provider is
// confirmed in the card and empties the roles bound to it; its keyring entry can go with it.
Item {
    id: root
    required property var services
    readonly property var ms: services ? services.modelSettings : null
    readonly property var document: ms ? ms.document : null
    readonly property var providers: document && Array.isArray(document.providers) ? document.providers : []
    readonly property bool uk: services.text("uk", "en") === "uk"
    readonly property bool writable: !!ms && ms.writableState.ok
    readonly property int columns: width >= 600 ? 3 : width >= 380 ? 2 : 1
    readonly property real gap: Metrics.space3
    readonly property real cardWidth: Math.floor((width - gap * (columns - 1)) / columns)
    readonly property real cardHeight: 172
    readonly property real pad: Metrics.space4
    property string confirming: ""
    property bool clearKey: true
    objectName: "settings-model-providers"
    implicitHeight: grid.height

    function t(uk, en) { return services.text(uk, en); }
    function roleName(role) {
        const names = { chat: ["Чат", "Chat"], fast: ["Швидка", "Fast"], vision: ["Зір", "Vision"], embed: ["Ембединги", "Embeddings"],
            translate: ["Переклад", "Translation"] };
        const pair = names[role] || [role, role];
        return t(pair[0], pair[1]);
    }
    // The sheet is drawn by the settings window over everything (flow 'model-provider').
    function openAdd(preset) {
        if (!ms) return;
        ms.sheet = { providerId: "", presetId: preset, keyFirst: false };
        services.settings.flow = "model-provider";
    }
    function openEdit(provider, keyFirst) {
        if (!ms) return;
        ms.sheet = { providerId: provider.id, presetId: "", keyFirst: keyFirst === true };
        services.settings.flow = "model-provider";
    }
    function addPreset() {
        return Rules.localOllamaProviders(document).length ? "openrouter" : "ollama";
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

    Grid {
        id: grid
        width: root.width
        columns: root.columns
        columnSpacing: root.gap
        rowSpacing: root.gap

        Repeater {
            model: root.providers
            delegate: SettingsTintCard {
                id: card
                required property var modelData
                required property int index
                readonly property bool local: Models.providerDisclosure(modelData, "").execution === "local"
                readonly property bool ollama: modelData.kind === "ollama"
                readonly property var list: root.ms ? root.ms.lists[modelData.id] : null
                readonly property string listState: list ? list.state : "loading"
                readonly property var roles: Rules.rolesUsing(root.document, modelData.id)
                readonly property string hueName: local ? "local" : "cloud"
                readonly property color hueInk: Rules.hue(Theme.config.appearance, hueName)
                readonly property var loadedModels: root.ms && root.ms.loaded[modelData.id] ? root.ms.loaded[modelData.id].models : []
                readonly property var meter: local && ollama && root.ms ? Rules.vramMeter(root.ms.vram, root.ms.loaded) : ({ available: false })
                readonly property string keyState: modelData.credential ? (root.ms ? root.ms.keyStatus[modelData.credential] || "checking" : "checking")
                    : modelData.credentialEnv ? "env" : "none"
                readonly property bool confirming: root.confirming === modelData.id
                readonly property bool localOnlyBlocks: !local && !!root.document && root.document.privacy && root.document.privacy.localOnly === true
                objectName: "settings-provider-card-" + modelData.id
                width: root.cardWidth
                height: root.cardHeight
                hue: hueInk
                tint: 0.12

                readonly property bool off: !!card.list && (card.list.reason === "safe-mode" || card.list.reason === "preview")
                function statusText() {
                    if (card.off) return root.t("вимкнено", "off");
                    if (!card.local) return root.t("хмара", "cloud");
                    if (card.listState === "ready") return root.t("працює", "running");
                    if (card.listState === "error") return root.t("недоступний", "offline");
                    return root.t("перевірка…", "checking…");
                }
                function statusInk() {
                    if (card.off) return Theme.tokens.textMuted;
                    if (!card.local) return card.hueInk;
                    if (card.listState === "ready") return Theme.tokens.success;
                    if (card.listState === "error") return Theme.tokens.error;
                    return Theme.tokens.textMuted;
                }
                function keyText() {
                    switch (card.keyState) {
                    case "stored": return root.t("ключ у сховищі", "key in the keyring");
                    case "missing": return root.t("ключа немає", "no key stored");
                    case "unavailable": return root.t("сховище недоступне", "keyring unavailable");
                    case "env": return root.t("змінна ", "variable ") + card.modelData.credentialEnv;
                    case "none": return root.t("без ключа", "no key");
                    default: return root.t("ключ: перевірка…", "key: checking…");
                    }
                }
                function detailText() {
                    if (card.off) return root.t("У безпечному режимі сервер не опитується.", "Safe mode does not ask the server.");
                    if (card.local && card.ollama) {
                        if (card.listState === "error") return root.t("Не вдалося з’єднатися з сервером.", "Could not reach the server.");
                        const names = card.loadedModels.map(function(model) { return model.name; });
                        const parts = [];
                        if (card.meter.available)
                            parts.push(root.t("Відеопам’ять ", "VRAM ") + Rules.formatBytes(card.meter.usedBytes, root.uk).value + "/"
                                + Rules.bytesText(card.meter.totalBytes, root.uk));
                        parts.push(names.length ? names.join(", ") + root.t(" у пам’яті", " in memory") : root.t("у пам’яті нічого", "nothing in memory"));
                        const first = card.loadedModels.length ? Rules.minutesUntil(card.loadedModels[0].expiresAt, Date.now()) : -1;
                        if (first > 0 && first !== Infinity) parts.push(root.t("ще ", "for ") + first + root.t(" хв", " min"));
                        return parts.join(" · ");
                    }
                    if (card.localOnlyBlocks) return root.t("Вимкнено: увімкнено «Лише локально».", "Off: “Local only” is on.");
                    if (card.listState === "error" && card.list.reason === "denied") return root.t("Сервер відхилив ключ.", "The server refused the key.");
                    return card.roles.length ? root.t("Ролі: ", "Roles: ") + card.roles.map(root.roleName).join(", ")
                        : root.t("Не використовується жодною роллю", "Not used by any role");
                }

                Item {
                    x: root.pad
                    y: root.pad
                    width: card.width - 2 * root.pad
                    height: card.height - 2 * root.pad

                    // Badge, name over endpoint, status.
                    Item {
                        id: head
                        width: parent.width
                        height: Metrics.controlSmall + Metrics.space1
                        Rectangle {
                            id: badge
                            width: head.height
                            height: head.height
                            radius: width / 2
                            color: Qt.alpha(card.hueInk, 0.16)
                            PentadIcon {
                                anchors.centerIn: parent
                                source: Qt.resolvedUrl(card.local ? "../../assets/icons/material/memory-symbolic.svg"
                                    : "../../assets/icons/material/media/cloud-symbolic.svg")
                                pixelSize: Metrics.statusIcon
                                color: card.hueInk
                                Accessible.ignored: true
                            }
                        }
                        // The name shares its line with the status; the endpoint takes the whole width.
                        Column {
                            anchors.left: badge.right
                            anchors.leftMargin: Metrics.space2
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            PentadText {
                                objectName: "settings-provider-name-" + card.modelData.id
                                width: parent.width - status.width - Metrics.space2
                                text: card.modelData.name || card.modelData.id
                                textFormat: Text.PlainText
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                solid: true
                            }
                            PentadText {
                                width: parent.width
                                text: Rules.endpointCaption(card.modelData.baseUrl)
                                textFormat: Text.PlainText
                                role: "caption"
                                font.family: "monospace"
                                color: Theme.tokens.textMuted
                                elide: Text.ElideMiddle
                                wrapMode: Text.NoWrap
                                solid: true
                            }
                        }
                        SettingsModelTag {
                            id: status
                            objectName: "settings-provider-status-" + card.modelData.id
                            anchors.right: parent.right
                            y: Math.round(head.height / 2) - height
                            text: card.statusText()
                            ink: card.statusInk()
                            dot: true
                        }
                    }

                    // The middle: memory for a local Ollama, the key and the roles otherwise.
                    Column {
                        id: middle
                        visible: !card.confirming
                        y: head.height + Metrics.space3
                        width: parent.width
                        spacing: Metrics.space2
                        SettingsVramMeter {
                            width: parent.width
                            visible: card.meter.available
                            meter: card.meter
                            hue: card.hueInk
                            uk: root.uk
                            services: root.services
                            barHeight: Metrics.space2 - 2
                        }
                        SettingsModelTag {
                            objectName: "settings-provider-key-" + card.modelData.id
                            visible: !(card.local && card.ollama)
                            text: card.keyText()
                            iconSource: Qt.resolvedUrl("../../assets/icons/material/controls/vpn-key-symbolic.svg")
                            ink: card.keyState === "missing" || card.keyState === "unavailable" ? Theme.tokens.warning : Theme.tokens.textMuted
                        }
                        PentadText {
                            objectName: "settings-provider-detail-" + card.modelData.id
                            width: parent.width
                            text: card.detailText()
                            textFormat: Text.PlainText
                            role: "caption"
                            color: Theme.tokens.textMuted
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    // Actions along the bottom edge.
                    Row {
                        id: actions
                        visible: !card.confirming
                        anchors.bottom: parent.bottom
                        spacing: Metrics.space1
                        PentadButton {
                            objectName: "settings-provider-primary-" + card.modelData.id
                            controlHeight: Metrics.controlSmall
                            restFill: Theme.tokens.surfaceOverlay
                            text: card.keyState !== "none" && card.keyState !== "env" && !card.local
                                ? root.t("Замінити ключ", "Replace key") : root.t("Оновити", "Refresh")
                            requestedEnabled: root.writable || text === root.t("Оновити", "Refresh")
                            onClicked: {
                                if (text === root.t("Оновити", "Refresh")) root.ms.refreshProvider(card.modelData.id);
                                else root.openEdit(card.modelData, true);
                            }
                        }
                        PentadButton {
                            objectName: "settings-provider-edit-" + card.modelData.id
                            controlHeight: Metrics.controlSmall
                            restFill: "transparent"
                            ink: Theme.tokens.textMuted
                            iconSource: Qt.resolvedUrl("../../assets/icons/material/controls/edit-symbolic.svg")
                            iconSize: Metrics.panelIcon
                            accessibleName: root.t("Змінити провайдера", "Edit provider")
                            requestedEnabled: root.writable
                            onClicked: root.openEdit(card.modelData, false)
                        }
                    }
                    PentadButton {
                        id: removeButton
                        objectName: "settings-provider-remove-" + card.modelData.id
                        visible: !card.confirming
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        controlHeight: Metrics.controlSmall
                        restFill: "transparent"
                        ink: Theme.tokens.textMuted
                        iconSource: Qt.resolvedUrl("../../assets/icons/material/devices/delete-symbolic.svg")
                        iconSize: Metrics.panelIcon
                        accessibleName: root.t("Видалити провайдера", "Remove provider")
                        requestedEnabled: root.writable
                        onClicked: {
                            root.clearKey = true;
                            root.confirming = card.modelData.id;
                        }
                    }

                    // The confirmation replaces the middle and the actions.
                    Column {
                        objectName: "settings-provider-confirm-" + card.modelData.id
                        visible: card.confirming
                        y: head.height + Metrics.space3
                        width: parent.width
                        height: parent.height - y
                        spacing: Metrics.space2
                        PentadText {
                            width: parent.width
                            text: card.roles.length
                                ? root.t("Видалити? Ролі ", "Remove it? The roles ") + card.roles.map(root.roleName).join(", ")
                                    + root.t(" стануть порожніми.", " become empty.")
                                : root.t("Видалити цього провайдера?", "Remove this provider?")
                            textFormat: Text.PlainText
                            role: "caption"
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        PentadChip {
                            objectName: "settings-provider-clear-key-" + card.modelData.id
                            visible: !!card.modelData.credential
                            text: root.t("Стерти ключ зі сховища", "Clear its keyring key")
                            checked: root.clearKey
                            onToggled: root.clearKey = !root.clearKey
                        }
                    }
                    Row {
                        visible: card.confirming
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        spacing: Metrics.space1
                        PentadButton {
                            objectName: "settings-provider-confirm-cancel-" + card.modelData.id
                            controlHeight: Metrics.controlSmall
                            restFill: "transparent"
                            ink: Theme.tokens.textMuted
                            text: root.t("Скасувати", "Cancel")
                            onClicked: root.confirming = ""
                        }
                        PentadButton {
                            objectName: "settings-provider-confirm-remove-" + card.modelData.id
                            controlHeight: Metrics.controlSmall
                            restFill: Theme.tokens.surfaceOverlay
                            ink: Theme.tokens.error
                            text: root.t("Видалити", "Remove")
                            pending: !!root.ms && root.ms.busy === "remove-provider"
                            onClicked: {
                                if (root.ms.removeProvider(card.modelData.id, !!card.modelData.credential && root.clearKey)) root.confirming = "";
                            }
                        }
                    }
                }
            }
        }

        // The quiet card that adds a provider: no depth, one step darker than the cards.
        SettingsTintCard {
            id: addCard
            objectName: "settings-provider-add"
            width: root.cardWidth
            height: root.cardHeight
            raised: false
            base: Qt.darker(Theme.tokens.surfaceRaised, Theme.config.appearance === "light" ? 1.02 : 1.12)
            Column {
                anchors.centerIn: parent
                width: parent.width - 2 * root.pad
                spacing: Metrics.space2
                PentadButton {
                    objectName: "settings-provider-add-button"
                    anchors.horizontalCenter: parent.horizontalCenter
                    controlHeight: Metrics.controlSmall
                    restFill: "transparent"
                    text: "+ " + root.t("Додати провайдера", "Add provider")
                    requestedEnabled: root.writable
                    onClicked: root.openAdd(root.addPreset())
                }
                // Centred as a block: the widest line decides the offset.
                Flow {
                    x: Math.max(0, Math.round((parent.width - childrenRect.width) / 2))
                    width: parent.width
                    spacing: Metrics.space1
                    Repeater {
                        model: Rules.providerPresets
                        delegate: SettingsModelTag {
                            required property var modelData
                            objectName: "settings-provider-add-" + modelData.id
                            interactive: true
                            enabled: root.writable
                            opacity: enabled ? 1 : Metrics.stateDisabled
                            text: modelData.id === "openai-compatible" ? root.t("OpenAI-сумісний", "OpenAI-compatible") : modelData.name
                            onClicked: root.openAdd(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
