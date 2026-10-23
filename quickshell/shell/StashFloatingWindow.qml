import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.features.shelf

// The Stash as a normal application window: it tiles like any other window and stays open
// until it is closed. Closing it hides the Stash and keeps the window mode for next time.
FloatingWindow {
    id: window
    required property var services
    readonly property var stash: services.stash
    readonly property string kind: 'window'
    readonly property alias view: stashView
    // This window's entry in the compositor's toplevel list, where the compositor offers one.
    readonly property var toplevel: ToplevelManager.toplevels.values.find(item => item.appId === Quickshell.appId && item.title === window.title) || null
    signal detachRequested

    visible: true
    title: services.text('Сховок', 'Stash')
    implicitWidth: 520
    implicitHeight: 640
    minimumSize: Qt.size(400, 360)
    color: Theme.tokens.surface
    onClosed: window.stash.hide()

    // The shortcut or IPC opened a Stash that is already open: bring the window forward. A
    // foreign-toplevel activation focuses it on wlroots-style compositors such as Hyprland; Qt's
    // own request needs an activation token, which a global shortcut does not carry.
    function bringForward() {
        if (window.minimized)
            window.minimized = false;
        if (window.toplevel)
            window.toplevel.activate();
        else if (stashView.Window.window)
            stashView.Window.window.requestActivate();
        stashView.forceActiveFocus();
    }

    Connections {
        target: window.stash
        function onFocusRequested() {
            window.bringForward();
        }
    }
    StashView {
        id: stashView
        anchors.fill: parent
        services: window.services
        focus: true
        onCloseRequested: window.stash.hide()
        onDetachRequested: window.detachRequested()
    }
}
