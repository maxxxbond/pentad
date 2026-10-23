import QtQuick
import QtTest
import Quickshell
import qs.shell

// SpotlightHost builds its search UI only while shown: hidden it holds no content, opening builds it
// and focuses the query field, and closing releases it. Query and results live in the service.
ShellRoot {
    id: root
    property var checks: []
    property int step: 0
    property TestEvent input: TestEvent {}
    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || '' });
    }
    property QtObject spotlight: QtObject {
        property bool visible: false
        property string outputName: ''
        property string query: ''
        property string page: 'results'
        property var results: []
        property int selectedIndex: 0
        readonly property var selectedResult: results[selectedIndex] || null
        property var actions: []
        property int actionIndex: 0
        property bool pending: false
        property bool searchPending: false
        property var history: ({ pinned: [] })
        property string previewImage: ''
        property string selectionImage: ''
        property string error: ''
        property string status: ''
        property int closed: 0
        function group(result) { return result ? result.category : ''; }
        function primaryLabel(result) { return 'Open'; }
        function pointerHover(hovered) {}
        function open() {
            query = ''; page = 'results'; selectedIndex = 0; results = [];
            outputName = Quickshell.screens[0].name;
            visible = true;
        }
        function close() { visible = false; query = ''; results = []; selectedIndex = 0; closed++; }
        function back() { if (page === 'results') return false; page = 'results'; return true; }
        function move(delta) { selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta)); }
        function showActions() { page = page === 'actions' ? 'results' : 'actions'; }
        function showDetails() {}
        function pin() {}
        function activate() {}
        function runAction() {}
    }
    property QtObject services: QtObject {
        property var spotlight: root.spotlight
        property var popups: QtObject {
            property var shown: ({})
            function hostVisibility(key, visible) {
                const next = Object.assign({}, shown);
                next[key] = visible;
                shown = next;
            }
        }
        property var config: QtObject { property var documents: ({ layout: { barHeight: 40 } }) }
        function text(uk, en) { return en; }
    }
    SpotlightHost {
        id: host
        services: root.services
    }
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            const s = root.step++;
            if (s === 0) {
                root.check('hidden-spotlight-builds-no-content', !host.visible && host.search === null && host.emojiGrid === null);
                root.spotlight.open();
            } else if (s === 1) {
                root.check('open-builds-content-and-focuses-query', host.visible && !!host.search && host.search.activeFocus
                    && root.services.popups.shown.spotlight === true,
                    JSON.stringify({ visible: host.visible, search: !!host.search, focus: !!host.search && host.search.activeFocus }));
                root.check('query-key-dispatched', root.input.keyClick(Qt.Key_F, Qt.NoModifier, 0));
            } else if (s === 2) {
                root.check('typing-updates-service-query', root.spotlight.query === 'f' && host.search.text === 'f',
                    JSON.stringify({ query: root.spotlight.query, text: host.search ? host.search.text : null }));
                root.spotlight.results = [
                    { id: 'emoji-fire', category: 'emoji', title: 'fire', subtitle: 'fire', preview: { content: '🔥' } },
                    { id: 'emoji-star', category: 'emoji', title: 'star', subtitle: 'star', preview: { content: '⭐' } }
                ];
                root.spotlight.query = ':f';
            } else if (s === 3) {
                root.check('service-query-shows-emoji-grid', host.emojiMode && !!host.emojiGrid && host.emojiGrid.visible
                    && host.search.text === ':f');
                root.check('arrow-key-dispatched', root.input.keyClick(Qt.Key_Right, Qt.NoModifier, 0));
                root.check('arrow-moves-emoji-selection', root.spotlight.selectedIndex === 1);
                root.check('escape-key-dispatched', root.input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0));
            } else if (s === 4) {
                root.check('escape-closes-and-releases-content', !host.visible && root.spotlight.closed === 1
                    && host.search === null && host.emojiGrid === null && root.services.popups.shown.spotlight === false);
                root.spotlight.open();
            } else if (s === 5) {
                root.check('reopen-rebuilds-and-focuses-empty-query', host.visible && !!host.search && host.search.activeFocus
                    && host.search.text === '');
                root.check('outside-click-dispatched', root.input.mouseClick(host.contentItem, 8, host.height - 8,
                    Qt.LeftButton, Qt.NoModifier, 0));
            } else {
                root.check('outside-click-closes', !host.visible && root.spotlight.closed === 2 && host.search === null);
                console.log('PENTAD_TEST ' + JSON.stringify({
                    status: root.checks.every(function(check) { return check.passed; }) ? 'pass' : 'fail',
                    checks: root.checks
                }));
                stop();
                Qt.quit();
            }
        }
    }
}
