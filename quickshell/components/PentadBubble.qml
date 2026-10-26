pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import QtQuick.Window
import qs.theme
import "../logic/help-bubble.mjs" as HelpBubble

// The one speech-bubble surface for hints and explanations, with its tail on the item it is declared in.
// PentadHint shows it passively; PentadInfoButton pins it. It can lead with a clip or image (`media`) and end
// with one action (`actionText`).
Popup {
    id: bubble
    property string text: ""
    // A video (mp4, webm, mkv, mov, ogv) loops muted; anything else is shown as a still or animated image.
    property url media: ""
    property real mediaRatio: 16 / 9
    property string actionText: ""
    // Opened externally when set; the action shows the "open in new" mark only then.
    property url actionUrl: ""
    // "vertical" puts the bubble above its item (below when there is no room); "horizontal" beside it.
    property string axis: "vertical"
    // Space between the item and the tail tip; raise it when the item sits on a padded surface.
    property real gap: 4
    signal actionTriggered()
    readonly property alias label: label
    readonly property alias action: action
    readonly property bool hovered: bubbleHover.hovered
    readonly property bool hasMedia: media.toString() !== ""
    readonly property bool hasAction: actionText !== ""
    readonly property bool video: /\.(mp4|webm|mkv|mov|ogv)$/i.test(media.toString())
    readonly property bool horizontal: axis === "horizontal"
    readonly property real tailHeight: 8
    readonly property real inset: 8
    readonly property real maxWidth: Math.max(160, (parent && parent.Window.window ? parent.Window.window.width : 320) - 16)
    // Re-measured on every open: the item may have moved since the last one.
    readonly property var placement: place(width, height, visible)
    readonly property string side: placement.side
    // Wrapped text is balanced across its lines instead of leaving one word on the last.
    readonly property real textLimit: Math.min(264, maxWidth) - 4 * inset
    readonly property int textLines: Math.max(1, Math.ceil(textMetrics.advanceWidth / textLimit))
    // TextMetrics measures a few pixels narrower than the laid-out Text, so a single line gets that slack back.
    readonly property real balancedWidth: Math.min(textLimit,
        Math.ceil(textMetrics.advanceWidth / textLines) + (textLines > 1 ? 16 : 4))
    // Long words can push a balanced width onto an extra line; then the full width wins. One line always fits.
    readonly property real textWidth: textLines > 1 && balanceProbe.lineCount > textLines ? textLimit : balancedWidth
    readonly property real bodyWidth: hasMedia ? Math.min(296, maxWidth)
        : Math.min(maxWidth, Math.max(hasAction ? 208 : 0, textWidth + 4 * inset))
    x: placement.x
    y: placement.y
    width: bodyWidth + (horizontal ? tailHeight : 0)
    padding: 0
    transformOrigin: side === "above" ? Item.Bottom : side === "below" ? Item.Top
        : side === "left" ? Item.Right : Item.Left

    // `open` is unused: passing the visibility makes the placement binding re-run on every open.
    function place(width, height, open) {
        const item = bubble.parent;
        const area = item && item.Window.window ? item.Window.window.contentItem : null;
        if (!area) return { x: 0, y: item ? item.height : 0, side: horizontal ? "right" : "below", tail: 0 };
        const origin = item.mapToItem(area, 0, 0);
        const placed = HelpBubble.helpBubblePlacement(
            { x: origin.x, y: origin.y, width: item.width, height: item.height },
            { width: area.width, height: area.height }, width, height, gap, 8, axis);
        return { x: placed.x - origin.x, y: placed.y - origin.y, side: placed.side, tail: placed.tail };
    }

    HoverHandler {
        id: bubbleHover
        parent: bubble.contentItem
    }
    TextMetrics {
        id: textMetrics
        font: label.font
        text: bubble.text
    }
    // Transparent rather than invisible: a hidden Text keeps a stale layout when its width changes.
    PentadText {
        id: balanceProbe
        opacity: 0
        Accessible.ignored: true
        width: bubble.balancedWidth
        font: label.font
        text: bubble.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    background: Item {
        id: silhouette
        layer.enabled: true
        layer.effect: OverlayShadowEffect {}
        // The contour is drawn with its tail on top, then mirrored (above) or turned (beside) to face the item.
        Shape {
            id: bubbleShape
            anchors.centerIn: parent
            width: bubble.horizontal ? silhouette.height : silhouette.width
            height: bubble.horizontal ? silhouette.width : silhouette.height
            rotation: bubble.side === "left" ? 90 : bubble.side === "right" ? -90 : 0
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.y: bubbleShape.height / 2; yScale: bubble.side === "above" ? -1 : 1 }
            ShapePath {
                fillColor: Theme.tokens.bubble
                strokeColor: "transparent"
                PathSvg {
                    path: HelpBubble.helpBubbleGeometry(bubbleShape.width, bubbleShape.height,
                        bubble.side === "right" ? silhouette.height - bubble.placement.tail : bubble.placement.tail,
                        20, bubble.tailHeight, Metrics.radiusPopover).path || "M 0 0"
                }
            }
        }
    }

    contentItem: Item {
        implicitWidth: bubble.width
        implicitHeight: body.implicitHeight + 2 * bubble.inset + (bubble.horizontal ? 0 : bubble.tailHeight)
        Column {
            id: body
            x: bubble.inset + (bubble.side === "right" ? bubble.tailHeight : 0)
            y: bubble.inset + (bubble.side === "below" ? bubble.tailHeight : 0)
            width: bubble.bodyWidth - 2 * bubble.inset
            spacing: bubble.inset

            ContinuousSurface {
                objectName: "bubble-media"
                visible: bubble.hasMedia
                width: parent.width
                height: Math.round(width / Math.max(0.25, bubble.mediaRatio))
                // Concentric with the bubble: its radius less the inset.
                extent: Metrics.radiusPopover - bubble.inset
                fill: Theme.config.appearance === "dark" ? Theme.tokens.surface : "#FFFFFF"
                Loader {
                    anchors.fill: parent
                    active: bubble.visible && bubble.hasMedia && !bubble.video
                    sourceComponent: AnimatedImage {
                        source: bubble.media
                        fillMode: Image.PreserveAspectCrop
                        playing: !Theme.tokens.reducedMotion
                        asynchronous: true
                    }
                }
                // Loaded by URL, so a system without QtMultimedia loses only the clip.
                Loader {
                    anchors.fill: parent
                    active: bubble.visible && bubble.video
                    source: active ? Qt.resolvedUrl("PentadHelpVideo.qml") : ""
                    onLoaded: item.source = Qt.binding(() => bubble.media)
                }
            }

            PentadText {
                id: label
                width: parent.width
                leftPadding: bubble.inset
                rightPadding: bubble.inset
                topPadding: bubble.hasMedia ? 0 : 4
                bottomPadding: bubble.hasAction ? 0 : 4
                text: bubble.text
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: bubble.hasMedia ? Qt.alpha(Theme.tokens.onBubble, 0.72) : Theme.tokens.onBubble
            }

            Button {
                id: action
                objectName: "bubble-action"
                visible: bubble.hasAction
                width: parent.width
                implicitHeight: Metrics.controlMedium
                text: bubble.actionText
                Accessible.name: text
                Accessible.role: Accessible.Button
                onClicked: {
                    if (bubble.actionUrl.toString() !== "") Qt.openUrlExternally(bubble.actionUrl);
                    bubble.actionTriggered();
                    bubble.close();
                }
                contentItem: Item {
                    PentadText {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 2 * (externalMark.width + 12))
                        text: action.text
                        textFormat: Text.PlainText
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        color: Theme.tokens.onBubble
                    }
                    PentadIcon {
                        id: externalMark
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: bubble.actionUrl.toString() !== ""
                        source: Qt.resolvedUrl("../assets/icons/material/stash/open-in-new-symbolic.svg")
                        pixelSize: Metrics.panelIcon
                        color: Qt.alpha(Theme.tokens.onBubble, 0.6)
                        Accessible.ignored: true
                    }
                }
                background: Rectangle {
                    radius: height / 2
                    color: Qt.alpha(Theme.tokens.onBubble, action.down ? 0.16 : action.hovered ? 0.12 : 0.08)
                    border.width: action.visualFocus ? 2 : 0
                    border.color: Theme.tokens.accent
                    Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                }
            }
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.tokens.reducedMotion ? 0 : Motion.short }
            NumberAnimation {
                property: "scale"; from: 0.94; to: 1
                duration: Theme.tokens.reducedMotion ? 0 : Motion.medium
                easing.type: Easing.OutCubic
            }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.tokens.reducedMotion ? 0 : Motion.short }
    }
}
