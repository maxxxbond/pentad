pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components
import qs.features.keyhint
import '../logic/keybind-hints.mjs' as KeybindHints

// The submap hint: while a Hyprland submap (key mode) is active, a calm strip near the bottom
// centre of the focused output lists its binds. No submap, no window. The user is in the middle
// of using the submap, so the strip never takes the keyboard and every click passes through it.
// It gives way to the cheatsheet card, which lists the submaps itself, and to a screenshot, and
// comes back afterwards while the submap is still active.
Loader {
    id: host
    required property var services
    readonly property string submapName: services.submap ? services.submap.name : ''
    readonly property bool cheatsheetOpen: !!services.cheatsheet && services.cheatsheet.open
    readonly property bool capturing: !!services.screenshot && services.screenshot.active
    // Set when a screenshot is about to be taken or the compositor closed the surface (its output
    // went away); the end of the screenshot or another submap brings the strip back.
    property bool suspended: false
    readonly property var overlay: item
    // A submap that is entered and left at once (a leader key) never shows the strip.
    property bool due: false
    // A submap whose only bind is its way out (the pass-through idiom for games, VMs and remote
    // desktops) has nothing to hint at, and would otherwise sit over a fullscreen window for hours.
    readonly property var bindState: services.keybinds ? services.keybinds.state : null
    readonly property bool exitOnly: submapName !== '' && !!bindState && bindState.kind === 'ready' && !!bindState.value
        && KeybindHints.submapHint(bindState.value.groups, submapName).total === 1

    onCapturingChanged: if (!capturing)
        suspended = false
    onSubmapNameChanged: {
        suspended = false;
        if (submapName === '')
            due = false;
    }

    active: submapName !== '' && due && !exitOnly && !cheatsheetOpen && !capturing && !suspended
    property Timer showDelay: Timer {
        interval: Motion.mediumDuration
        running: host.submapName !== '' && !host.due
        onTriggered: host.due = true
    }
    property Connections captureEvents: Connections {
        target: host.services.popups || null
        enabled: host.submapName !== ''
        // A screenshot must not show the strip; it steps aside the way the cheatsheet does.
        function onCapturePreparing() {
            host.suspended = true;
        }
    }

    sourceComponent: Component {
        PanelWindow {
            id: window
            readonly property var services: host.services
            readonly property alias frame: card
            readonly property alias view: hintView
            readonly property real maxWidth: Math.max(1, Math.min(720, window.width - 2 * Metrics.space4))

            anchors {
                left: true
                right: true
                bottom: true
            }
            // Reserves no space, and a bottom bar's exclusive zone still lifts it clear of that bar.
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            // The card sits Metrics.overlayShadowRoom above the bottom edge; the room also keeps its shadow.
            implicitHeight: card.height + 2 * Metrics.overlayShadowRoom
            color: 'transparent'
            // No input region: every click and scroll goes to what is underneath.
            mask: Region {}
            WlrLayershell.namespace: 'pentad-submap-hint'
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            onClosed: host.suspended = true
            // Opens on the focused output and stays there for as long as the submap is active.
            Component.onCompleted: window.screen = window.focusedScreen()

            function focusedScreen() {
                const state = window.services.hyprland ? window.services.hyprland.state : null;
                const outputs = state && state.kind === 'ready' ? state.value.outputs : [];
                const focused = outputs.find(output => output.id === state.value.focusedOutputId);
                return Quickshell.screens.find(screen => !!focused && screen.name === focused.name) || null;
            }

            Item {
                id: card
                objectName: 'submap-hint-frame'
                // 0 → 1 as the strip fades and rises in; instant with reduced motion.
                property real reveal
                NumberAnimation on reveal {
                    from: 0
                    to: 1
                    duration: Motion.short
                    easing.type: Motion.easeEnter
                }
                x: Math.round((window.width - width) / 2)
                y: Metrics.overlayShadowRoom + Math.round((1 - reveal) * Metrics.space2)
                width: Math.max(1, Math.min(hintView.implicitWidth, window.maxWidth))
                height: Math.max(1, hintView.implicitHeight)
                opacity: reveal
                ContinuousSurface {
                    anchors.fill: parent
                    fill: Theme.tokens.surface
                    extent: Metrics.radiusPopover
                    castsShadow: true
                    clipContent: false
                }
                SubmapHintView {
                    id: hintView
                    anchors.fill: parent
                    services: window.services
                    maxWidth: window.maxWidth
                }
            }
        }
    }
}
