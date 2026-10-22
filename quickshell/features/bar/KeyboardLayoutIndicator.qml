pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/keyboard-layout.mjs" as KeyboardLayout

// The active keyboard layout as a bar status indicator: the label shows the state,
// scroll steps through the layouts, a left click moves to the next one and a right click lists them all.
Item {
    id: root
    required property var services
    property color ink: Qt.alpha(Theme.tokens.text, 0.8)
    readonly property var desktopState: services.desktop.state
    readonly property var value: desktopState.kind === 'ready' ? desktopState.value : null
    readonly property var layouts: value && value.keyboardLayouts ? value.keyboardLayouts : []
    readonly property int activeIndex: value && value.keyboardLayoutIndex !== undefined ? value.keyboardLayoutIndex : -1
    readonly property bool switchable: !!value && value.keyboardLayoutCount > 1
    // Scroll runs ahead of Hyprland's confirmation, so the next notch counts from the layout already requested.
    property int requestedIndex: -1
    readonly property int shownIndex: requestedIndex >= 0 ? requestedIndex : activeIndex
    readonly property var shownLayout: layouts.find(function(layout) { return layout.index === root.shownIndex; }) || null
    readonly property string layoutName: shownLayout ? shownLayout.name : value ? value.keyboardLayoutName || value.keyboardLayout || '' : ''
    property real wheelRemainder: 0
    readonly property alias menu: layoutMenu
    readonly property Item barItem: {
        let item = parent;
        while (item) {
            if (item.objectName === "pentad-bar-face") return item;
            item = item.parent;
        }
        return null;
    }

    visible: !!value && !!value.keyboardLayout
    implicitWidth: Math.max(24, label.implicitWidth + 8)
    implicitHeight: Metrics.panelControl
    activeFocusOnTab: switchable
    Accessible.role: Accessible.Button
    Accessible.name: layoutName
    Keys.onSpacePressed: activate()
    Keys.onReturnPressed: activate()
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            openMenu();
            event.accepted = true;
        }
    }

    function text(uk, en) { return typeof services.text === "function" ? services.text(uk, en) : en; }
    function activate() { step(1); }
    function select(index) {
        if (!switchable || index < 0 || index >= value.keyboardLayoutCount) return;
        requestedIndex = index;
        requestTimeout.restart();
        services.desktop.command('keyboard-layout:' + index);
    }
    function step(steps) {
        const target = KeyboardLayout.keyboardLayoutAfter(shownIndex, value ? value.keyboardLayoutCount : 0, steps);
        if (target < 0) return;
        select(target);
        tooltip.reveal(steps);
    }
    function openMenu() { if (layouts.length) layoutMenu.toggle(); }

    onActiveIndexChanged: if (activeIndex === requestedIndex) requestedIndex = -1
    // Without a confirmation the label returns to what Hyprland reports.
    Timer { id: requestTimeout; interval: 1500; onTriggered: root.requestedIndex = -1 }

    Text {
        id: label
        objectName: "bar-keyboard-label"
        // The label is all capitals, so its caps, not the line box, sit on the icons' center line.
        readonly property real capHeight: metrics.tightBoundingRect('H').height
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((parent.height + capHeight) / 2 - baselineOffset)
        text: root.shownLayout ? root.shownLayout.label : root.value ? root.value.keyboardLayout || '' : ''
        color: pointer.containsMouse || root.activeFocus || layoutMenu.opened ? Theme.tokens.text : root.ink
        font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.exposedFont
        renderType: Text.NativeRendering
    }
    FontMetrics { id: metrics; font: label.font }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.openMenu();
            else root.activate();
        }
        onWheel: function(wheel) {
            const rawSteps = wheel.angleDelta.y !== 0
                ? wheel.angleDelta.y / 120 : wheel.pixelDelta.y / 40;
            if (Math.sign(rawSteps) !== Math.sign(root.wheelRemainder)) root.wheelRemainder = 0;
            root.wheelRemainder += rawSteps;
            const wholeSteps = Math.trunc(root.wheelRemainder);
            root.wheelRemainder -= wholeSteps;
            if (wholeSteps) root.step(wholeSteps);
            wheel.accepted = true;
        }
        onExited: root.wheelRemainder = 0
    }
    PentadToolTip {
        id: tooltip
        objectName: "keyboard-tooltip"
        visible: pointer.containsMouse && !layoutMenu.opened
        sizeMode: "status"
        animateContent: false
        text: root.layoutName
        detail: root.switchable ? root.text("Розкладка клавіатури", "Keyboard layout") : ""
    }
    AttachedPopover {
        id: layoutMenu
        objectName: "keyboard-layout-menu"
        anchorItem: root
        barItem: root.barItem
        manager: root.services.popups || null
        contentItem: Item {
            implicitHeight: menuContent.height
            implicitWidth: Math.max(192, menuTitle.implicitWidth)
            width: implicitWidth
            Column {
                id: menuContent
                width: parent.width
                spacing: 4
                PentadText {
                    id: menuTitle
                    width: parent.width
                    role: "caption"
                    solid: true
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    color: Theme.tokens.textMuted
                    text: root.text("Розкладка клавіатури", "Keyboard layout")
                }
                Repeater {
                    model: root.layouts
                    delegate: PentadButton {
                        required property var modelData
                        objectName: "keyboard-layout-option"
                        width: menuContent.width
                        controlHeight: 28
                        checked: modelData.index === root.shownIndex
                        text: modelData.name
                        onClicked: { layoutMenu.close(); root.select(modelData.index); }
                    }
                }
            }
        }
    }
}
