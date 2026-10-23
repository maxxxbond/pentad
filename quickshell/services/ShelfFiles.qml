import QtQuick
import Quickshell.Io
import '../logic/shelf.mjs' as ShelfLogic

QtObject {
    id: root
    property var entries: []
    property string helperPath: ''
    property bool enabled: true
    property var metadata: ({})
    property int generation: 0
    property int runningGeneration: -1
    property var requestedUris: []
    // The helper runs once per chunk, in the order of `entries`, so the first rows get their metadata first.
    readonly property int chunkSize: 50
    property int chunkStart: 0
    onEntriesChanged: refresh()
    onEnabledChanged: refresh()
    onHelperPathChanged: refresh()
    function refresh() { generation++; debounce.restart(); }
    property Timer debounce: Timer {
        interval: 80
        onTriggered: {
            if (!root.enabled || !root.helperPath) return;
            if (worker.running) return;
            root.requestedUris = root.entries.map(ShelfLogic.shelfLocalUri).filter(uri => !!uri);
            const retained = {};
            for (const uri of root.requestedUris) if (root.metadata[uri]) retained[uri] = root.metadata[uri];
            root.metadata = retained;
            if (!root.requestedUris.length) return;
            root.runningGeneration = root.generation;
            root.chunkStart = 0;
            root.startChunk();
        }
    }
    function startChunk() {
        worker.stdinEnabled = true;
        worker.running = true;
    }
    property Process worker: Process {
        command: ['python3', root.helperPath]
        stdinEnabled: true
        onStarted: {
            watchdog.restart();
            write(JSON.stringify({ uris: root.requestedUris.slice(root.chunkStart, root.chunkStart + root.chunkSize) }));
            stdinEnabled = false;
        }
        stdout: SplitParser {
            onRead: line => {
                if (root.runningGeneration !== root.generation) return;
                try {
                    const item = JSON.parse(line);
                    if (root.requestedUris.indexOf(item.uri) >= 0)
                        root.metadata = Object.assign({}, root.metadata, { [item.uri]: item });
                } catch (error) {  }
            }
        }
        onExited: {
            watchdog.stop();
            if (root.runningGeneration !== root.generation) { debounce.restart(); return; }
            root.chunkStart += root.chunkSize;
            if (root.chunkStart < root.requestedUris.length) nextChunk.restart();
        }
    }
    property Timer nextChunk: Timer {
        interval: 0
        onTriggered: {
            if (root.enabled && root.helperPath && !worker.running && root.runningGeneration === root.generation) root.startChunk();
        }
    }
    property Timer watchdog: Timer {
        interval: 15000
        onTriggered: if (worker.running) worker.signal(9)
    }
    Component.onDestruction: {
        debounce.stop(); nextChunk.stop(); watchdog.stop();
        if (worker.running) worker.signal(9);
    }
}
