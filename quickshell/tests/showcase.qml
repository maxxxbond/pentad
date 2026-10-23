import QtQuick
import QtQml
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.theme
import qs.services
import qs.components
import qs.features.bar
import qs.features.media
import qs.features.system
import '../logic/lyrics.mjs' as LyricsLogic
import '../logic/organizer.mjs' as OrganizerLogic

// Renders the README images: a generated wallpaper with the real bar and one open surface, fed by
// invented English data. Nothing here is personal; the desktop is composed inside one window because
// the virtual compositor offers no screen capture.
ShellRoot {
    id: root
    readonly property bool light: Quickshell.env('PENTAD_GALLERY_APPEARANCE') === 'light'
    readonly property date now: new Date(2026, 9, 23, 19, 42, 0)
    readonly property int canvasWidth: 1280
    readonly property int canvasHeight: 800
    readonly property int barHeight: services.config.documents.layout.barHeight
    property Services services: Services { preview: true; safeMode: true }
    property var checks: []
    property bool ready: false
    property string scene: 'control-center'

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
        const children = item.children || [];
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
            { id: 'showcase.music', name: 'spotify', title: 'Paper Lanterns', artist: 'Lumen Fields', album: 'Low Tide',
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
        readonly property var state: ({ kind: 'ready', value: {
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
        function stateFor(id) { return states[id] || ({ kind: 'unavailable', source: '', reason: 'no-artwork' }); }
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
                return { id: id, name: id, monitor: 'showcase', special: false, active: id === '2', occupied: number <= 3 };
            }),
            focusedOutputId: 'showcase', activeTitle: 'Release notes', activeClass: 'editor'
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
            streams: [{ id: 'showcase-music', nodeId: '41', appName: 'Music', label: 'Paper Lanterns', mediaName: 'Paper Lanterns',
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
                bluetoothDevices: [{ id: 'headphones', label: 'Headphones', connected: true, paired: true }],
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
        const notes = [{ app: 'Calendar', title: 'Design review in 15 minutes', body: 'Room 4' }];
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
            calendarSource('work', '#F2C94C', [{ offset: 0, title: 'Design review', hour: 20, minutes: 45 },
                { offset: 3, title: 'Team sync', hour: 10, minutes: 30 }]),
            calendarSource('home', '#4FA3F7', [{ offset: 1, title: 'Dinner with Sam', hour: 19, minutes: 120 },
                { offset: 6, title: 'Climbing', hour: 18, minutes: 90 }])
        ];
    }

    Component.onCompleted: Theme.resolve({ appearance: light ? 'light' : 'dark',
        accent: Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677', fontFamily: 'Geist', reducedMotion: true })

    FloatingWindow {
        visible: true
        implicitWidth: root.canvasWidth
        implicitHeight: root.canvasHeight
        color: Theme.tokens.surface
        Item {
            id: capture
            width: root.canvasWidth; height: root.canvasHeight
            clip: true

            // A generated wallpaper: soft accent-tinted light pools over a deep field.
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: 'transparent'
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: root.canvasWidth; y2: root.canvasHeight
                        GradientStop { position: 0; color: root.light ? '#E4E9DE' : '#0E120E' }
                        GradientStop { position: 1; color: root.light ? '#C3CDB8' : '#1A2419' }
                    }
                    PathRectangle { x: 0; y: 0; width: root.canvasWidth; height: root.canvasHeight }
                }
                LightPool { cx: 180; cy: 660; radius: 580; tint: root.light ? '#9DB38A' : '#5E7D4E' }
                LightPool { cx: 700; cy: 110; radius: 470; tint: root.light ? '#B7CDC6' : '#2F5A55' }
                LightPool { cx: 1160; cy: 740; radius: 440; tint: root.light ? '#A9BC8E' : '#71864F' }
                LightPool { cx: 960; cy: 320; radius: 300; tint: root.light ? '#C6D3B4' : '#3C4F33' }
                LightPool { cx: 420; cy: 240; radius: 320; tint: root.light ? '#D2DCCB' : '#26392E' }
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
                    shelf: root.fakeShelf
                    outputId: 'showcase-menu'
                }
            }
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: !root.ready
        onTriggered: {
            const manifests = [['clock', root.clockManifest], ['telemetry', root.telemetryManifest],
                ['tools', root.toolsManifest], ['activity', root.activityManifest]];
            if (!manifests.every(function(entry) { return entry[1].loaded; })) return;
            for (const [name, file] of manifests)
                root.barPlugins.registerManifest(JSON.parse(file.text()), Qt.resolvedUrl('widgets/' + name + '/'), true);
            root.barPlugins.reconcile(root.services.config.documents.layout.widgets || []);
            root.services.activity.karaoke = true;
            root.addContent();
            root.ready = true;
            stop();
            steps.start();
        }
    }
    Timer {
        id: steps
        interval: 900
        repeat: true
        property int step: 0
        onTriggered: {
            step++;
            const path = Quickshell.env('PENTAD_ARTIFACT_PATH');
            if (step === 1) {
                root.check('island-shows-the-track', !!root.findNamed(bar, 'island-lyrics') || !!root.findNamed(bar, 'island-focus-card'));
                root.check('control-center-loaded', !!root.findNamed(rightPanel, 'control-center-notifications'));
                stop();
                capture.grabToImage(function(result) {
                    root.check('control-center-capture', !!path && result.saveToFile(path));
                    root.scene = 'media';
                    steps.start();
                });
            } else if (step === 2) {
                stop();
                capture.grabToImage(function(result) {
                    root.check('media-capture', !!path && result.saveToFile(path + '.media.png'));
                    root.finish();
                });
            }
        }
    }
}
