pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import QtQuick.Window
import qs.theme
import "../logic/help-bubble.mjs" as HelpBubble

// A quiet "?" that explains one setting in a speech bubble. Resting the pointer or moving keyboard focus onto it
// shows the bubble passively; a click pins it and gives it focus, so its action is reachable.
// The bubble can lead with a short clip or image (`helpMedia`) and end with one action (`helpActionText`).
PentadButton {
    id: control
    required property string helpText
    // A video (mp4, webm, mkv, mov, ogv) loops muted; anything else is shown as a still or animated image.
    property url helpMedia: ""
    property real helpMediaRatio: 16 / 9
    property string helpActionText: ""
    // Opened externally when set; the action shows the "open in new" mark only then.
    property url helpActionUrl: ""
    signal helpActionTriggered()
    readonly property alias helpPopup: explanation
    readonly property alias helpLabel: label
    readonly property alias helpAction: action
    readonly property alias helpHoverTimer: hoverDelay
    // A pinned bubble came from a click or Space and stays until Escape or a press elsewhere.
    property bool pinned: false
    readonly property bool engaged: hovered || visualFocus || explanation.visible
    text: "?"
    accessibleName: "Information"
    Accessible.description: helpText
    implicitWidth: 24
    controlHeight: 24
    iconSize: Metrics.panelIcon
    checked: explanation.visible
    onClicked: {
        if (explanation.visible && pinned) {
            explanation.close();
            return;
        }
        pinned = true;
        if (explanation.visible) explanation.contentItem.forceActiveFocus();
        else explanation.open();
    }
    onHoveredChanged: {
        if (hovered) {
            leaveGrace.stop();
            if (!explanation.visible) hoverDelay.restart();
        } else {
            hoverDelay.stop();
            if (explanation.visible && !pinned) leaveGrace.restart();
        }
    }
    onVisualFocusChanged: if (visualFocus && !explanation.visible) explanation.open()
    onActiveFocusChanged: if (!activeFocus && explanation.visible && !pinned) leaveGrace.restart()
    Keys.onEscapePressed: event => {
        event.accepted = explanation.visible;
        explanation.close();
    }

    Timer {
        id: hoverDelay
        interval: Metrics.tooltipDelay
        onTriggered: if (control.hovered && !explanation.visible) explanation.open()
    }
    // A short grace lets the pointer cross from the "?" onto the bubble without it closing.
    Timer {
        id: leaveGrace
        interval: 160
        onTriggered: if (!control.pinned && !control.hovered && !bubbleHover.hovered && !control.activeFocus)
            explanation.close()
    }

    // `open` is unused: passing the popup's visibility makes the binding re-run on every open.
    function placeBubble(width, height, open) {
        const area = control.Window.window ? control.Window.window.contentItem : null;
        if (!area) return { x: 0, y: control.height, side: "below", tailX: width / 2 };
        const origin = control.mapToItem(area, 0, 0);
        const placed = HelpBubble.helpBubblePlacement(
            { x: origin.x, y: origin.y, width: control.width, height: control.height },
            { width: area.width, height: area.height }, width, height);
        return { x: placed.x - origin.x, y: placed.y - origin.y, side: placed.side, tailX: placed.tailX };
    }

    contentItem: Item {
        implicitWidth: control.iconSize
        implicitHeight: control.iconSize
        PentadIcon {
            anchors.centerIn: parent
            visible: !explanation.visible
            source: Qt.resolvedUrl("../assets/icons/pentad/help-symbolic.svg")
            pixelSize: control.iconSize
            color: control.engaged ? Theme.tokens.text : Qt.alpha(Theme.tokens.textMuted, 0.9)
            Accessible.ignored: true
            Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
        }
        // While the explanation is open the mark turns into a solid accent dot, so the tail has something to point at.
        Rectangle {
            anchors.centerIn: parent
            visible: explanation.visible
            width: control.iconSize + 2
            height: width
            radius: width / 2
            color: Theme.tokens.accent
            PentadIcon {
                anchors.centerIn: parent
                source: Qt.resolvedUrl("../assets/icons/pentad/question-symbolic.svg")
                pixelSize: control.iconSize - 4
                color: Theme.tokens.onAccent
                Accessible.ignored: true
            }
        }
    }
    background: Rectangle {
        radius: width / 2
        color: control.down && !explanation.visible ? Theme.tokens.surfaceOverlay
            : control.hovered && !explanation.visible ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.tokens.accent
        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
    }

    Popup {
        id: explanation
        objectName: "info-button-explanation"
        readonly property bool hasMedia: control.helpMedia.toString() !== ""
        readonly property bool hasAction: control.helpActionText !== ""
        readonly property bool video: /\.(mp4|webm|mkv|mov|ogv)$/i.test(control.helpMedia.toString())
        readonly property real tailHeight: 8
        readonly property real inset: 8
        readonly property real maxWidth: Math.max(160, (control.Window.window ? control.Window.window.width : 320) - 16)
        // Re-measured on every open: the trigger may have scrolled since the last one.
        readonly property var placement: control.placeBubble(width, height, visible)
        readonly property bool above: placement.side === "above"
        // A dark ink bubble on light surfaces; on the dark theme it lifts one step and leans on its shadow.
        readonly property bool darkTheme: Theme.config.appearance === "dark"
        readonly property color fill: darkTheme ? Theme.tokens.surfaceOverlay : "#1C211B"
        readonly property color ink: darkTheme ? Theme.tokens.text : "#F2F4F1"
        x: placement.x
        y: placement.y
        // Wrapped text is balanced across its lines instead of leaving one word on the last.
        readonly property real textLimit: Math.min(264, maxWidth) - 4 * inset
        readonly property int textLines: Math.max(1, Math.ceil(textMetrics.advanceWidth / textLimit))
        readonly property real balancedWidth: Math.min(textLimit, Math.ceil(textMetrics.advanceWidth / textLines) + (textLines > 1 ? 16 : 0))
        // Long words can push a balanced width onto an extra line; then the full width wins.
        readonly property real textWidth: balanceProbe.lineCount > textLines ? textLimit : balancedWidth
        width: hasMedia ? Math.min(296, maxWidth)
            : Math.min(maxWidth, Math.max(hasAction ? 208 : 96, textWidth + 4 * inset))
        padding: 0
        // A passive bubble must not take keyboard focus from wherever it is.
        focus: control.pinned
        // Both flags: a press closes it only outside the bubble and outside the "?", which toggles it itself.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent
        transformOrigin: above ? Item.Bottom : Item.Top
        onClosed: {
            control.pinned = false;
            leaveGrace.stop();
        }

        HoverHandler {
            id: bubbleHover
            parent: explanation.contentItem
            onHoveredChanged: {
                if (hovered) leaveGrace.stop();
                else if (!control.pinned && !control.hovered) leaveGrace.restart();
            }
        }

        TextMetrics {
            id: textMetrics
            font: label.font
            text: control.helpText
        }
        PentadText {
            id: balanceProbe
            visible: false
            width: explanation.balancedWidth
            font: label.font
            text: control.helpText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }

        background: Item {
            layer.enabled: true
            layer.effect: OverlayShadowEffect {}
            Shape {
                id: bubbleShape
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transform: Scale { origin.y: bubbleShape.height / 2; yScale: explanation.above ? -1 : 1 }
                ShapePath {
                    fillColor: explanation.fill
                    strokeColor: "transparent"
                    PathSvg {
                        path: HelpBubble.helpBubbleGeometry(bubbleShape.width, bubbleShape.height,
                            explanation.placement.tailX, 20, explanation.tailHeight, Metrics.radiusPopover).path || "M 0 0"
                    }
                }
            }
        }

        contentItem: Item {
            implicitWidth: explanation.width
            implicitHeight: body.implicitHeight + 2 * explanation.inset + explanation.tailHeight
            Column {
                id: body
                x: explanation.inset
                y: explanation.inset + (explanation.above ? 0 : explanation.tailHeight)
                width: parent.width - 2 * explanation.inset
                spacing: explanation.inset

                ContinuousSurface {
                    objectName: "info-button-media"
                    visible: explanation.hasMedia
                    width: parent.width
                    height: Math.round(width / Math.max(0.25, control.helpMediaRatio))
                    // Concentric with the bubble: its radius less the inset.
                    extent: Metrics.radiusPopover - explanation.inset
                    fill: explanation.darkTheme ? Theme.tokens.surface : "#FFFFFF"
                    Loader {
                        anchors.fill: parent
                        active: explanation.visible && explanation.hasMedia && !explanation.video
                        sourceComponent: AnimatedImage {
                            source: control.helpMedia
                            fillMode: Image.PreserveAspectCrop
                            playing: !Theme.tokens.reducedMotion
                            asynchronous: true
                        }
                    }
                    // Loaded by URL, so a system without QtMultimedia loses only the clip.
                    Loader {
                        id: videoLoader
                        anchors.fill: parent
                        active: explanation.visible && explanation.video
                        source: active ? Qt.resolvedUrl("PentadHelpVideo.qml") : ""
                        onLoaded: item.source = Qt.binding(() => control.helpMedia)
                    }
                }

                PentadText {
                    id: label
                    width: parent.width
                    leftPadding: explanation.inset
                    rightPadding: explanation.inset
                    topPadding: explanation.hasMedia ? 0 : 4
                    bottomPadding: explanation.hasAction ? 0 : 4
                    text: control.helpText
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: explanation.hasMedia ? Qt.alpha(explanation.ink, 0.72) : explanation.ink
                }

                Button {
                    id: action
                    objectName: "info-button-action"
                    visible: explanation.hasAction
                    width: parent.width
                    implicitHeight: Metrics.controlMedium
                    text: control.helpActionText
                    Accessible.name: text
                    Accessible.role: Accessible.Button
                    onClicked: {
                        if (control.helpActionUrl.toString() !== "") Qt.openUrlExternally(control.helpActionUrl);
                        control.helpActionTriggered();
                        explanation.close();
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
                            color: explanation.ink
                        }
                        PentadIcon {
                            id: externalMark
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: control.helpActionUrl.toString() !== ""
                            source: Qt.resolvedUrl("../assets/icons/material/stash/open-in-new-symbolic.svg")
                            pixelSize: Metrics.panelIcon
                            color: Qt.alpha(explanation.ink, 0.6)
                            Accessible.ignored: true
                        }
                    }
                    background: Rectangle {
                        radius: height / 2
                        color: Qt.alpha(explanation.ink, action.down ? 0.16 : action.hovered ? 0.12 : 0.08)
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
}
