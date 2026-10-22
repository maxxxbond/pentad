pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import QtQuick.Window
import qs.theme
import "../logic/attached-popover.mjs" as PopoverGeometry
import "../logic/bar-tooltip.mjs" as BarTooltipGeometry

Item {
    id: root
    readonly property var window: sharedTooltip ? sharedTooltip.window : bubble
    property Item anchorItem: parent
    property bool sharedRenderer: false
    property var sourceTooltip: null
    readonly property var sharedTooltip: !sharedRenderer && bar && bar.tooltip ? bar.tooltip : null
    property string text: ""
    property string detail: ""
    property string sizeMode: "auto"
    property bool animateContent: true
    property int delay: Metrics.tooltipDelay
    property bool ready: false
    property int direction: 1
    property int transitionDirection: 1
    property real progress: 1
    readonly property bool captureSuppressed: !!bar && !!bar.services?.screenshot?.active
    // An open popover owns the bar: no tooltip of that bar shows over it, not even one held by reveal().
    readonly property bool popoverSuppressed: {
        const popups = bar && bar.services ? bar.services.popups : null;
        const window = bar ? bar.QsWindow.window : null;
        return !!popups && !!window && (popups.children || []).some(function(entry) {
            return !!entry.child && entry.child.ownerWindow === window;
        });
    }
    onPopoverSuppressedChanged: if (popoverSuppressed) hold.stop()
    readonly property bool requested: !captureSuppressed && !popoverSuppressed && !!parent && ((visible && ready) || hold.running)
    property real exposure: requested ? 1 : 0
    Behavior on exposure {
        NumberAnimation {
            duration: Motion.medium
            easing.type: Easing.OutCubic
        }
    }
    property string currentText: ""
    property string currentDetail: ""
    property string previousText: ""
    property string previousDetail: ""
    property string lockedBarSizeMode: ""
    readonly property Item bar: {
        let item = anchorItem;
        while (item) {
            if (item.objectName === "pentad-bar-face") return item;
            item = item.parent;
        }
        return null;
    }

    function claim(source) {
        dismiss.stop();
        sourceTooltip = source;
        visible = true;
    }
    function release(source) {
        if (sourceTooltip === source) dismiss.restart();
    }
    Timer {
        id: dismiss
        interval: 120
        onTriggered: root.visible = false
    }
    function forget(source) {
        if (sourceTooltip !== source) return;
        dismiss.stop();
        visible = false;
        sourceTooltip = null;
    }
    function reveal(steps) {
        direction = steps < 0 ? -1 : 1;
        ready = true;
        hold.restart();
    }
    function chooseBarSizeMode() {
        if (detail.length || currentDetail.length || (progress < 1 && previousDetail.length)) return "status";
        const measured = Math.ceil(Math.max(
            requestedTextMetrics.width, requestedTextMetrics.advanceWidth,
            currentTextMetrics.width, currentTextMetrics.advanceWidth,
            progress < 1 ? previousTextMetrics.width : 0,
            progress < 1 ? previousTextMetrics.advanceWidth : 0));
        if (measured <= Metrics.barTooltipCompactWidth - bubble.barHorizontalOverhead) return "compact";
        if (measured <= Metrics.barTooltipLabelWidth - bubble.barHorizontalOverhead) return "label";
        return "status";
    }
    function updateContent() {
        if (currentText === text && currentDetail === detail) return;
        if (slide.running && requested && animateContent) return;
        slide.stop();
        previousText = currentText;
        previousDetail = currentDetail;
        currentText = text;
        currentDetail = detail;
        transitionDirection = direction;
        if (animateContent && requested && exposure > 0.2 && previousText && !Theme.tokens.reducedMotion) {
            progress = 0;
            slide.restart();
        } else progress = 1;
    }
    readonly property string automaticBarSizeMode: chooseBarSizeMode()
    readonly property string activeBarSizeMode: {
        if (!bar) return "content";
        if (sizeMode === "compact" || sizeMode === "label" || sizeMode === "status") return sizeMode;
        return lockedBarSizeMode || automaticBarSizeMode;
    }
    onRequestedChanged: {
        if (sharedTooltip) {
            if (requested) sharedTooltip.claim(root);
            else sharedTooltip.release(root);
        }
        if (requested && sizeMode === "auto" && !lockedBarSizeMode) lockedBarSizeMode = automaticBarSizeMode;
        else if (!requested && exposure <= 0) lockedBarSizeMode = "";
    }
    onExposureChanged: if (!requested && exposure <= 0) lockedBarSizeMode = ""
    onSizeModeChanged: {
        if ((requested || exposure > 0) && sizeMode === "auto" && !lockedBarSizeMode)
            lockedBarSizeMode = automaticBarSizeMode;
        else if (sizeMode !== "auto") lockedBarSizeMode = "";
    }
    onAnimateContentChanged: if (!animateContent) {
        if (slide) slide.stop();
        progress = 1;
        Qt.callLater(updateContent);
    }
    onTextChanged: Qt.callLater(updateContent)
    onDetailChanged: Qt.callLater(updateContent)
    Component.onCompleted: updateContent()
    onVisibleChanged: {
        if (!visible) ready = false;
        else if (sharedTooltip && sharedTooltip.exposure > 0) {
            ready = true;
            sharedTooltip.claim(root);
        }
    }
    Component.onDestruction: if (sharedTooltip) sharedTooltip.forget(root)
    Timer {
        interval: root.delay
        running: root.visible && !root.sharedRenderer
        onTriggered: root.ready = true
    }
    Timer { id: hold; interval: 1800 }
    NumberAnimation {
        id: slide
        target: root
        property: "progress"
        from: 0; to: 1
        duration: Theme.tokens.reducedMotion ? 0 : 180
        easing.type: Easing.OutCubic
        onFinished: Qt.callLater(root.updateContent)
    }

    PopupWindow {
        id: bubble
        grabFocus: false
        readonly property alias captureItem: bubbleContent
        visible: !root.captureSuppressed && !root.sharedTooltip && (root.requested || root.exposure > 0)
        color: "transparent"
        mask: Region {}
        readonly property var sourceScreen: root.bar && root.bar.QsWindow.window && root.bar.QsWindow.window.screen
            ? root.bar.QsWindow.window.screen : screen
        readonly property real availableBarWidth: Math.max(1, sourceScreen ? sourceScreen.width : 1920)
        readonly property real barShoulder: 16
        readonly property real barTextPadding: 10
        readonly property real barVerticalPadding: 6
        readonly property real barHorizontalOverhead: 2 * (barShoulder + barTextPadding)
        readonly property real barPresetWidth: root.activeBarSizeMode === "compact" ? Metrics.barTooltipCompactWidth
            : root.activeBarSizeMode === "label" ? Metrics.barTooltipLabelWidth : Metrics.barTooltipStatusWidth
        readonly property real barPresetHeight: root.activeBarSizeMode === "compact" ? Metrics.barTooltipCompactHeight
            : root.activeBarSizeMode === "label" ? Metrics.barTooltipLabelHeight : Metrics.barTooltipStatusHeight
        readonly property real barMeasuredLabelWidth: Math.ceil(Math.max(
            currentTextMetrics.width, currentTextMetrics.advanceWidth,
            currentDetailMetrics.width, currentDetailMetrics.advanceWidth,
            previousTextMetrics.width, previousTextMetrics.advanceWidth,
            previousDetailMetrics.width, previousDetailMetrics.advanceWidth))
        readonly property real labelWidth: Math.max(1, Math.min(root.bar
            ? Math.max(1, Math.min(360, Math.min(availableBarWidth, barPresetWidth) - barHorizontalOverhead)) : 360, Math.max(
            root.bar ? barMeasuredLabelWidth : Math.max(
                currentTextMetrics.width, currentDetailMetrics.width,
                previousTextMetrics.width, previousDetailMetrics.width))))
        readonly property real triggerCenterX: {
            if (!root.anchorItem || !root.bar || !root.bar.Window.window) return width / 2;
            const placementTransform = bubble.windowTransform;
            const sourceTransform = root.bar.Window.window.windowTransform;
            const parentX = root.anchorItem.x;
            const globalPoint = root.anchorItem.mapToGlobal(root.anchorItem.width / 2, 0);
            return bubble.contentItem.mapFromGlobal(globalPoint).x;
        }
        readonly property var geometry: root.bar
            ? BarTooltipGeometry.barTooltipGeometry(width, height, barShoulder)
            : PopoverGeometry.attachedPopoverGeometry(
                width, height, triggerCenterX, root.anchorItem ? Math.max(32, Math.min(64, root.anchorItem.width)) : 40)
        property real animatedWidth: root.bar
            ? Math.min(availableBarWidth, barPresetWidth)
            : Math.max(100, labelWidth + 36)
        property real animatedHeight: root.bar ? barPresetHeight : Math.max(44, Math.max(
            currentTextMeasure.implicitHeight + (root.currentDetail ? currentDetailMeasure.implicitHeight : 0),
            previousTextMeasure.implicitHeight + (root.previousDetail ? previousDetailMeasure.implicitHeight : 0))
            + 42)
        implicitWidth: animatedWidth
        implicitHeight: animatedHeight
        anchor.item: root.bar || root.anchorItem
        property real animatedCenterX: {
            if (!root.anchorItem) return 0;
            let item = root.anchorItem;
            while (item && item !== root.bar) { item.x; item.width; item = item.parent; }
            return root.anchorItem.mapToItem(root.bar || root.anchorItem, root.anchorItem.width / 2, 0).x;
        }
        readonly property bool animateGeometry: root.sharedRenderer && root.exposure > 0 && !Theme.tokens.reducedMotion
        Behavior on animatedCenterX {
            enabled: bubble.animateGeometry
            NumberAnimation { duration: Motion.long; easing.type: Easing.OutCubic }
        }
        Behavior on animatedWidth {
            enabled: bubble.animateGeometry
            NumberAnimation { duration: Motion.long; easing.type: Easing.OutCubic }
        }
        Behavior on animatedHeight {
            enabled: bubble.animateGeometry
            NumberAnimation { duration: Motion.long; easing.type: Easing.OutCubic }
        }
        anchor.rect.x: {
            const centeredX = animatedCenterX - animatedWidth / 2;
            if (!root.bar || !root.bar.QsWindow.window || !sourceScreen) return centeredX;
            const sourceWindowTransform = root.bar.QsWindow.window.windowTransform;
            const barGlobalX = root.bar.mapToGlobal(0, 0).x;
            const minX = sourceScreen.x - barGlobalX;
            const maxX = sourceScreen.x + sourceScreen.width - width - barGlobalX;
            return Math.max(minX, Math.min(maxX, centeredX));
        }
        anchor.rect.y: root.bar ? root.bar.height
            : root.anchorItem ? root.anchorItem.height : 0
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.SlideX

        TextMetrics { id: requestedTextMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: 12; font.weight: Font.Medium; text: root.text }
        TextMetrics { id: currentTextMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: 12; font.weight: Font.Medium; text: root.currentText }
        TextMetrics { id: currentDetailMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: 12; text: root.currentDetail }
        TextMetrics { id: previousTextMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: 12; font.weight: Font.Medium; text: root.previousText }
        TextMetrics { id: previousDetailMetrics; font.family: Theme.tokens.fontFamily; font.pixelSize: 12; text: root.previousDetail }
        PentadText {
            id: currentTextMeasure
            solid: true
            visible: false
            width: bubble.labelWidth
            text: root.currentText
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }
        PentadText {
            id: currentDetailMeasure
            solid: true
            visible: false
            width: bubble.labelWidth
            text: root.currentDetail
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }
        PentadText {
            id: previousTextMeasure
            solid: true
            visible: false
            width: bubble.labelWidth
            text: root.previousText
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }
        PentadText {
            id: previousDetailMeasure
            solid: true
            visible: false
            width: bubble.labelWidth
            text: root.previousDetail
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }

        Item {
            id: bubbleContent
            objectName: "pentad-tooltip-content"
            anchors.fill: parent
            transform: Translate { y: root.bar ? -bubbleContent.height * (1 - root.exposure) : 0 }
            Shape {
                id: tooltipShape
                anchors.fill: parent
                opacity: root.bar ? 1 : root.exposure
                containsMode: Shape.FillContains
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.tokens.surface
                    strokeColor: "transparent"
                    PathSvg { path: bubble.geometry.path || "M 0 0" }
                }
            }
            Item {
                x: root.bar ? bubble.geometry.contentLeft + bubble.barTextPadding : 18
                y: root.bar ? bubble.barVerticalPadding : bubble.geometry.bodyTop + 8 - 4 * (1 - root.exposure)
                width: parent ? (root.bar
                    ? Math.max(0, bubble.geometry.contentRight - bubble.geometry.contentLeft - 2 * bubble.barTextPadding)
                    : Math.max(0, parent.width - 36)) : 0
                height: parent ? (root.bar ? Math.max(0, parent.height - 2 * bubble.barVerticalPadding) : parent.height - y - 10) : 0
                clip: true
                Item {
                    id: textStack
                    width: parent ? Math.max(0, parent.width) : 0
                    height: Math.max(
                        stackRepeater.itemAt(0) ? stackRepeater.itemAt(0).implicitHeight : 0,
                        stackRepeater.itemAt(1) ? stackRepeater.itemAt(1).implicitHeight : 0)
                    y: parent ? (parent.height - height) / 2 : 0
                    Repeater {
                        id: stackRepeater
                        model: 2
                        delegate: Column {
                            required property int index
                            readonly property bool outgoing: index === 0
                            readonly property real slideProgress: root ? root.progress : 1
                            readonly property real slideDirection: root ? root.transitionDirection : 1
                            readonly property string displayText: root
                                ? (outgoing ? root.previousText : root.currentText) : ""
                            readonly property string displayDetail: root
                                ? (outgoing ? root.previousDetail : root.currentDetail) : ""
                            width: parent ? Math.max(0, parent.width) : 0
                            spacing: 0
                            y: (parent ? (parent.height - height) / 2 : 0)
                                + (outgoing ? -slideProgress : 1 - slideProgress) * slideDirection * 12
                            opacity: outgoing ? 1 - slideProgress : slideProgress
                            visible: !outgoing || slideProgress < 1
                            PentadText {
                                objectName: root && root.bar ? (outgoing ? "tooltip-previous-title" : "tooltip-title") : ""
                                width: parent ? Math.max(0, parent.width) : 0
                                text: parent ? parent.displayText : ""
                                textFormat: Text.PlainText
                                solid: true
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                verticalAlignment: root && root.bar ? Text.AlignVCenter : Text.AlignTop
                                wrapMode: root && root.bar ? Text.NoWrap : Text.WordWrap
                                maximumLineCount: root && root.bar ? 1 : 2
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                            PentadText {
                                objectName: root && root.bar ? (outgoing ? "tooltip-previous-detail" : "tooltip-detail") : ""
                                width: parent ? Math.max(0, parent.width) : 0
                                text: parent ? parent.displayDetail : ""
                                visible: root && root.bar
                                    ? root.activeBarSizeMode === "status" && text.length > 0 : text.length > 0
                                textFormat: Text.PlainText
                                solid: true
                                font.pixelSize: 12
                                color: Theme.tokens.textMuted
                                verticalAlignment: root && root.bar ? Text.AlignVCenter : Text.AlignTop
                                wrapMode: root && root.bar ? Text.NoWrap : Text.WordWrap
                                maximumLineCount: root && root.bar ? 1 : 2
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
