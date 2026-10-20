pragma ComponentBehavior: Bound
import QtQuick
import qs.plugins
import qs.theme
import '../../logic/placement.mjs' as Placement

Row {
    id: root
    required property var services
    required property string slot
    required property string outputId
    required property bool compact
    signal activated(string action, string instanceId)
    spacing: 8
    readonly property var inputRegions: {
        const result = [];
        for (let i = 0; i < views.count; i++) {
            const host = views.itemAt(i);
            if (host && host.inputRegion) result.push(host.inputRegion);
        }
        return result;
    }
    readonly property real visualHeight: {
        var result = height;
        for (var i = 0; i < views.count; i++) {
            var host = views.itemAt(i);
            if (host) result = Math.max(result, host.renderedHeight);
        }
        return result;
    }
    readonly property var placements: {
        const catalog = services.plugins ? services.plugins.catalog : null;
        return Placement.placementsForSlot(services.config.documents.layout.widgets, catalog, root.slot);
    }
    Repeater {
        id: views
        model: root.placements
        delegate: Item {
            id: placement
            required property var modelData
            readonly property real frameInset: modelData.frame.margin + modelData.frame.padding
            width: host.implicitWidth + 8 + 2 * frameInset
            height: root.height || host.implicitHeight
            WidgetSurface {
                kind: placement.modelData.frame.background
                x: placement.modelData.frame.margin
                y: placement.modelData.frame.margin
                width: parent.width - 2 * placement.modelData.frame.margin
                height: parent.height - 2 * placement.modelData.frame.margin
                radius: Metrics.radiusMedium
            }
            readonly property real renderedHeight: host.renderedHeight
            readonly property var inputRegion: host.inputRegion
            PluginHost {
                id: host
                x: 4 + placement.frameInset
                width: implicitWidth
                height: implicitHeight
                anchors.verticalCenter: parent.verticalCenter
                instanceId: placement.modelData.instanceId
                moduleId: placement.modelData.moduleId
                settings: placement.modelData.settings
                context: ({ slot: root.slot, outputId: root.outputId, compact: root.compact, preview: root.services.preview,
                    placementZone: placement.modelData.zone, placementSize: placement.modelData.size })
                services: root.services
                registry: root.services.plugins
                onActionRequested: function(action) { root.activated(action, instanceId) }
            }
        }
    }
}
