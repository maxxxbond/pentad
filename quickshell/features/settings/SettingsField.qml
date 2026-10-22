import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/settings-bindings.mjs" as Bindings
import "../../logic/pentads.mjs" as Pentads

SettingsRow {
    id: field
    required property var item
    required property var controller
    property var documents: ({})
    property var services: null
    objectName: "settings-field-" + (item && item.key !== undefined ? String(item.key) : "")

    readonly property string control: item.control || "value"
    readonly property bool isAction: control === "button" || control === "link"
    // Editors that own the whole page width and bring their own chrome.
    readonly property bool fullBleed: control === "catalog"
    wideControl: control === "cards" || control === "pentads" || control === "framePreview"
        || control === "list" || control === "catalog" || control === "chips"
        || (control === "options" && Array.isArray(displayed))
    bare: fullBleed
    readonly property var confirmed: item.document ? Bindings.readValue(documents, item) : item.default
    readonly property var displayed: hasDesired ? desired : confirmed
    property var desired: undefined
    property bool hasDesired: false
    property string requestId: ""
    property bool failed: false
    readonly property bool blocked: controller.pendingId !== ""
    readonly property string labelText: t(item.labelUk, item.labelEn)
    readonly property var optionList: (item.options || []).map(function(option) {
        return { value: option.value, label: field.t(option.labelUk, option.labelEn) };
    })

    // Reset support. SettingsRow may not declare `modified`/`resetRequested` yet, so both are feature-checked.
    readonly property bool rowHasModified: typeof field.modified !== "undefined"
    readonly property bool canReset: !isAction && item.document !== undefined && item.default !== undefined
    readonly property bool differsFromDefault: canReset && JSON.stringify(displayed) !== JSON.stringify(item.default)
    Binding {
        target: field
        property: "modified"
        value: field.differsFromDefault
        when: field.rowHasModified
    }
    Connections {
        target: field
        ignoreUnknownSignals: true
        function onResetRequested() {
            if (field.canReset && field.differsFromDefault) field.change(field.item.default);
        }
    }

    function clampNumber(v) {
        const lo = item.min !== undefined ? item.min : -Infinity;
        const hi = item.max !== undefined ? item.max : Infinity;
        const step = item.step !== undefined && item.step > 0 ? item.step : 0;
        let n = Math.min(hi, Math.max(lo, v));
        if (step > 0 && Number.isFinite(lo)) n = lo + Math.round((n - lo) / step) * step;
        n = Math.min(hi, Math.max(lo, n));
        return item.kind === "integer" ? Math.round(n) : Math.round(n * 1000) / 1000;
    }
    function t(uk, en) {
        return services && services.text ? services.text(uk, en) : (en !== undefined ? en : uk);
    }
    function optionIndex(value) {
        for (let i = 0; i < optionList.length; i++) if (optionList[i].value === value) return i;
        return -1;
    }
    function change(value) {
        if (blocked) return false;
        failed = false;
        const id = controller.commit(item, value);
        if (id) {
            requestId = id;
            desired = value;
            hasDesired = true;
            return true;
        }
        failed = controller.error !== "";
        return false;
    }
    function ending() {
        if (!hasDesired && !failed) return;
        failed = controller.error !== "";
        hasDesired = false;
        desired = undefined;
        requestId = "";
    }
    function manifestOf(entry) {
        if (typeof entry !== "object" || entry === null || entry.moduleId === undefined) return null;
        const catalog = services && services.plugins ? services.plugins.catalog : null;
        const found = catalog ? catalog[entry.moduleId] : null;
        return found && found.manifest ? found.manifest : null;
    }
    function zonesOf(entry, manifest) {
        if (manifest) return Pentads.resolvePlacement(manifest, entry.settings, entry.slot).zones;
        return entry && entry.slot !== undefined ? Pentads.zonesForSlots([entry.slot]) : [];
    }
    function zoneLabel(zones) {
        return zones.map(function(id) {
            const zone = Pentads.zoneOf(id);
            return zone ? field.t(zone.labelUk, zone.labelEn) : id;
        }).join(" · ");
    }

    label: isAction || fullBleed ? "" : labelText
    infoAccessibleName: t("Про цей параметр", "About this setting")
    helpText: !fullBleed && (item.helpUk !== undefined || item.helpEn !== undefined) ? t(item.helpUk, item.helpEn) : ""
    iconSource: item.icon ? Qt.resolvedUrl("../../assets/icons/" + item.icon) : ""
    pending: hasDesired && requestId !== "" && controller.pendingId === requestId
    error: failed
    errorText: failed ? controller.error : ""

    Connections {
        target: field.controller
        function onPendingIdChanged() {
            if (field.requestId !== "" && field.controller.pendingId !== field.requestId) field.ending();
        }
    }

    Loader {
        id: loader
        Layout.fillWidth: true
        width: parent ? parent.width : implicitWidth
        sourceComponent: {
            switch (field.control) {
            case "toggle": return toggleControl;
            case "segmented": return segmentedControl;
            case "dropdown": return dropdownControl;
            case "slider": return sliderControl;
            case "stepper": return stepperControl;
            case "text": return textControl;
            case "font": return fontControl;
            case "color": return colorControl;
            case "chips": return chipsControl;
            case "catalog": return catalogControl;
            case "options":
            case "list": return optionsControl;
            case "cards": return cardsControl;
            case "shortcut": return shortcutControl;
            case "pentads": return pentadsControl;
            case "framePreview": return framePreviewControl;
            case "button":
            case "link": return buttonControl;
            default: return valueControl;
            }
        }
    }
    readonly property alias controlItem: loader.item

    Component {
        id: toggleControl
        PentadToggle {
            implicitHeight: Metrics.controlSmall
            accessibleName: field.labelText
            checked: !!field.displayed
            pending: field.pending
            requestedEnabled: !field.blocked
            onToggled: {
                field.change(checked);
                checked = Qt.binding(function() { return !!field.displayed; });
            }
        }
    }

    Component {
        id: segmentedControl
        SettingsSegmented {
            options: field.optionList
            value: field.displayed
            accessibleName: field.labelText
            enabled: !field.blocked
            onActivated: function(value) { field.change(value); }
        }
    }

    Component {
        id: dropdownControl
        PentadComboBox {
            fill: Theme.tokens.surfaceOverlay
            model: field.optionList
            textRole: "label"
            valueRole: "value"
            currentIndex: field.optionIndex(field.displayed)
            accessibleName: field.labelText
            enabled: !field.blocked
            onActivated: function(index) {
                field.change(field.optionList[index].value);
                currentIndex = Qt.binding(function() { return field.optionIndex(field.displayed); });
            }
        }
    }

    Component {
        id: sliderControl
        SettingsSliderEditor { owner: field }
    }

    Component {
        id: stepperControl
        PentadSpinBox {
            id: spin
            accessibleName: field.labelText
            // Number fields keep three decimals (see clampNumber); the SpinBox works in scaled integers.
            decimals: field.item.kind === "number" ? 3 : 0
            readonly property real lowest: Math.max(-2147483647, Math.round((field.item.min !== undefined ? field.item.min : 0) * factor))
            readonly property real highest: Math.min(2147483647, Math.round((field.item.max !== undefined ? field.item.max : 100) * factor))
            from: lowest
            to: highest
            stepSize: Math.max(1, Math.round((field.item.step !== undefined ? field.item.step : 1) * factor))
            value: Math.round(Number(field.displayed) * factor)
            enabled: !field.blocked
            onValueModified: {
                // Typed values are only clamped; the step applies to the arrow buttons.
                field.change(Math.min(highest / factor, Math.max(lowest / factor, Math.round(realValue * factor) / factor)));
                value = Qt.binding(function() { return Math.round(Number(field.displayed) * spin.factor); });
            }
        }
    }

    Component {
        id: textControl
        RowLayout {
            spacing: 8
            property alias input: textInput
            PentadText {
                visible: field.item.prefix !== undefined
                text: field.item.prefix || ""
                textFormat: Text.PlainText
                color: Theme.tokens.textMuted
                wrapMode: Text.NoWrap
            }
            PentadTextField {
                id: textInput
                Layout.fillWidth: true
                implicitHeight: Metrics.controlMedium
                fill: Theme.tokens.surfaceOverlay
                accessibleName: field.labelText
                placeholderText: field.item.placeholderUk !== undefined || field.item.placeholderEn !== undefined
                    ? field.t(field.item.placeholderUk, field.item.placeholderEn) : ""
                text: field.displayed === undefined ? "" : String(field.displayed)
                error: field.failed
                enabled: !field.blocked
                onEditingFinished: {
                    if (text !== String(field.displayed)) field.change(text);
                    text = Qt.binding(function() { return field.displayed === undefined ? "" : String(field.displayed); });
                }
                Keys.onEscapePressed: function(event) {
                    text = Qt.binding(function() { return field.displayed === undefined ? "" : String(field.displayed); });
                    event.accepted = true;
                }
            }
        }
    }

    Component {
        id: fontControl
        SettingsFontField {
            value: field.displayed === undefined ? "" : String(field.displayed)
            accessibleName: field.labelText
            searchPlaceholder: field.t("Фільтр шрифтів", "Filter fonts")
            emptyText: field.t("Нічого не знайдено", "No font matches")
            enabled: !field.blocked
            onCommitted: function(family) { field.change(family); }
        }
    }

    Component {
        id: colorControl
        SettingsColorField {
            accessibleName: field.labelText
            value: field.displayed === undefined ? "" : String(field.displayed)
            invalidText: field.t("Потрібен колір #RRGGBB.", "Use a 6-digit hex color, like #869677.")
            customLabel: field.t("Власний", "Custom")
            enabled: !field.blocked
            onCommitted: function(color) { field.change(color); }
        }
    }

    Component {
        id: chipsControl
        SettingsChipSet {
            choices: (field.item.choices || []).map(function(choice) {
                return { value: choice.value, label: field.t(choice.labelUk, choice.labelEn) };
            })
            value: field.displayed
            sentinel: field.item.sentinel !== undefined ? String(field.item.sentinel) : "auto"
            sentinelLabel: field.t(field.item.sentinelUk !== undefined ? field.item.sentinelUk : "Авто",
                field.item.sentinelEn !== undefined ? field.item.sentinelEn : "Auto")
            accessibleName: field.labelText
            enabled: !field.blocked
            onActivated: function(value) { field.change(value); }
        }
    }

    Component {
        id: cardsControl
        SettingsOptionCards {
            options: (field.item.options || []).map(function(option) {
                return { value: option.value, label: field.t(option.labelUk, option.labelEn), art: option.art !== undefined ? option.art : field.item.art };
            })
            value: field.displayed
            accessibleName: field.labelText
            enabled: !field.blocked
            onActivated: function(value) { field.change(value); }
        }
    }

    Component {
        id: shortcutControl
        SettingsShortcutField {
            value: field.displayed === undefined ? "" : String(field.displayed)
            accessibleName: field.labelText
            recordLabel: field.t("Записати", "Record")
            cancelLabel: field.t("Скасувати", "Cancel")
            clearLabel: field.t("Очистити", "Clear")
            pressText: field.t("Натисніть клавіші", "Press keys")
            disabledText: field.t("Вимкнено", "Off")
            modifierText: field.t("Додайте модифікатор: Super або Alt.", "Add a modifier, like Super or Alt.")
            invalidText: field.t("Цю клавішу не можна призначити.", "That key cannot be bound.")
            requireModifier: field.item.requireModifier !== false
            clearable: field.item.clearable === true
            enabled: !field.blocked
            onCommitted: function(shortcut) { field.change(shortcut); }
        }
    }

    Component {
        id: buttonControl
        PentadButton {
            text: field.labelText
            accessibleName: field.labelText
            pending: false
            requestedEnabled: !field.blocked
            onClicked: field.controller.runAction(field.item.action)
        }
    }

    Component {
        id: valueControl
        PentadText {
            text: field.displayed === undefined ? "" : String(field.displayed)
            color: Theme.tokens.textMuted
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }

    Component {
        id: catalogControl
        SettingsWidgetCatalogEditor { owner: field }
    }

    Component {
        id: optionsControl
        SettingsListEditor { owner: field }
    }

    Component {
        id: pentadsControl
        SettingsPentadPicker {
            allowed: field.item.allowed
            value: field.displayed
            services: field.services
            accessibleName: field.labelText
            enabled: !field.blocked
            onActivated: function(zones) { field.change(zones); }
        }
    }

    Component {
        id: framePreviewControl
        SettingsFramePreview { item: field.item; documents: field.documents; services: field.services }
    }
}
