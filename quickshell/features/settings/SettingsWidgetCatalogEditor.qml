import QtQuick
import qs.components
import qs.theme

// Widget catalog editor for a SettingsField: maps the field's widget entries onto
// SettingsWidgetCatalog and writes reorder/remove/toggle edits back through the owner.
// `owner` is the owning SettingsField.
SettingsWidgetCatalog {
    id: widgetCatalog
    required property var owner
    enabled: !owner.blocked
    readonly property var entries: Array.isArray(owner.displayed) ? owner.displayed : []
    addLabel: owner.t("Додати віджет", "Add widget")
    configureLabel: owner.t("Налаштування", "Settings")
    removeLabel: owner.t("Видалити", "Remove")
    enableLabel: owner.t("Увімкнено", "Enabled")
    offLabel: owner.t("Вимкнено", "Off")
    moveHint: owner.t("Alt + стрілки змінюють порядок", "Alt + arrows reorder")
    function entryId(entry) { return String(entry.instanceId !== undefined ? entry.instanceId : entry.moduleId); }
    model: entries.map(function(entry) {
        const manifest = owner.manifestOf(entry);
        const zones = owner.zonesOf(entry, manifest);
        return {
            id: widgetCatalog.entryId(entry),
            moduleId: String(entry.moduleId),
            label: manifest && manifest.name ? String(manifest.name) : String(entry.moduleId),
            enabled: entry.enabled !== false,
            zones: zones,
            zoneLabel: owner.zoneLabel(zones),
            configurable: manifest !== null,
        };
    })
    onConfigure: function(id) { owner.controller.openWidget(id); }
    onAdded: owner.controller.runAction("widgets.add")
    onReordered: function(ids) {
        const byId = {};
        entries.forEach(function(entry) { byId[widgetCatalog.entryId(entry)] = entry; });
        owner.change(ids.map(function(id) { return byId[id]; }));
    }
    onRemoved: function(id) {
        owner.change(entries.filter(function(entry) { return widgetCatalog.entryId(entry) !== id; }));
    }
    onToggled: function(id, enabled) {
        owner.change(entries.map(function(entry) {
            return widgetCatalog.entryId(entry) === id ? Object.assign({}, entry, { enabled: enabled }) : entry;
        }));
    }
}
