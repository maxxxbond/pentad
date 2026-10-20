import QtQuick
import Quickshell
import "../shell" as Shell

ShellRoot {
    id: root
    property var checks: []
    property QtObject spotlight: QtObject {
        property var results: [
            { category: 'emoji', title: 'fire', subtitle: 'fire', preview: { content: '🔥' } },
            { category: 'emoji', title: 'star', subtitle: 'star', preview: { content: '⭐' } }
        ]
        property int selectedIndex: 0
        readonly property var selectedResult: results[selectedIndex]
        property bool pending: false
        property bool searchPending: false
        function activate(index) {}
        function showActions() {}
    }
    property QtObject services: QtObject {
        function text(uk, en) { return en; }
    }
    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || '' }); }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    FloatingWindow {
        visible: true
        implicitWidth: 640
        implicitHeight: 420
        Shell.SpotlightEmojiGrid {
            id: grid
            width: 600
            height: 340
            spotlight: root.spotlight
            services: root.services
        }
    }
    Timer {
        id: steps
        property int phase: 0
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            if (phase === 0) {
                root.check('wide-grid-shows-preview', grid.wide && grid.showPreview);
                grid.width = 360;
                grid.height = 396;
                phase = 1;
            } else {
                root.check('narrow-grid-shows-preview', !grid.wide && grid.showPreview);
                console.log('PENTAD_TEST ' + JSON.stringify({
                    status: root.checks.every(function (item) { return item.passed; }) ? 'pass' : 'fail',
                    checks: root.checks
                }));
                stop();
                Qt.quit();
            }
        }
    }
}
