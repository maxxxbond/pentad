pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/pentads.mjs" as Pentads
import "../../logic/widget-settings.mjs" as Builder

// Settings of one widget instance, built from its manifest: General (fields + Frame) and Placement.
// The page is rendered by SettingsPage, so it shares its header, tabs, Reset and Saved/Undo.
// The host (settings window) shows it instead of a catalog page and listens to `back`.
Item {
    id: root
    required property var services
    property string instanceId: ""
    property alias tabId: inner.tabId
    property string backLabel: t("Віджети", "Widgets")
    signal back()

    readonly property var documents: services.config.documents
    readonly property var widgets: documents.layout && documents.layout.widgets ? documents.layout.widgets : []
    readonly property int index: widgets.findIndex(function(entry) { return entry.instanceId === root.instanceId; })
    readonly property var placement: index >= 0 ? widgets[index] : null
    readonly property var entry: placement && services.plugins ? services.plugins.catalog[placement.moduleId] || null : null
    readonly property var manifest: entry ? entry.manifest : null
    // The page is rebuilt only when the set of active sections changes, not on every value edit.
    readonly property string zonesKey: manifest && placement
        ? Pentads.resolvePlacement(manifest, placement.settings, placement.slot).zones.join(",") : ""
    readonly property var page: {
        if (!manifest || !placement) return null;
        return Builder.widgetSettingsPage(manifest, { pathPrefix: "widgets." + index + ".settings",
            settings: { _zones: zonesKey.split(",") }, slot: placement.slot });
    }

    function t(uk, en) { return services.text(uk, en); }

    SettingsPage {
        id: inner
        objectName: "widget-settings-page"
        anchors.fill: parent
        visible: root.page !== null
        services: root.services
        pageOverride: root.page
        backLabel: root.backLabel
        onBack: root.back()
    }

    PentadText {
        objectName: "widget-settings-missing"
        visible: root.page === null
        x: 24
        y: 24
        text: root.t("Віджет не знайдено.", "Widget not found.")
        textFormat: Text.PlainText
        color: Theme.tokens.textMuted
    }
}
