import QtQuick

// Thumbnails and file icons for the sidebar tools, produced by the same helper as the Stash.
// Callers ask for URIs they show; the most recent 40 stay resolved.
QtObject {
    id: root
    required property string helperPath
    property var wanted: []
    readonly property var metadata: files.metadata
    function want(uris) {
        const fresh = (uris || []).filter(uri => typeof uri === 'string' && uri.startsWith('file://') && root.wanted.indexOf(uri) < 0);
        if (!fresh.length) return;
        wanted = wanted.concat(fresh).slice(-40);
        files.entries = wanted.map(uri => ({ uri: uri }));
    }
    property ShelfFiles files: ShelfFiles { helperPath: root.helperPath }
}
