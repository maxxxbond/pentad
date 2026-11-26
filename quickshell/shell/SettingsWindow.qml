import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components
import "../features/settings"
import "../logic/settings-state.mjs" as State

PanelWindow {
    id: window
    required property var services
    screen: {
        const state = services.hyprland.state;
        const outputs = state.kind === 'ready' ? state.value.outputs : [];
        const focused = outputs.find(output => state.kind === 'ready' && output.id === state.value.focusedOutputId);
        return Quickshell.screens.find(output => focused && output.name === focused.name) || Quickshell.screens[0] || null;
    }
    visible: services.settings.open
    onVisibleChanged: {
        services.popups.hostVisibility('settings', visible);
        if (visible) card.forceActiveFocus();
    }
    Component.onDestruction: services.popups.hostVisibility('settings', false)
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: 'transparent'
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: 'pentad-settings'
    WlrLayershell.layer: WlrLayer.Overlay
    // While a screenshot is being taken or edited, the keyboard belongs to the screenshot overlay.
    WlrLayershell.keyboardFocus: visible && !(services.screenshot && services.screenshot.active)
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function dismiss() {
        const settings = window.services.settings;
        if (settings.widgetId !== '') {
            settings.closeWidget();
        } else if (settings.flow !== '') {
            if (typeof settings.closeFlow === 'function') settings.closeFlow();
            else settings.flow = '';
        } else {
            settings.close();
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea {
            anchors.fill: parent
            onClicked: card.forceActiveFocus()
        }
    }
    ContinuousSurface {
        id: card
        anchors.centerIn: parent
        width: Math.max(1, Math.min(960, parent.width - 32))
        height: Math.max(1, Math.min(640, parent.height - 32))
        fill: Theme.tokens.surface
        extent: Metrics.radiusPopover
        // A floating surface, like the other full-window overlays: it lifts off the scrim.
        castsShadow: true
        focus: true
        Keys.onEscapePressed: window.dismiss()

        Keys.onPressed: function(event) {
            // "/" focuses the sidebar search when no text field consumed it.
            if (event.key === Qt.Key_Slash && event.modifiers === Qt.NoModifier) {
                sidebar.focusSearch();
                event.accepted = true;
            }
        }

        SettingsSidebar {
            id: sidebar
            x: 0
            y: 0
            z: 5
            width: preferredWidth
            height: parent.height
            services: window.services
            collapsed: card.width < 720
            badges: ({ widgets: State.enabledWidgetCount(window.services.config.documents) })
        }
        Item {
            id: content
            x: sidebar.width
            y: 0
            width: parent.width - x
            height: parent.height
            SettingsPage {
                anchors.fill: parent
                visible: window.services.settings.query === '' && window.services.settings.widgetId === ''
                services: window.services
            }
            Loader {
                anchors.fill: parent
                active: window.services.settings.query === '' && window.services.settings.widgetId !== ''
                sourceComponent: WidgetSettings {
                    services: window.services
                    instanceId: window.services.settings.widgetId
                    onBack: window.services.settings.closeWidget()
                }
            }
            SettingsSearchResults {
                anchors.fill: parent
                visible: window.services.settings.query !== ''
                services: window.services
            }
        }
        Loader {
            anchors.fill: parent
            active: window.services.settings.flow === 'add-widget'
            onActiveChanged: if (!active) card.forceActiveFocus()
            sourceComponent: AddWidgetSheet { services: window.services }
        }
    }
    // Opening: the scrim fades in while the card settles from a slightly smaller scale. Opacity and
    // scale only, and the resting values are the defaults, so nothing depends on the animation running.
    ParallelAnimation {
        id: openReveal
        NumberAnimation {
            target: scrim
            property: "opacity"
            from: 0
            to: 1
            duration: Motion.reveal
            easing.type: Motion.easeEnter
        }
        NumberAnimation {
            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: Motion.reveal
            easing.type: Motion.easeEnter
        }
        NumberAnimation {
            target: card
            property: "scale"
            from: 0.98
            to: 1
            duration: Motion.reveal
            easing.type: Motion.easeEnter
        }
    }
    Component.onCompleted: {
        card.forceActiveFocus();
        if (!Motion.reducedMotion) openReveal.start();
    }
}
