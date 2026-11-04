import QtQuick
import QtQml

// The keybind cheatsheet's UI state lives here, not in its window: the host creates the overlay
// only while `open` is true, and the view binds to the query and the "Show all" choice. The
// choice outlives the window; the query starts empty on every opening.
QtObject {
    id: root
    property bool open: false
    property string query: ''
    // Also list the Lua binds that have no description, which have nothing to read but their keys.
    property bool showAll: false

    function show() {
        if (root.open)
            return;
        root.query = '';
        root.open = true;
    }

    function hide() {
        root.open = false;
    }

    function toggle() {
        if (root.open)
            root.hide();
        else
            root.show();
    }
}
