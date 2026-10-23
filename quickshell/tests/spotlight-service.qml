import QtQuick
import Quickshell
import "../services" as Native

// The real Spotlight service with its Python helper, bundled emoji data and file search.
ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    property int waited: 0
    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || '' }); }
    function summary() {
        const first = spotlight.results[0];
        return JSON.stringify({ error: spotlight.error, pending: spotlight.searchPending, count: spotlight.results.length,
            categories: spotlight.results.map(item => item.category).filter((item, index, all) => all.indexOf(item) === index),
            first: first ? { category: first.category, title: first.title } : null });
    }
    property QtObject services: QtObject {
        property bool preview: false
        property bool safeMode: false
        property var hyprland: ({ state: { kind: 'ready', value: { outputs: [], focusedOutputId: '' } } })
        property QtObject popups: QtObject {
            property string surface: ''
            signal changed()
            signal capturePreparing()
            function close() {}
        }
        property QtObject navigation: QtObject {
            property bool active: false
            function cancel() {}
        }
        property QtObject config: QtObject {
            readonly property string helperPath: Quickshell.env('XDG_CONFIG_HOME') + '/quickshell-fixture/helpers/pentad-files.py'
            readonly property string stateRoot: Quickshell.env('XDG_STATE_HOME') + '/pentad'
            property var documents: ({ interface: { language: 'uk' }, spotlight: { emoji: { languages: ['uk', 'en'] } }, layout: { barHeight: 40 } })
            signal documentChanged(string name)
        }
        function text(uk, en) { return uk; }
    }
    Native.Spotlight { id: spotlight; services: root.services }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.length > 0 && checks.every(c => c.passed) ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
    // Waits until a predicate holds or about six seconds pass, then runs the phase's checks.
    function settled(ready) { if (!ready && ++waited < 20) return false; waited = 0; return true; }
    Timer {
        id: step
        interval: 300; running: true; repeat: true
        onTriggered: {
            if (root.phase === 0) {
                spotlight.toggle();
                root.check('opens', spotlight.visible);
                spotlight.query = ':вогонь';
                root.phase = 1;
            } else if (root.phase === 1) {
                if (!root.settled(!spotlight.searchPending && spotlight.results.length > 0)) return;
                const first = spotlight.results[0];
                root.check('emoji-results-arrive', !!first && first.category === 'emoji' && first.preview.content === '🔥', root.summary());
                spotlight.query = 'sunset';
                root.phase = 2;
            } else {
                if (!root.settled(spotlight.results.some(item => item.category === 'file'))) return;
                const file = spotlight.results.find(item => item.category === 'file');
                root.check('file-results-arrive', !!file && file.title === 'Sea Sunset.png' && file.subtitle === '~/Pictures', root.summary());
                step.stop();
                root.finish();
            }
        }
    }
    Timer { interval: 25000; running: true; onTriggered: { root.check('fixture-timeout', false); root.finish(); } }
}
