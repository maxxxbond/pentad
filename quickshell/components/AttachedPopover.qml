pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Shapes
import QtQuick.Window
import qs.theme
import "../logic/attached-popover.mjs" as PopoverGeometry
import "../logic/continuous-corners.mjs" as CornerGeometry

Item {
    id: root
    property Item anchorItem: null
    property Item barItem: null
    readonly property Item attachedBar: {
        let item = barItem || anchorItem;
        while (item) {
            if (item.objectName === "pentad-bar-face") return item;
            item = item.parent;
        }
        return null;
    }
    readonly property Item decoratedBar: placement === "right" ? null : attachedBar
    property color fill: Theme.tokens.surface
    property var manager: null
    property Item contentItem: defaultContent
    readonly property var ownerWindow: anchorItem ? anchorItem.QsWindow.window : null
    property bool grabFocus: true
    property bool focusManagedExternally: false
    property bool pointerDismissEnabled: true
    property bool pointerIntentDebug: false
    property string placement: "below"
    readonly property bool opened: popup.visible
    readonly property alias surface: surfaceItem
    readonly property alias window: popup
    readonly property alias pointerIntent: pointerIntent
    readonly property real availableContentHeight: contentHost.height
    default property alias content: defaultContent.data
    property bool contentWidthFollowsPopover: false
    property bool contentHeightFollowsPopover: false
    property Item focusBeforeOpen: null
    property bool wasOpened: false
    property bool focusRequestedForOpen: false
    property int focusGeneration: 0
    property string closeReason: ""

    signal closed()
    signal contourChanged()

    MenuPointerIntent {
        id: pointerIntent
        anchorItem: root.anchorItem
        surfaceItem: pointerField
        useAnchorCorridor: !popup.sidePlacement
        debugEnabled: root.pointerIntentDebug
        coordinateItem: parentIntent ? parentIntent.coordinateItem
            : root.attachedBar && root.attachedBar.Window.window
                ? root.attachedBar.Window.window.contentItem : null
        coordinateOrigin: parentIntent ? parentIntent.coordinateOrigin
            : Qt.point(popup.sourceScreen ? popup.sourceScreen.x : 0,
                popup.sourceScreen ? popup.sourceScreen.y : 0)
        topReservation: parentIntent ? parentIntent.topReservation : popup.topReservation
        active: root.opened
        pointerDismissEnabled: root.pointerDismissEnabled
        inputRegion: popup.mask
        inputRegionOrigin: Qt.point(popup.placementRect.x
                - (pointerIntent.coordinateItem ? pointerIntent.coordinateOrigin.x : 0),
            popup.placementRect.y - (pointerIntent.coordinateItem ? pointerIntent.coordinateOrigin.y : 0))
        onDismissRequested: root.close("pointer-controller")
    }

    MenuPointerIntentOverlay {
        intent: pointerIntent
        targetScreen: popup.sourceScreen
        debugEnabled: root.pointerIntentDebug
        debugActive: root.opened
    }

    HyprlandFocusGrab {
        active: root.opened && root.grabFocus && !root.focusManagedExternally
            && (!root.manager || !root.manager.hosts || !root.manager.hosts.length)
        windows: [popup, root.ownerWindow].filter(window => !!window)
        onCleared: if (root.opened) root.close("outside-click")
    }

    readonly property real contentWidth: {
        let result = 0;
        if (contentItem !== defaultContent)
            return Math.max(contentItem.implicitWidth, contentWidthFollowsPopover ? 0 : contentItem.width);
        for (const child of defaultContent.children)
            if (child.visible) result = Math.max(result, child.x + Math.max(child.width, child.implicitWidth));
        return result;
    }
    readonly property real contentHeight: {
        let result = 0;
        if (contentItem !== defaultContent)
            return contentItem.implicitHeight > 0 ? contentItem.implicitHeight
                : contentHeightFollowsPopover ? 0 : contentItem.height;
        for (const child of defaultContent.children)
            if (child.visible) result = Math.max(result, child.y + Math.max(child.height, child.implicitHeight));
        return result;
    }

    function open() {
        if (!anchorItem || !anchorItem.Window.window || popup.visible) return;
        closeReason = "";
        const generation = ++focusGeneration;
        focusRequestedForOpen = grabFocus;
        focusBeforeOpen = grabFocus ? anchorItem.Window.window.activeFocusItem || anchorItem : null;
        wasOpened = true;
        if (manager && typeof manager.registerChild === "function") manager.registerChild(root);
        popup.visible = true;
        if (focusRequestedForOpen) Qt.callLater(function() {
            if (generation === root.focusGeneration && root.opened && root.grabFocus)
                contentHost.forceActiveFocus(Qt.PopupFocusReason);
        });
    }

    function finishClose() {
        if (!wasOpened) return;
        pointerIntent.trace("popup-closed", root.closeReason || "native-popup-dismissal");
        wasOpened = false;
        const generation = ++focusGeneration;
        const restore = focusRequestedForOpen;
        focusRequestedForOpen = false;
        if (manager && typeof manager.unregisterChild === "function") manager.unregisterChild(root);
        const target = focusBeforeOpen;
        focusBeforeOpen = null;
        if (restore && target && (!manager || !manager.childSurface)) Qt.callLater(function() {
            if (generation === root.focusGeneration && !root.opened
                && (!root.manager || !root.manager.childSurface)
                && target.Window && target.Window.window)
                target.forceActiveFocus(Qt.PopupFocusReason);
        });
        closed();
    }

    function close(reason) {
        root.closeReason = reason || "api-close";
        if (popup.visible) popup.visible = false;
    }

    function toggle() {
        if (opened) close();
        else open();
    }

    function requestWindowFrame() {
        if (!popup.visible) return;
        const window = popup.contentItem.Window.window;
        if (window) window.update();
    }

    function requestResizeFrames() {
        resizeRetryCount = 0;
        if (!popup.visible) return;
        resizeFrameRetry.restart();
        requestWindowFrame();
    }

    property int resizeRetryCount: 0

    function layoutContent() {
        if (!contentItem || contentItem === defaultContent) return;
        contentItem.parent = contentHost;
        contentItem.x = 0;
        contentItem.y = 0;
        if (contentWidthFollowsPopover) contentItem.width = contentHost.width;
        else if (decoratedBar) contentItem.width = Math.min(Math.max(contentItem.width, contentItem.implicitWidth), contentHost.width);
        else contentItem.width = Math.max(contentItem.width, contentItem.implicitWidth);
        if (contentHeightFollowsPopover) contentItem.height = contentHost.height;
    }

    onContentItemChanged: {
        if (!contentItem) { contentItem = defaultContent; return; }
        contentWidthFollowsPopover = contentItem !== defaultContent && contentItem.width <= 0;
        contentHeightFollowsPopover = contentItem !== defaultContent
            && contentItem.height <= 0 && contentItem.implicitHeight <= 0;
        defaultContent.visible = contentItem === defaultContent;
        Qt.callLater(layoutContent);
    }

    onAnchorItemChanged: if (!anchorItem) close()
    Component.onDestruction: if (manager && typeof manager.unregisterChild === "function") manager.unregisterChild(root)

    width: 0
    height: 0

    PanelWindow {
        id: popup
        visible: false
        color: "transparent"
        screen: root.ownerWindow ? root.ownerWindow.screen : null
        anchors { top: true; left: true }
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "pentad-attached-popover"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.grabFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        readonly property var sourceScreen: screen
        readonly property real topReservation: {
            if (pointerIntent.parentIntent) return pointerIntent.parentIntent.topReservation;
            const barWindow = root.attachedBar ? root.attachedBar.QsWindow.window
                : root.ownerWindow && root.ownerWindow.barWindow ? root.ownerWindow.barWindow : null;
            return barWindow ? Math.max(0, barWindow.exclusiveZone) : 0;
        }
        readonly property real availableBarWidth: Math.max(1, sourceScreen ? sourceScreen.width : 1920)
        readonly property real barContentWidth: !root.attachedBar ? 0
            : root.contentItem !== defaultContent && root.contentItem.implicitWidth > 0
                ? root.contentItem.implicitWidth : root.contentWidth
        readonly property real barContentHeight: root.contentHeight
        readonly property bool sidePlacement: root.placement === "right"
        readonly property Item barAttachment: root.decoratedBar
        // The surface keeps its size and place; the window adds shadow room on its free edges.
        // Only side menus float free at the top, the rest meet the bar or their trigger there.
        readonly property real shadowRoom: Metrics.overlayShadowRoom
        readonly property real topRoom: sidePlacement ? shadowRoom : 0
        readonly property real surfaceWidth: Math.max(0, width - 2 * shadowRoom)
        readonly property real surfaceHeight: Math.max(0, height - topRoom - shadowRoom)
        readonly property real surfaceImplicitWidth: barAttachment
            ? Math.min(availableBarWidth, barContentWidth + 2 * (Metrics.attachedShoulder + 16))
            : Math.min(availableBarWidth, Math.max(100, root.contentWidth + 24))
        implicitWidth: surfaceImplicitWidth + 2 * shadowRoom
        readonly property real preferredHeight: sidePlacement
            ? Math.max(48, barContentHeight + 24)
            : barAttachment
            ? Math.max(Metrics.attachedShoulder + Metrics.attachedRadius, barContentHeight + 32)
            : Math.max(56, root.contentHeight + 48)
        readonly property real surfaceImplicitHeight: Math.min(preferredHeight, sourceScreen
            ? sidePlacement ? sourceScreen.height : Math.max(1, sourceScreen.y + sourceScreen.height - seamY)
            : 1080)
        implicitHeight: surfaceImplicitHeight + topRoom + shadowRoom
        onImplicitWidthChanged: Qt.callLater(root.requestResizeFrames)
        onImplicitHeightChanged: Qt.callLater(root.requestResizeFrames)
        readonly property rect anchorRect: {
            if (!popup.visible || !root.anchorItem || !root.anchorItem.Window.window) return Qt.rect(0, 0, 1, 1);
            const window = root.anchorItem.Window.window;
            let item = root.anchorItem;
            while (item) { item.x; item.y; item.width; item.height; item = item.parent; }
            const transform = root.ownerWindow ? root.ownerWindow.windowTransform : window.x + window.y;
            const mapped = pointerIntent.globalPoint(root.anchorItem, { x: 0, y: 0 });
            const offset = pointerIntent.coordinateItem ? pointerIntent.coordinateOrigin : { x: 0, y: 0 };
            const point = { x: mapped.x + offset.x, y: mapped.y + offset.y };
            return Qt.rect(point.x, point.y, root.anchorItem.width, root.anchorItem.height);
        }
        readonly property real seamY: {
            if (!popup.visible) return 0;
            const edge = root.decoratedBar || root.barItem || root.anchorItem;
            if (!edge) return 0;
            let item = edge;
            while (item) { item.x; item.y; item.width; item.height; item = item.parent; }
            const transform = root.ownerWindow ? root.ownerWindow.windowTransform : null;
            return pointerIntent.globalPoint(edge, { x: 0, y: edge.height }).y
                + (pointerIntent.coordinateItem ? pointerIntent.coordinateOrigin.y : 0);
        }
        readonly property var placementRect: PopoverGeometry.popoverPlacement(anchorRect,
            { x: sourceScreen ? sourceScreen.x : 0, y: sourceScreen ? sourceScreen.y : 0,
                width: availableBarWidth, height: sourceScreen ? sourceScreen.height : 1080 },
            surfaceImplicitWidth, surfaceImplicitHeight, root.placement, seamY)
        margins.left: placementRect.x - shadowRoom - (sourceScreen ? sourceScreen.x : 0)
        margins.top: placementRect.y - topRoom - (sourceScreen ? sourceScreen.y : 0) - topReservation
        mask: SurfaceRegion { surface: surfaceItem; active: popup.visible && surfaceItem.visible }

        readonly property real triggerCenterX: {
            if (!root.anchorItem || !root.anchorItem.Window.window) return surfaceWidth / 2;
            const placementTransform = popup.windowTransform;
            const sourceTransform = root.anchorItem.Window.window.windowTransform;
            return anchorRect.x + anchorRect.width / 2 - placementRect.x;
        }
        readonly property var geometry: {
            if (sidePlacement) {
                const side = CornerGeometry.surfaceGeometry(surfaceWidth, surfaceHeight, Metrics.radiusLarge);
                return { path: side.path, contentLeft: 0, contentRight: surfaceWidth, bodyTop: 0, radius: side.radius };
            }
            if (!root.attachedBar)
                return PopoverGeometry.attachedPopoverGeometry(
                    surfaceWidth, surfaceHeight, triggerCenterX, root.anchorItem ? Math.max(32, Math.min(64, root.anchorItem.width)) : 40);
            const contour = CornerGeometry.surfaceGeometry(
                surfaceWidth, surfaceHeight, Metrics.attachedRadius, Metrics.attachedShoulder);
            return { path: contour.path, contentLeft: contour.shoulder,
                contentRight: surfaceWidth - contour.shoulder, bodyTop: 0, radius: contour.radius };
        }

        Item {
            id: surfaceItem
            x: popup.shadowRoom
            y: popup.topRoom
            width: popup.surfaceWidth
            height: popup.surfaceHeight
            objectName: "attached-popover-surface"
            readonly property point pointerGlobalOrigin: Qt.point(popup.placementRect.x, popup.placementRect.y)
            containmentMask: surfaceShape
            signal contourChanged()
            Shape {
                id: surfaceShape
                anchors.fill: parent
                containsMode: Shape.FillContains
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.effect: OverlayShadowEffect {}
                ShapePath {
                    fillColor: root.fill
                    strokeColor: "transparent"
                    PathSvg { path: popup.geometry.path || "M 0 0" }
                }
            }
            Item {
                id: pointerField
                x: popup.barAttachment ? popup.geometry.contentLeft : 0
                y: popup.geometry.bodyTop
                width: popup.barAttachment
                    ? popup.geometry.contentRight - popup.geometry.contentLeft : popup.surfaceWidth
                height: Math.max(0, popup.surfaceHeight - y)
            }
            Item {
                id: contentHost
                parent: pointerField
                x: popup.barAttachment ? 16 : 12
                y: popup.barAttachment ? 16 : 12
                width: Math.max(0, pointerField.width - 2 * x)
                height: Math.max(0, pointerField.height - 2 * y)
                focus: root.grabFocus
                objectName: "attached-popover-content"
                onWidthChanged: root.layoutContent()
                onHeightChanged: root.layoutContent()
                Keys.priority: Keys.BeforeItem
                Keys.onEscapePressed: function(event) { event.accepted = true; root.close("escape"); }
                Item {
                    id: defaultContent
                    width: parent.width
                    height: parent.height
                }
            }
        }

        onVisibleChanged: {
            if (!visible) {
                resizeFrameRetry.stop();
                root.finishClose();
            } else Qt.callLater(root.requestResizeFrames);
        }
        onWindowTransformChanged: { root.contourChanged(); surfaceItem.contourChanged(); }
        onGeometryChanged: { root.contourChanged(); surfaceItem.contourChanged(); }
        onTriggerCenterXChanged: { root.contourChanged(); surfaceItem.contourChanged(); }
        onWidthChanged: { root.contourChanged(); surfaceItem.contourChanged(); root.layoutContent(); }
        onHeightChanged: { root.contourChanged(); surfaceItem.contourChanged(); root.layoutContent(); }
    }

    Timer {
        id: resizeFrameRetry
        interval: 32
        repeat: true
        onTriggered: {
            if (!popup.visible || root.resizeRetryCount >= 8) { stop(); return; }
            root.requestWindowFrame();
            root.resizeRetryCount++;
            if (Math.abs(popup.height - popup.implicitHeight) < 1
                && Math.abs(popup.width - popup.implicitWidth) < 1) stop();
        }
    }
}
