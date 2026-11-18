import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import qs.services
import "../features/sidebar"

ShellRoot {
    id: root
    property int step: 0
    property bool finished: false
    property int geocodeRequestCount: 0
    property string lastGeocodeUrl: ''
    property var weatherRequestsByCity: ({})
    property int chatRequestCount: 0
    property bool chatFinished: false
    property bool weatherSearchStarted: false
    property bool weatherSearchSaved: false
    property bool weatherSaveConfirmed: false
    property bool weatherSearchReplaced: false
    property bool weatherStaleResponsePending: false
    property bool weatherSearchReopened: false
    property bool weatherSearchReopenRequested: false
    property bool weatherStaleResponseIgnored: false
    property string weatherSelectedMessage: ''
    property int weatherStaleResponseWait: 0
    property bool weatherDisposeSearchStarted: false
    property bool weatherDisposedResponsePending: false
    property bool weatherDisposedResponseIgnored: false
    property int weatherDisposeSearchStep: 0
    property var resolveStaleGeocode: null
    property var rejectDisposedGeocode: null
    readonly property var weatherForecast: ({
        current: { temperature_2m: 18, apparent_temperature: 17, wind_speed_10m: 9, weather_code: 2, is_day: 1 },
        daily: { time: ['2026-10-10', '2026-10-11', '2026-10-12'],
            temperature_2m_min: [10, 11, 12], temperature_2m_max: [18, 19, 20], weather_code: [2, 3, 61] }
    })
    readonly property var weatherSettings: ({ city: 'Kyiv', country: 'Ukraine', region: 'Kyiv City',
        latitude: 50.45, longitude: 30.52, timezone: 'Europe/Kyiv', units: 'celsius' })
    property var placements: [
        { instanceId: 'workspaces-fixture', moduleId: 'pentad.workspaces', slot: 'sidebar-left', enabled: true, settings: {} },
        { instanceId: 'weather-fixture', moduleId: 'pentad.weather', slot: 'sidebar-left', enabled: true, settings: weatherSettings },
        { instanceId: 'disabled-fixture', moduleId: 'pentad.chat', slot: 'sidebar-left', enabled: false, settings: {} },
        { instanceId: 'chat-fixture', moduleId: 'pentad.chat', slot: 'sidebar-left', enabled: true, settings: {
            modelSource: 'custom', provider: 'ollama', baseUrl: 'http://127.0.0.1:11434', model: 'fixture' } },
        { instanceId: 'bar-fixture', moduleId: 'pentad.clock', slot: 'system', enabled: false, settings: {} },
    ]
    property QtObject fakeHyprland: QtObject {
        readonly property var state: ({ kind: 'ready', value: {
            outputs: [{ id: '7', name: 'fixture-output', activeWorkspaceId: '2' }],
            focusedOutputId: '7',
            activeTitle: 'Fixture terminal',
            workspaces: [
                { id: '1', name: '1', monitor: 'fixture-output', active: false, occupied: true },
                { id: '2', name: '2', monitor: 'fixture-output', active: true, occupied: true },
            ]
        } })
    }
    property var fakeServices: QtObject {
        readonly property bool preview: false
        readonly property bool safeMode: false
        readonly property var config: root.fakeConfig
        readonly property var hyprland: root.fakeHyprland
        readonly property var plugins: root.registry
        readonly property ToolWorkspace toolWorkspace: ToolWorkspace {}
        readonly property var weather: root.weatherService
        readonly property var chat: root.chatService
        function text(uk, en) { return en; }
    }
    property QtObject fakeConfig: QtObject {
        property var layout: ({ widgets: root.placements })
        property int serial: 0
        readonly property var documents: ({ layout: layout })
        signal commandFinished(string requestId, var result)
        function save(name, value) {
            const requestId = 'fixture-' + (++serial);
            Qt.callLater(function() {
                if (name === 'layout') {
                    root.fakeConfig.layout = value;
                    root.placements = value.widgets;
                    root.weatherSearchSaved = root.placements.some(function(item) {
                        return item.instanceId === 'weather-fixture' && item.settings.city === 'Berlin'
                            && item.settings.latitude === 52.52 && item.settings.longitude === 13.405
                            && item.settings.timezone === 'Europe/Berlin'
                            && item.settings.units === 'celsius';
                    });
                    root.weatherSaveConfirmed = root.weatherSearchSaved;
                }
                commandFinished(requestId, { ok: true });
            });
            return requestId;
        }
    }
    property Plugins registry: Plugins { safeMode: true; services: root.fakeServices }
    property Weather weatherService: Weather {
        preview: false
        safeMode: false
        fetchJsonOverride: function(url, cancellation) {
            if (url.indexOf('geocoding-api.open-meteo.com') >= 0) {
                root.geocodeRequestCount++;
                root.lastGeocodeUrl = url;
                if (url.indexOf('name=Paris') >= 0) {
                    return new Promise(function(resolve) { root.resolveStaleGeocode = resolve; });
                }
                if (url.indexOf('name=Hamburg') >= 0) {
                    return new Promise(function(_resolve, reject) { root.rejectDisposedGeocode = reject; });
                }
                return Promise.resolve({ results: [{ name: 'Berlin', country: 'Germany', admin1: 'Berlin',
                    latitude: 52.52, longitude: 13.405, timezone: 'Europe/Berlin' }] });
            }
            var city = url.indexOf('latitude=52.52') >= 0 ? 'Berlin' : 'Kyiv';
            root.weatherRequestsByCity = Object.assign({}, root.weatherRequestsByCity,
                { [city]: (root.weatherRequestsByCity[city] || 0) + 1 });
            return Promise.resolve(city === 'Berlin' ? Object.assign({}, root.weatherForecast, {
                current: Object.assign({}, root.weatherForecast.current, { temperature_2m: 22 }),
            }) : root.weatherForecast);
        }
    }
    property Chat chatService: Chat {
        preview: false
        safeMode: false
        streamOverride: function(profile, messages, key, cancellation, onDelta) {
            root.chatRequestCount++;
            return new Promise(function(resolve) {
                onDelta({ type: 'text', text: 'Fixture response' });
                onDelta({ type: 'done', reason: 'stop' });
                resolve();
            });
        }
    }
    property FileView workspaceManifest: FileView {
        path: Qt.resolvedUrl('widgets/workspaces/manifest.json')
        printErrors: false
    }
    property FileView weatherManifest: FileView {
        path: Qt.resolvedUrl('widgets/weather/manifest.json')
        printErrors: false
    }
    property FileView chatManifest: FileView {
        path: Qt.resolvedUrl('widgets/chat/manifest.json')
        printErrors: false
    }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        var children = item.children || [];
        for (var index = 0; index < children.length; index++) {
            var found = findNamed(children[index], name);
            if (found) return found;
        }
        return null;
    }

    FloatingWindow {
        visible: true
        implicitWidth: 900
        implicitHeight: 740
        Row {
            anchors.fill: parent
            spacing: 12
            SidebarView {
                id: sidebarPrimary
                services: root.fakeServices
                outputId: 'fixture-output'
            }
            SidebarView {
                id: sidebarSecondary
                services: root.fakeServices
                outputId: 'fixture-output-two'
            }
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            root.step++;
            if (root.step === 100 && !root.finished) {
                var weatherHost = root.findNamed(sidebarPrimary, 'sidebar-widget-weather-fixture');
                var weatherView = weatherHost ? weatherHost.view : null;
                var searchForm = root.findNamed(weatherView, 'weather-location-search');
                var cityField = root.findNamed(weatherView, 'weather-city-search');
                root.finish(false, [{ name: 'weather-geocoding-progress', passed: false, detail: JSON.stringify({
                    saved: root.weatherSearchSaved, replaced: root.weatherSearchReplaced,
                    stalePending: root.weatherStaleResponsePending, staleIgnored: root.weatherStaleResponseIgnored,
                    reopened: root.weatherSearchReopened, disposedStarted: root.weatherDisposeSearchStarted,
                    disposedPending: root.weatherDisposedResponsePending, disposedIgnored: root.weatherDisposedResponseIgnored,
                    query: root.findNamed(weatherView, 'weather-city-search')
                        ? cityField.text : null,
                    message: searchForm ? searchForm.message : null, results: searchForm ? searchForm.results : null,
                    locationMessage: weatherView ? weatherView.locationMessage : null,
                    saveRequestId: weatherView ? weatherView.locationSaveRequestId : null,
                    geocodeRequests: root.geocodeRequestCount, url: root.lastGeocodeUrl,
                    weatherService: !!root.weatherService }) }]);
                return;
            }
            if (root.step === 1) {
                if (!root.workspaceManifest.loaded || !root.weatherManifest.loaded || !root.chatManifest.loaded) return;
                var registered = root.registry.registerManifest(JSON.parse(root.workspaceManifest.text()),
                    Qt.resolvedUrl('widgets/workspaces/'), true);
                var weatherRegistered = root.registry.registerManifest(JSON.parse(root.weatherManifest.text()),
                    Qt.resolvedUrl('widgets/weather/'), true);
                var chatRegistered = root.registry.registerManifest(JSON.parse(root.chatManifest.text()),
                    Qt.resolvedUrl('widgets/chat/'), true);
                root.registry.reconcile(root.placements);
                if (!registered.ok || !weatherRegistered.ok || !chatRegistered.ok) {
                    root.finish(false, [{ name: 'sidebar-manifests-register', passed: false,
                        detail: JSON.stringify({ workspace: registered.errors || [], weather: weatherRegistered.errors || [], chat: chatRegistered.errors || [] }) }]);
                    return;
                }
            } else if (root.step === 3) {
                var chatHost = root.findNamed(sidebarPrimary, 'sidebar-widget-chat-fixture');
                if (!chatHost || !chatHost.view || !chatHost.view.session) {
                    root.finish(false, [{ name: 'chat-widget-host-mounts', passed: false, detail: chatHost ? chatHost.diagnostic : 'host missing' }]);
                    return;
                }
                chatHost.view.session.send('fixture prompt').then(function() { root.chatFinished = true; });
            } else if (root.step === 4) {
                var weatherHost = root.findNamed(sidebarPrimary, 'sidebar-widget-weather-fixture');
                var weatherView = weatherHost ? weatherHost.view : null;
                var changeCity = root.findNamed(weatherView, 'weather-change-city');
                if (!changeCity) {
                    root.finish(false, [{ name: 'weather-card-city-control-exists', passed: false, detail: 'Change city control missing from weather card' }]);
                    return;
                }
                changeCity.click();
                var search = root.findNamed(weatherView, 'weather-city-search');
                if (!search) {
                    root.finish(false, [{ name: 'weather-location-search-mounts-in-card', passed: false, detail: 'Search field missing from weather card' }]);
                    return;
                }
                search.text = 'Paris';
                root.findNamed(weatherView, 'weather-location-search').editQuery();
                root.weatherSearchStarted = true;
            } else if (root.step >= 5 && root.chatFinished) {
                var weatherHost = root.findNamed(sidebarPrimary, 'sidebar-widget-weather-fixture');
                var weatherView = weatherHost ? weatherHost.view : null;
                if (root.step >= 12 && !root.weatherSearchReplaced) {
                    var cityField = root.findNamed(weatherView, 'weather-city-search');
                    cityField.text = 'Berlin';
                    root.findNamed(weatherView, 'weather-location-search').editQuery();
                    root.weatherSearchReplaced = true;
                }
                var cityResult = root.findNamed(weatherView, 'weather-city-result');
                if (root.weatherSearchStarted && root.weatherSearchReplaced && cityResult && !root.weatherSearchSaved) {
                    cityResult.click();
                    if (root.resolveStaleGeocode) {
                        root.weatherStaleResponsePending = true;
                        root.resolveStaleGeocode({ results: [{ name: 'Paris', country: 'France', admin1: 'Île-de-France',
                            latitude: 48.85, longitude: 2.35, timezone: 'Europe/Paris' }] });
                        root.resolveStaleGeocode = null;
                    }
                }
                if (root.weatherStaleResponsePending && !root.weatherSearchReopenRequested
                    && root.weatherSaveConfirmed && !weatherView.locationSaveRequestId
                    && !root.findNamed(weatherView, 'weather-location-search')) {
                    root.findNamed(weatherView, 'weather-change-city').click();
                    root.weatherSearchReopenRequested = true;
                }
                if (root.weatherSearchReopenRequested && root.findNamed(weatherView, 'weather-location-search')) {
                    root.weatherSearchReopened = true;
                }
                if (root.weatherStaleResponsePending && !root.weatherStaleResponseIgnored) {
                    root.weatherStaleResponseWait++;
                    if (root.weatherSearchReopened && root.weatherStaleResponseWait >= 2) {
                        var searchForm = root.findNamed(weatherView, 'weather-location-search');
                        root.weatherSelectedMessage = searchForm ? searchForm.message : '';
                        root.weatherStaleResponseIgnored = !!searchForm && searchForm.results.length === 0
                            && root.placements.find(function(item) { return item.instanceId === 'weather-fixture'; }).settings.city === 'Berlin';
                    }
                }
                if (root.weatherStaleResponseIgnored && !root.weatherDisposeSearchStarted) {
                    root.findNamed(weatherView, 'weather-city-search').text = 'Hamburg';
                    root.findNamed(weatherView, 'weather-location-search').editQuery();
                    root.weatherDisposeSearchStarted = true;
                    root.weatherDisposeSearchStep = root.step;
                }
                if (root.weatherDisposeSearchStarted && root.rejectDisposedGeocode && !root.weatherDisposedResponsePending) {
                    root.findNamed(weatherView, 'weather-change-city').click();
                    root.weatherDisposedResponsePending = true;
                    root.rejectDisposedGeocode(new Error('fixture late rejection'));
                    root.rejectDisposedGeocode = null;
                }
                if (root.weatherDisposedResponsePending && root.step >= root.weatherDisposeSearchStep + 2)
                    root.weatherDisposedResponseIgnored = root.findNamed(weatherView, 'weather-location-search') === null;
                var actualView = root.findNamed(sidebarPrimary, 'sidebar-widget-workspaces-fixture');
                var weather = root.findNamed(sidebarPrimary, 'sidebar-widget-weather-fixture');
                var weatherOnSecondOutput = root.findNamed(sidebarSecondary, 'sidebar-widget-weather-fixture');
                var chat = root.findNamed(sidebarPrimary, 'sidebar-widget-chat-fixture');
                var hostOrder = sidebarPrimary.placements.map(function(item) { return item.instanceId; });
                var ordered = JSON.stringify(hostOrder) === JSON.stringify([
                    'workspaces-fixture', 'weather-fixture', 'chat-fixture',
                ]);
                var workspaceMounted = !!actualView && !!actualView.view
                    && actualView.view.instanceId === 'workspaces-fixture'
                    && actualView.view.choices.length >= 2
                    && actualView.view.hyprState.value.activeTitle === 'Fixture terminal';
                var weatherMounted = !!weather && !!weather.view && weather.view.weatherState.status === 'ready'
                    && weather.view.weatherState.value.temperature === 22
                    && weather.view.config.location.name === 'Berlin'
                    && !!weatherOnSecondOutput && !!weatherOnSecondOutput.view
                    && weatherOnSecondOutput.view.weatherState.status === 'ready'
                    && weatherOnSecondOutput.view.weatherState.value.temperature === 22
                    && weatherOnSecondOutput.view.config.location.name === 'Berlin'
                    && root.weatherRequestsByCity.Kyiv === 1 && root.weatherRequestsByCity.Berlin === 1;
                var chatReady = !!chat && !!chat.view && chat.view.chatState.status === 'idle'
                    && chat.view.chatState.messages.length === 2
                    && chat.view.chatState.messages[1].content === 'Fixture response'
                    && root.chatRequestCount === 1;
                var weatherLocationSaved = root.weatherSearchSaved && root.placements.some(function(item) {
                    return item.instanceId === 'weather-fixture' && item.settings.city === 'Berlin';
                });
                if (!root.weatherSearchSaved || !root.weatherStaleResponseIgnored || !root.weatherDisposedResponseIgnored) return;
                root.finish(ordered && workspaceMounted && weatherMounted && chatReady && weatherLocationSaved
                    && root.weatherStaleResponseIgnored && root.weatherDisposedResponseIgnored, [
                    { name: 'enabled-sidebar-placements-retain-layout-order', passed: ordered, detail: JSON.stringify(hostOrder) },
                    { name: 'workspace-plugin-host-mounts-live-output-data', passed: workspaceMounted,
                        detail: actualView ? JSON.stringify({ loaded: !!actualView.view, choices: actualView.view ? actualView.view.choices.length : 0 }) : 'Workspace host not found' },
                    { name: 'weather-widget-renders-settings-and-shares-one-fetch-across-outputs', passed: weatherMounted,
                        detail: JSON.stringify({ requestCount: root.weatherRequestsByCity,
                            primary: weather ? weather.weatherState : null,
                            secondary: weatherOnSecondOutput ? weatherOnSecondOutput.weatherState : null }) },
                    { name: 'geocoded-city-selection-saves-weather-settings', passed: weatherLocationSaved,
                        detail: JSON.stringify(root.placements.find(function(item) { return item.instanceId === 'weather-fixture'; }).settings) },
                    { name: 'late-cancelled-geocode-cannot-replace-selected-city', passed: root.weatherStaleResponseIgnored,
                        detail: root.weatherSelectedMessage },
                    { name: 'disposal-cancels-late-geocode-rejection', passed: root.weatherDisposedResponseIgnored,
                        detail: 'Weather settings closed before the rejected lookup completed.' },
                    { name: 'chat-widget-streams-fake-provider-response-without-network', passed: chatReady,
                        detail: JSON.stringify({ requestCount: root.chatRequestCount, state: chat ? chat.view.chatState : null,
                            session: chat && chat.view.session ? chat.view.session.read() : null }) },
                ]);
            }
        }
    }

    function finish(passed, checks) {
        if (finished) return;
        finished = true;
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
}
