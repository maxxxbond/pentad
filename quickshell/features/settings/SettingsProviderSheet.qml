pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules

// The "Add provider" / "Edit provider" sheet of the Models page, shown over the settings window
// while services.settings.flow is 'model-provider' (services.modelSettings.sheet says which
// provider or preset). Kind chips (Ollama, OpenAI-compatible, Anthropic, Gemini and the OpenRouter
// preset), name, base URL with the endpoint rule checked as you type, and where the key comes from:
// none, the system keyring or an environment variable. A typed key lives only in the password
// field; on save it goes to `secret.store` through services.modelSettings and the field is cleared
// at once, whatever the outcome. Escape, the close button or a tap outside closes the sheet.
FocusScope {
    id: root
    required property var services
    readonly property var ms: services ? services.modelSettings : null
    readonly property var request: ms && ms.sheet ? ms.sheet : ({ providerId: "", presetId: "ollama", keyFirst: false })
    readonly property string providerId: request.providerId || ""
    readonly property var provider: {
        const list = ms && ms.document && Array.isArray(ms.document.providers) ? ms.document.providers : [];
        return list.find(function(item) { return item.id === root.providerId; }) || null;
    }
    readonly property bool editing: providerId !== "" && provider !== null
    property string presetId: editing ? "" : request.presetId || "ollama"
    property var draft: editing ? Rules.draftFor(provider) : Rules.draftFor(null, presetId)
    // Shown under the fields after a failed save.
    property string failure: ""
    property bool touched: false
    readonly property var checked: Rules.draftErrors(draft)
    readonly property bool busy: ms ? ms.busy === "add-provider" || ms.busy === "edit-provider" : false
    readonly property bool keyringBlocked: ms ? ms.blocked !== "" : true
    readonly property real labelWidth: 112
    readonly property real padding: Metrics.space5
    readonly property alias keyField: keyInput
    objectName: "settings-provider-sheet"

    function t(uk, en) { return services.text(uk, en); }
    function dismiss() {
        keyInput.clear();
        services.settings.flow = "";
    }
    function patch(fields) {
        draft = Object.assign({}, draft, fields);
    }
    function choosePreset(id) {
        presetId = id;
        const preset = Rules.presetFor(id);
        if (editing) patch({ kind: preset.kind });
        else draft = Rules.draftFor(null, id);
    }
    function urlError() {
        const code = checked.errors.baseUrl;
        if (!code || (!touched && code === "required")) return "";
        if (code === "insecure-endpoint") return t("Потрібна адреса https://. Звичайний http — лише для цього комп’ютера.",
            "Use an https:// address. Plain http is only for this computer.");
        if (code === "required") return t("Вкажіть адресу.", "Enter an address.");
        return t("Це не адреса http(s), наприклад https://openrouter.ai/api/v1.", "This is not an http(s) address, like https://openrouter.ai/api/v1.");
    }
    function save() {
        touched = true;
        if (!checked.ok || !ms || busy) return false;
        // The key is read once, handed on and cleared; nothing else keeps it.
        const started = editing ? ms.updateProvider(providerId, draft, keyInput.text) : ms.addProvider(draft, keyInput.text);
        keyInput.clear();
        failure = "";
        return started;
    }
    function failureText(result) {
        if (!result || result.ok) return "";
        const reason = result.reason || "";
        if (reason === "document-invalid" || reason === "document-unreadable" || reason === "document-loading")
            return t("Файл моделей містить помилку — виправте models.json.", "The models file has an error — fix models.json.");
        if (reason === "safe-mode" || reason === "preview") return t("Ключі не зберігаються в безпечному режимі.", "Keys are not stored in safe mode.");
        if (reason === "unavailable" || reason === "service-missing")
            return t("Сховище ключів недоступне. Потрібні secret-tool і служба ключів.", "The keyring is unavailable. It needs secret-tool and a Secret Service.");
        if (reason === "id-taken") return t("Такий провайдер уже є.", "That provider already exists.");
        return t("Не вдалося зберегти: ", "Could not save: ") + (result.message || reason);
    }
    Connections {
        target: root.ms
        function onFinished(action, result) {
            if (action !== "add-provider" && action !== "edit-provider") return;
            if (result.ok) root.dismiss();
            else root.failure = root.failureText(result);
        }
    }

    focus: true
    Component.onCompleted: {
        if (request.keyFirst === true && keyInput.visible && keyInput.enabled) keyInput.forceActiveFocus();
        else nameField.forceActiveFocus();
    }
    Component.onDestruction: keyInput.clear()
    Keys.onEscapePressed: function(event) {
        root.dismiss();
        event.accepted = true;
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.alpha(Theme.tokens.surface, 0.72)
        // Only a tap outside the sheet dismisses it.
        TapHandler {
            onTapped: function(eventPoint) {
                const local = sheet.mapFromItem(scrim, eventPoint.position.x, eventPoint.position.y);
                if (!sheet.contains(Qt.point(local.x, local.y))) root.dismiss();
            }
        }
    }

    ContinuousSurface {
        id: sheet
        anchors.centerIn: parent
        width: Math.max(1, Math.min(520, root.width - 2 * Metrics.space6))
        height: content.implicitHeight + 2 * root.padding
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusPopover
        clipContent: false
        castsShadow: true
        Accessible.role: Accessible.Dialog
        Accessible.name: title.text

        Column {
            id: content
            x: root.padding
            y: root.padding
            width: sheet.width - 2 * root.padding
            spacing: Metrics.space3
            Item {
                width: parent.width
                height: Metrics.controlSmall
                PentadText {
                    id: title
                    objectName: "settings-provider-sheet-title"
                    anchors.left: parent.left
                    anchors.right: closeButton.left
                    anchors.rightMargin: Metrics.space3
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property string providerName: root.editing ? root.provider.name || root.provider.id : ""
                    text: root.editing ? root.t("Змінити «%1»", "Edit “%1”").arg(providerName) : root.t("Новий провайдер", "New provider")
                    textFormat: Text.PlainText
                    role: "section"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    Accessible.role: Accessible.Heading
                }
                PentadButton {
                    id: closeButton
                    objectName: "settings-provider-close"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    controlHeight: Metrics.controlSmall
                    restFill: "transparent"
                    ink: Theme.tokens.textMuted
                    iconSource: Qt.resolvedUrl("../../assets/icons/material/close-symbolic.svg")
                    iconSize: Metrics.panelIcon
                    accessibleName: root.t("Закрити", "Close")
                    onClicked: root.dismiss()
                }
            }
            Flow {
                width: parent.width
                spacing: Metrics.space2
                Repeater {
                    model: Rules.providerPresets
                    delegate: PentadChip {
                        required property var modelData
                        objectName: "settings-provider-kind-" + modelData.id
                        text: modelData.id === "openai-compatible" ? root.t("OpenAI-сумісний", "OpenAI-compatible") : modelData.name
                        checked: root.presetId !== "" ? modelData.id === root.presetId
                            : modelData.kind === root.draft.kind && modelData.id !== "openrouter"
                        onToggled: root.choosePreset(modelData.id)
                    }
                }
            }
            Column {
                width: parent.width
                spacing: Metrics.space1
                SettingsSheetRow {
                    width: parent.width
                    labelWidth: root.labelWidth
                    label: root.t("Назва", "Name")
                    PentadTextField {
                        id: nameField
                        objectName: "settings-provider-name"
                        width: parent.width
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        accessibleName: root.t("Назва", "Name")
                        text: root.draft.name
                        error: root.touched && !!root.checked.errors.name
                        onTextEdited: root.patch({ name: text })
                    }
                }
                SettingsSheetRow {
                    width: parent.width
                    labelWidth: root.labelWidth
                    label: root.t("Адреса", "Base URL")
                    errorText: root.urlError()
                    PentadTextField {
                        objectName: "settings-provider-url"
                        width: parent.width
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        accessibleName: root.t("Адреса", "Base URL")
                        text: root.draft.baseUrl
                        error: root.urlError() !== ""
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                        onTextEdited: {
                            root.touched = true;
                            root.patch({ baseUrl: text });
                        }
                    }
                }
                SettingsSheetRow {
                    width: parent.width
                    labelWidth: root.labelWidth
                    label: root.t("Ключ", "Key")
                    PentadSegmented {
                        objectName: "settings-provider-key-source"
                        width: parent.width
                        fill: Theme.tokens.surfaceOverlay
                        accessibleName: root.t("Звідки брати ключ", "Where the key comes from")
                        options: [
                            { value: "none", label: root.t("Без ключа", "None") },
                            { value: "keyring", label: root.t("Сховище", "Keyring") },
                            { value: "env", label: root.t("Змінна", "Variable") }
                        ]
                        value: root.draft.keySource
                        onActivated: function(value) { root.patch({ keySource: value }); }
                    }
                }
                SettingsSheetRow {
                    width: parent.width
                    visible: root.draft.keySource === "keyring"
                    labelWidth: root.labelWidth
                    label: root.t("Ключ API", "API key")
                    errorText: root.keyringBlocked ? root.t("Сховище ключів вимкнене в безпечному режимі.", "The keyring is off in safe mode.") : ""
                    PentadTextField {
                        id: keyInput
                        objectName: "settings-provider-key"
                        width: parent.width
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        enabled: !root.keyringBlocked
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        placeholderText: root.editing ? root.t("Порожньо — лишити як є", "Empty keeps the stored key")
                            : root.t("Вставте ключ", "Paste the key")
                        accessibleName: root.t("Ключ API", "API key")
                        Keys.onReturnPressed: root.save()
                        Keys.onEnterPressed: root.save()
                    }
                }
                SettingsSheetRow {
                    width: parent.width
                    visible: root.draft.keySource === "env"
                    labelWidth: root.labelWidth
                    label: root.t("Змінна", "Variable")
                    errorText: root.touched && root.checked.errors.credentialEnv
                        ? root.t("Назва великими літерами, наприклад OPENROUTER_API_KEY.", "An upper-case name, like OPENROUTER_API_KEY.") : ""
                    PentadTextField {
                        objectName: "settings-provider-env"
                        width: parent.width
                        implicitHeight: Metrics.controlMedium
                        fill: Theme.tokens.surfaceOverlay
                        font.family: "monospace"
                        placeholderText: "OPENROUTER_API_KEY"
                        accessibleName: root.t("Змінна середовища", "Environment variable")
                        text: root.draft.credentialEnv
                        error: root.touched && !!root.checked.errors.credentialEnv
                        inputMethodHints: Qt.ImhPreferUppercase | Qt.ImhNoPredictiveText
                        onTextEdited: root.patch({ credentialEnv: text.toUpperCase() })
                    }
                }
            }
            PentadText {
                objectName: "settings-provider-failure"
                visible: root.failure !== ""
                width: parent.width
                text: root.failure
                textFormat: Text.PlainText
                role: "caption"
                color: Theme.tokens.error
            }
            Item {
                width: parent.width
                height: Metrics.controlMedium
                Row {
                    anchors.right: parent.right
                    spacing: Metrics.space2
                    PentadButton {
                        objectName: "settings-provider-cancel"
                        text: root.t("Скасувати", "Cancel")
                        restFill: "transparent"
                        ink: Theme.tokens.textMuted
                        onClicked: root.dismiss()
                    }
                    PentadButton {
                        objectName: "settings-provider-save"
                        text: root.editing ? root.t("Зберегти", "Save") : root.t("Додати", "Add")
                        restFill: Theme.tokens.surfaceOverlay
                        pending: root.busy
                        requestedEnabled: root.checked.ok && !!root.ms && root.ms.writableState.ok
                        onClicked: root.save()
                    }
                }
            }
        }
    }
}
