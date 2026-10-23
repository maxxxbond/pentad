pragma ComponentBehavior: Bound
import QtQuick

// Shows the Stash in the frame interface.stashWindow asks for: the centered overlay or a normal
// window. The view's state lives in services.stash, so swapping the frame keeps the search, the
// filter, the selection and an unsent draft. A closed Stash has no window at all.
Loader {
    id: host
    required property var services
    readonly property var stash: services.stash

    // The header's detach/attach button. `visible` stays true, so the Loader swaps the frame.
    function switchMode() {
        return host.stash.setMode(host.stash.mode === 'overlay' ? 'window' : 'overlay');
    }

    sourceComponent: !stash.visible ? null : stash.mode === 'window' ? floatingFrame : overlayFrame

    Component {
        id: overlayFrame
        StashOverlayWindow {
            services: host.services
            onDetachRequested: host.switchMode()
        }
    }
    Component {
        id: floatingFrame
        StashFloatingWindow {
            services: host.services
            onDetachRequested: host.switchMode()
        }
    }
}
