import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.theme
import qs.plugins
import qs.services
import qs.components
import qs.features.bar
import qs.features.media
import qs.features.screenshot
import qs.features.sidebar
import qs.features.system
import "../shell" as Shell
import '../logic/lyrics.mjs' as LyricsLogic
import '../logic/organizer.mjs' as OrganizerLogic
import '../logic/screenshot.mjs' as ScreenshotModel

// Renders the README images: a brand wallpaper with the real bar and one open surface per scene, fed by
// invented data. Nothing here is personal; the desktop is composed inside one window because the virtual
// compositor offers no screen capture. Scenes: rest, control-center, tools, media, karaoke, spotlight and
// screen-tools, each saved as <artifact>.<scene>.png (the control centre also as <artifact>).
ShellRoot {
    id: root
    readonly property bool light: Quickshell.env('PENTAD_GALLERY_APPEARANCE') === 'light'
    readonly property real captureScale: Number(Quickshell.env('PENTAD_GALLERY_SCALE') || 1)
    readonly property string brand: Quickshell.env('PENTAD_SHOWCASE_BRAND')
    readonly property string brandIcon: brand ? 'file://' + brand + '/app-icon.svg' : ''
    // A real cover only when the maintainer supplied one locally (see test-quickshell.mjs).
    readonly property string coverPath: Quickshell.env('PENTAD_SHOWCASE_COVER')
    readonly property date now: new Date(2026, 10, 27, 9, 41, 0)
    readonly property int canvasWidth: 1280
    readonly property int canvasHeight: 800
    readonly property int barHeight: services.config.documents.layout.barHeight
    property Services services: Services { preview: true; safeMode: true }
    property var checks: []
    property bool ready: false
    property string scene: 'rest'
    // 'crawling' is the real track and never shows lyrics. 'lanterns' is the invented track with invented
    // synced lines.
    property string track: 'crawling'
    property string screenSource: ''

    component LightPool: ShapePath {
        property real cx
        property real cy
        property real radius
        property color tint
        strokeColor: 'transparent'
        fillGradient: RadialGradient {
            centerX: cx; centerY: cy; centerRadius: radius
            focalX: cx; focalY: cy
            GradientStop { position: 0; color: tint }
            GradientStop { position: 1; color: 'transparent' }
        }
        PathRectangle { x: 0; y: 0; width: root.canvasWidth; height: root.canvasHeight }
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || '' });
    }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        // The island's karaoke overhang is a popup window, outside the visual tree.
        const children = (item.children || []).concat(item.overhangSurface ? [item.overhangSurface] : []);
        for (let index = 0; index < children.length; index++) {
            const found = findNamed(children[index], name);
            if (found) return found;
        }
        return null;
    }
    function finish() {
        const passed = checks.every(function(item) { return item.passed; });
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }

    property QtObject fakeMedia: QtObject {
        property var consumers: []
        readonly property var players: [
            root.track === 'crawling'
            ? { id: 'showcase.music', name: 'spotify', title: 'Crawling', artist: 'Linkin Park', album: 'Hybrid Theory',
              playback: 'playing', positionMicros: 72000000, positionUpdatedAt: Date.now() + 600000, lengthMicros: 209000000,
              trackId: '/track/crawling', trackRevision: 'crawling', canPlayPause: true, canPrevious: true, canNext: true, canSeek: true }
            : { id: 'showcase.music', name: 'spotify', title: 'Paper Lanterns', artist: 'Lumen Fields', album: 'Low Tide',
              playback: 'playing', positionMicros: 71000000, positionUpdatedAt: Date.now() + 600000, lengthMicros: 214000000,
              trackId: '/track/lanterns', trackRevision: 'lanterns', canPlayPause: true, canPrevious: true, canNext: true, canSeek: true },
            { id: 'showcase.video', name: 'mpv', title: 'Harbor at Night', artist: 'Field recording', playback: 'paused',
              positionMicros: 0, lengthMicros: 90000000, trackId: '/track/harbor', trackRevision: 'harbor',
              canPlayPause: true, canPrevious: false, canNext: false, canSeek: true }
        ]
        property string selectedId: 'showcase.music'
        signal commandFinished(string requestId, var result)
        readonly property var state: ({ kind: 'ready', value: { players: players, selectedId: selectedId,
            current: players.find(function(item) { return item.id === selectedId; }) || null } })
        function acquire(id) { if (id && !consumers.includes(id)) consumers = consumers.concat([id]); }
        function release(id) { consumers = consumers.filter(function(item) { return item !== id; }); }
        function selectPlayer(id) { selectedId = id; return 'showcase-selection'; }
        function command(id, action) { return 'showcase-command'; }
        function seek(id, track, value, revision) { return 'showcase-seek'; }
    }
    property QtObject fakeLyrics: QtObject {
        property var consumers: []
        property int offsetMs: 0
        readonly property var state: root.track === 'crawling'
            ? ({ kind: 'unavailable', reason: 'not-found' })
            : ({ kind: 'ready', value: {
            lines: LyricsLogic.parseLrc('[01:02.00]We left the porch light burning\n'
                + '[01:08.00]<01:08.00>Paper <01:09.20>lanterns <01:10.60>on <01:11.20>the <01:11.80>water\n'
                + '[01:15.00]Carry what the evening knows'),
            plain: '', instrumental: false
        } })
        function acquire(id) { if (id && !consumers.includes(id)) consumers = consumers.concat([id]); }
        function release(id) { consumers = consumers.filter(function(item) { return item !== id; }); }
    }
    property QtObject fakeVisualizer: QtObject {
        property var consumers: []
        readonly property var state: ({ kind: 'ready', value: { values: [0.25, 0.5, 0.8, 0.95, 0.7, 0.45, 0.3, 0.5, 0.75, 0.6, 0.35, 0.2] } })
        function acquire(id) { if (id && !consumers.includes(id)) consumers = consumers.concat([id]); }
        function release(id) { consumers = consumers.filter(function(item) { return item !== id; }); }
    }
    property QtObject fakeArtwork: QtObject {
        property var states: ({})
        // The real track never shows its real cover unless one was supplied locally; the brand icon stands in.
        function stateFor(id) {
            if (root.track === 'crawling' && (root.coverPath || root.brandIcon))
                return { kind: 'ready', source: root.coverPath ? 'file://' + root.coverPath : root.brandIcon, key: 'showcase-cover' };
            return states[id] || ({ kind: 'unavailable', source: '', reason: 'no-artwork' });
        }
        function request(id, urls) {}
        function release(id) {}
    }
    property QtObject fakeShelf: QtObject {
        property bool ready: true
        property bool writable: false
        property string loadError: ''
        property var entries: []
        signal commandFinished(string requestId, var result)
        function addUris(uris) { return ''; }
        function remove(id) { return ''; }
    }
    property QtObject fakeHyprland: QtObject {
        readonly property var state: ({ kind: 'ready', value: {
            outputs: [{ id: 'showcase', name: 'showcase', activeWorkspaceId: '2' }],
            workspaces: [1, 2, 3, 4, 5].map(function(number) {
                const id = String(number);
                return { id: id, name: id, monitor: 'showcase', special: false, active: id === '2', occupied: number <= 3,
                    apps: id === '2' ? [{ appId: 'org.pentad.Settings', appClass: 'org.pentad.Settings', width: 1200, height: 760 }] : [] };
            }),
            focusedOutputId: 'showcase', activeTitle: 'Settings — Appearance', activeClass: 'Pentad'
        } })
        function focusWorkspace(id) { return ''; }
    }
    property QtObject fakeTray: QtObject {
        readonly property var state: ({ kind: 'unavailable', reason: 'showcase' })
        function nativeItemFor(id) { return null; }
    }
    property QtObject fakeClock: QtObject {
        readonly property var locale: Qt.locale('en_US')
        readonly property date date: root.now
        readonly property var state: ({ kind: 'ready', value: { date: date } })
    }
    property QtObject fakeAudio: QtObject {
        property bool active: true
        property bool preview: false
        property bool safeMode: false
        property real contextualFeedbackUntil: 0
        property var retained: ({})
        function retainMixer(id) { retained = Object.assign({}, retained, { [id]: true }); }
        function releaseMixer(id) { const next = Object.assign({}, retained); delete next[id]; retained = next; }
        property var state: ({ kind: 'ready', value: {
            streams: [{ id: 'showcase-music', nodeId: '41', appName: 'Music', label: root.fakeMedia.state.value.current.title, mediaName: root.fakeMedia.state.value.current.title,
                icon: '', volume: 0.6, muted: false, pendingVolume: false, pendingMute: false, requestedVolume: 0.6 }],
            output: { id: 'speakers', label: 'Speakers', volume: 0.58, muted: false },
            input: { id: 'microphone', label: 'Microphone', volume: 0.4, muted: false },
            outputs: [{ id: 'speakers', label: 'Speakers', volume: 0.58, muted: false }],
            inputs: [{ id: 'microphone', label: 'Microphone', volume: 0.4, muted: false }]
        } })
        signal commandFinished(string requestId, var result)
        function setStreamVolume(id, value) { return ''; }
        function toggleStreamMute(id) { return ''; }
        function setVolume(kind, value) { return ''; }
        function adjustVolume(kind, steps) { return ''; }
        function toggleMute(kind) { return ''; }
        function cycleDefault(kind, steps) { return ''; }
        function setDefault(kind, id) { return ''; }
    }
    property QtObject fakeNetwork: QtObject {
        readonly property bool active: true
        readonly property bool preview: false
        readonly property bool safeMode: false
        readonly property var operation: null
        readonly property var state: ({ kind: 'ready', value: {
            label: 'Home', primary: 'wifi', connected: true, connectivity: 'Internet',
            wifiEnabled: true, wifiHardwareEnabled: true, wifiScanEnabled: false,
            devices: [{ name: 'wlan0', type: 'wifi', connected: true }],
            accessPoints: [{ name: 'Home', connected: true, security: 'wpa2', signal: 82, device: 'wlan0' }]
        } })
        signal commandFinished(string requestId, var result)
    }
    // A desktop without a battery, so the bar shows no charge indicator.
    property QtObject fakePower: QtObject {
        readonly property bool active: true
        readonly property bool safeMode: false
        readonly property var state: ({ kind: 'ready', value: { battery: null } })
        property var profileState: ({ kind: 'ready', value: { actual: 'balanced', profiles: ['power-saver', 'balanced', 'performance'], pending: false } })
        signal commandFinished(string id, var result)
        function setProfile(profile) { return ''; }
    }
    property QtObject fakeBrightness: QtObject {
        property bool active: true
        property bool safeMode: false
        property var state: ({ kind: 'ready', value: 0.68 })
        property var operation: null
        signal commandFinished(string requestId, var result)
        function adjust(steps) { return ''; }
    }
    property QtObject fakeDesktop: QtObject {
        readonly property bool preview: false
        readonly property bool safeMode: false
        readonly property string inhibitRequest: ''
        readonly property var state: ({ kind: 'ready', value: { inhibited: false, recording: false, keyboardLayout: 'EN',
            telemetry: { cpuPercent: 0.18, gpuPercent: 0.09, memory: { used: 7.4 * 1073741824, total: 32 * 1073741824 },
                rxBytesPerSecond: 182000, txBytesPerSecond: 24000 } } })
        signal commandFinished(string requestId, var result)
        function command(action) { return ''; }
    }
    property FileView clockManifest: FileView { path: Qt.resolvedUrl('widgets/clock/manifest.json') }
    property FileView telemetryManifest: FileView { path: Qt.resolvedUrl('widgets/telemetry/manifest.json') }
    property FileView toolsManifest: FileView { path: Qt.resolvedUrl('widgets/tools/manifest.json') }
    property FileView activityManifest: FileView { path: Qt.resolvedUrl('widgets/activity/manifest.json') }
    property Plugins barPlugins: Plugins {
        safeMode: true
        services: root.barServices
        onChanged: reconcile(root.services.config.documents.layout.widgets || [])
    }
    property QtObject barServices: QtObject {
        readonly property bool preview: false
        readonly property bool safeMode: false
        readonly property var config: root.services.config
        readonly property var plugins: root.barPlugins
        readonly property var clock: root.fakeClock
        readonly property var tray: root.fakeTray
        readonly property var audio: root.fakeAudio
        readonly property var hyprland: root.fakeHyprland
        readonly property var network: root.fakeNetwork
        readonly property var power: root.fakePower
        readonly property var media: root.fakeMedia
        readonly property var artwork: root.fakeArtwork
        readonly property var lyrics: root.fakeLyrics
        readonly property var activity: root.services.activity
        readonly property var visualizer: root.fakeVisualizer
        readonly property var popups: root.services.popups
        readonly property var shelf: root.fakeShelf
        readonly property var desktop: root.fakeDesktop
        function text(uk, en) { return en; }
    }
    property QtObject panelServices: QtObject {
        readonly property bool preview: false
        readonly property var plugins: root.services.plugins
        readonly property var popups: root.services.popups
        readonly property var config: root.services.config
        readonly property var organizer: root.services.organizer
        readonly property var notifications: root.services.notifications
        readonly property var clock: root.fakeClock
        readonly property var audio: root.fakeAudio
        readonly property var network: root.fakeNetwork
        readonly property var desktop: root.fakeDesktop
        function brightnessFor(outputId) { return root.fakeBrightness; }
        readonly property QtObject session: QtObject {
            readonly property string userName: 'alex'
            readonly property string displayName: 'Alex'
            readonly property string hostName: 'workstation'
            readonly property bool writable: true
            readonly property var capabilities: ({ lock: 'yes', logout: 'yes', reboot: 'yes', poweroff: 'yes' })
            readonly property var state: ({ action: '', confirmation: '', pending: '', error: '' })
            readonly property string confirmation: ''
            readonly property string pending: ''
            signal actionFinished(string action, bool ok)
            function canRequest(action) { return true; }
            function request(action) { return ''; }
            function confirm() { return ''; }
            function cancel() {}
        }
        readonly property QtObject quickSettings: QtObject {
            readonly property var operation: null
            readonly property string error: ''
            readonly property var state: ({ kind: 'ready', value: {
                bluetooth: true, bluetoothAvailable: true,
                bluetoothDevices: [{ id: 'headphones', label: 'Earbuds', connected: true, paired: true }],
                vpns: [{ uuid: 'work', name: 'Work VPN', active: false }],
                airplane: false, airplaneAvailable: true, night: true, nightAvailable: true,
                profile: 'balanced', busy: false, errorSetting: '', error: ''
            } })
            function toggleBluetooth() { return ''; }
            function toggleVpn(uuid) {}
            function toggleAirplane() {}
            function toggleNight() {}
        }
        readonly property var power: root.fakePower
        function text(uk, en) { return en; }
    }

    function calendarSource(id, color, items) {
        return {
            id: id, label: id, color: color,
            read: function(range, cancellation) {
                return items.map(function(item, index) {
                    const day = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate() + item.offset);
                    if (item.allDay) {
                        const next = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
                        return { id: id + '-' + index, title: item.title, allDay: true,
                            start: OrganizerLogic.dayKey(day), end: OrganizerLogic.dayKey(next) };
                    }
                    const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), item.hour, 0);
                    return { id: id + '-' + index, title: item.title, allDay: false,
                        start: start.toISOString(), end: new Date(start.getTime() + item.minutes * 60000).toISOString() };
                });
            }
        };
    }
    function addContent() {
        const controller = services.notifications.controller;
        controller.setStatus('available');
        const notes = [{ app: 'Calendar', title: 'Design review at 10:00',
            body: 'Room 4' }];
        for (const note of notes) {
            controller.notify({ app: note.app, icon: '', title: note.title, body: note.body, actions: [],
                hints: { urgency: 1, transient: false, resident: true }, expireTimeout: 0, sender: 'showcase' });
        }
        services.organizer.addTask('Send the release notes');
        services.organizer.addTask('Book train tickets');
        services.organizer.setTab('calendar');
        // Collapsed, the organizer leaves room for every quick control and slider at this height.
        services.organizer.setCollapsed(true);
        services.organizer.setSelectedDay(OrganizerLogic.dayKey(root.now));
        services.calendarSources = [
            calendarSource('work', '#F2C94C', [{ offset: 0, title: 'Design review', hour: 10, minutes: 45 },
                { offset: 3, title: 'Team sync', hour: 10, minutes: 30 }]),
            calendarSource('home', '#4FA3F7', [{ offset: 1, title: 'Dinner with Sam', hour: 19, minutes: 120 },
                { offset: 6, title: 'Climbing', hour: 18, minutes: 90 }])
        ];
    }

    // The left menu holds only tools: a registry of the bundled file and content tools, shown as the catalog.
    function helper(name) { return decodeURIComponent(Qt.resolvedUrl('helpers/' + name).toString().replace(/^file:\/\//, '')); }
    readonly property var toolNames: ['images', 'image-text', 'pdf', 'archive', 'checksum', 'qr', 'color', 'translate',
        'text-cleaner', 'json', 'codec', 'units']
    property var toolManifests: ({})
    property Plugins toolRegistry: Plugins { safeMode: true; services: root.toolServices }
    property QtObject toolServices: QtObject {
        readonly property bool preview: true
        readonly property bool safeMode: true
        function text(uk, en) { return en; }
        readonly property var config: QtObject { readonly property var documents: ({ layout: { widgets: [] } }) }
        readonly property var plugins: root.toolRegistry
        readonly property ToolWorkspace toolWorkspace: ToolWorkspace {}
        readonly property FileInput fileInput: FileInput { helperPath: root.helper('pentad_read_input.py') }
        readonly property FileTools fileTools: FileTools { helperPath: root.helper('pentad_file_tool.py') }
        readonly property ToolPreviews toolPreviews: ToolPreviews { helperPath: root.helper('pentad_shelf_preview.py') }
    }
    Variants {
        model: root.toolNames
        delegate: Component {
            FileView {
                required property var modelData
                path: Qt.resolvedUrl('widgets/' + modelData + '/manifest.json')
                printErrors: false
                onLoaded: root.toolManifests = Object.assign({}, root.toolManifests, { [modelData]: JSON.parse(text()) })
            }
        }
    }

    // Spotlight with a short query; the only application result carries the repository's own icon.
    property QtObject fakeSpotlight: QtObject {
        property bool visible: true
        property string outputName: ''
        property string query: 'set'
        property string page: 'results'
        property int selectedIndex: 0
        property int actionIndex: 0
        property string error: ''
        property string status: ''
        property bool searchPending: false
        readonly property bool pending: searchPending
        property var steamIcons: ({})
        property var results: [
            { id: 'app-org.pentad.Settings.desktop', category: 'app', title: 'Pentad Settings',
                subtitle: 'Appearance, bar and widgets', icon: root.brand ? root.brand + '/app-icon.svg' : '' },
            { id: 'file-setlist', category: 'file', title: 'Setlist — Friday.pdf', subtitle: '~/Documents', icon: 'application-pdf',
                preview: { type: 'file', kind: 'pdf', path: '/home/alex/Documents/Setlist — Friday.pdf', size: 48000, modified: 1795400000000 } },
            { id: 'file-sunset', category: 'file', title: 'Sunset over the bay.png', subtitle: '~/Pictures', icon: 'image-x-generic',
                preview: { type: 'file', kind: 'image', path: '/home/alex/Pictures/Sunset over the bay.png', size: 192345, modified: 1795400000000 } },
            { id: 'file-settings-backup', category: 'file', title: 'Settings backup', subtitle: '~/Documents', icon: 'folder',
                preview: { type: 'file', kind: 'folder', path: '/home/alex/Documents/Settings backup', size: -1, modified: 1795400000000 } },
            { id: 'web-set', category: 'web', title: 'Search the web for “set”',
                subtitle: 'https://duckduckgo.com/?q=set', icon: 'world-search', preview: { metadata: { Query: 'set' } } }
        ]
        readonly property var selectedResult: results[selectedIndex] || null
        property var history: ({ pinned: [], recent: [] })
        property string previewImage: ''
        property string selectionImage: ''
        property var selectionText: null
        property bool clipboardPastes: true
        readonly property var actions: [
            { id: 'primary', label: 'Open', shortcut: 'Enter' },
            { id: 'pin', label: 'Pin', shortcut: 'Ctrl+Shift+P' },
            { id: 'details', label: 'Details', shortcut: 'Ctrl+Space' }
        ]
        function group(result) {
            if (!result) return '';
            return ({ app: 'Applications', file: 'Files', web: 'Web search' })[result.category] || '';
        }
        function primaryLabel(result) { return result?.category === 'web' ? 'Search' : 'Open'; }
        function back() { if (page === 'results') return false; page = 'results'; return true; }
        function runAction(id) {}
        function showActions() {}
        function showDetails() {}
        function activate(index) { return false; }
        function move(delta) {}
        function pin() {}
        function close() {}
        function pointerHover(hovered) {}
    }
    property QtObject spotlightServices: QtObject {
        property var spotlight: root.fakeSpotlight
        property var popups: QtObject { function hostVisibility(name, visible) {} }
        property var config: ({ documents: { interface: { language: 'en' }, layout: { barHeight: root.barHeight } } })
        function text(uk, en) { return en; }
    }

    // The screenshot editor opens on a frozen frame of this very desktop with a document window on it.
    property QtObject screenshotServices: QtObject {
        property bool preview: true
        property bool safeMode: true
        property var config: QtObject {
            property var documents: ({ screenshots: { color: '#FF5A4F', strokeWidth: 4, fontSize: 24,
                localKeys: { cancel: 'Esc', copy: 'Ctrl+C', save: 'Ctrl+S', undo: 'Ctrl+Z', redo: 'Ctrl+Shift+Z' } } })
            function save(name, value) {}
        }
        function text(uk, en) { return en; }
    }
    property QtObject fakeScreenshot: QtObject {
        property string outputId: 'showcase'
        property string imagePath: root.screenSource
        property int imageWidth: root.canvasWidth * root.captureScale
        property int imageHeight: root.canvasHeight * root.captureScale
        property var windowRegions: []
        property bool busy: false
        property string phase: 'selecting'
        property string error: ''
        property var lastExport: null
        property var pickEngines: []
        signal exported(bool closeAfter)
        function chooseOutput(output) { return true; }
        function exportImage(document, action, closeAfter) { return true; }
        function close() {}
    }
    readonly property rect documentWindow: Qt.rect(250, 150, 720, 470)

    Component.onCompleted: {
        Theme.resolve({ appearance: light ? 'light' : 'dark',
            accent: Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677', fontFamily: 'Geist', reducedMotion: true });
    }

    Shell.SpotlightHost {
        id: spotlightHost
        services: root.spotlightServices
    }

    FloatingWindow {
        visible: true
        implicitWidth: root.canvasWidth
        implicitHeight: root.canvasHeight
        color: '#0A0F0C'
        Item {
            id: capture
            width: root.canvasWidth; height: root.canvasHeight
            clip: true

            // The brand wallpaper, the same in every appearance: a deep field with two emerald glows, the
            // colour mark very large and soft with a blurred glow behind it, and a dark veil so it stays quiet.
            Item {
                id: wallpaper
                anchors.fill: parent
                Rectangle { anchors.fill: parent; color: '#0A0F0C' }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    LightPool { cx: 0; cy: 0; radius: 900; tint: '#1B4A33' }
                    LightPool { cx: root.canvasWidth; cy: root.canvasHeight; radius: 700; tint: Qt.alpha('#123B2A', 0.8) }
                }
                Image {
                    id: markSource
                    visible: false
                    width: 800; height: 800
                    source: root.brand ? 'file://' + root.brand + '/mark.svg' : ''
                    sourceSize: Qt.size(1600, 1600)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                MultiEffect {
                    source: markSource
                    width: markSource.width; height: markSource.height
                    x: root.canvasWidth * 0.72 - width / 2
                    y: root.canvasHeight * 0.55 - height / 2
                    rotation: -8
                    opacity: 0.4
                    blurEnabled: true
                    blur: 1
                    blurMax: 64
                    autoPaddingEnabled: true
                }
                MultiEffect {
                    source: markSource
                    width: markSource.width; height: markSource.height
                    x: root.canvasWidth * 0.72 - width / 2
                    y: root.canvasHeight * 0.55 - height / 2
                    rotation: -8
                    opacity: 0.24
                    blurEnabled: true
                    blur: 0.4
                    blurMax: 16
                    autoPaddingEnabled: true
                }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }
            }

            // A document window, only on the frame the screenshot editor freezes.
            Rectangle {
                id: documentWindow
                visible: root.scene === 'screen-source'
                x: root.documentWindow.x; y: root.documentWindow.y
                width: root.documentWindow.width; height: root.documentWindow.height
                radius: 14
                color: '#F4F2EC'
                Rectangle { width: parent.width; height: 40; radius: 14; color: '#E7E3D9'
                    Rectangle { y: 26; width: parent.width; height: 14; color: parent.color } }
                Text { x: 20; y: 11; text: 'Release notes — Pentad 0.1'; color: '#4A4A44'; font.family: 'Geist'; font.pixelSize: 14 }
                Text { x: 36; y: 62; text: 'Pentad 0.1'; color: '#1E211D'; font.family: 'Geist'; font.pixelSize: 30; font.weight: 600 }
                Text { x: 36; y: 104; text: 'The first public preview of the shell.'; color: '#5C5F57'; font.family: 'Geist'; font.pixelSize: 16 }
                Text { x: 36; y: 150; text: 'What’s new'; color: '#1E211D'; font.family: 'Geist'; font.pixelSize: 18; font.weight: 600 }
                Column {
                    x: 36; y: 184; spacing: 10
                    Repeater {
                        model: ['Drag anything onto the bar to route it', 'Spotlight for apps, files, clipboard and emoji',
                            'A screenshot editor with arrows, boxes and blur', 'Synced lyrics in the live island']
                        Row {
                            required property string modelData
                            spacing: 10
                            Rectangle { width: 6; height: 6; radius: 3; color: '#3F7D5C'; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: parent.modelData; color: '#2E312C'; font.family: 'Geist'; font.pixelSize: 16 }
                        }
                    }
                }
                Text { x: 36; y: 330; text: 'Access token'; color: '#5C5F57'; font.family: 'Geist'; font.pixelSize: 14 }
                Text { x: 150; y: 328; text: '4f9c-2b71-a0de-77c3-e015'; color: '#1E211D'; font.family: 'monospace'; font.pixelSize: 16 }
                Rectangle {
                    x: 36; y: 386; width: 150; height: 44; radius: 22; color: '#1E3D2C'
                    Text { anchors.centerIn: parent; text: 'Download'; color: '#F4F2EC'; font.family: 'Geist'; font.pixelSize: 16; font.weight: 500 }
                }
            }

            Rectangle { x: 0; y: 0; width: parent.width; height: root.barHeight; color: Theme.tokens.surface }
            BarFace {
                id: bar
                x: 0; y: 0; width: parent.width; height: root.barHeight
                horizontalInset: 16
                services: root.barServices
                outputId: 'showcase'
            }

            AttachedSideSurface {
                id: leftSurface
                visible: root.scene === 'tools'
                x: 0
                y: root.barHeight
                width: 390 + shoulder
                height: parent.height - root.barHeight
                side: 'left'
                contentComponent: Component { Item {} }
                loadContent: false
                SidebarView {
                    id: sidebar
                    width: 390
                    height: leftSurface.height
                    services: root.toolServices
                    outputId: 'showcase'
                }
            }

            AttachedSideSurface {
                id: rightSurface
                visible: root.scene === 'control-center'
                x: parent.width - width
                y: root.barHeight
                width: 390 + shoulder
                height: parent.height - root.barHeight
                side: 'right'
                contentComponent: Component { Item {} }
                loadContent: false
                RightPanel {
                    id: rightPanel
                    width: 390
                    height: rightSurface.height
                    services: root.panelServices
                    outputId: 'showcase'
                    brightness: root.fakeBrightness
                    presented: true
                }
            }

            ContinuousSurface {
                id: menuSurface
                visible: root.scene === 'media'
                x: (parent.width - width) / 2
                y: root.barHeight
                width: 508
                height: menu.implicitHeight + 24
                extent: Metrics.attachedRadius
                concaveShoulder: Metrics.attachedShoulder
                joinOffset: 0
                fill: Theme.tokens.surface
                ActivityMenu {
                    id: menu
                    x: 44; y: 12; width: 420
                    services: root.barServices
                    stashServices: root.barServices
                    outputId: 'showcase-menu'
                }
            }

            // Spotlight's layer-shell content cannot be grabbed, so its search UI is moved in here.
            Item {
                id: spotlightHolder
                anchors.fill: parent
                visible: root.scene === 'spotlight'
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.18) }
            }

            Loader {
                id: editorLoader
                anchors.fill: parent
                active: root.scene === 'screen-tools' && !!root.screenSource
                sourceComponent: ScreenshotEditor {
                    services: root.screenshotServices
                    screenshot: root.fakeScreenshot
                    outputId: 'showcase'
                    capture: ({ path: root.screenSource, width: root.canvasWidth * root.captureScale,
                        height: root.canvasHeight * root.captureScale, windowRegions: [] })
                    mode: 'edit'
                    initialCrop: null
                }
            }
        }
    }

    function findItem(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = findItem(child, name); if (found) return found; }
        return null;
    }
    function save(suffix, next) {
        const path = Quickshell.env('PENTAD_ARTIFACT_PATH');
        capture.grabToImage(function(result) {
            root.check('capture-' + (suffix || 'main'), !!path && result.saveToFile(path + suffix));
            next();
        });
    }
    function annotateEditor() {
        const editor = editorLoader.item;
        const canvas = root.findItem(editor, 'screenshot-canvas');
        const s = root.captureScale;
        const w = root.documentWindow;
        const px = function(value) { return Math.round(value * s); };
        editor.edit(ScreenshotModel.setCrop(editor.document, { x: px(w.x - 24), y: px(w.y - 24), width: px(w.width + 48), height: px(w.height + 40) }));
        canvas.selecting = false;
        editor.tool = 'arrow';
        const base = { color: '#FF5A4F', strokeWidth: 3 * s, points: [] };
        editor.edit(ScreenshotModel.addAnnotation(editor.document, Object.assign({}, base, { id: 'box', type: 'rectangle',
            x: px(w.x + 22), y: px(w.y + 140), width: px(436), height: px(168) })));
        editor.edit(ScreenshotModel.addAnnotation(editor.document, Object.assign({}, base, { id: 'arrow', type: 'arrow',
            x: px(w.x + 400), y: px(w.y + 448), width: px(-196), height: px(-38) })));
        // The editor has no blur; a redaction bar in the ink colour hides the token instead.
        editor.edit(ScreenshotModel.addAnnotation(editor.document, Object.assign({}, base, { id: 'redact', type: 'redact', color: '#1E211D',
            x: px(w.x + 142), y: px(w.y + 322), width: px(250), height: px(32) })));
        root.check('editor-annotated', editor.document.annotations.length === 3, String(editor.document.annotations.length));
    }

    Timer {
        interval: 100
        repeat: true
        running: !root.ready
        onTriggered: {
            const manifests = [['clock', root.clockManifest], ['telemetry', root.telemetryManifest],
                ['tools', root.toolsManifest], ['activity', root.activityManifest]];
            if (!manifests.every(function(entry) { return entry[1].loaded; })) return;
            if (Object.keys(root.toolManifests).length !== root.toolNames.length) return;
            for (const [name, file] of manifests)
                root.barPlugins.registerManifest(JSON.parse(file.text()), Qt.resolvedUrl('widgets/' + name + '/'), true);
            root.barPlugins.reconcile(root.services.config.documents.layout.widgets || []);
            for (const name of root.toolNames) {
                const registered = root.toolRegistry.registerManifest(root.toolManifests[name], Qt.resolvedUrl('widgets/' + name + '/'), true);
                if (!registered.ok) root.check('tool-manifest-' + name, false, registered.errors.join('; '));
            }
            root.services.activity.karaoke = true;
            root.addContent();
            root.ready = true;
            stop();
            steps.start();
        }
    }
    Timer {
        id: steps
        interval: 1200
        repeat: true
        property int step: 0
        onTriggered: {
            step++;
            const path = Quickshell.env('PENTAD_ARTIFACT_PATH');
            if (step === 1) {
                root.check('island-shows-crawling', !!root.findNamed(bar, 'island-focus-card') || !!root.findNamed(bar, 'island-lyrics')
                    || !!root.findNamed(bar, 'island'), 'island');
                root.check('workspace-shows-app-icon', !!root.findNamed(bar, 'collapsed-workspace-icon')
                    && root.findNamed(bar, 'collapsed-workspace-icon').status === Image.Ready);
                stop();
                root.save('.rest.png', function() { root.scene = 'control-center'; steps.start(); });
            } else if (step === 2) {
                root.check('control-center-loaded', !!root.findNamed(rightPanel, 'control-center-notifications'));
                root.check('control-center-logo', !!root.findNamed(rightPanel, 'control-center-logo'));
                stop();
                root.save('', function() { root.scene = 'tools'; steps.start(); });
            } else if (step === 3) {
                root.check('tool-catalog-shown', sidebar.visibleTools.length >= 8, String(sidebar.visibleTools.length));
                stop();
                root.save('.tools.png', function() { root.scene = 'media'; steps.start(); });
            } else if (step === 4) {
                stop();
                root.save('.media.png', function() { root.track = 'lanterns'; steps.start(); });
            } else if (step === 5) {
                stop();
                root.save('.karaoke.png', function() {
                    root.track = 'crawling';
                    const capsule = root.findItem(spotlightHost.contentItem, 'spotlight-capsule');
                    root.check('spotlight-exists', !!capsule);
                    if (capsule) {
                        const content = capsule.parent.parent;
                        content.parent = spotlightHolder;
                        content.width = root.canvasWidth;
                        content.height = root.canvasHeight;
                    }
                    root.scene = 'spotlight';
                    steps.start();
                });
            } else if (step === 6) {
                stop();
                root.save('.spotlight.png', function() { root.scene = 'screen-source'; steps.start(); });
            } else if (step === 7) {
                stop();
                capture.grabToImage(function(result) {
                    const source = path + '.screen-source.png';
                    root.check('screen-source', result.saveToFile(source));
                    root.screenSource = source;
                    root.scene = 'screen-tools';
                    steps.start();
                });
            } else if (step === 8) {
                if (!editorLoader.item || !editorLoader.item.ready) { step--; return; }
                root.annotateEditor();
            } else if (step === 9) {
                stop();
                root.save('.screen-tools.png', function() { root.finish(); });
            }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: { root.check('showcase-timeout', false); root.finish(); } }
}
