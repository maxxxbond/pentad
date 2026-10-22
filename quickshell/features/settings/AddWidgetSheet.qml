pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/settings-widget-flow.mjs" as WidgetFlow
import "../../logic/pentads.mjs" as Pentads

// "Add a widget": a sheet over the settings with one card per installed widget. Choosing a
// card adds an instance with its defaults in the first section it supports and opens that
// widget's own page, where placement and options live. No wizard, no review step.
FocusScope {
    id: root
    required property var services
    readonly property var layoutDocument: services.config.documents.layout || ({})
    readonly property var placements: Array.isArray(layoutDocument.widgets) ? layoutDocument.widgets : []
    readonly property var registry: {
        services.plugins.revision;
        return WidgetFlow.registryFromCatalog(services.plugins.catalog).slice().sort(function(a, b) {
            return String(a.name || a.id).localeCompare(String(b.name || b.id));
        });
    }
    readonly property var syntheticItem: ({ key: "widgets", kind: "select", control: "options", document: "layout", path: "widgets" })
    property string pendingRequest: ""
    property string pendingInstance: ""
    readonly property bool busy: pendingRequest !== ""
    readonly property real padding: 20
    readonly property real gap: 8
    readonly property int columns: sheet.width >= 640 ? 3 : sheet.width >= 420 ? 2 : 1
    readonly property real cardHeight: 128
    readonly property alias repeater: cards
    signal cancelled()

    function t(uk, en) { return services.text(uk, en); }
    function dismiss() { cancelled(); services.settings.flow = ""; }
    function manifestOf(id) {
        const entry = services.plugins.catalog ? services.plugins.catalog[id] : null;
        return entry && entry.manifest ? entry.manifest : null;
    }
    function zonesFor(entry) {
        const manifest = manifestOf(entry.id);
        if (manifest && Array.isArray(manifest.pentads) && manifest.pentads.length) return manifest.pentads;
        return Pentads.zonesForSlots(entry.allowedSlots);
    }
    function zoneLabel(zones) {
        return zones.map(function(id) {
            const zone = Pentads.zoneOf(id);
            return zone ? root.t(zone.labelUk, zone.labelEn) : id;
        }).join(" · ");
    }
    function countFor(entry) {
        return placements.filter(function(placement) { return placement.moduleId === entry.id; }).length;
    }
    // The slot of the first supported section, so the widget shows up where its manifest says first.
    function firstSlot(entry) {
        const zones = zonesFor(entry);
        const owned = Pentads.slotsFor(zones.slice(0, 1));
        return owned.find(function(slot) { return entry.allowedSlots.indexOf(slot) >= 0; }) || entry.allowedSlots[0];
    }
    function add(entry) {
        if (busy) return false;
        const placement = WidgetFlow.buildPlacement({ moduleId: entry.id, slot: firstSlot(entry),
            settings: Object.assign({}, entry.defaults),
            existing: placements.map(function(placement) { return placement.instanceId; }) });
        const requestId = services.settings.commit(syntheticItem, placements.concat([placement]));
        if (requestId === "") return false;
        pendingRequest = requestId;
        pendingInstance = placement.instanceId;
        return true;
    }

    Connections {
        target: root.services.config
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingRequest) return;
            root.pendingRequest = "";
            const instance = root.pendingInstance;
            root.pendingInstance = "";
            if (result && result.ok) {
                // Open the page first: clearing the flow unloads this sheet at once.
                root.services.settings.openWidget(instance);
                root.services.settings.flow = "";
            }
        }
    }

    focus: true
    activeFocusOnTab: false
    // Focus stays on the sheet so Esc works; a focus ring appears only once Tab reaches a card.
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: function(event) { root.dismiss(); event.accepted = true; }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.alpha(Theme.tokens.surface, 0.72)
        // Tap handlers see every tap passively, so a tap on a card also lands here:
        // only a tap outside the sheet dismisses it.
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
        width: Math.max(1, Math.min(760, root.width - 32))
        height: Math.max(1, Math.min(560, root.height - 32))
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusPopover
        Accessible.role: Accessible.Dialog
        Accessible.name: root.t("Додати віджет", "Add a widget")

        Item {
            id: header
            x: root.padding
            y: 0
            width: parent.width - 2 * root.padding
            height: 64
            PentadText {
                anchors.left: parent.left
                anchors.right: closeButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("Додати віджет", "Add a widget")
                textFormat: Text.PlainText
                role: "title"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                Accessible.role: Accessible.Heading
            }
            PentadButton {
                id: closeButton
                objectName: "add-widget-close"
                anchors.right: parent.right
                anchors.rightMargin: -4
                anchors.verticalCenter: parent.verticalCenter
                iconSource: Qt.resolvedUrl("../../assets/icons/material/close-symbolic.svg")
                iconSize: Metrics.panelIcon
                controlHeight: Metrics.controlSmall
                implicitWidth: Metrics.controlSmall
                accessibleName: root.t("Закрити", "Close")
                background: Rectangle {
                    radius: width / 2
                    color: closeButton.down ? Theme.tokens.surfaceOverlay : closeButton.hovered ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
                    border.width: closeButton.visualFocus ? 2 : 0
                    border.color: Theme.tokens.accent
                }
                onClicked: root.dismiss()
            }
        }

        PentadScrollView {
            id: scroll
            x: 0
            y: header.height
            width: parent.width
            height: Math.max(0, parent.height - header.height)
            contentWidth: availableWidth
            clip: true
            Item {
                id: grid
                x: root.padding
                width: Math.max(0, scroll.availableWidth - 2 * root.padding)
                readonly property real cardWidth: Math.max(1, Math.floor((width - root.gap * (root.columns - 1)) / root.columns))
                readonly property int rowCount: Math.ceil(Math.max(1, root.registry.length) / root.columns)
                implicitHeight: rowCount * root.cardHeight + (rowCount - 1) * root.gap + root.padding
                Repeater {
                    id: cards
                    model: root.registry
                    delegate: Control {
                        id: card
                        required property int index
                        required property var modelData
                        readonly property var zones: root.zonesFor(modelData)
                        readonly property int added: root.countFor(modelData)
                        readonly property string label: String(modelData.name || modelData.id)
                        objectName: "widgetPick_" + modelData.id
                        x: (index % root.columns) * (grid.cardWidth + root.gap)
                        y: Math.floor(index / root.columns) * (root.cardHeight + root.gap)
                        width: grid.cardWidth
                        height: root.cardHeight
                        activeFocusOnTab: true
                        enabled: !root.busy
                        Accessible.role: Accessible.Button
                        Accessible.name: root.t("Додати ", "Add ") + label
                        Accessible.onPressAction: root.add(modelData)
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.add(card.modelData);
                                event.accepted = true;
                            }
                        }
                        // Cards sit one tonal step below the sheet; focus is the only edge.
                        ContinuousSurface {
                            anchors.fill: parent
                            fill: cardHover.hovered || cardTap.pressed ? Theme.tokens.surfaceOverlay : Theme.tokens.surface
                            edge: card.visualFocus ? Theme.tokens.accent : "transparent"
                            extent: Metrics.radiusCard
                            opacity: root.busy ? 0.6 : 1
                            Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                        }
                        SettingsPlacementArt {
                            id: art
                            x: 12
                            y: 12
                            zones: card.zones
                            accessibleName: card.label
                        }
                        Rectangle {
                            id: addedBadge
                            objectName: "widgetPickCount"
                            visible: card.added > 0
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            y: 12
                            width: badgeText.implicitWidth + 16
                            height: 20
                            radius: Metrics.radiusTag
                            color: Theme.tokens.surfaceOverlay
                            PentadText {
                                id: badgeText
                                anchors.centerIn: parent
                                text: card.added === 1 ? root.t("Додано", "Added") : root.t("Додано ×" + card.added, "Added ×" + card.added)
                                textFormat: Text.PlainText
                                role: "caption"
                                font.weight: Font.Medium
                                color: Theme.tokens.text
                                wrapMode: Text.NoWrap
                            }
                        }
                        Column {
                            x: 12
                            anchors.top: art.bottom
                            anchors.topMargin: 8
                            width: parent.width - 24
                            PentadText {
                                objectName: "widgetPickName"
                                width: parent.width
                                text: card.label
                                textFormat: Text.PlainText
                                solid: true
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                            PentadText {
                                width: parent.width
                                visible: card.label !== card.modelData.id
                                text: card.modelData.id
                                textFormat: Text.PlainText
                                solid: true
                                role: "caption"
                                color: Theme.tokens.textMuted
                                elide: Text.ElideMiddle
                                wrapMode: Text.NoWrap
                            }
                            PentadText {
                                width: parent.width
                                text: root.zoneLabel(card.zones)
                                textFormat: Text.PlainText
                                solid: true
                                role: "caption"
                                font.weight: Font.Medium
                                color: Theme.tokens.textMuted
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                        }
                        HoverHandler { id: cardHover; enabled: !root.busy; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: cardTap
                            enabled: !root.busy
                            onTapped: { card.forceActiveFocus(); root.add(card.modelData); }
                        }
                    }
                }
                PentadText {
                    visible: root.registry.length === 0
                    anchors.centerIn: parent
                    text: root.t("Немає встановлених віджетів.", "No widgets are installed.")
                    textFormat: Text.PlainText
                    color: Theme.tokens.textMuted
                }
            }
        }
    }
}
