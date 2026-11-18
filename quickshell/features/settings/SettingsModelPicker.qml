pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules

// The model picker of one role: a dropdown fed by every provider's live model list, filtered for
// the role (embeddings, vision or completion models), with the capability chips and the size of
// each model; a relayed Ollama cloud model or a remote provider is marked "cloud". "Type a name…"
// switches to a field for providers that cannot list their models.
Item {
    id: root
    required property var services
    required property string role
    readonly property var ms: services ? services.modelSettings : null
    readonly property var document: ms ? ms.document : null
    readonly property bool uk: services.text("uk", "en") === "uk"
    readonly property var providers: document && Array.isArray(document.providers) ? document.providers : []
    readonly property var choices: ms ? Rules.roleChoices(document, role, ms.lists) : []
    readonly property var current: ms ? Rules.currentChoice(document, role, ms.lists) : null
    readonly property bool writable: !!ms && ms.writableState.ok
    readonly property bool busy: !!ms && ms.busy === "role:" + role
    readonly property var cloudInk: Rules.hue(Theme.config.appearance, "cloud")
    property bool manual: false
    readonly property var entries: {
        const list = [{ value: "", label: t("Не вибрано", "None"), chips: [], sizeBytes: 0, cloud: false, providerName: "" }];
        const known = current ? choices.some(function(choice) { return choice.value === current.value; }) : true;
        if (current && !known) list.push(Object.assign({ label: current.model }, current));
        for (const choice of choices) list.push(Object.assign({ label: choice.model }, choice));
        list.push({ value: "__manual__", label: t("Ввести назву…", "Type a name…"), chips: [], sizeBytes: 0, cloud: false, providerName: "" });
        return list;
    }
    readonly property int currentIndex: {
        const value = current ? current.value : "";
        for (let i = 0; i < entries.length; i++) if (entries[i].value === value) return i;
        return 0;
    }
    readonly property bool manyProviders: providers.length > 1
    objectName: "settings-model-picker-" + role
    implicitHeight: Metrics.controlMedium
    implicitWidth: 260

    function t(uk, en) { return services.text(uk, en); }
    function chipLabel(chip) {
        if (chip === "vision") return t("зір", "vision");
        return chip;
    }
    function chipInk(chip) {
        if (chip === "vision") return Rules.hue(Theme.config.appearance, "vision");
        if (chip === "embedding") return Rules.hue(Theme.config.appearance, "embed");
        return Theme.tokens.textMuted;
    }
    function pick(index) {
        const entry = entries[index];
        if (!entry || !ms) return;
        if (entry.value === "__manual__") {
            manualProvider.currentIndex = Math.max(0, providers.findIndex(function(item) {
                return current ? item.id === current.providerId : true;
            }));
            manualField.text = current ? current.model : "";
            manual = true;
            manualField.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        if (entry.value === (current ? current.value : "")) return;
        ms.setRole(role, entry.providerId || "", entry.value === "" ? "" : entry.model);
    }
    function commitManual() {
        const provider = providers[Math.max(0, manualProvider.currentIndex)];
        if (!provider || manualField.text.trim() === "") return;
        if (ms.setRole(role, provider.id, manualField.text.trim())) manual = false;
    }

    PentadComboBox {
        id: combo
        objectName: "settings-model-picker-combo-" + root.role
        visible: !root.manual
        anchors.fill: parent
        fill: Theme.tokens.surfaceOverlay
        model: root.entries
        textRole: "label"
        valueRole: "value"
        currentIndex: root.currentIndex
        accessibleName: root.t("Модель", "Model")
        enabled: root.writable && !root.busy
        rightPadding: wellSize + wellInset + Metrics.space2 + (overlay.width > 0 ? overlay.width + Metrics.space2 : 0)
        onActivated: function(index) {
            root.pick(index);
            currentIndex = Qt.binding(function() { return root.currentIndex; });
        }
        // A new entries array (a list refreshed, a role saved) makes ComboBox reset its index,
        // which drops the binding above; put it back once the reset is done.
        onModelChanged: Qt.callLater(function() {
            combo.currentIndex = Qt.binding(function() { return root.currentIndex; });
        })
        delegate: ItemDelegate {
            id: row
            required property int index
            required property var modelData
            readonly property bool selected: combo.currentIndex === index
            width: ListView.view ? ListView.view.width : combo.width
            height: Metrics.controlMedium
            leftPadding: Metrics.space3
            rightPadding: Metrics.space3
            text: modelData.label
            highlighted: combo.highlightedIndex === index
            opacity: combo.rowLevel(index)
            transform: Translate { y: combo.rowDrop(row.index) }
            background: null
            Accessible.name: modelData.label
            contentItem: Item {
                PentadText {
                    anchors.left: parent.left
                    anchors.right: tags.left
                    anchors.rightMargin: Metrics.space2
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label
                    textFormat: Text.PlainText
                    color: row.selected || row.highlighted || row.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                    font.weight: row.selected ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                Row {
                    id: tags
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.space1
                    Repeater {
                        model: row.modelData.chips || []
                        delegate: SettingsModelTag {
                            required property string modelData
                            text: root.chipLabel(modelData)
                            ink: root.chipInk(modelData)
                        }
                    }
                    SettingsModelTag {
                        visible: row.modelData.cloud === true
                        text: root.t("хмара", "cloud")
                        ink: root.cloudInk
                    }
                    SettingsModelTag {
                        visible: root.manyProviders && !!row.modelData.providerName && row.modelData.value !== "__manual__"
                        text: row.modelData.providerName || ""
                    }
                    PentadText {
                        visible: row.modelData.sizeBytes > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: Rules.bytesText(row.modelData.sizeBytes, root.uk)
                        textFormat: Text.PlainText
                        role: "caption"
                        color: Theme.tokens.textMuted
                        font.features: ({ tnum: 1 })
                    }
                }
            }
        }
    }
    // The chips and size of the bound model, inside the box before the chevron well.
    Row {
        id: overlay
        objectName: "settings-model-picker-tags-" + root.role
        visible: !root.manual && !!root.current
        x: combo.width - combo.wellSize - combo.wellInset - Metrics.space2 - width
        anchors.verticalCenter: combo.verticalCenter
        spacing: Metrics.space1
        opacity: combo.enabled ? 1 : 0.55
        Repeater {
            model: root.current ? root.current.chips : []
            delegate: SettingsModelTag {
                required property string modelData
                text: root.chipLabel(modelData)
                ink: root.chipInk(modelData)
            }
        }
        SettingsModelTag {
            visible: !!root.current && root.current.cloud === true
            text: root.t("хмара", "cloud")
            ink: root.cloudInk
        }
        SettingsModelTag {
            visible: !!root.current && root.current.sizeBytes > 0
            text: root.current ? Rules.bytesText(root.current.sizeBytes, root.uk) : ""
        }
    }

    // Manual entry: the provider (when there are several), the model name, apply and cancel.
    Row {
        id: manualRow
        visible: root.manual
        anchors.fill: parent
        spacing: Metrics.space1
        PentadComboBox {
            id: manualProvider
            objectName: "settings-model-picker-provider-" + root.role
            visible: root.manyProviders
            width: visible ? Math.min(140, manualRow.width / 3) : 0
            height: parent.height
            fill: Theme.tokens.surfaceOverlay
            model: root.providers.map(function(provider) { return { label: provider.name || provider.id, value: provider.id }; })
            textRole: "label"
            valueRole: "value"
            accessibleName: root.t("Провайдер", "Provider")
        }
        PentadTextField {
            id: manualField
            objectName: "settings-model-picker-field-" + root.role
            width: manualRow.width - (manualProvider.visible ? manualProvider.width + manualRow.spacing : 0) - 2 * (Metrics.controlMedium + manualRow.spacing)
            height: parent.height
            fill: Theme.tokens.surfaceOverlay
            placeholderText: root.t("назва моделі", "model name")
            accessibleName: root.t("Назва моделі", "Model name")
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            Keys.onReturnPressed: root.commitManual()
            Keys.onEnterPressed: root.commitManual()
            Keys.onEscapePressed: function(event) {
                root.manual = false;
                event.accepted = true;
            }
        }
        PentadButton {
            objectName: "settings-model-picker-apply-" + root.role
            controlHeight: Metrics.controlMedium
            restFill: Theme.tokens.surfaceOverlay
            iconSource: Qt.resolvedUrl("../../assets/icons/material/controls/check-symbolic.svg")
            accessibleName: root.t("Застосувати", "Apply")
            requestedEnabled: manualField.text.trim() !== "" && root.writable
            pending: root.busy
            onClicked: root.commitManual()
        }
        PentadButton {
            objectName: "settings-model-picker-cancel-" + root.role
            controlHeight: Metrics.controlMedium
            restFill: "transparent"
            ink: Theme.tokens.textMuted
            iconSource: Qt.resolvedUrl("../../assets/icons/material/media/close-symbolic.svg")
            accessibleName: root.t("Скасувати", "Cancel")
            onClicked: root.manual = false
        }
    }
}
