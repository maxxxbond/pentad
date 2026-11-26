pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme

// Tabs whose pill and panels follow one spring, after Kokonut UI's "Smooth tab" (MIT,
// kokonutui.com/docs/navigation/smooth-tab; only its motion numbers are used, no code).
// The capsule pill slides to the chosen tab and the panels slide with it; the panels can also be
// dragged sideways, the pill follows the finger, and a release (or a quick flick) settles on a tab
// with the release velocity carried into the spring. Past either end the drag is rubber-banded.
//
//   PentadSmoothTabs {
//       options: [{ value: "a", label: "One" }, { value: "b", label: "Two" }]
//       Item { /* panel for "One": gets the full width and height of the panel area */ }
//       Item { /* panel for "Two" */ }
//   }
//
// One child per option, in order. Panels beside the current one fade to 35 %.
Control {
    id: root
    property var options: []
    property int currentIndex: 0
    property string accessibleName: ""
    // 0 shows the tab list alone, for a page that swaps its own content when the tab changes.
    property real panelHeight: 220
    property color fill: Theme.tokens.surface
    property bool activateOnPress: false
    property string segmentObjectName: ""
    readonly property int selectedIndex: currentIndex
    signal activated(int index)
    default property alias panels: strip.data

    // Motion numbers from the source: spring, rubber band, swipe speed (px/ms), axis lock (px), neighbour fade.
    readonly property real springStiffness: 420
    readonly property real springDamping: 38
    readonly property real rubberBand: 0.35
    readonly property real flingSpeed: 0.11
    readonly property real axisLock: 6
    readonly property real neighbourOpacity: 0.35

    readonly property int count: options ? options.length : 0
    readonly property real position: spring.value
    readonly property real inset: 4
    readonly property real tabHeight: Metrics.controlMedium
    readonly property real segmentWidth: count > 0 ? Math.max(0, (width - 2 * inset) / count) : 0
    readonly property bool rtl: LayoutMirroring.enabled
    readonly property real direction: rtl ? -1 : 1
    readonly property alias dragging: drag.active

    FontMetrics {
        id: labelMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
    }
    readonly property real widestLabel: {
        let widest = 0;
        for (let i = 0; i < count; ++i)
            widest = Math.max(widest, Math.ceil(labelMetrics.advanceWidth(String(options[i].label))));
        return widest;
    }
    implicitWidth: Math.max(160, 2 * inset + count * Math.max(96, widestLabel + 24))
    implicitHeight: panelHeight > 0 ? tabHeight + Metrics.space3 + panelHeight : tabHeight
    activeFocusOnTab: true
    Accessible.name: accessibleName
    Accessible.role: Accessible.PageTabList

    function select(index) {
        const next = Math.max(0, Math.min(count - 1, index));
        if (next === currentIndex) return;
        currentIndex = next;
        activated(next);
    }
    function placePanels() {
        const items = strip.children;
        for (let i = 0; i < items.length; ++i) {
            items[i].x = direction * i * viewport.width;
            items[i].y = 0;
            items[i].width = viewport.width;
            items[i].height = viewport.height;
            items[i].opacity = 1 - (1 - neighbourOpacity) * Math.min(1, Math.abs(i - position));
        }
    }
    onPositionChanged: placePanels()
    onDirectionChanged: placePanels()
    Component.onCompleted: {
        spring.jump(currentIndex);
        placePanels();
    }

    Keys.onPressed: function(event) {
        const forward = rtl ? Qt.Key_Left : Qt.Key_Right;
        const backward = rtl ? Qt.Key_Right : Qt.Key_Left;
        if (event.key === forward) select(currentIndex + 1);
        else if (event.key === backward) select(currentIndex - 1);
        else if (event.key === Qt.Key_Home) select(0);
        else if (event.key === Qt.Key_End) select(count - 1);
        else return;
        event.accepted = true;
    }

    PentadSpring {
        id: spring
        stiffness: root.springStiffness
        damping: root.springDamping
        target: root.currentIndex
    }
    FrameAnimation {
        running: !spring.settled && !drag.active
        onTriggered: spring.advance(frameTime)
    }

    // Tab list: a capsule track with the pill concentric inside it.
    ContinuousSurface {
        id: track
        width: root.width
        height: root.tabHeight
        fill: root.fill
        capsule: true
        opacity: root.enabled ? 1 : 0.55
        ContinuousSurface {
            id: pill
            x: root.inset + (root.rtl ? root.count - 1 - root.position : root.position) * root.segmentWidth
            y: root.inset
            width: root.segmentWidth
            height: root.tabHeight - 2 * root.inset
            fill: Theme.tokens.surfaceOverlay
            capsule: true
        }
        Rectangle {
            visible: root.visualFocus
            x: pill.x
            y: pill.y
            width: pill.width
            height: pill.height
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.tokens.accent
        }
        Row {
            x: root.inset
            y: root.inset
            height: root.tabHeight - 2 * root.inset
            layoutDirection: root.rtl ? Qt.RightToLeft : Qt.LeftToRight
            Repeater {
                model: root.options
                delegate: Item {
                    id: tab
                    required property int index
                    required property var modelData
                    readonly property bool selected: Math.abs(index - root.position) < 0.5
                    objectName: root.segmentObjectName !== "" ? root.segmentObjectName + index : ""
                    width: root.segmentWidth
                    height: parent.height
                    Accessible.name: modelData.label
                    Accessible.role: Accessible.PageTab
                    Accessible.selected: index === root.currentIndex
                    PentadText {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Math.max(0, tab.width - 16))
                        text: tab.modelData.label
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        color: tab.selected || hover.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                    }
                    HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        enabled: root.enabled
                        function activate() {
                            root.forceActiveFocus();
                            root.select(tab.index);
                        }
                        onPressedChanged: if (pressed && root.activateOnPress) activate()
                        onTapped: if (!root.activateOnPress) activate()
                    }
                }
            }
        }
    }

    // Panel area: the strip of panels slides under the clip; dragging it moves the spring directly.
    ContinuousSurface {
        id: viewport
        visible: root.panelHeight > 0
        y: root.tabHeight + Metrics.space3
        width: root.width
        height: root.panelHeight
        extent: Metrics.radiusCard
        onWidthChanged: root.placePanels()
        onHeightChanged: root.placePanels()
        Item {
            id: strip
            x: -root.direction * root.position * viewport.width
            width: viewport.width * Math.max(1, root.count)
            height: viewport.height
            onChildrenChanged: root.placePanels()
        }
        DragHandler {
            id: drag
            property real startPosition: 0
            target: null
            enabled: root.enabled && !Theme.tokens.reducedMotion && root.count > 1
            yAxis.enabled: false
            dragThreshold: root.axisLock
            onActiveChanged: {
                if (active) {
                    startPosition = spring.value;
                    return;
                }
                // pointer speed in px/ms, converted to pages per second for the spring
                const speed = centroid.velocity.x / 1000;
                const swiped = Math.abs(speed) > root.flingSpeed;
                let landing = Math.round(spring.value);
                if (swiped) landing = Math.round(startPosition) + (speed * root.direction < 0 ? 1 : -1);
                landing = Math.max(0, Math.min(root.count - 1, landing));
                const pagesPerSecond = -speed * 1000 * root.direction / Math.max(1, viewport.width);
                root.select(landing);
                spring.launch(pagesPerSecond);
            }
            onTranslationChanged: {
                if (!active) return;
                const raw = startPosition - root.direction * translation.x / Math.max(1, viewport.width);
                const last = root.count - 1;
                const banded = raw < 0 ? raw * root.rubberBand
                    : raw > last ? last + (raw - last) * root.rubberBand : raw;
                spring.kick(banded);
            }
        }
    }
}
