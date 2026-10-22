import QtQuick
import Quickshell.Io

// Opens the desktop's own file chooser (xdg-desktop-portal, else zenity) through
// tools/pentad_pick_files.py. The drawer is a layer above normal windows, so it hides while
// the chooser is open and returns afterwards; chosen files land in ToolWorkspace.picked,
// which the sidebar consumes even if it was rebuilt meanwhile.
QtObject {
    id: root
    required property string helperPath
    property var popups: null
    property var workspace: null
    property var request: null
    // Set on request, not on process start, so controls disable immediately.
    property bool busy: false
    function pick(options) {
        if (busy) return false;
        busy = true;
        process.startedOnce = false;
        request = options || {};
        if (popups && request.outputId && popups.isOpen('left', request.outputId)) popups.closeSurface('left', request.outputId);
        process.running = true;
        return true;
    }
    function cancel() { if (process.running) process.signal(15); }
    property Process process: Process {
        command: ['python3', '-I', root.helperPath]
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        property bool startedOnce: false
        // A helper that never starts gets no exit: bring the drawer back and release the controls.
        onRunningChanged: if (!running && !startedOnce && root.busy) {
            if (root.popups && root.request && root.request.outputId) root.popups.open('left', root.request.outputId);
            if (root.workspace) root.workspace.ingressMessage = 'Could not start the file chooser.';
            root.request = null;
            root.busy = false;
        }
        onStarted: {
            startedOnce = true;
            write(JSON.stringify({ title: root.request.title || 'Choose files', multiple: root.request.multiple !== false,
                filters: root.request.filters || [] }));
            stdinEnabled = false;
        }
        onExited: function(code, status) {
            let result;
            try { result = JSON.parse(stdout.text || '{}'); }
            catch (error) { result = { ok: false, reason: 'The file chooser returned invalid data.' }; }
            const request = root.request || {};
            if (root.popups && request.outputId) root.popups.open('left', request.outputId);
            if (root.workspace) {
                if (result.ok && result.uris && result.uris.length)
                    root.workspace.picked = { uris: Array.prototype.slice.call(result.uris), targetId: request.targetId || '', choice: request.choice || '' };
                else if (!result.ok && !result.cancelled) root.workspace.ingressMessage = result.reason || 'The file chooser failed.';
            }
            stdinEnabled = true;
            root.request = null;
            root.busy = false;
        }
    }
}
