import QtQuick
import QtQml
import Quickshell
import Quickshell.Hyprland
import '../logic/spotlight-apps.mjs' as Apps
import '../logic/spotlight-providers.mjs' as Search
import '../logic/spotlight-dispatch.mjs' as Dispatch

QtObject {
    id: root
    required property var services
    property bool visible: false
    property string outputName: ''
    property string query: ''
    property string page: 'results'
    property int selectedIndex: 0
    property int actionIndex: 0
    property string error: ''
    property string status: ''
    property bool searchPending: false
    property bool actionPending: false
    readonly property bool pending: searchPending || actionPending
    property var results: []
    readonly property var selectedResult: results[selectedIndex] || null
    readonly property var catalog: Apps.indexApplications(DesktopEntries.applications.values)
    property var history: Dispatch.emptyHistory()
    property var clipboard: []
    property var emojiRecords: ({})
    property var emojiLayouts: []
    property bool layoutsLoaded: false
    property string previewImage: ''
    property var session: new Dispatch.LauncherSession()
    property var dispatcher: Dispatch.createSearchDispatcher([])
    readonly property var emojiOptions: ({
        languages: services.config.documents.spotlight?.emoji?.languages,
        locales: [services.config.documents.interface.language, Qt.locale().name,
            Quickshell.env('LANGUAGE'), Quickshell.env('LANG')],
        layouts: emojiLayouts,
        displayLocale: services.config.documents.interface.language || Qt.locale().name
    })
    readonly property var actions: [ ...(!pending && selectedResult ? [
        { id: 'primary', label: primaryLabel(selectedResult), shortcut: 'Enter' },
        ...(selectedResult.category === 'app' ? [{ id: 'pin', label: history.pinned.includes(selectedResult.id)
            ? tr('Відкріпити', 'Unpin') : tr('Закріпити', 'Pin'), shortcut: 'Ctrl+Shift+P' }] : []),
        ...(selectedResult.category === 'clipboard' ? [{ id: 'delete', label: tr('Видалити', 'Delete'), shortcut: 'Ctrl+Delete' }] : []),
        { id: 'details', label: tr('Докладніше', 'Show details'), shortcut: 'Ctrl+Space' }
        ] : []),
        { id: 'mode-app', label: tr('Застосунки', 'Applications'), shortcut: '' },
        { id: 'mode-clipboard', label: tr('Буфер обміну', 'Clipboard'), shortcut: 'cb' },
        { id: 'mode-emoji', label: 'Emoji', shortcut: ':' }
    ]
    onQueryChanged: {
        page = 'results'; previewImage = ''; error = ''; status = '';
        if (visible) { session.revision++; dispatcher.cancel(); searchPending = true; queryTimer.restart(); }
    }
    onCatalogChanged: if (visible) queryTimer.restart()
    onSelectedIndexChanged: session.selected = selectedIndex
    property Timer queryTimer: Timer { interval: 80; onTriggered: root.search() }
    property Connections popupConnections: Connections {
        target: root.services.popups
        function onChanged() { if (root.services.popups.surface) root.close(); }
        function onCapturePreparing() { root.close(); }
    }
    property Connections navigationConnections: Connections {
        target: root.services.navigation
        function onActiveChanged() { if (root.services.navigation.active) root.close(); }
    }
    property Connections screenConnections: Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.visible && !Quickshell.screens.some(screen => screen.name === root.outputName)) root.close();
        }
    }
    // Spotlight belongs to the monitor it opened on: leave when the cursor/focus moves
    // to another monitor or a compositor hotkey changes the desktop under it.
    readonly property var dismissEvents: ['focusedmon', 'focusedmonv2', 'workspace', 'workspacev2',
        'movewindow', 'movewindowv2', 'fullscreen', 'changefloatingmode', 'submap']
    property Connections hyprlandConnections: Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            const monitor = Hyprland.focusedMonitor;
            if (root.visible && monitor && monitor.name !== root.outputName) root.close();
        }
        function onRawEvent(event) {
            if (root.visible && event && root.dismissEvents.includes(event.name)) root.close();
        }
    }
    property Connections localeConnections: Connections {
        target: root.services.config
        function onDocumentChanged(name) {
            if (root.visible && ['spotlight', 'interface'].includes(name) && /^\s*:/.test(root.query)) root.search();
        }
    }
    Component.onCompleted: if (!services.preview && !services.safeMode) request({ operation: 'history' }, result => {
        if (result.ok) { history = Dispatch.parseHistory(JSON.stringify(result.history)); if (visible) rerank(); }
        else error = tr('Історія виборів недоступна', 'Launch history unavailable');
    })
    function tr(uk, en) { return services.text(uk, en); }
    function request(payload, done) {
        if (services.preview || services.safeMode) { Qt.callLater(() => done({ ok: false, reason: 'denied' })); return; }
        const component = Qt.createComponent('SpotlightRequest.qml');
        if (component.status !== Component.Ready) { done({ ok: false, reason: component.errorString() }); return; }
        const worker = component.createObject(root, {
            helperPath: services.config.helperPath.replace(/pentad-files\.py$/, 'pentad_spotlight.py'),
            stateRoot: services.config.stateRoot,
            emojiPath: decodeURIComponent(Qt.resolvedUrl('../assets/spotlight/emoji.json').toString().replace(/^file:\/\//, '')),
            payload: payload
        });
        if (!worker) { done({ ok: false, reason: 'unavailable' }); return; }
        worker.finished.connect(done);
        worker.running = true;
    }
    function toggle() {
        if (visible) { close(); return; }
        const state = services.hyprland.state;
        const outputs = state.kind === 'ready' ? state.value.outputs : [];
        const focused = outputs.find(output => output.id === state.value.focusedOutputId);
        const screen = Quickshell.screens.find(screen => focused && screen.name === focused.name) || Quickshell.screens[0];
        if (!screen) return;
        services.navigation.cancel(); services.popups.close();
        query = ''; page = 'results'; selectedIndex = 0; actionIndex = 0;
        error = ''; status = ''; previewImage = '';
        layoutsLoaded = false;
        outputName = screen.name;
        session.open(); visible = true; search();
    }
    function close() {
        visible = false; session.close(); dispatcher.cancel(); queryTimer.stop();
        query = ''; results = []; selectedIndex = 0; page = 'results';
        searchPending = false; actionPending = false; previewImage = ''; error = ''; status = '';
    }
    function accept(token) {
        if (!session.current(token)) return;
        dispatcher.cancel();
        dispatcher = Dispatch.createSearchDispatcher(Search.createDefaultProviders({
            apps: catalog, clipboard: clipboard, emojiRecords: emojiRecords, emoji: emojiOptions
        }));
        dispatcher.query(query, true).then(items => {
            if (!session.accept(token, items)) return;
            const previous = results[selectedIndex]?.id;
            results = Dispatch.rankResults(items, history, !query.trim()).slice(0, 60);
            session.results = results; selectedIndex = Math.max(0, results.findIndex(item => item.id === previous));
            searchPending = false;
        });
    }
    function search() {
        if (!visible) return;
        const token = session.beginQuery(); searchPending = true;
        const clean = query.trim();
        if (clean === 'cb' || clean.startsWith('cb ')) {
            request({ operation: 'clipboard-list' }, result => {
                if (!session.current(token)) return;
                clipboard = result.ok ? result.text.split('\n').map(Search.parseCliphistLine).filter(item => item !== null) : [];
                if (!result.ok) error = tr('Історія буфера обміну недоступна', 'Clipboard history unavailable');
                accept(token);
            });
        } else if (clean.startsWith(':')) {
            if (!layoutsLoaded && !Array.isArray(emojiOptions.languages)) {
                request({ operation: 'keyboard-layouts' }, reply => {
                    if (!session.current(token)) return;
                    layoutsLoaded = true;
                    if (reply.ok) emojiLayouts = reply.layouts;
                    search();
                });
                return;
            }
            const languages = Search.resolveEmojiLanguages(emojiOptions);
            if (languages.every(language => emojiRecords[language])) { accept(token); return; }
            request({ operation: 'emoji', languages: languages }, result => {
                if (!session.current(token)) return;
                if (result.ok) emojiRecords = result.records;
                else error = tr('Не вдалося завантажити emoji', 'Could not load emoji');
                accept(token);
            });
        } else accept(token);
    }
    function rerank() {
        const id = selectedResult?.id;
        results = Dispatch.rankResults(results, history, !query.trim());
        session.results = results; selectedIndex = Math.max(0, results.findIndex(item => item.id === id));
    }
    function move(delta) {
        if (page === 'details') return;
        if (page === 'actions' && actions.length) actionIndex = (actionIndex + delta + actions.length) % actions.length;
        else if (!pending) { session.move(delta); selectedIndex = session.selected; }
    }
    function back() { if (page === 'results') return false; page = 'results'; previewImage = ''; return true; }
    function showActions() { page = page === 'actions' ? 'results' : 'actions'; actionIndex = 0; }
    function showDetails() {
        if (!selectedResult || pending) return;
        if (page === 'details') { back(); return; }
        page = 'details'; previewImage = '';
        const result = selectedResult, token = session.token();
        if (result.preview?.type === 'image') request({ operation: 'preview-clip', id: result.preview.metadata.ID }, reply => {
            if (!session.current(token) || selectedResult?.id !== result.id || page !== 'details') return;
            if (reply.ok) previewImage = reply.image;
            else error = tr('Попередній перегляд недоступний', 'Preview unavailable');
        });
    }
    function pin() {
        if (selectedResult?.category !== 'app' || pending || services.preview || services.safeMode) return;
        const id = selectedResult.id, token = session.beginAction();
        if (!token) return;
        actionPending = session.actionPending;
        request({ operation: 'pin', id: id }, reply => {
            if (reply.ok) history = Dispatch.parseHistory(JSON.stringify(reply.history));
            if (!session.live(token)) return;
            const current = session.endAction(token);
            actionPending = session.actionPending;
            if (!current) return;
            if (reply.ok) { page = 'results'; rerank(); }
            else error = tr('Не вдалося зберегти закріплення', 'Could not save pin');
        });
    }
    function primaryLabel(result) {
        return result?.category === 'app' ? tr('Відкрити', 'Open')
            : result?.category === 'web' ? tr('Шукати', 'Search') : tr('Копіювати', 'Copy');
    }
    function group(result) {
        if (!result) return '';
        if (!query.trim() && result.category === 'app') {
            if (history.pinned.includes(result.id)) return tr('Закріплені', 'Pinned');
            if (history.recent.some(item => item.id === result.id)) return tr('Нещодавні', 'Recent');
        }
        return ({ app: tr('Застосунки', 'Applications'), calc: tr('Калькулятор', 'Calculator'),
            clipboard: tr('Буфер обміну', 'Clipboard'), emoji: 'Emoji', web: tr('Вебпошук', 'Web search') })[result.category] || '';
    }
    function runAction(id) {
        if (id === 'mode-app' || id === 'mode-clipboard' || id === 'mode-emoji') {
            const nextQuery = id === 'mode-app' ? '' : id === 'mode-clipboard' ? 'cb ' : ':';
            page = 'results';
            if (query === nextQuery && pending) {
                session.revision++; dispatcher.cancel(); searchPending = true; queryTimer.restart();
            } else query = nextQuery;
        } else if (pending) {
            return;
        } else if (id === 'pin') pin();
        else if (id === 'details') showDetails();
        else activate(selectedIndex, id === 'delete');
    }
    function activate(index, remove, keepOpen) {
        if (services.preview || services.safeMode || pending) return false;
        if (index !== undefined) selectedIndex = index;
        const result = selectedResult;
        if (!result) return false;
        const token = session.beginAction();
        if (!token) return false;
        actionPending = session.actionPending; error = ''; status = '';
        const done = reply => {
            const current = session.endAction(token);
            if (reply.ok && result.category === 'app') {
                history = Dispatch.recordLaunch(history, result.id);
                request({ operation: 'record', id: result.id }, saved => {
                    if (saved.ok) history = Dispatch.parseHistory(JSON.stringify(saved.history));
                    else if (session.current(token)) error = tr('Не вдалося зберегти історію', 'Could not save launch history');
                });
            }
            if (!session.live(token)) return;
            actionPending = session.actionPending;
            if (!current) return;
            if (!reply.ok) { error = tr('Не вдалося виконати дію', 'Could not complete this action'); return; }
            if (remove) { page = 'results'; search(); }
            else if (keepOpen) { page = 'results'; status = tr('Скопійовано', 'Copied'); }
            else close();
        };
        if (result.category === 'app' || result.category === 'web') {
            const argv = result.category === 'app'
                ? ['gtk-launch', '--', result.actions[0].data.desktopId]
                : ['xdg-open', result.actions[0].data.url];
            const component = Qt.createComponent('SpotlightCommand.qml');
            if (component.status !== Component.Ready) { done({ ok: false }); return false; }
            const worker = component.createObject(root, { argv: argv });
            if (!worker) { done({ ok: false }); return false; }
            worker.finished.connect(done); worker.running = true;
        } else if (result.category === 'clipboard') {
            request({ operation: remove ? 'delete-clip' : 'copy-clip', id: result.preview.metadata.ID }, done);
        } else request({ operation: 'copy-text', text: result.actions[0].data.text }, done);
        return true;
    }
}
