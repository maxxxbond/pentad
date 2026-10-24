import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"
import "../features/bar"
import '../features/media'
import '../features/system'
import '../features/notifications'
import '../features/sidebar'
import qs.components
import qs.theme

PanelWindow {
    id: window
    required property Services services
    readonly property string outputId: screen ? screen.name : ""
    property var brightness: null
    property string lastSurface: 'activity'
    readonly property var popup: lastSurface === 'left' ? leftSurface : lastSurface === 'right' ? rightSurface : surface
    readonly property alias leftPopup: leftSurface
    readonly property alias rightPopup: rightSurface
    readonly property alias activityPopup: surface
    // OutputHost builds this bar's menus ahead of time (the "speed" bar menu mode) once this long has
    // passed since the bar appeared; -1 means never, so a bar on its own builds menus on hover or open.
    property int menuPrebuildDelay: -1
    property bool menuPrebuildDue: false
    readonly property var menusPrepared: ({ right: rightSurface.rightPrepared, left: leftSurface.leftPrepared,
        activity: surface.activityPrepared })
    function prebuildMenu(side) {
        (side === 'left' ? leftSurface : side === 'right' ? rightSurface : surface).prebuild(side);
    }
    Timer {
        interval: Math.max(0, window.menuPrebuildDelay)
        running: window.menuPrebuildDelay >= 0 && !window.menuPrebuildDue
        onTriggered: window.menuPrebuildDue = true
    }
    Connections {
        target: window.services.popups
        function onChanged() {
            if (window.services.popups.outputId === window.outputId && window.services.popups.surface)
                window.lastSurface = window.services.popups.surface;
        }
    }
    readonly property alias barFace: bar
    readonly property var activityController: {
        var selectedId = services.popups.instanceFor('activity', outputId);
        if (!selectedId) {
            var placement = services.config.documents.layout.widgets.find(function(item) { return item.enabled && item.moduleId === 'pentad.activity' });
            selectedId = placement ? placement.instanceId : '';
        }
        var wrapper = services.plugins.controllers[selectedId];
        return wrapper ? wrapper.item : null;
    }
    readonly property var activityServices: activityController ? activityController.serviceFacade : services
    onOutputIdChanged: Qt.callLater(function() {
        if (window.outputId) window.brightness = window.services.brightnessFor(window.outputId);
    })
    function toggleSaver() {
        const power = window.services.power;
        const state = power.profileState;
        if (state.kind !== "ready") return;
        const balanced = state.value.profiles.indexOf("balanced") >= 0 ? "balanced" : state.value.profiles[0];
        power.setProfile(state.value.actual === "power-saver" ? balanced : "power-saver");
    }
    anchors { top: true; left: true; right: true }
    // Holds the island's karaoke overhang from the start: a mapped layer surface that grew kept its
    // 40 px input size on Hyprland, so nothing below the bar took the pointer. The mask decides input.
    implicitHeight: Math.max(bar.renderedHeight, Metrics.islandReach)
    margins.top: 0
    exclusiveZone: services.preview ? 0 : services.config.documents.layout.barHeight
    color: "transparent"
    WlrLayershell.namespace: "pentad-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    BarFace {
        id: bar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: services.config.documents.layout.barHeight
        services: window.services
        outputId: window.outputId
        brightness: window.brightness
        workspaceHeld: window.services.workspaceHeld && !window.services.navigation.active
        onSideRequested: function(side) { window.services.popups.toggle(side, window.outputId) }
        onSideHovered: function(side) { (side === 'left' ? leftSurface : rightSurface).prepareSide(side) }
        onActivityHovered: surface.prepareSide('activity')
        onActivityRequested: function(instanceId) { window.services.popups.toggle('activity', window.outputId, instanceId) }
        onActionRequested: function(action) {
            if (action === "dnd") window.services.notifications.setDnd(!window.services.notifications.state.dnd);
            else if (action === "screenshot") window.services.screenshot.open('edit', window.outputId);
            else if (action === "screenshot-copy") window.services.screenshot.open('copy', window.outputId);
            else if (action === "screenshot-settings") window.services.screenshot.openSettings();
            else if (action === "night") window.services.quickSettings.toggleNight();
            else if (action === "bluetooth") window.services.quickSettings.toggleBluetooth();
            else if (action === "airplane") window.services.quickSettings.toggleAirplane();
            else if (action === "saver") window.toggleSaver();
            else if (action === "privacy") window.services.notifications.privacy = !window.services.notifications.privacy;
            else if (action === "focus") {
                // Focus mode also silences notifications, matching the quiet-mode marker.
                const entering = !window.services.desktop.state.value.focus;
                window.services.desktop.command("focus");
                window.services.notifications.setDnd(entering);
            }
            else window.services.desktop.command(action);
        }
    }
    mask: Region {
        regions: [barRegion].concat(bar.inputRegions)
    }
    property Region barRegion: Region { width: window.width; height: window.services.config.documents.layout.barHeight }
    DragIngress {
        anchors.fill: bar
        services: window.services
        surfaceHost: surface
        leftHost: leftSurface
        outputId: window.outputId
        sidebarWidth: bar.centerLeft
        centerRight: bar.centerRight
        leftContentStart: bar.horizontalInset
        leftContentEnd: bar.leftContentRight
    }
    LevelOverlay {
        screen: window.screen
        services: window.services
        outputId: window.outputId
        brightness: window.brightness
        topInset: window.margins.top + window.services.config.documents.layout.barHeight + 12
    }
    SurfaceHost {
        id: leftSurface
        services: window.services
        barWindow: window
        outputId: window.outputId
        surfaceName: 'left'
        leftComponent: sidebarPanel
        surfaceComponent: sidebarPanel
    }
    SurfaceHost {
        id: rightSurface
        services: window.services
        barWindow: window
        outputId: window.outputId
        surfaceName: 'right'
        rightComponent: rightPanel
        surfaceComponent: rightPanel
    }
    SurfaceHost {
        id: surface
        services: window.services
        barWindow: window
        outputId: window.outputId
        surfaceName: 'activity'
        activityComponent: activityPanel
        surfaceComponent: activityPanel
    }
    NotificationPopupHost {
        services: window.services
        barWindow: window
        outputId: window.outputId
    }
    Component {
        id: activityPanel
        ActivityMenu {
            services: window.activityServices
            stashServices: window.services
            outputId: window.outputId
            readOnly: window.services.preview || window.services.safeMode
            onCloseRequested: window.services.popups.closeSurface('activity', window.outputId)
        }
    }
    Component { id: rightPanel; RightPanel {
        services: window.services
        outputId: window.outputId
        presented: rightSurface.visible
    } }
    Component { id: sidebarPanel; SidebarView { services: window.services; outputId: window.outputId } }
    Component.onDestruction: { services.popups.disposeOutput(outputId); services.releaseBrightness(outputId); }
    Component.onCompleted: brightness = services.brightnessFor(outputId)
}
