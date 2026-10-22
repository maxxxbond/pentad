import QtQuick
import Quickshell
import qs.theme
import qs.components

Item {
    id: root
    objectName: "pentad-bar-face"
    readonly property point pointerGlobalOrigin: Qt.point(QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.x : 0,
        QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.y : 0)
    required property var services
    required property string outputId
    property bool workspaceHeld: false
    property var brightness: null
    readonly property var layout: services.config.documents.layout
    readonly property bool compact: width < 1200
    property real horizontalInset: Math.min(24, Math.max(12, Math.round(width * 0.0125)))
    readonly property real islandCenter: center.x + center.width / 2
    readonly property real centerLeft: center.x
    readonly property real renderedHeight: Math.max(height, (height - activity.height) / 2 + activity.visualHeight)
    readonly property real islandWidth: activity.width
    readonly property var inputRegions: activity.inputRegions
    readonly property alias workspaceSwitcher: workspaces
    readonly property var workspaceState: services.hyprland.state
    readonly property var desktopState: services.desktop.state
    readonly property color ink: Qt.alpha(Theme.tokens.text, 0.8)
    readonly property string identityFont: Qt.fontFamilies().indexOf('Google Sans Flex') >= 0 ? 'Google Sans Flex' : Theme.tokens.fontFamily
    readonly property alias tooltip: sharedTooltip
    PentadToolTip {
        id: sharedTooltip
        sharedRenderer: true
        visible: false
        ready: true
        anchorItem: sourceTooltip ? sourceTooltip.anchorItem : root
        text: sourceTooltip ? sourceTooltip.text : ""
        detail: sourceTooltip ? sourceTooltip.detail : ""
        sizeMode: sourceTooltip ? sourceTooltip.activeBarSizeMode : "auto"
        animateContent: !sourceTooltip || sourceTooltip.animateContent
        direction: sourceTooltip ? sourceTooltip.direction : 1
        onVisibleChanged: ready = true
    }
    signal sideRequested(string side)
    signal sideHovered(string side)
    signal activityRequested(string instanceId)
    signal actionRequested(string action)
    implicitHeight: layout.barHeight

    function systemHasClock(placements) {
        return placements.some(function(item) { return item.moduleId === 'pentad.clock'; });
    }

    Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
    MouseArea {
        anchors.fill: parent
        property real leftWheelRemainder: 0
        property real rightWheelRemainder: 0
        hoverEnabled: true
        onExited: { leftWheelRemainder = 0; rightWheelRemainder = 0; }
        // The center belongs to the island; side menus and level scrolling live on the sides only.
        function inCenter(x) { return x >= center.x && x <= center.x + center.width }
        onPressed: function(event) {
            if (!inCenter(event.x)) root.sideRequested(event.x < width / 2 ? 'left' : 'right');
        }
        onWheel: function(event) {
            event.accepted = true;
            if (inCenter(event.x)) {
                leftWheelRemainder = 0;
                rightWheelRemainder = 0;
                return;
            }
            const rightSide = event.x >= width / 2;
            const delta = event.angleDelta.y !== 0 ? event.angleDelta.y / 120 : event.pixelDelta.y / 40;
            let remainder = rightSide ? rightWheelRemainder : leftWheelRemainder;
            if (Math.sign(delta) !== Math.sign(remainder)) remainder = 0;
            remainder += delta;
            const steps = Math.trunc(remainder);
            if (rightSide) { rightWheelRemainder = remainder - steps; leftWheelRemainder = 0; }
            else { leftWheelRemainder = remainder - steps; rightWheelRemainder = 0; }
            if (steps && rightSide) root.services.audio.adjustVolume('output', steps);
            else if (steps && root.brightness) root.brightness.nudge(steps);
        }
    }
    readonly property string hoveredSide: barHover.hovered
        ? (barHover.point.position.x < width / 2 ? 'left' : 'right') : ''
    onHoveredSideChanged: if (hoveredSide) sideHovered(hoveredSide)
    HoverHandler { id: barHover }
    Row {
        id: left
        x: root.horizontalInset
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        BarSlot { services: root.services; slot: 'navigation'; outputId: root.outputId; compact: root.compact; height: parent.height }
        WorkspaceSwitcher {
            id: workspaces
            services: root.services
            outputId: root.outputId
            held: root.workspaceHeld
            presentationSuppressed: !!root.services.navigation && root.services.navigation.active
            barRegionHovered: barHover.hovered
                && barHover.point.position.x >= left.x + workspaces.x - 12
                && barHover.point.position.x <= left.x + workspaces.x + workspaces.width + 12
            visible: root.layout.showWorkspaces && choices.length > 0
            height: root.height
        }
        Column {
            id: activeTitle
            objectName: "active-window-title"
            readonly property var value: root.workspaceState.kind === 'ready' ? root.workspaceState.value : null
            readonly property var output: value ? value.outputs.find(function(item) { return item.name === root.outputId || item.id === root.outputId }) : null
            visible: root.layout.showActiveTitle && !root.compact && !!value && !!output
                && value.focusedOutputId === output.id && !!value.activeTitle
            width: visible ? Math.max(0, Math.min(320, center.x - left.x - x - 8)) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2
            Text { width: parent.width; height: 12; text: parent.value ? parent.value.activeClass : ''; color: Theme.tokens.textMuted; font.family: root.identityFont; font.pixelSize: 12; font.weight: 450; renderType: Text.NativeRendering; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            Text { width: parent.width; height: 15; text: parent.value ? parent.value.activeTitle : ''; color: Theme.tokens.text; font.family: root.identityFont; font.pixelSize: 15; font.weight: 400; renderType: Text.NativeRendering; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        }
    }
    Row {
        id: center
        anchors.centerIn: parent
        spacing: Metrics.centerGap
        readonly property real wingWidth: Math.max(telemetry.implicitWidth, tools.implicitWidth)
        Item {
            width: root.compact ? 0 : center.wingWidth
            height: root.height
            visible: !root.compact
            BarSlot { id: telemetry; services: root.services; slot: 'telemetry'; outputId: root.outputId; compact: root.compact; height: parent.height; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
        }
        BarSlot {
            id: activity
            services: root.services; slot: 'center'; outputId: root.outputId; compact: root.compact
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            onActivated: function(action, instanceId) { root.activityRequested(instanceId) }
        }
        Item {
            width: root.compact ? 0 : center.wingWidth
            height: root.height
            visible: !root.compact
            BarSlot { id: tools; services: root.services; slot: 'tools'; outputId: root.outputId; compact: root.compact; height: parent.height; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; onActivated: function(action) { root.actionRequested(action) } }
        }
    }
    Row {
        id: right
        height: parent.height
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalInset
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.statusGap
        PentadIcon {
            visible: root.desktopState.kind === 'ready' && root.desktopState.value.recording
            source: Qt.resolvedUrl('../../assets/icons/material/videocam-symbolic.svg')
            color: Theme.tokens.error
            pixelSize: Metrics.statusIcon
            anchors.verticalCenter: parent.verticalCenter
            accessibleName: 'Recording'
        }
        TrayWidget { id: tray; objectName: "bar-tray-widget"; services: root.services; outputId: root.outputId; mode: root.layout.trayIcons; anchors.verticalCenter: parent.verticalCenter }
        Item {
            objectName: "tray-status-divider"
            width: 10
            height: Metrics.panelControl
            visible: tray.trayItems.length > 0
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.centerIn: parent
                width: 4; height: 4; radius: 2
                color: Theme.tokens.textMuted
                opacity: 0.9
            }
        }
        Item {
            id: keyboardIndicator
            objectName: "bar-keyboard-indicator"
            readonly property var value: root.desktopState.kind === 'ready' ? root.desktopState.value : null
            readonly property bool switchable: !!value && value.keyboardLayoutCount > 1
            visible: !!value && !!value.keyboardLayout
            implicitWidth: Math.max(24, keyboardLabel.implicitWidth + 8)
            implicitHeight: Metrics.panelControl
            anchors.verticalCenter: parent.verticalCenter
            activeFocusOnTab: switchable
            Accessible.role: Accessible.Button
            Accessible.name: value ? value.keyboardLayoutName || value.keyboardLayout || '' : ''
            Keys.onSpacePressed: activate()
            Keys.onReturnPressed: activate()
            function activate() { if (switchable) root.services.desktop.command('keyboard-layout') }
            Text {
                id: keyboardLabel
                objectName: "bar-keyboard-label"
                anchors.centerIn: parent
                text: keyboardIndicator.value ? keyboardIndicator.value.keyboardLayout || '' : ''
                color: keyboardMouse.containsMouse || keyboardIndicator.activeFocus ? Theme.tokens.text : root.ink
                font.family: Theme.tokens.fontFamily; font.pixelSize: Metrics.exposedFont
                renderType: Text.NativeRendering
            }
            MouseArea {
                id: keyboardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: keyboardIndicator.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: keyboardIndicator.activate()
            }
            PentadToolTip {
                objectName: "keyboard-tooltip"
                visible: keyboardMouse.containsMouse
                sizeMode: "status"
                text: keyboardIndicator.Accessible.name
                detail: !keyboardIndicator.switchable ? ""
                    : (typeof root.services.text === "function"
                        ? root.services.text("Натисніть, щоб змінити розкладку", "Click to switch layout") : "Click to switch layout")
            }
        }
        StatusCluster { objectName: "bar-status-cluster"; services: root.services; onActivated: root.sideRequested('right') }
        Item {
            objectName: "clock-status-divider"
            width: 10; height: Metrics.panelControl
            visible: root.systemHasClock(system.placements)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Theme.tokens.textMuted; opacity: 0.9 }
        }
        BarSlot { id: system; objectName: "bar-system-slot"; services: root.services; slot: 'system'; outputId: root.outputId; compact: root.compact; height: parent.height; anchors.verticalCenter: parent.verticalCenter; onActivated: function(action) { if (action === 'right') root.sideRequested('right') } }
    }
}
