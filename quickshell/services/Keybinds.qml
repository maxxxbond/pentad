pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import '../logic/keybinds.mjs' as KeybindsLogic
import '../logic/keybinds-sample.mjs' as KeybindsSample

// Hyprland's key bindings for the cheatsheet and the submap hint. `hyprctl binds -j` runs only on
// demand: each time the cheatsheet opens or a submap becomes active (`active` turns true) and when
// Hyprland reloads its config meanwhile. Between uses the last list stays, so the next one shows
// it at once while it is read again.
// Preview mode shows a built-in sample and never runs hyprctl. Safe mode still reads the list:
// the command only reports, it changes nothing.
QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    // True while the cheatsheet is open or a Hyprland submap is active.
    property bool active: false
    // The reader's command. Fixtures point it at other programs (a missing one, `false`, printf)
    // so that they never run hyprctl; nothing else changes it.
    property var command: ['hyprctl', 'binds', '-j']
    // { kind: 'loading' | 'ready' | 'unavailable', value: { groups, total, truncated } | null, reason }
    property var state: ({ kind: 'loading', value: null, reason: '' })
    // Why the last read failed while an older list stayed on screen; '' after a good read.
    property string lastError: ''
    property bool pending: false
    property bool startedOnce: false
    property bool settled: true

    onActiveChanged: if (active) refresh()
    onPreviewChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()
    Component.onDestruction: {
        root.deadline.stop();
        if (root.reader.running)
            root.reader.signal(9);
    }

    function refresh() {
        if (root.preview) {
            root.accept(KeybindsLogic.parseBinds(KeybindsSample.SAMPLE_BINDS));
            return;
        }
        if (root.reader.running) {
            root.pending = true;
            return;
        }
        root.pending = false;
        root.startedOnce = false;
        root.settled = false;
        root.reader.command = root.command;
        root.reader.running = true;
        root.deadline.restart();
    }

    function accept(parsed) {
        if (parsed.error) {
            root.fail(parsed.error);
            return;
        }
        root.lastError = '';
        root.state = { kind: 'ready', value: { groups: parsed.groups, total: parsed.total, truncated: parsed.truncated }, reason: '' };
    }

    // A failed re-read keeps the list that is already shown; only a first read turns unavailable.
    function fail(reason) {
        root.lastError = reason;
        if (root.state.kind === 'ready')
            return;
        root.state = { kind: 'unavailable', value: null, reason: reason };
    }

    function settle(ok, reason) {
        if (root.settled)
            return;
        root.settled = true;
        root.deadline.stop();
        if (ok) {
            const text = output.text || '';
            if (text.length > KeybindsLogic.MAX_INPUT_LENGTH)
                root.fail('too-large');
            else
                root.accept(KeybindsLogic.parseBinds(text));
        } else {
            root.fail(reason);
        }
        if (root.pending && root.active)
            Qt.callLater(root.refresh);
    }

    property Process reader: Process {
        stdout: StdioCollector {
            id: output
        }
        stderr: StdioCollector {}
        onStarted: root.startedOnce = true
        // A program that cannot start never reports `started`; that is a missing hyprctl.
        onRunningChanged: {
            if (!running && !root.startedOnce)
                root.settle(false, 'missing');
        }
        onExited: function (code, status) {
            root.settle(code === 0 && status === 0, 'failed');
        }
    }

    property Timer deadline: Timer {
        interval: 5000
        onTriggered: {
            if (root.reader.running)
                root.reader.signal(9);
            root.settle(false, 'timeout');
        }
    }

    // A config reload can change every bind; while active it reads them again.
    property Connections configEvents: Connections {
        target: Hyprland
        enabled: root.active && !root.preview
        function onRawEvent(event) {
            if (event && event.name === 'configreloaded')
                root.refresh();
        }
    }
}
