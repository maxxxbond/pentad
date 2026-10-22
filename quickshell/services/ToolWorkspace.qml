import QtQuick

QtObject {
    id: root
    property string selectedTool: ''
    property string searchQuery: ''
    property string catalogView: 'all'
    property string catalogCategory: ''
    property real catalogScrollY: 0
    property var drafts: ({})
    property var favorites: []
    property var recent: []
    property var pendingInput: null
    property string ingressMessage: ''
    // Set by a drop on a quick-action tile: the tool that receives the input selects this action.
    property var preset: null
    // Native drags of tool results currently in progress; the drawer stays open while any run.
    property int exports: 0
    function takePreset(id) {
        if (!preset || preset.toolId !== id) return null;
        const value = preset;
        preset = null;
        return value;
    }

    function selectTool(id, preserveInput) {
        selectedTool = id;
        recent = [id].concat(recent.filter(function(value) { return value !== id; })).slice(0, 8);
        if (!preserveInput) pendingInput = null;
        ingressMessage = '';
    }
    function draftFor(id) { return Object.prototype.hasOwnProperty.call(drafts, id) ? drafts[id] : ''; }
    function setDraft(id, value) { drafts = Object.assign({}, drafts, { [id]: value }); }
    function toggleFavorite(id) {
        favorites = favorites.indexOf(id) >= 0 ? favorites.filter(function(value) { return value !== id; }) : favorites.concat([id]);
    }
    function receive(value, compatibleIds, targetId) {
        if (!targetId) selectedTool = '';
        ingressMessage = '';
        pendingInput = { value: value, compatibleIds: compatibleIds, targetId: targetId || '' };
    }
    function clearIngress() { pendingInput = null; }
}
