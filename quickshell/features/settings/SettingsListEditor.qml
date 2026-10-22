import QtQuick
import qs.components
import qs.theme

// List/options editor for a SettingsField: a reorderable option list for array values,
// a plain muted value otherwise. `owner` is the owning SettingsField.
Loader {
    required property var owner
    sourceComponent: Array.isArray(owner.displayed) ? list : scalar
    Component {
        id: list
        SettingsOptionList {
            id: optionList
            enabled: !owner.blocked
            removable: owner.control !== "list"
            removeLabel: owner.t("Видалити", "Remove")
            moveHint: owner.t("Alt + стрілки змінюють порядок", "Alt + arrows reorder")
            readonly property var entries: owner.displayed
            function entryId(entry) {
                if (typeof entry === "string") return entry;
                return String(entry.instanceId !== undefined ? entry.instanceId
                    : entry.id !== undefined ? entry.id : entry.definitionId);
            }
            function visibleKey(entry) {
                return typeof entry === "object" && entry !== null
                    ? ("visible" in entry ? "visible" : "enabled" in entry ? "enabled" : "") : "";
            }
            model: entries.map(function(entry) {
                const key = visibleKey(entry);
                const id = entryId(entry);
                const manifest = owner.manifestOf(entry);
                return {
                    id: id,
                    label: typeof entry === "string" ? entry
                        : String(entry.label !== undefined ? entry.label
                            : manifest && manifest.name ? manifest.name
                            : entry.moduleId !== undefined ? entry.moduleId
                            : entry.definitionId !== undefined ? entry.definitionId : id),
                    visible: key ? !!entry[key] : undefined,
                    zones: manifest ? owner.zonesOf(entry, manifest) : undefined,
                    configurable: manifest !== null,
                };
            })
            configureLabel: owner.t("Налаштування", "Settings")
            onConfigure: function(id) { owner.controller.openWidget(id); }
            onReordered: function(ids) {
                const byId = {};
                entries.forEach(function(entry) { byId[entryId(entry)] = entry; });
                owner.change(ids.map(function(id) { return byId[id]; }));
            }
            onRemoved: function(id) {
                owner.change(entries.filter(function(entry) { return entryId(entry) !== id; }));
            }
            onToggled: function(id, visible) {
                owner.change(entries.map(function(entry) {
                    const key = visibleKey(entry);
                    if (entryId(entry) !== id || !key) return entry;
                    return Object.assign({}, entry, { [key]: visible });
                }));
            }
        }
    }
    Component {
        id: scalar
        PentadText {
            text: owner.displayed === undefined ? "" : String(owner.displayed)
            color: Theme.tokens.textMuted
        }
    }
}
