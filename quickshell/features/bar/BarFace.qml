import QtQuick
import Quickshell
import qs.theme
import qs.components
import '../../logic/bar-density.mjs' as Density

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
    property real horizontalInset: Math.min(24, Math.max(12, Math.round(width * 0.0125)))
    readonly property real islandCenter: center.x + activity.x + activity.width / 2
    readonly property real centerLeft: center.x
    readonly property real centerRight: center.x + center.width
    readonly property real leftContentRight: left.x + left.width
    readonly property real rightContentLeft: right.x
    // The left content without the window title, with the workspace strip at rest: the strip grows on
    // hover only into the room the telemetry wing leaves, and the title takes whatever is left.
    readonly property real leftRestingWidth: {
        const parts = [navigation.implicitWidth, workspaces.visible ? workspaces.restingWidth : 0]
            .filter(function(part) { return part > 0; });
        return parts.reduce(function(sum, part) { return sum + part; }, 0) + Math.max(0, parts.length - 1) * left.spacing;
    }
    readonly property real titleMinimum: 120
    readonly property real titleRoom: center.x - Metrics.statusGap - left.x - leftRestingWidth - (leftRestingWidth > 0 ? left.spacing : 0)
    property bool telemetryShown: false
    property bool toolsShown: false
    // The right side as planning sees it: the microphone icon counts whether it shows or not, so a
    // push-to-talk press never changes which wings fit; at rest its room stays empty. Screen recording
    // is rare, so its icon counts only while recording, as a Row would lay it out. Every input here is
    // an item's own width or the recording state, never the outer Row's laid-out width, so planning
    // never sees a state between the icon's change and the Row's next relayout.
    readonly property bool recordingShown: desktopState.kind === 'ready' && !!desktopState.value.recording
    readonly property real rightPlannedWidth: Density.rowWidth([microphone.width, recordingShown ? recording.width : 0,
        steadyRight.width], right.spacing)
    readonly property var wingInputs: ({ width: width, inset: horizontalInset, gap: Metrics.centerGap,
        spacing: Metrics.statusGap, island: activity.width, left: leftRestingWidth, right: rightPlannedWidth,
        telemetry: telemetry.implicitWidth, tools: tools.implicitWidth })
    onWingInputsChanged: planWings()
    Component.onCompleted: planWings()
    function planWings() {
        const plan = Density.planWings(wingInputs, { telemetry: telemetryShown, tools: toolsShown });
        telemetryShown = plan.telemetry;
        toolsShown = plan.tools;
    }
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
    signal activityHovered()
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
    // The center island opens the activity menu, so hovering it prepares that menu as well.
    readonly property bool centerHovered: barHover.hovered && barHover.point.position.x >= center.x
        && barHover.point.position.x <= center.x + center.width
    onCenterHoveredChanged: if (centerHovered) activityHovered()
    HoverHandler { id: barHover }
    Row {
        id: left
        x: root.horizontalInset
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        BarSlot { id: navigation; services: root.services; slot: 'navigation'; outputId: root.outputId; height: parent.height }
        WorkspaceSwitcher {
            id: workspaces
            services: root.services
            outputId: root.outputId
            held: root.workspaceHeld
            maximumWidth: center.x - Metrics.statusGap - left.x - x
            presentationSuppressed: !!root.services.navigation && root.services.navigation.active
            // The active window title next to the capsule belongs to the same hover zone.
            barRegionHovered: barHover.hovered
                && barHover.point.position.x >= left.x + workspaces.x - 40
                && barHover.point.position.x <= left.x + 40 + (activeTitle.visible
                    ? activeTitle.x + activeTitle.width : workspaces.x + workspaces.width)
            visible: root.layout.showWorkspaces && choices.length > 0
            height: root.height
        }
        Column {
            id: activeTitle
            objectName: "active-window-title"
            readonly property var value: root.workspaceState.kind === 'ready' ? root.workspaceState.value : null
            readonly property var output: value ? value.outputs.find(function(item) { return item.name === root.outputId || item.id === root.outputId }) : null
            visible: root.layout.showActiveTitle && root.titleRoom >= root.titleMinimum && !!value && !!output
                && value.focusedOutputId === output.id && !!value.activeTitle
            width: visible ? Math.max(0, Math.min(320, center.x - left.x - x - 8)) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2
            Text { width: parent.width; height: 12; text: parent.value ? parent.value.activeClass : ''; color: Theme.tokens.textMuted; font.family: root.identityFont; font.pixelSize: 12; font.weight: 450; renderType: Text.NativeRendering; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            Text { width: parent.width; height: 15; text: parent.value ? parent.value.activeTitle : ''; color: Theme.tokens.text; font.family: root.identityFont; font.pixelSize: 15; font.weight: 400; renderType: Text.NativeRendering; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        }
    }
    // The island sits on the bar's physical centre and each wing takes room only from its own half (see
    // logic/bar-density.mjs). A wing that does not fit stays laid out but transparent and disabled, so
    // its natural width keeps steering the plan.
    Item {
        id: center
        readonly property real leading: root.telemetryShown ? telemetry.implicitWidth + Metrics.centerGap : 0
        readonly property real trailing: root.toolsShown ? Metrics.centerGap + tools.implicitWidth : 0
        x: Math.round((root.width - activity.width) / 2) - leading
        width: leading + activity.width + trailing
        height: parent.height
        BarSlot {
            id: telemetry
            services: root.services; slot: 'telemetry'; outputId: root.outputId
            x: activity.x - Metrics.centerGap - width
            height: parent.height
            enabled: root.telemetryShown
            opacity: enabled ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
        }
        BarSlot {
            id: activity
            services: root.services; slot: 'center'; outputId: root.outputId
            x: center.leading
            height: parent.height
            onActivated: function(action, instanceId) { root.activityRequested(instanceId) }
        }
        BarSlot {
            id: tools
            services: root.services; slot: 'tools'; outputId: root.outputId
            x: activity.x + activity.width + Metrics.centerGap
            height: parent.height
            enabled: root.toolsShown
            opacity: enabled ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
            onActivated: function(action) { root.actionRequested(action) }
        }
    }
    Row {
        id: right
        height: parent.height
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalInset
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.statusGap
        MicrophoneIndicator { id: microphone; services: root.services; anchors.verticalCenter: parent.verticalCenter }
        PentadIcon {
            id: recording
            visible: root.recordingShown
            source: Qt.resolvedUrl('../../assets/icons/material/videocam-symbolic.svg')
            color: Theme.tokens.error
            pixelSize: Metrics.statusIcon
            anchors.verticalCenter: parent.verticalCenter
            accessibleName: 'Recording'
        }
        // Everything after the privacy icons; its width is what planning measures.
        Row {
            id: steadyRight
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            spacing: right.spacing
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
            KeyboardLayoutIndicator {
                objectName: "bar-keyboard-indicator"
                services: root.services
                ink: root.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            StatusCluster { objectName: "bar-status-cluster"; services: root.services; onActivated: root.sideRequested('right') }
            Item {
                objectName: "clock-status-divider"
                width: 10; height: Metrics.panelControl
                visible: root.systemHasClock(system.placements)
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Theme.tokens.textMuted; opacity: 0.9 }
            }
            BarSlot { id: system; objectName: "bar-system-slot"; services: root.services; slot: 'system'; outputId: root.outputId; height: parent.height; anchors.verticalCenter: parent.verticalCenter; onActivated: function(action) { if (action === 'right') root.sideRequested('right') } }
        }
    }
}
