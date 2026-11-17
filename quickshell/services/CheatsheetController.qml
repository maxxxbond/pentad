import QtQuick
import QtQml
import '../logic/keybinds.mjs' as KeybindsLogic
import '../logic/cheatsheets.mjs' as CheatsheetsLogic

// The keybind cheatsheet's UI state lives here, not in its window: the host creates the overlay
// only while `open` is true, and the view binds to the query, the filters and the choices.
// "Show all" and the list or keyboard view outlive the window (in memory only); the query and the
// filters start empty on every opening and whenever the sheet changes.
QtObject {
    id: root
    // services.hyprland, read once per opening for the focused window; null in fixtures.
    property var hyprland: null
    property bool open: false
    property string query: ''
    property string sheet: 'live'
    // Also list the Lua binds that have no description, which have nothing to read but their keys.
    property bool showAll: false
    // 'list' or 'keys' (the keyboard map above the list).
    property string view: 'list'
    // Modifier names in KeybindsLogic.MODIFIER_NAMES order. The list keeps the binds that use all
    // of them; the keyboard map shows exactly this layer.
    property var mods: []
    // A key's label from the keyboard map ('Q', '/'); the list keeps the binds on that key.
    property string key: ''
    // Only the binds whose trigger also fires another action (live bindings only).
    property bool duplicates: false
    // The reference that fits the window that had focus when the cheatsheet opened, or ''.
    property string contextSheet: ''
    // How views draw the Super key: 'pentad' or 'tux' (a logo) or 'text' (the word "Super"), from
    // interface.superKeyLogo. Services binds it and passes nothing but these three values.
    property string superKeyLogo: 'pentad'

    function selectSheet(id) {
        if (['live'].concat(CheatsheetsLogic.sheetIds()).indexOf(id) < 0 || root.sheet === id)
            return;
        root.resetFilters();
        root.sheet = id;
    }

    function setView(value) {
        if (value === 'list' || value === 'keys')
            root.view = value;
    }

    // Keeps the known modifier names of `list`, once each, in display order.
    function setMods(list) {
        const wanted = Array.isArray(list) ? list : [];
        root.mods = KeybindsLogic.MODIFIER_NAMES.filter(name => wanted.indexOf(name) >= 0);
    }

    function toggleModifier(name) {
        const held = root.mods.indexOf(name) >= 0;
        root.setMods(held ? root.mods.filter(item => item !== name) : root.mods.concat([name]));
    }

    // The same key again clears the key filter.
    function toggleKey(label) {
        const value = typeof label === 'string' ? label.trim().slice(0, 32) : '';
        root.key = value === '' || value.toLowerCase() === root.key.toLowerCase() ? '' : value;
    }

    // What Esc clears before it closes: the query, the key filter and the duplicates filter.
    readonly property bool clearable: root.query !== '' || root.key !== '' || root.duplicates

    function clearSearch() {
        root.query = '';
        root.key = '';
        root.duplicates = false;
    }

    function resetFilters() {
        root.clearSearch();
        root.mods = [];
    }

    function focusedSheet() {
        const hyprland = root.hyprland;
        // Preview shows fixtures only and never asks the compositor.
        if (!hyprland || hyprland.preview)
            return '';
        const active = hyprland && typeof hyprland.activeWindow === 'function' ? hyprland.activeWindow() : null;
        if (!active)
            return '';
        // The title comes with the snapshot Hyprland already keeps; it names Neovim inside a terminal.
        const state = hyprland.state;
        const title = state && state.kind === 'ready' && state.value && typeof state.value.activeTitle === 'string' ? state.value.activeTitle : '';
        return CheatsheetsLogic.sheetForWindow(active.class, title);
    }

    function show() {
        if (root.open)
            return;
        // Read before the overlay takes the keyboard from that window.
        root.contextSheet = root.focusedSheet();
        root.resetFilters();
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
