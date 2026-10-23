import QtQuick
import QtQml

// Every piece of Stash UI state lives here, not in a window, so the Stash can switch between
// the layer-shell overlay and a normal toplevel without losing the search, the filter, the
// selection, an unsent draft or the scroll position. Views and window frames only bind to it.
QtObject {
    id: root
    required property var config
    property bool preview: false
    property bool safeMode: false

    readonly property bool writable: !preview && !safeMode && !config.preview
    // 'overlay' (centered layer-shell panel) or 'window' (tiling toplevel), from interface.stashWindow.
    readonly property string mode: config.documents && config.documents.interface
        && config.documents.interface.stashWindow === 'window' ? 'window' : 'overlay'

    property bool visible: false
    property string query: ''
    // 'all' | 'file' | 'photo' | 'link' | 'text'
    property string filter: 'all'
    // Entry ids; always reassign the array so bindings see the change.
    property var selectedIds: []
    property string selectionAnchor: ''
    property string draft: ''
    property real contentY: 0
    // Section ids whose photo strip is expanded into a grid.
    property var expandedDays: []
    // True while a native drag-out runs; the overlay lets input through until it ends.
    property bool exporting: false

    // show() was called while a toplevel window is already open: raise and focus it.
    signal focusRequested

    function show() {
        if (root.visible) {
            if (root.mode === 'window')
                root.focusRequested();
            return;
        }
        root.visible = true;
    }

    function hide() {
        root.visible = false;
    }

    // An open toplevel window is focused, not hidden: in 'window' mode the shortcut raises it.
    function toggle() {
        if (root.visible && root.mode === 'window')
            root.focusRequested();
        else if (root.visible)
            root.hide();
        else
            root.show();
    }

    // Saves the whole interface document with the new mode. The window frame follows `mode`
    // once the config store confirms the write; `visible` and the rest of the state stay as they are.
    function setMode(next) {
        if (!root.writable || (next !== 'overlay' && next !== 'window'))
            return false;
        if (next === root.mode)
            return true;
        const current = root.config.documents.interface || {};
        return root.config.save('interface', Object.assign({}, current, {
            stashWindow: next
        })) !== '';
    }

    function selectOnly(id) {
        const value = id === undefined || id === null ? '' : String(id);
        root.selectedIds = value ? [value] : [];
        root.selectionAnchor = value;
    }

    function clearSelection() {
        root.selectedIds = [];
        root.selectionAnchor = '';
    }
}
