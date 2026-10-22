pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.theme

// A Control so keyboard focus (visualFocus) is told apart from pointer focus; arrows inside the
// group count as keyboard too, so the ring shows after an arrow even if the click came first.
Control {
    id: root
    property var options: []
    property var value: undefined
    property string accessibleName: ""
    property color fill: Theme.tokens.surface
    property bool activateOnPress: false
    property bool tabList: false
    property string segmentObjectName: ""
    signal activated(var value)
    property bool keyboardEngaged: false
    readonly property bool ringVisible: activeFocus && (visualFocus || keyboardEngaged) && focusIndex >= 0

    readonly property int count: options ? options.length : 0
    readonly property int selectedIndex: {
        for (let i = 0; i < count; ++i) if (options[i].value === value) return i;
        return -1;
    }
    property int focusIndex: -1
    readonly property real inset: 3
    readonly property real segmentWidth: count > 0 ? Math.max(0, (width - 2 * inset) / count) : 0
    readonly property bool rtl: LayoutMirroring.enabled
    readonly property alias indicator: thumb
    readonly property alias segments: segmentRepeater

    implicitWidth: Math.max(160, count * 96)
    implicitHeight: Metrics.controlMedium
    activeFocusOnTab: true
    Accessible.name: accessibleName
    Accessible.role: tabList ? Accessible.PageTabList : Accessible.RadioButton
    Accessible.description: selectedIndex >= 0 ? options[selectedIndex].label : ""

    onActiveFocusChanged: {
        if (activeFocus) focusIndex = selectedIndex >= 0 ? selectedIndex : 0;
        else keyboardEngaged = false;
    }
    onSelectedIndexChanged: if (!activeFocus) focusIndex = selectedIndex

    function moveFocus(target) {
        if (count === 0) return;
        focusIndex = Math.max(0, Math.min(count - 1, target));
    }
    function commit(index) {
        if (index < 0 || index >= count) return;
        activated(options[index].value);
    }

    Keys.onPressed: function(event) {
        const forward = rtl ? Qt.Key_Left : Qt.Key_Right;
        const backward = rtl ? Qt.Key_Right : Qt.Key_Left;
        const current = focusIndex >= 0 ? focusIndex : Math.max(0, selectedIndex);
        if (event.key === forward || event.key === Qt.Key_Down) moveFocus(current + 1);
        else if (event.key === backward || event.key === Qt.Key_Up) moveFocus(current - 1);
        else if (event.key === Qt.Key_Home) moveFocus(0);
        else if (event.key === Qt.Key_End) moveFocus(count - 1);
        else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) commit(current);
        else return;
        keyboardEngaged = true;
        event.accepted = true;
    }

    // A capsule track (user decision, 2026-10-20); the thumb stays concentric:
    // inner radius = outer radius - inset.
    readonly property real thumbRadius: Math.max(Metrics.radiusTag, height / 2 - inset)
    ContinuousSurface {
        id: track
        anchors.fill: parent
        fill: root.fill
        extent: root.height / 2
        opacity: root.enabled ? 1 : 0.55
    }
    ContinuousSurface {
        id: thumb
        visible: root.selectedIndex >= 0
        x: root.inset + (root.rtl ? root.count - 1 - root.selectedIndex : root.selectedIndex) * root.segmentWidth
        y: root.inset
        width: root.segmentWidth
        height: root.height - 2 * root.inset
        fill: Theme.tokens.surfaceOverlay
        extent: root.thumbRadius
        opacity: root.enabled ? 1 : 0.55
        Behavior on x { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        id: focusRing
        objectName: "segmentedFocusRing"
        visible: root.ringVisible
        x: root.inset + (root.rtl ? root.count - 1 - root.focusIndex : root.focusIndex) * root.segmentWidth
        y: root.inset
        width: root.segmentWidth
        height: root.height - 2 * root.inset
        radius: root.thumbRadius
        color: "transparent"
        border.width: 2
        border.color: Theme.tokens.accent
        Behavior on x { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
    }
    Row {
        x: root.inset
        y: root.inset
        height: root.height - 2 * root.inset
        layoutDirection: root.rtl ? Qt.RightToLeft : Qt.LeftToRight
        Repeater {
            id: segmentRepeater
            model: root.options
            delegate: Item {
                id: segment
                required property int index
                required property var modelData
                readonly property bool selected: index === root.selectedIndex
                objectName: root.segmentObjectName !== "" ? root.segmentObjectName + index : ""
                width: root.segmentWidth
                height: parent.height
                Accessible.name: modelData.label
                Accessible.role: root.tabList ? Accessible.PageTab : Accessible.RadioButton
                Accessible.selected: root.tabList && selected
                Accessible.checked: !root.tabList && selected
                readonly property string iconSource: modelData.icon !== undefined ? String(modelData.icon) : ""
                readonly property color foreground: segment.selected ? Theme.tokens.text
                    : hover.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                Row {
                    id: segmentContent
                    anchors.centerIn: parent
                    spacing: 8
                    layoutDirection: root.rtl ? Qt.RightToLeft : Qt.LeftToRight
                    PentadIcon {
                        visible: segment.iconSource !== ""
                        source: segment.iconSource
                        pixelSize: Metrics.statusIcon
                        color: segment.foreground
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                    }
                    PentadText {
                        width: Math.min(implicitWidth, Math.max(0, segment.width - 16
                            - (segment.iconSource !== "" ? Metrics.statusIcon + segmentContent.spacing : 0)))
                        text: segment.modelData.label
                        textFormat: Text.PlainText
                        color: segment.foreground
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                    }
                }
                HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: root.enabled
                    function activate() {
                        root.forceActiveFocus();
                        root.keyboardEngaged = false;
                        root.focusIndex = segment.index;
                        root.commit(segment.index);
                    }
                    onPressedChanged: if (pressed && root.activateOnPress) activate()
                    onTapped: if (!root.activateOnPress) activate()
                }
            }
        }
    }
}
