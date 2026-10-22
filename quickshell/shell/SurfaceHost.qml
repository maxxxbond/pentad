import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components

PanelWindow {
    id: popup
    required property var services
    required property var barWindow
    required property string outputId
    property string surfaceName: ''
    readonly property string visibilityKey: JSON.stringify([outputId, surfaceName])
    property Component surfaceComponent: null
    property Component leftComponent: null
    property Component rightComponent: null
    property Component activityComponent: null
    property bool leftPrepared: false
    property bool rightPrepared: false
    property bool activityPrepared: false
    readonly property alias leftContent: leftBody.item
    readonly property alias rightContent: rightBody.item
    readonly property alias leftContentStatus: leftBody.status
    readonly property alias rightContentStatus: rightBody.status
    function prepareSide(side) {
        if (side === 'left') leftPrepared = true;
        else if (side === 'right') rightPrepared = true;
    }
    property Component shownComponent: null
    readonly property string surface: services.popups.isOpen(surfaceName, outputId) ? surfaceName : ''
    property string shownSurface: ''
    property int focusGeneration: 0
    property real slideProgress: 0
    readonly property alias inputRegion: outlineRegion
    readonly property alias focusItem: keyOwner
    readonly property alias attachedSurface: attached
    readonly property alias activitySurface: outline
    readonly property var activityContent: body.item
    readonly property alias activityContentStatus: body.status
    readonly property bool pointerHovered: visible && surfaceHover.hovered
    readonly property bool dragOutActive: shownSurface === 'activity' && !!body.item?.dragOutActive
        || shownSurface === 'left' && !!leftBody.item?.dragOutActive
    readonly property bool dragHovered: visible && (backgroundDrop.containsDrag
        || (shownSurface === 'left' && !!leftBody.item?.dragHover?.mime)
        || (shownSurface === 'activity' && !!body.item?.dragHovered))
    Timer {
        interval: 150
        running: true
        onTriggered: {
            popup.prepareSide('left');
            popup.prepareSide('right');
            popup.activityPrepared = true;
        }
    }
    visible: false
    screen: barWindow.screen
    exclusiveZone: 0
    WlrLayershell.namespace: "pentad-surface"
    WlrLayershell.layer: sideSurface ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: 'transparent'
    readonly property bool sideSurface: shownSurface === 'left' || shownSurface === 'right'
    readonly property int panelWidth: 390
    readonly property int shoulder: Metrics.attachedShoulder
    property int sideSurfaceHeightOverride: 0
    // Transparent room for the overlay shadow on free edges only: never toward the bar seam or a
    // screen edge the surface is flush with.
    readonly property int shadowRoom: Metrics.overlayShadowRoom
    readonly property int bottomRoom: !sideSurface || sideSurfaceHeightOverride > 0 ? shadowRoom : 0
    implicitWidth: sideSurface ? panelWidth + shoulder + shadowRoom : 508 + 2 * shadowRoom
    implicitHeight: sideSurface
        ? Math.max(0, sideSurfaceHeightOverride > 0
            ? Math.min(sideSurfaceHeightOverride, barWindow.screen ? barWindow.screen.height : 800) + bottomRoom
            : 0)
        : Math.min(Math.max(0, (barWindow.screen ? barWindow.screen.height : 800) - services.config.documents.layout.barHeight - 48),
            Math.max(128, body.implicitHeight + 2 * Metrics.activityPadding)) + bottomRoom
    anchors.top: true
    anchors.bottom: sideSurface && sideSurfaceHeightOverride <= 0
    anchors.left: shownSurface === 'left'
    anchors.right: shownSurface === 'right'
    margins.top: 0
    exclusionMode: ExclusionMode.Normal
    onVisibleChanged: {
        if (typeof services.popups.hostVisibility === 'function') services.popups.hostVisibility(visibilityKey, visible);
        if (!visible) {
            ++focusGeneration;
            slideIn.stop();
            slideOut.stop();
            if (surface && shownSurface === surface) services.popups.closeSurface(surfaceName, outputId);
            shownSurface = '';
            shownComponent = null;
        }
    }
    Connections {
        target: popup.services.popups
        function onCapturePreparing() {
            slideIn.stop();
            slideOut.stop();
            popup.visible = false;
        }
        function onChanged() {
            if (popup.surface) {
                const continuing = popup.visible && popup.shownSurface === popup.surface;
                if (continuing && !slideOut.running) return;
                slideIn.stop();
                slideOut.stop();
                popup.shownSurface = popup.surface;
                popup.prepareSide(popup.surface);
                if (popup.surface === 'activity') popup.activityPrepared = true;
                popup.shownComponent = popup.surfaceComponent;
                if (!continuing) popup.slideProgress = 0;
                popup.visible = !!popup.shownComponent;
                if (popup.visible) {
                    slideIn.restart();
                    const generation = ++popup.focusGeneration;
                    Qt.callLater(function() {
                        if (generation === popup.focusGeneration && popup.visible
                                && popup.surface && popup.shownSurface === popup.surface)
                            keyOwner.forceActiveFocus();
                    });
                }
            } else if (popup.visible) {
                ++popup.focusGeneration;
                slideIn.stop();
                if (!slideOut.running) slideOut.restart();
            } else {
                popup.visible = false;
                popup.shownSurface = '';
            }
        }
    }
    NumberAnimation { id: slideIn; target: popup; property: 'slideProgress'; to: 1; duration: Motion.medium; easing.type: Easing.OutCubic }
    NumberAnimation {
        id: slideOut
        target: popup
        property: 'slideProgress'
        to: 0
        duration: Motion.medium
        easing.type: Easing.InCubic
        onFinished: popup.visible = false
    }
    Item {
        id: keyOwner
        readonly property point pointerGlobalOrigin: Qt.point(
            (popup.screen ? popup.screen.x : 0) + (popup.anchors.left ? popup.margins.left
                : popup.anchors.right ? popup.screen.width - popup.width - popup.margins.right
                : (popup.screen.width - popup.width) / 2),
            (popup.screen ? popup.screen.y : 0) + Math.max(0, popup.barWindow.exclusiveZone) + popup.margins.top)
        anchors.fill: parent
        clip: true
        focus: true
        Keys.onEscapePressed: popup.services.popups.dismissTop()
        HoverHandler { id: surfaceHover }
        DropArea {
            id: backgroundDrop
            anchors.fill: parent
            onEntered: drag => { drag.accepted = popup.surface !== ''; }
            onDropped: drop => { drop.accepted = false; }
        }
        AttachedSideSurface {
            id: attached
            x: popup.shownSurface === 'left' ? -width * (1 - popup.slideProgress)
                : popup.shadowRoom + width * (1 - popup.slideProgress)
            width: Math.max(0, parent.width - popup.shadowRoom)
            height: Math.max(0, parent.height - popup.bottomRoom)
            side: popup.shownSurface
            contentComponent: popup.shownComponent
            loadContent: popup.shownSurface === 'left' ? !popup.leftComponent : !popup.rightComponent
            visible: popup.sideSurface
            enabled: popup.surface !== ''
            Loader {
                id: leftBody
                width: popup.panelWidth
                height: popup.sideSurface ? parent.height
                    : Math.max(0, (popup.screen ? popup.screen.height : 800)
                        - popup.services.config.documents.layout.barHeight)
                sourceComponent: popup.leftComponent
                active: popup.leftPrepared && !!sourceComponent
                asynchronous: !(popup.visible && popup.shownSurface === 'left')
                visible: popup.shownSurface === 'left'
            }
            Loader {
                id: rightBody
                width: popup.panelWidth
                height: popup.sideSurface ? parent.height
                    : Math.max(0, (popup.screen ? popup.screen.height : 800)
                        - popup.services.config.documents.layout.barHeight)
                sourceComponent: popup.rightComponent
                active: popup.rightPrepared
                asynchronous: false
                visible: popup.shownSurface === 'right'
            }
        }
        ContinuousSurface {
            id: outline
            x: popup.shadowRoom
            y: -height * (1 - popup.slideProgress)
            width: Math.max(0, parent.width - 2 * popup.shadowRoom)
            height: Math.max(0, parent.height - popup.bottomRoom)
            castsShadow: true
            extent: Metrics.attachedRadius
            concaveShoulder: Metrics.attachedShoulder
            joinOffset: 0
            fill: Theme.tokens.surface
            visible: !popup.sideSurface
            enabled: popup.surface !== ''
            PentadScrollView {
                id: scroller
                x: outline.cornerGeometry.shoulder + Metrics.activityPadding
                y: Metrics.activityPadding
                width: parent.width - 2 * x
                height: Math.max(0, parent.height - 2 * Metrics.activityPadding)
                contentWidth: availableWidth
                Loader {
                    id: body
                    width: scroller.availableWidth
                    sourceComponent: popup.activityComponent || popup.shownComponent
                    active: popup.activityComponent ? popup.activityPrepared : popup.visible && !popup.sideSurface
                    asynchronous: !(popup.visible && popup.shownSurface === 'activity')
                    visible: popup.visible && popup.shownSurface === 'activity'
                    height: item ? item.implicitHeight : 0
                }
            }
        }
    }
    mask: SurfaceRegion { id: outlineRegion; surface: popup.sideSurface ? attached : outline }
    Component.onCompleted: services.popups.registerHost(popup)
    Component.onDestruction: {
        services.popups.unregisterHost(popup);
        if (typeof services.popups.hostVisibility === 'function') services.popups.hostVisibility(visibilityKey, false);
        services.popups.closeSurface(surfaceName, outputId);
    }
}
