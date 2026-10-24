import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import "../../logic/workspaces.mjs" as Workspaces
import qs.theme
import qs.components

Item {
    id: root
    required property var services
    required property string outputId
    property bool held: false
    property bool presentationSuppressed: false
    property bool barRegionHovered: false
    property string focusedWorkspaceId: ""
    property int hoveredIndex: -1
    property int lastHoveredIndex: 0
    onHoveredIndexChanged: if (hoveredIndex >= 0) lastHoveredIndex = hoveredIndex
    signal switchRequested(string workspaceId)

    readonly property var hyprland: services.hyprland
    readonly property var state: hyprland ? hyprland.state : ({ kind: 'unavailable' })
    readonly property var value: state.kind === 'ready' ? state.value
        : ({ workspaces: [], outputs: [], focusedOutputId: '', activeTitle: '', activeClass: '' })
    readonly property var choices: Workspaces.workspaceChoicesForOutput(value, outputId,
        services.config ? services.config.documents.layout.workspaceCount : undefined)
    readonly property var workspaceApps: Workspaces.representativeWorkspaceApps(value, outputId)
    readonly property var active: choices.find(function(item) { return item.active; }) || null
    readonly property int activeIndex: active ? choices.indexOf(active) : -1
    readonly property bool expanded: !presentationSuppressed && (held || barRegionHovered || hover.hovered || capsule.activeFocus || focusedWorkspaceId !== "")
    readonly property color fg: Qt.alpha(Theme.tokens.text, 0.8)
    readonly property int slotSize: 32
    readonly property int slotStride: slotSize + 2
    readonly property int circleInset: 2
    readonly property int circleSize: slotSize - circleInset * 2
    property real heldProgress: held ? 1 : 0
    Behavior on heldProgress { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 240; easing.type: Easing.OutCubic } }
    readonly property real contentWidth: expanded
        ? Math.min(300, Math.max(36, choices.length * slotStride + 2)) : 36

    width: contentWidth
    height: 40
    implicitWidth: width
    implicitHeight: height
    Behavior on width { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 240; easing.type: Easing.OutCubic } }

    function activate(id) {
        if (!hyprland || !id) return;
        if (root.active && String(root.active.id) === String(id)) return;
        switchRequested(String(id));
        hyprland.focusWorkspace(String(id));
    }
    function appIconSources(workspaceId) {
        var app = workspaceApps.find(function(item) { return item.workspaceId === String(workspaceId); });
        if (!app) return [];
        // The model's list is a QML sequence, not a JS Array, and the matcher rejects anything but an Array.
        var entries = Array.from(DesktopEntries.applications.values);
        var candidates = Workspaces.matchWorkspaceDesktopEntries(app, entries);
        var entry = candidates.length ? candidates[0] : null;
        var sources = [];
        for (var c = 0; c < candidates.length; c++) {
            var icon = String(candidates[c].icon || "");
            var iconSource = "";
            if (icon.indexOf("file://") === 0) iconSource = icon;
            else if (icon.indexOf("/") === 0) iconSource = "file://" + icon;
            else if (icon) iconSource = Quickshell.iconPath(icon, true);
            if (iconSource && sources.indexOf(iconSource) < 0) sources.push(iconSource);
        }
        var command = entry ? String(entry.execString || (entry.command || []).join(" ")) : "";
        var steamId = /(?:steam_app_|rungameid\/)(\d+)/i.exec(app.appId + " " + app.appClass + " " + command);
        if (steamId) {
            var home = Quickshell.env("HOME");
            var dataHome = Quickshell.env("XDG_DATA_HOME") || (home ? home + "/.local/share" : "");
            var roots = [];
            if (dataHome) roots.push(dataHome + "/Steam/appcache/librarycache");
            if (home) roots.push(home + "/.steam/steam/appcache/librarycache");
            for (var i = 0; i < roots.length; i++)
                sources.push("file://" + roots[i] + "/" + steamId[1] + "/logo.png");
        }
        var classIcon = String(app.appClass || "").trim().toLocaleLowerCase()
            .replace(/_/g, "-").replace(/[^a-z0-9.-]/g, "");
        if (classIcon && Quickshell.hasThemeIcon(classIcon)) sources.push(Quickshell.iconPath(classIcon, true));
        sources.push(Quickshell.iconPath("preferences-system-windows-symbolic"));
        return sources;
    }
    function revealActiveWorkspace() {
        var maxScroll = Math.max(0, strip.contentWidth - strip.width);
        strip.contentX = Math.max(0, Math.min(maxScroll, strip.contentX));
        if (!root.expanded) return;
        if (!root.active) return;
        var left = root.choices.indexOf(root.active) * root.slotStride;
        if (left < strip.contentX) strip.contentX = left;
        else if (left + root.slotSize > strip.contentX + strip.width)
            strip.contentX = Math.min(maxScroll, left + root.slotSize - strip.width);
    }
    function focusSlot(slot) {
        var choice = Workspaces.workspaceChoiceAtSlot(value, outputId, slot);
        var output = value.outputs.find(function(item) {
            return item.id === String(outputId) || item.name === String(outputId);
        });
        if (choice && output && choice.monitor === output.name) activate(choice.id);
    }
    function switchBy(step) {
        if (!choices.length) return;
        var index = choices.findIndex(function(item) { return item.active; });
        if (index < 0) index = 0;
        var next = Math.max(0, Math.min(choices.length - 1, index + step));
        activate(choices[next].id);
    }
    onActiveChanged: Qt.callLater(root.revealActiveWorkspace)
    onExpandedChanged: if (expanded) Qt.callLater(root.revealActiveWorkspace)
    onChoicesChanged: if (focusedWorkspaceId && !choices.some(function(item) { return String(item.id) === focusedWorkspaceId; })) focusedWorkspaceId = ""

    Rectangle {
        id: capsule
        objectName: "workspace-capsule"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 36
        radius: Metrics.radiusPill
        color: activeFocus ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
        border.width: 0
        clip: true

        Flickable {
            id: strip
            objectName: "workspace-strip"
            anchors.fill: parent
            anchors.margins: 2
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0
            enabled: root.expanded
            onWidthChanged: root.revealActiveWorkspace()
            onContentWidthChanged: Qt.callLater(root.revealActiveWorkspace)
            Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 240; easing.type: Easing.OutCubic } }
            clip: true
            contentWidth: workspaceRow.width
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            Row {
                id: workspaceRow
                z: 1
                height: strip.height
                spacing: 2
                Repeater {
                    model: root.choices
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: root.slotSize
                        height: root.slotSize
                        readonly property bool keyboardFocused: root.focusedWorkspaceId === String(modelData.id)
                        Rectangle {
                            objectName: "workspace-slot-background-" + modelData.id
                            anchors.fill: parent
                            anchors.margins: root.circleInset
                            radius: Metrics.radiusPill
                            border.width: 0
                            color: workspaceMouse.activeFocus || parent.keyboardFocused
                                ? modelData.active ? Qt.alpha(Theme.tokens.text, 0.1) : Theme.tokens.surfaceOverlay
                                : 'transparent'
                            Behavior on color {
                                enabled: !parent.keyboardFocused && !Theme.tokens.reducedMotion
                                ColorAnimation { duration: 180; easing.type: Easing.InOutCubic }
                            }
                        }
                        Image {
                            id: workspaceIcon
                            objectName: "expanded-workspace-icon"
                            property var iconSources: root.appIconSources(modelData.id)
                            property int iconIndex: 0
                            source: iconSources.length ? iconSources[Math.min(iconIndex, iconSources.length - 1)] : ""
                            width: 22
                            height: width
                            anchors.centerIn: parent
                            opacity: 1 - 0.3 * root.heldProgress
                            layer.enabled: root.heldProgress > 0
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blurMax: 16
                                blur: 0.08 * root.heldProgress
                                saturation: -0.15 * root.heldProgress
                            }
                            scale: (workspaceMouse.containsMouse ? 1.08 : 1) * (1 - 0.08 * root.heldProgress)
                            Behavior on scale { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 240; easing.type: Easing.OutCubic } }
                            visible: String(source) !== ""
                            fillMode: Image.PreserveAspectFit
                            onIconSourcesChanged: iconIndex = 0
                            onStatusChanged: if (status === Image.Error && iconIndex + 1 < iconSources.length) iconIndex++
                        }
                        Text {
                            objectName: String(modelData.id) === "1"
                                ? "expanded-workspace-fallback" : "expanded-workspace-fallback-" + modelData.id
                            anchors.centerIn: parent
                            text: workspaceIcon.visible || root.held ? Workspaces.workspaceNumberLabel(modelData) : '•'
                            opacity: workspaceIcon.visible ? root.heldProgress : 1
                            scale: workspaceIcon.visible ? 0.8 + 0.2 * root.heldProgress : 1
                            color: parent.keyboardFocused || workspaceMouse.activeFocus || root.held
                                ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.5)
                            font.family: Qt.fontFamilies().indexOf('Google Sans Flex') >= 0 ? 'Google Sans Flex' : Theme.tokens.fontFamily
                            font.pixelSize: workspaceIcon.visible || root.held ? 17 : 14
                            font.weight: parent.keyboardFocused || workspaceMouse.activeFocus || root.held ? 700 : Font.Normal
                            renderType: Text.NativeRendering
                            Behavior on color {
                                enabled: !parent.keyboardFocused && !Theme.tokens.reducedMotion
                                ColorAnimation { duration: 180; easing.type: Easing.InOutCubic }
                            }
                        }
                        MouseArea {
                            id: workspaceMouse
                            objectName: "workspace-focus-target-" + modelData.id
                            anchors.fill: parent
                            hoverEnabled: true
                            activeFocusOnTab: true
                            onContainsMouseChanged: {
                                if (containsMouse) root.hoveredIndex = index;
                                else if (root.hoveredIndex === index) root.hoveredIndex = -1;
                            }
                            onActiveFocusChanged: {
                                if (activeFocus) root.focusedWorkspaceId = String(modelData.id);
                                else if (root.focusedWorkspaceId === String(modelData.id)) root.focusedWorkspaceId = '';
                            }
                            onClicked: root.activate(modelData.id)
                        }
                        Accessible.name: Workspaces.workspaceDescription(modelData)
                        Accessible.role: Accessible.Button
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.activate(modelData.id);
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: hoverIndicator
                objectName: "hover-workspace-indicator"
                x: root.lastHoveredIndex * root.slotStride + root.circleInset
                y: root.circleInset
                width: root.circleSize
                height: root.circleSize
                radius: Metrics.radiusPill
                color: Theme.tokens.surfaceOverlay
                opacity: root.hoveredIndex >= 0 && root.hoveredIndex !== root.activeIndex ? 1 : 0
                z: 0
                property bool seen: false
                Behavior on x {
                    enabled: hoverIndicator.seen && !Theme.tokens.reducedMotion
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }
                Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 180; easing.type: Easing.OutCubic } }
                onOpacityChanged: seen = opacity > 0
            }
            Rectangle {
                id: workspaceIndicator
                objectName: "active-workspace-indicator"
                x: Math.max(0, root.activeIndex) * root.slotStride + root.circleInset
                y: root.circleInset
                width: root.circleSize
                height: root.circleSize
                radius: Metrics.radiusPill
                color: Qt.alpha(Theme.tokens.text, 0.35)
                border.width: 0
                visible: root.activeIndex >= 0
                z: 0
                property bool motionReady: false
                Component.onCompleted: motionReady = true
                Behavior on x {
                    enabled: workspaceIndicator.motionReady && !Theme.tokens.reducedMotion
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }
            }
            WheelHandler {
                target: strip
                onWheel: function(event) {
                    var delta = event.angleDelta.y < 0 ? root.slotStride * 2 : -root.slotStride * 2;
                    strip.contentX = Math.max(0, Math.min(strip.contentWidth - strip.width, strip.contentX + delta));
                    event.accepted = true;
                }
            }
        }
        Column {
            objectName: "collapsed-face"
            anchors.centerIn: parent
            spacing: 0
            opacity: root.expanded ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.tokens.reducedMotion ? 0 : 240; easing.type: Easing.OutCubic } }
            Item {
                width: 30
                height: 24
                Text {
                    objectName: "collapsed-workspace-fallback"
                    anchors.centerIn: parent
                    text: '•'
                    color: Qt.alpha(Theme.tokens.text, 0.5)
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: 11
                    visible: !collapsedAppIcon.visible
                }
                Image {
                    id: collapsedAppIcon
                    objectName: "collapsed-workspace-icon"
                    property var iconSources: root.active ? root.appIconSources(root.active.id) : []
                    property int iconIndex: 0
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    source: iconSources.length ? iconSources[Math.min(iconIndex, iconSources.length - 1)] : ""
                    visible: String(source) !== ""
                    fillMode: Image.PreserveAspectFit
                    onIconSourcesChanged: iconIndex = 0
                    onStatusChanged: if (status === Image.Error && iconIndex + 1 < iconSources.length) iconIndex++
                }
            }
        }
        MouseArea {
            id: capsuleMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !root.expanded
            onClicked: if (root.active) root.activate(root.active.id)
            onWheel: function(event) {
                if (!root.choices.length) return;
                var index = root.choices.findIndex(function(item) { return item.active; });
                var step = event.angleDelta.y < 0 ? 1 : -1;
                var next = Math.max(0, Math.min(root.choices.length - 1, index + step));
                root.activate(root.choices[next].id);
                event.accepted = true;
            }
        }
        activeFocusOnTab: true
        Keys.onPressed: function(event) {
            if (root.held && event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                root.focusSlot(event.key - Qt.Key_0);
                event.accepted = true;
            } else if (event.key === Qt.Key_Left) {
                root.switchBy(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                root.switchBy(1);
                event.accepted = true;
            }
        }
        Accessible.name: root.active ? Workspaces.workspaceLabel(root.active) : 'Workspace switcher'
        Accessible.role: Accessible.Grouping
    }
    HoverHandler { id: hover; parent: capsule }
}
