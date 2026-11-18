pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import qs.features.notifications
import qs.plugins
import '../../logic/placement.mjs' as Placement

Item {
    id: root
    required property var services
    required property string outputId
    property bool presented: false
    property string detailsSection: ""
    property string renderedSection: ""
    property real detailProgress: 0
    property var brightness: null
    implicitHeight: parent ? parent.height : 600
    property alias quickSettingsGrid: quickGrid
    property alias quickSettingsDetails: quickDetails
    // The level sliders live in the quick grid and can be hidden there, so these may be null.
    readonly property var brightnessControl: quickGrid.levelControls["brightness"] || null
    readonly property var audioControls: quickGrid.levelControls["audio-output"] || null
    readonly property var microphoneControls: quickGrid.levelControls["audio-input"] || null
    property alias sessionHeader: heading
    readonly property bool organizerCollapsed: services.organizer.document.collapsed
    readonly property real organizerHeight: organizerCollapsed ? 40 : Math.min(328, Math.max(280, height * 0.40))
    readonly property var rightPlacements: services.plugins
        ? Placement.placementsForSlot(services.config.documents.layout.widgets, services.plugins.catalog, "sidebar-right") : []
    readonly property int headerGap: 12
    // The details view needs room for its list and the password field even when the grid is short.
    readonly property real detailsMinHeight: 384
    readonly property real topPreferredHeight: controls.implicitHeight
        + Math.max(0, detailsMinHeight - controls.implicitHeight) * detailProgress
    readonly property real topAllocation: Math.max(0, height - 24 - heading.height - headerGap - organizerHeight - 8)
    // Editing the grid borrows the room kept for notifications, so the add tray stays in reach.
    readonly property real topHeight: Math.min(topPreferredHeight, Math.max(0, topAllocation
        - (quickGrid.editing ? 0 : Math.min(128, topAllocation * 0.32))))
    readonly property real centerHeight: Math.max(0, height - 24 - heading.height - headerGap - topHeight - 8 - organizerHeight - 8)
    objectName: "right-control-center"

    function syncBrightness() { brightness = outputId ? services.brightnessFor(outputId) : null; }
    function openDetails(section) {
        quickGrid.finishEdit();
        renderedSection = section;
        detailsSection = section;
        topScroll.contentY = 0;
        detailProgress = 1;
    }
    function closeDetails() {
        if (detailsSection === "session" && services.session) services.session.cancel();
        detailsSection = "";
        detailProgress = 0;
        if (Theme.tokens.reducedMotion) renderedSection = "";
    }
    onOutputIdChanged: Qt.callLater(syncBrightness)
    Component.onCompleted: syncBrightness()
    onPresentedChanged: if (!presented) {
        quickGrid.finishEdit();
        if (services.session) services.session.cancel();
    }
    Component.onDestruction: if (services.session) services.session.cancel()
    Behavior on detailProgress {
        enabled: !Theme.tokens.reducedMotion
        NumberAnimation {
            duration: Motion.short
            easing.type: Easing.OutCubic
            onStopped: if (root.detailsSection === "" && root.detailProgress === 0) root.renderedSection = ""
        }
    }

    Connections {
        target: root.services.quickSettings
        ignoreUnknownSignals: true
        function onTailscaleFallbackRequested() { quickGrid.openTailscale(); }
    }

    SessionHeader {
        id: heading
        x: 12; y: 8
        width: Math.max(0, root.width - 24)
        height: implicitHeight
        services: root.services
        editing: quickGrid.editing
        onDetailsRequested: function(section) { root.openDetails(section); }
        onEditRequested: {
            if (quickGrid.editing) { quickGrid.finishEdit(); return; }
            if (root.detailsSection !== "") root.closeDetails();
            topScroll.contentY = 0;
            quickGrid.beginEdit();
        }
    }

    Flickable {
        id: topScroll
        objectName: "control-center-controls-scroll"
        x: 12
        y: heading.y + heading.height + root.headerGap
        width: Math.max(0, root.width - 24)
        height: root.topHeight
        clip: true
        contentWidth: width
        contentHeight: stage.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: root.detailsSection === ""
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Item {
            id: stage
            width: topScroll.width
            height: root.topPreferredHeight
            Column {
                id: controls
                width: stage.width
                spacing: 8
                enabled: root.detailsSection === ""
                visible: root.detailProgress < 1
                opacity: 1 - root.detailProgress
                scale: 1 - 0.07 * root.detailProgress
                transformOrigin: Item.Top
                layer.enabled: !Theme.tokens.reducedMotion && root.detailProgress > 0
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 8
                    blur: root.detailProgress * 0.5
                }
                QuickSettingsGrid {
                    id: quickGrid
                    objectName: "control-center-quick-grid"
                    width: controls.width
                    services: root.services
                    brightness: root.brightness
                    onDetailsRequested: function(section) { root.openDetails(section); }
                }
                Column {
                    id: rightWidgets
                    width: controls.width
                    spacing: 8
                    visible: root.rightPlacements.length > 0
                    Repeater {
                        model: root.rightPlacements
                        delegate: Item {
                            id: framed
                            required property var modelData
                            readonly property real frameInset: modelData.frame.margin + modelData.frame.padding
                            width: rightWidgets.width
                            height: rightHost.implicitHeight + 2 * frameInset
                            WidgetSurface {
                                kind: framed.modelData.frame.background
                                x: framed.modelData.frame.margin
                                y: framed.modelData.frame.margin
                                width: parent.width - 2 * framed.modelData.frame.margin
                                height: parent.height - 2 * framed.modelData.frame.margin
                                radius: Metrics.radiusCard
                            }
                            PluginHost {
                                id: rightHost
                                x: framed.frameInset
                                y: framed.frameInset
                                width: parent.width - 2 * framed.frameInset
                                height: implicitHeight
                                instanceId: framed.modelData.instanceId
                                moduleId: framed.modelData.moduleId
                                settings: framed.modelData.settings
                                registry: root.services.plugins
                                services: root.services
                                context: ({slot: "sidebar-right", outputId: root.outputId,
                                    compact: false, preview: root.services.preview,
                                    presented: root.presented && root.detailsSection === "",
                                    placementZone: framed.modelData.zone, placementSize: framed.modelData.size})
                            }
                        }
                    }
                }
            }
            ContinuousSurface {
                id: detailSurface
                width: stage.width
                height: Math.max(0, 72 + (topScroll.height - 72) * root.detailProgress)
                extent: 20
                fill: Theme.tokens.surfaceRaised
                clipContent: true
                visible: root.renderedSection !== "" && root.detailProgress > 0
                enabled: root.detailsSection !== ""
                opacity: root.detailProgress
                scale: 0.94 + 0.06 * root.detailProgress
                transformOrigin: Item.Top
                QuickSettingsDetails {
                    id: quickDetails
                    anchors.fill: parent
                    anchors.margins: 12
                    services: root.services
                    section: root.renderedSection
                    onBackRequested: root.closeDetails()
                    onTrayscaleRequested: quickGrid.openTailscale()
                }
            }
        }
    }

    NotificationCenter {
        id: notificationCenter
        objectName: "control-center-notifications"
        x: 12
        y: topScroll.y + topScroll.height + 8
        width: Math.max(0, root.width - 24)
        height: root.centerHeight
        services: root.services
        outputId: root.outputId
        presented: root.presented
    }

    PanelOrganizer {
        id: organizer
        x: 12
        y: root.height - height - 8
        width: Math.max(0, root.width - 24)
        height: root.organizerHeight
        services: root.services
        organizer: root.services.organizer
    }
}
