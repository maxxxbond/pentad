import QtQuick
import Quickshell
import qs.theme
import "../shell" as Shell

ShellRoot {
    id: root
    property var checks: []
    property int phase: 0
    readonly property string artifact: Quickshell.env('PENTAD_ARTIFACT_PATH')
    readonly property var apps: [
        { id: 'app-firefox.desktop', category: 'app', title: 'Firefox', subtitle: 'Вебоглядач', icon: 'firefox' },
        { id: 'app-org.gnome.Nautilus.desktop', category: 'app', title: 'Файли', subtitle: 'Доступ до файлів і тек', icon: 'org.gnome.Nautilus' },
        { id: 'app-kitty.desktop', category: 'app', title: 'kitty', subtitle: 'Швидкий термінал з GPU', icon: 'kitty' },
        { id: 'app-discord.desktop', category: 'app', title: 'Discord', subtitle: 'Голосовий і текстовий чат', icon: 'discord' },
        { id: 'app-steam.desktop', category: 'app', title: 'Steam', subtitle: 'Ігрова платформа', icon: 'steam' },
        { id: 'app-org.kde.dolphin.desktop', category: 'app', title: 'Dolphin', subtitle: 'Файловий менеджер', icon: 'org.kde.dolphin' }
    ]
    property QtObject spotlight: QtObject {
        property bool visible: true
        property string outputName: ''
        property string query: ''
        property string page: 'results'
        property int selectedIndex: 0
        property int actionIndex: 0
        property string error: ''
        property string status: ''
        property bool searchPending: false
        readonly property bool pending: searchPending
        property var results: root.apps
        readonly property var selectedResult: results[selectedIndex] || null
        property var history: ({ pinned: ['app-firefox.desktop'], recent: [{ id: 'app-org.gnome.Nautilus.desktop' }] })
        property string previewImage: ''
        readonly property var actions: [
            { id: 'primary', label: 'Відкрити', shortcut: 'Enter' },
            { id: 'pin', label: 'Відкріпити', shortcut: 'Ctrl+Shift+P' },
            { id: 'details', label: 'Докладніше', shortcut: 'Ctrl+Space' },
            { id: 'mode-app', label: 'Застосунки', shortcut: '' },
            { id: 'mode-clipboard', label: 'Буфер обміну', shortcut: 'cb' },
            { id: 'mode-emoji', label: 'Emoji', shortcut: ':' }
        ]
        function group(result) {
            if (!result) return '';
            if (!query.trim() && result.category === 'app') {
                if (history.pinned.includes(result.id)) return 'Закріплені';
                if (history.recent.some(item => item.id === result.id)) return 'Нещодавні';
            }
            return ({ app: 'Застосунки', calc: 'Калькулятор', clipboard: 'Буфер обміну', emoji: 'Emoji', web: 'Вебпошук' })[result.category] || '';
        }
        function primaryLabel(result) { return result?.category === 'app' ? 'Відкрити' : result?.category === 'web' ? 'Шукати' : 'Копіювати'; }
        function back() { if (page === 'results') return false; page = 'results'; return true; }
        function runAction(id) {}
        function showActions() { page = page === 'actions' ? 'results' : 'actions'; }
        function showDetails() {}
        function activate(index) { return false; }
        function move(delta) {}
        function pin() {}
        function close() {}
        function pointerHover(hovered) {}
    }
    property QtObject services: QtObject {
        property var spotlight: root.spotlight
        property var popups: QtObject { function hostVisibility(name, visible) {} }
        property var config: ({ documents: { interface: { language: 'uk' }, layout: { barHeight: 40 } } })
        function text(uk, en) { return uk; }
    }
    Component.onCompleted: Theme.resolve({ appearance: Quickshell.env('PENTAD_GALLERY_APPEARANCE') || 'dark',
        accent: Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677', fontFamily: 'Geist',
        reducedMotion: Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1' })
    function check(name, passed, detail) { checks.push({ name: name, passed: passed === true, detail: detail || '' }); }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    Shell.SpotlightHost {
        id: host
        services: root.services
        // The layer-shell content item cannot be grabbed, so the dock is moved onto this backdrop.
        Rectangle { id: backdrop; z: -1; anchors.fill: parent; color: Qt.darker(Theme.tokens.surface, Theme.tokens.surface.hslLightness > 0.5 ? 1.08 : 0.7) }
    }
    function capture(suffix, next) {
        if (!artifact) { check('capture' + suffix, false, 'no artifact path'); next(); return; }
        backdrop.grabToImage(result => {
            check('capture' + (suffix || '.home'), result.saveToFile(artifact + suffix));
            next();
        });
    }
    function finish() {
        console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.length > 0 && checks.every(c => c.passed) ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
    Timer {
        id: step
        interval: 400; running: true
        onTriggered: {
            const capsule = root.find(host.contentItem, 'spotlight-capsule');
            const card = root.find(host.contentItem, 'spotlight-card');
            if (root.phase === 0) {
                if (capsule) capsule.parent.parent = backdrop;
                root.check('capsule-and-card-exist', !!capsule && !!card);
                root.check('capsule-is-a-56px-pill', !!capsule && capsule.height === 56 && capsule.extent === 28,
                    JSON.stringify({ height: capsule?.height, extent: capsule?.extent }));
                root.check('card-sits-8px-below-capsule', !!card && card.y === capsule.height + 8, String(card?.y));
                root.check('surfaces-are-borderless', !!card && capsule.edge.a === 0 && card.edge.a === 0);
                root.check('home-list-shows-all-rows', !!card && card.height >= 6 * 48, String(card?.height));
                root.capture('', () => {
                    root.spotlight.query = '24*7';
                    root.spotlight.results = [
                        { id: 'math-24*7', category: 'calc', title: '168', subtitle: '24*7 = 168', preview: { content: '168' } },
                        root.apps[2],
                        { id: 'web-24*7', category: 'web', title: 'Шукати в інтернеті «24*7»', subtitle: 'https://duckduckgo.com/?q=24*7', icon: 'world-search' }
                    ];
                    root.spotlight.selectedIndex = 0;
                    root.phase = 1; step.restart();
                });
            } else if (root.phase === 1) {
                root.check('query-card-shrinks-to-results', !!card && card.height < 6 * 48, String(card?.height));
                root.capture('.query.png', () => {
                    root.spotlight.query = '';
                    root.spotlight.results = root.apps;
                    root.spotlight.page = 'actions';
                    root.spotlight.actionIndex = 1;
                    root.phase = 2; step.restart();
                });
            } else if (root.phase === 2) {
                root.capture('.actions.png', () => {
                    root.spotlight.page = 'results';
                    root.spotlight.query = ':вогонь';
                    root.spotlight.results = [
                        { id: 'emoji-1f525', category: 'emoji', title: '🔥 :fire:', subtitle: 'вогонь', preview: { content: '🔥' } },
                        { id: 'emoji-2764', category: 'emoji', title: '❤️‍🔥 :heart_on_fire:', subtitle: 'серце у вогні', preview: { content: '❤️‍🔥' } },
                        { id: 'emoji-1f9ef', category: 'emoji', title: '🧯 :fire_extinguisher:', subtitle: 'вогнегасник', preview: { content: '🧯' } },
                        { id: 'emoji-1f692', category: 'emoji', title: '🚒 :fire_engine:', subtitle: 'пожежна машина', preview: { content: '🚒' } }
                    ];
                    root.spotlight.selectedIndex = 0;
                    root.phase = 3; step.restart();
                });
            } else {
                root.capture('.emoji.png', () => root.finish());
            }
        }
    }
    Timer { interval: 20000; running: true; onTriggered: { root.check('fixture-timeout', false); root.finish(); } }
}
