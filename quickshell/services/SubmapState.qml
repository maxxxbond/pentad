import QtQuick
import QtQml
import Quickshell.Hyprland
import '../logic/keybind-hints.mjs' as KeybindHints

// The Hyprland submap (key mode) that is active right now, for the submap hint. Hyprland's event
// socket reports `submap>>NAME` on every change and an empty NAME on a reset; the name comes from
// the user's config, so it is kept as clipped plain text. Preview mode never subscribes, and
// fixtures set `name` directly. Safe mode still listens: the event only reports.
QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    // '' while no submap is active.
    property string name: ''

    property Connections events: Connections {
        target: root.preview ? null : Hyprland
        function onRawEvent(event) {
            if (event && event.name === 'submap')
                root.name = KeybindHints.submapName(event.data);
        }
    }
}
