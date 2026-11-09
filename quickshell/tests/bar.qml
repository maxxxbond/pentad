import QtQuick
import QtQml
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import qs.services
import qs.features.bar

ShellRoot {
    id: root
    property Services nativeServices: Services { preview: true; safeMode: true }
    property bool captureBaseline: false
    property QtObject fixtureHyprland: QtObject {
        readonly property var state: root.captureBaseline ? ({ kind: 'unavailable' }) : ({ kind: 'ready', value: {
            outputs: [{ id: 'preview', name: 'preview', activeWorkspaceId: '1' }],
            workspaces: Array.from({ length: 24 }, function(_, index) { var id = index + 1; return {
                id: String(id), name: String(id), monitor: 'preview', special: false, active: id === 1, occupied: false
            }; }),
            focusedOutputId: 'preview', activeTitle: 'A long fixture title used to check available width', activeClass: 'fixture-app'
        } })
        function focusWorkspace(id) { return root.nativeServices.hyprland.focusWorkspace(id); }
    }
    property QtObject fixtureTrayNativeItem: QtObject {
        readonly property string title: 'Fixture tray item'
        readonly property url icon: Qt.resolvedUrl('assets/icons/material/network-wired-symbolic.svg')
        readonly property bool hasMenu: false
        readonly property var menu: null
        function activate() {}
    }
    property QtObject fixtureTray: QtObject {
        readonly property var state: root.captureBaseline
            ? ({ kind: 'unavailable' })
            : ({ kind: 'ready', value: { items: [{ id: 'fixture-tray' }] } })
        function nativeItemFor(id) { return id === 'fixture-tray' ? root.fixtureTrayNativeItem : null; }
    }
    property FileView clockManifest: FileView { path: Qt.resolvedUrl('widgets/clock/manifest.json') }
    property QtObject fakeClock: QtObject {
        readonly property var locale: Qt.locale('en_US')
        readonly property date date: new Date(2026, 9, 9, 13, 45, 0)
        readonly property var state: ({ kind: 'ready', value: { date: date } })
    }
    property Plugins fixturePlugins: Plugins {
        safeMode: true
        services: root.fixtureServices
        onChanged: reconcile(root.nativeServices.config.documents.layout.widgets || [])
    }
    property QtObject fixtureServices: QtObject {
        readonly property bool preview: true
        readonly property bool safeMode: true
        function text(uk, en) { return uk; }
        readonly property var config: root.nativeServices.config
        readonly property var plugins: root.fixturePlugins
        readonly property var clock: root.fakeClock
        readonly property var tray: root.fixtureTray
        readonly property var audio: root.nativeServices.audio
        readonly property var hyprland: root.fixtureHyprland
        readonly property var network: root.nativeServices.network
        readonly property var power: root.nativeServices.power
        readonly property var media: root.nativeServices.media
        readonly property var artwork: root.nativeServices.artwork
        readonly property var lyrics: root.nativeServices.lyrics
        readonly property var activity: root.nativeServices.activity
        readonly property var visualizer: root.nativeServices.visualizer
        readonly property var popups: root.nativeServices.popups
        readonly property var shelf: root.nativeServices.shelf
        readonly property QtObject desktop: QtObject {
            property var commands: []
            function command(name) { commands = commands.concat([name]); return 'fixture-' + commands.length; }
            readonly property var state: ({ kind: 'ready', value: { recording: false, keyboardLayout: 'EN',
                keyboardLayoutName: 'English (US)', keyboardLayoutIndex: 0, keyboardLayoutCount: 2, keyboardLayouts: [
                    { index: 0, label: 'EN', name: 'English (US)' }, { index: 1, label: 'UA', name: 'Ukrainian' }
                ], telemetry: {
                cpuPercent: 0.12, gpuPercent: null, memory: { used: 4 * 1073741824, total: 16 * 1073741824 }, rxBytesPerSecond: 1024, txBytesPerSecond: 2048
            } } })
        }
    }
    property bool ready: false
    property string privacyProbeDetail: ''
    property bool telemetryPopupChecksDone: false
    property bool telemetryCaptureDone: false
    property bool telemetryStressCaptureDone: false
    property QtObject ukrainianText: QtObject { function text(uk, en) { return uk; } }
    property bool captureReported: false
    property var pendingChecks: []
    property var outputProbe: null
    property var outputProbePopup: null
    property Component outputProbeFactory: Component {
        PanelWindow {
            visible: true
            anchors { top: true; left: true; right: true }
            implicitHeight: 40
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            property alias widget: outputWidget
            Item {
                objectName: 'pentad-bar-face'
                anchors.fill: parent
                TelemetryWidget { id: outputWidget; x: 24; y: 6; width: 260; services: root.fixtureServices }
            }
        }
    }
    property TestEvent pointer: TestEvent {}
    property var interactionChecks: []
    property string requestedWorkspace: ''
    function findNamedItem(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const items = item.children || [];
        for (let index = 0; index < items.length; index++) {
            const found = findNamedItem(items[index], name);
            if (found) return found;
        }
        return null;
    }
    function gaugeFractions(item) {
        let fractions = item.objectName === 'telemetry-resource-gauge' ? [item.fraction] : [];
        for (const child of item.children || []) fractions = fractions.concat(gaugeFractions(child));
        return fractions.sort(function(a, b) { return a - b; });
    }
    function check(name, passed, detail) {
        interactionChecks.push({ name: name, passed: passed === true, detail: detail || '' });
    }
    // A shown wing keeps clear of its side's content: the left one with the workspace strip at rest.
    function wingsClearSides(bar) {
        const leftEnd = bar.horizontalInset + bar.leftRestingWidth + (bar.leftRestingWidth > 0 ? 8 : 0);
        return (!bar.telemetryShown || bar.centerLeft >= leftEnd)
            && (!bar.toolsShown || bar.centerRight <= bar.rightContentLeft - 8);
    }
    function wingState(bar) {
        return JSON.stringify({ width: bar.width, telemetry: bar.telemetryShown, tools: bar.toolsShown,
            centerLeft: bar.centerLeft, centerRight: bar.centerRight, leftResting: bar.leftRestingWidth,
            rightContentLeft: bar.rightContentLeft });
    }
    function reportChecks(checks) {
        if (captureReported) return;
        captureReported = true;
        const passed = checks.every(function(check) { return check.passed; });
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
    Connections { target: wide.workspaceSwitcher; function onSwitchRequested(id) { root.requestedWorkspace = id; } }
    Component.onCompleted: {
        var appearance = Quickshell.env('PENTAD_GALLERY_APPEARANCE') === 'light' ? 'light' : 'dark';
        var requestedAccent = Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677';
        var accent = /^#[0-9a-f]{6}$/i.test(requestedAccent) ? requestedAccent : '#869677';
        var reducedMotion = Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1';
        Theme.resolve({ appearance: appearance, accent: accent, fontFamily: 'Geist', reducedMotion: reducedMotion });
    }
    FloatingWindow {
        visible: true
        implicitWidth: 2048
        implicitHeight: 140
        color: Theme.tokens.surface
        Item {
            id: capture
            width: 2048; height: 140
            Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
            BarFace { id: wide; y: 0; width: 2048; height: 40; horizontalInset: 16; services: root.fixtureServices; outputId: 'preview' }
            BarFace { id: compact; y: 80; width: 1024; height: 40; horizontalInset: 16; services: root.fixtureServices; outputId: 'preview' }
            BarFace { id: widthProbe; y: 40; opacity: 0; width: 1240; height: 40; horizontalInset: 16; workspaceHeld: true; services: root.fixtureServices; outputId: 'preview' }
            BarFace { id: privacyProbe; y: 40; opacity: 0; width: 1080; height: 40; services: root.privacyProbeServices; outputId: 'preview' }
        }
    }
    PanelWindow {
        id: telemetryProbeWindow
        visible: true
        anchors { top: true; left: true; right: true }
        implicitHeight: 40
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Item {
            objectName: 'pentad-bar-face'
            anchors.fill: parent
            TelemetryWidget { id: telemetryProbe; x: 24; y: 6; width: 260; services: root.fixtureServices }
            StatusCluster { id: audioProbe; x: 600; services: root.audioProbeServices }
            StatusCluster { id: batteryProbe; x: 760; services: root.batteryProbeServices }
            Row { id: microphoneRow; x: 900; y: 10; MicrophoneIndicator { id: microphoneProbe; services: root.microphoneProbeServices } }
        }
    }
    // The preview audio service is unavailable, so the microphone indicator reads a fake capture state.
    property QtObject microphoneProbeServices: QtObject {
        function text(uk, en) { return en; }
        readonly property QtObject audio: QtObject {
            property bool active: true
            property bool muted: false
            property bool omitMicrophone: false
            property var apps: [{ key: 'handy', label: 'Handy', icon: '' }]
            readonly property var state: ({ kind: 'ready', value: omitMicrophone ? {}
                : { microphone: { active: active, muted: muted, apps: apps } } })
        }
    }
    // A 1080 px portrait bar whose microphone and screen-recording icons the test switches on and off.
    // Everything but audio, desktop and tray comes from the shared fixture.
    readonly property var privacyFixture: root.fixtureServices
    property QtObject privacyProbeServices: QtObject {
        readonly property bool preview: true
        readonly property bool safeMode: true
        function text(uk, en) { return uk; }
        readonly property var config: root.privacyFixture.config
        readonly property var plugins: root.privacyFixture.plugins
        readonly property var clock: root.privacyFixture.clock
        // No tray, so the 1080 px bar's tools wing has its threshold within reach of the inset.
        readonly property QtObject tray: QtObject {
            readonly property var state: ({ kind: 'unavailable' })
            function nativeItemFor(id) { return null; }
        }
        readonly property var hyprland: root.privacyFixture.hyprland
        readonly property var network: root.privacyFixture.network
        readonly property var power: root.privacyFixture.power
        readonly property var media: root.privacyFixture.media
        readonly property var artwork: root.privacyFixture.artwork
        readonly property var lyrics: root.privacyFixture.lyrics
        readonly property var activity: root.privacyFixture.activity
        readonly property var visualizer: root.privacyFixture.visualizer
        readonly property var popups: root.privacyFixture.popups
        readonly property var shelf: root.privacyFixture.shelf
        readonly property QtObject audio: QtObject {
            property bool microphoneActive: false
            property real contextualFeedbackUntil: 0
            signal commandFinished(string requestId, var result)
            readonly property var state: ({ kind: 'ready', value: { output: null, input: null, outputs: [], inputs: [],
                microphone: { active: microphoneActive, muted: false, apps: [{ key: 'handy', label: 'Handy', icon: '' }] } } })
            function setDefault(kind, id) { return ''; }
            function toggleMute(kind) { return ''; }
            function cycleDefault(kind, steps) { return ''; }
            function adjustVolume(kind, steps) { return ''; }
        }
        readonly property QtObject desktop: QtObject {
            property bool recording: false
            function command(name) { return ''; }
            // No keyboard layout either: the tray and the layout label are what this side can spare.
            readonly property var state: ({ kind: 'ready', value: { recording: recording, keyboardLayout: '', telemetry: {
                cpuPercent: 0.12, gpuPercent: null, memory: { used: 4 * 1073741824, total: 16 * 1073741824 }, rxBytesPerSecond: 1024, txBytesPerSecond: 2048
            } } })
        }
    }
    // A laptop battery with layout.showBatteryPercent on; the audio probe above keeps the default (off).
    property QtObject batteryProbeServices: QtObject {
        readonly property var network: root.nativeServices.network
        readonly property var popups: root.nativeServices.popups
        readonly property var audio: root.audioProbeServices.audio
        function text(uk, en) { return en; }
        readonly property QtObject power: QtObject {
            readonly property var state: ({ kind: 'ready', value: { battery: { percent: 63.6, state: 'discharging' } } })
        }
        readonly property QtObject config: QtObject {
            readonly property var documents: ({ layout: { showBatteryPercent: true } })
        }
    }
    // The preview audio service is unavailable, so the device list is checked against a fake one.
    property QtObject audioProbeServices: QtObject {
        readonly property var network: root.nativeServices.network
        readonly property var power: root.nativeServices.power
        readonly property var popups: root.nativeServices.popups
        function text(uk, en) { return en; }
        readonly property QtObject audio: QtObject {
            property real contextualFeedbackUntil: 0
            property var selected: []
            signal commandFinished(string requestId, var result)
            readonly property var state: ({ kind: 'ready', value: {
                output: { id: '2', label: 'Speakers', volume: 0.5, muted: false },
                input: null,
                outputs: [{ id: '1', label: 'Headphones', volume: 0.3, muted: false }, { id: '2', label: 'Speakers', volume: 0.5, muted: false }],
                inputs: []
            } })
            function setDefault(kind, id) { selected = selected.concat([kind + ':' + id]); return 'probe-' + selected.length; }
            function toggleMute(kind) { return ''; }
            function cycleDefault(kind, steps) { return ''; }
        }
    }
    Timer {
        id: telemetryPopupTest
        interval: 120
        repeat: true
        running: root.ready
        property int step: 0
        onTriggered: {
            step++;
            if (step === 1) {
                const percent = root.findNamedItem(batteryProbe, 'battery-percent');
                const hiddenPercent = root.findNamedItem(audioProbe, 'battery-percent');
                root.check('battery-percent-follows-layout', !!percent && percent.visible && percent.text === '64%'
                    && (!hiddenPercent || !hiddenPercent.visible),
                    percent ? percent.text + '/' + percent.visible : 'missing');
                root.check('telemetry-popup-starts-closed', !telemetryProbe.detailsOpen);
                root.pointer.mouseMove(telemetryProbe.capsuleItem, telemetryProbe.capsuleItem.width / 2, telemetryProbe.capsuleItem.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                interval = 250;
            } else if (step === 2) {
                root.check('telemetry-hover-does-not-open-details', !telemetryProbe.detailsOpen);
                root.check('telemetry-pointer-click-dispatched', root.pointer.mouseClick(telemetryProbe.capsuleItem, telemetryProbe.capsuleItem.width / 2, telemetryProbe.capsuleItem.height / 2, Qt.LeftButton, Qt.NoModifier, 0));
                interval = 100;
            } else if (step === 3) {
                root.check('telemetry-click-opens-details', telemetryProbe.detailsOpen);
                root.check('telemetry-popup-is-native-and-exceeds-panel-height', !!telemetryProbe.detailsPopup.contentItem
                    && telemetryProbeWindow.implicitHeight === 40 && telemetryProbe.detailsPopup.height > telemetryProbeWindow.height);
                root.check('telemetry-popup-uses-shared-popover', telemetryProbe.detailsPopover.anchorItem === telemetryProbe.capsuleItem
                    && telemetryProbe.detailsPopover.surface.objectName === 'attached-popover-surface'
                    && telemetryProbe.detailsPopover.manager === root.fixtureServices.popups);
                root.check('telemetry-gauges-show-cpu-gpu-and-memory-values',
                    JSON.stringify(root.gaugeFractions(telemetryProbe.detailsPopover.contentItem)) === JSON.stringify([0, 0.12, 0.25]));
                root.check('telemetry-popup-stays-compact', telemetryProbe.detailsPopup.surfaceHeight <= 248
                    && telemetryProbe.detailsPopover.contentItem.width <= 216,
                    JSON.stringify({ width: telemetryProbe.detailsPopover.contentItem.width, height: telemetryProbe.detailsPopup.surfaceHeight }));
                const networkCircle = root.findNamedItem(telemetryProbe.detailsPopover.contentItem, 'telemetry-network-circle');
                const download = root.findNamedItem(networkCircle, 'telemetry-download');
                const upload = root.findNamedItem(networkCircle, 'telemetry-upload');
                const downloadPoint = download.mapToItem(networkCircle, 0, 0);
                const uploadPoint = upload.mapToItem(networkCircle, 0, 0);
                root.check('telemetry-network-rates-are-two-rows-inside-circle', networkCircle.width === networkCircle.height
                    && downloadPoint.y < uploadPoint.y && downloadPoint.x >= 0 && uploadPoint.x >= 0
                    && downloadPoint.x + download.width <= networkCircle.width
                    && uploadPoint.y + upload.height <= networkCircle.height);
                const networkCell = root.findNamedItem(telemetryProbe.detailsPopover.contentItem, 'telemetry-network-cell');
                root.check('telemetry-four-cells-use-two-column-grid', telemetryProbe.detailsPopover.contentItem.columns === 2
                    && networkCell.x === networkCell.width + 8 && networkCell.y === 104);
                root.check('telemetry-popup-has-contract-rounding', telemetryProbe.detailsPopup.geometry.radius === Metrics.attachedRadius
                    && telemetryProbe.detailsInputRegion.containsPoint(telemetryProbe.detailsPopup.shadowRoom + Metrics.attachedShoulder + 1,
                        telemetryProbe.detailsPopup.topRoom + telemetryProbe.detailsPopup.surfaceHeight / 2)
                    && !telemetryProbe.detailsInputRegion.containsPoint(telemetryProbe.detailsPopup.shadowRoom + Metrics.attachedShoulder + 1,
                        telemetryProbe.detailsPopup.topRoom + telemetryProbe.detailsPopup.surfaceHeight - 1));
                root.check('telemetry-popup-input-follows-continuous-contour', telemetryProbe.detailsInputRegion.rows.length > 0
                    && telemetryProbe.detailsInputRegion.containsPoint(telemetryProbe.detailsPopup.width / 2, 70)
                    && !telemetryProbe.detailsInputRegion.containsPoint(0, telemetryProbe.detailsPopup.height - 1));
                const requestedCapture = telemetryProbe.detailsInputRegion.surface.grabToImage(function(result) {
                    root.check('telemetry-popup-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.telemetry-popup.png'));
                    root.telemetryCaptureDone = true;
                });
                if (!requestedCapture) {
                    root.check('telemetry-popup-capture', false, 'Popup surface rejected the capture request.');
                    root.telemetryCaptureDone = true;
                }
                root.pointer.mouseMove(telemetryProbeWindow.contentItem,
                    telemetryProbeWindow.width - 20, 20, 0, Qt.NoButton, Qt.NoModifier);
                root.pointer.mouseMove(telemetryProbe.detailsPopover.surface,
                    telemetryProbe.detailsPopup.width / 2, 40, 0, Qt.NoButton, Qt.NoModifier);
                interval = 250;
            } else if (step === 4) {
                root.check('telemetry-pointer-over-details-keeps-popup-open', telemetryProbe.detailsOpen);
                root.pointer.mouseClick(telemetryProbe.capsuleItem, telemetryProbe.capsuleItem.width / 2,
                    telemetryProbe.capsuleItem.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                interval = 150;
            } else if (step === 5) {
                root.check('telemetry-second-click-closes-details', !telemetryProbe.detailsOpen);
                root.pointer.mouseClick(telemetryProbe.capsuleItem, telemetryProbe.capsuleItem.width / 2,
                    telemetryProbe.capsuleItem.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                interval = 100;
            } else if (step === 6) {
                root.check('telemetry-opens-before-escape', telemetryProbe.detailsOpen);
                root.fixtureServices.popups.dismissTop();
                interval = 100;
            } else if (step === 7) {
                root.check('telemetry-shared-escape-dismissal-closes-details', !telemetryProbe.detailsOpen);
                root.pointer.mouseClick(telemetryProbe.capsuleItem, telemetryProbe.capsuleItem.width / 2,
                    telemetryProbe.capsuleItem.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                interval = 100;
            } else if (step === 8) {
                root.check('telemetry-reopens-after-escape', telemetryProbe.detailsOpen);
                telemetryProbe.detailsPopup.visible = false;
                root.check('telemetry-native-dismissal-clears-open-state', !telemetryProbe.detailsOpen,
                    'Exercises the native dismissal state hook, not a compositor click-away event.');
                telemetryProbe.openDetails();
                telemetryProbe.visible = false;
                root.check('telemetry-hidden-view-closes-details', !telemetryProbe.detailsOpen);
                // A bar wing without room keeps the widget laid out but disabled.
                telemetryProbe.visible = true;
                telemetryProbe.openDetails();
                const openBeforeDisabling = telemetryProbe.detailsOpen;
                telemetryProbe.enabled = false;
                root.check('telemetry-disabled-wing-closes-details', openBeforeDisabling && !telemetryProbe.detailsOpen,
                    JSON.stringify({ openBeforeDisabling: openBeforeDisabling, open: telemetryProbe.detailsOpen }));
                telemetryProbe.openDetails();
                root.check('telemetry-disabled-wing-does-not-open-details', !telemetryProbe.detailsOpen);
                telemetryProbe.enabled = true;
                telemetryProbe.visible = false;
                root.pointer.mouseMove(capture, 500, 60, 0, Qt.NoButton, Qt.NoModifier);
                root.outputProbe = root.outputProbeFactory.createObject(root);
            } else if (step === 9) {
                root.outputProbe.widget.detailsPopover.grabFocus = false;
                root.outputProbe.widget.openDetails();
            } else if (step === 10) {
                root.check('telemetry-output-owned-popup-opens', root.outputProbe.widget.detailsOpen);
                root.outputProbePopup = root.outputProbe.widget.detailsPopup;
                root.outputProbe.destroy();
            } else if (step === 11) {
                root.check('telemetry-output-destruction-disposes-popup', !root.outputProbe && !root.outputProbePopup);
                telemetryProbe.visible = true;
                const content = telemetryProbe.detailsPopover.contentItem;
                content.services = root.ukrainianText;
                content.value = { cpuPercent: 1, memory: { used: 15.9 * 1073741824, total: 16 * 1073741824 },
                    gpus: [ { id: 'card0', load: 0.89, memory: { used: 7.2 * 1073741824, total: 8 * 1073741824 } },
                        { id: 'card1', load: null, memory: null } ],
                    rxBytesPerSecond: 987.6 * 1048576, txBytesPerSecond: 12.3 * 1048576 };
                telemetryProbe.openDetails();
                interval = Motion.medium + 60;
            } else if (step === 12) {
                const content = telemetryProbe.detailsPopover.contentItem;
                function textFits(item) {
                    if (item.text !== undefined && item.truncated === true) return false;
                    if (item.contentWidth !== undefined && item.contentWidth > item.width + 1) return false;
                    return Array.from(item.children || []).every(textFits);
                }
                root.check('telemetry-ukrainian-multiple-gpus-and-large-rates-fit', textFits(content));
                const networkCell = root.findNamedItem(content, 'telemetry-network-cell');
                root.check('telemetry-five-metrics-use-three-columns-and-centered-last-pair', content.columns === 3
                    && networkCell.y === 104 && networkCell.x - networkCell.width - 8 === content.width - networkCell.x - networkCell.width);
                const fractions = root.gaugeFractions(content);
                root.check('telemetry-multiple-gpu-gauges-preserve-values', fractions.length === 4
                    && [0, 0.89, 0.99375, 1].every(function(value, index) { return Math.abs(fractions[index] - value) < 0.000001; }));
                const requestedCapture = telemetryProbe.detailsPopover.surface.grabToImage(function(result) {
                    root.check('telemetry-stress-popup-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.telemetry-stress.png'));
                    root.telemetryStressCaptureDone = true;
                });
                if (!requestedCapture) {
                    root.check('telemetry-stress-popup-capture', false);
                    root.telemetryStressCaptureDone = true;
                }
            } else if (step === 13) {
                if (!root.telemetryStressCaptureDone) { step--; return; }
                telemetryProbe.detailsPopover.contentItem.value = null;
            } else if (step === 14) {
                const content = telemetryProbe.detailsPopover.contentItem;
                function fillsAreEmpty(item) {
                    if (item.objectName === 'telemetry-resource-gauge' && item.fraction !== 0) return false;
                    return Array.from(item.children || []).every(fillsAreEmpty);
                }
                root.check('telemetry-missing-data-has-empty-meters-and-no-fabricated-rates', fillsAreEmpty(content)
                    && root.findNamedItem(content, 'telemetry-download').text === '—'
                    && root.findNamedItem(content, 'telemetry-upload').text === '—');
                telemetryProbe.visible = false;
            } else if (step === 15) {
                const content = telemetryProbe.detailsPopover.contentItem;
                content.value = { gpus: [{ id: 'card0', load: 0.1 }, { id: 'card1', load: 0.2 }, { id: 'card2', load: 0.3 }] };
            } else if (step === 16) {
                const content = telemetryProbe.detailsPopover.contentItem;
                const network = root.findNamedItem(content, 'telemetry-network-cell');
                root.check('telemetry-six-metrics-fill-two-rows', content.columns === 3 && content.metricCount === 6
                    && network.y === 104 && network.x + network.width === content.width);
                content.value = { gpus: [{ id: 'card0', load: 0.1 }, { id: 'card1', load: 0.2 },
                    { id: 'card2', load: 0.3 }, { id: 'card3', load: 0.4 }] };
            } else if (step === 17) {
                const content = telemetryProbe.detailsPopover.contentItem;
                const network = root.findNamedItem(content, 'telemetry-network-cell');
                root.check('telemetry-seven-metrics-center-the-last-circle', content.columns === 3 && content.metricCount === 7
                    && network.y === 208 && network.x === (content.width - network.width) / 2);
                root.telemetryPopupChecksDone = true;
                stop();
            }
        }
    }
    Timer {
        interval: 20000
        running: root.ready && !root.captureReported
        onTriggered: {
            const checks = root.pendingChecks.length ? root.pendingChecks : root.interactionChecks.slice();
            checks.push({ name: 'bar-capture-callback', passed: false,
                detail: 'The native image capture callback did not complete before the fixture deadline.' });
            root.reportChecks(checks);
        }
    }
    Timer {
        interval: 120; repeat: true; running: true
        property int attempts: 0
        onTriggered: {
            if (!root.ready) {
                if (!root.clockManifest.loaded) return;
                root.fixturePlugins.registerManifest(JSON.parse(root.clockManifest.text()), Qt.resolvedUrl('widgets/clock/'), true);
                root.fixturePlugins.reconcile(root.nativeServices.config.documents.layout.widgets);
                root.ready = true;
                return;
            }
            if (!root.telemetryPopupChecksDone || !root.telemetryCaptureDone || !root.telemetryStressCaptureDone) return;
            if (++attempts < 4) return;
            if (attempts === 4) {
                root.pointer.mouseMove(wide.workspaceSwitcher, 8, 20, 0, Qt.NoButton, Qt.NoModifier);
                return;
            }
            if (attempts === 5) {
                root.interactionChecks.push({ name: 'left-bar-hover-expands-workspaces', passed: wide.workspaceSwitcher.expanded && wide.workspaceSwitcher.width > 36 });
                var expandedIcon = root.findNamedItem(wide.workspaceSwitcher, 'expanded-workspace-icon');
                var expandedFallback = root.findNamedItem(wide.workspaceSwitcher, 'expanded-workspace-fallback');
                root.interactionChecks.push({ name: 'empty-workspace-image-keeps-expanded-dot', passed: !!expandedIcon && String(expandedIcon.source) === ''
                    && !expandedIcon.visible && !!expandedFallback && expandedFallback.visible && expandedFallback.text === '•' });
                wide.workspaceHeld = true;
                // Click the slot itself: a fixed x lands in the 2 px gap between 32 px slots.
                var secondWorkspace = root.findNamedItem(wide.workspaceSwitcher, 'workspace-focus-target-2');
                if (secondWorkspace)
                    root.pointer.mouseClick(secondWorkspace, secondWorkspace.width / 2, secondWorkspace.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
                root.interactionChecks.push({ name: 'workspace-pointer-dispatches-selected-id', passed: root.requestedWorkspace === '2' });
                wide.workspaceHeld = false;
                root.pointer.mouseMove(capture, 500, 60, 0, Qt.NoButton, Qt.NoModifier);
                interval = 250;
                return;
            }
            stop();
            var collapsedIcon = root.findNamedItem(wide.workspaceSwitcher, 'collapsed-workspace-icon');
            var collapsedFallback = root.findNamedItem(wide.workspaceSwitcher, 'collapsed-workspace-fallback');
            root.interactionChecks.push({ name: 'empty-workspace-image-keeps-collapsed-dot', passed: !!collapsedIcon && String(collapsedIcon.source) === ''
                && !collapsedIcon.visible && !!collapsedFallback && collapsedFallback.visible && collapsedFallback.text === '•' });
            const toolsWidget = root.findNamedItem(wide, 'quick-tools-widget');
            const toggleCapsule = root.findNamedItem(toolsWidget, 'quick-tool-toggles');
            const actionCapsule = root.findNamedItem(toolsWidget, 'quick-tool-actions');
            const toolButtons = toolsWidget ? toolsWidget.buttonRepeater : null;
            const activeTitle = root.findNamedItem(wide, 'active-window-title');
            const trayCell = root.findNamedItem(wide, 'tray-icon-cell');
            const trayIcon = root.findNamedItem(wide, 'tray-icon');
            const trayWidget = root.findNamedItem(wide, 'bar-tray-widget');
            const trayDivider = root.findNamedItem(wide, 'tray-status-divider');
            const keyboardIndicator = root.findNamedItem(wide, 'bar-keyboard-indicator');
            const statusCluster = root.findNamedItem(wide, 'bar-status-cluster');
            const clockDivider = root.findNamedItem(wide, 'clock-status-divider');
            const systemSlot = root.findNamedItem(wide, 'bar-system-slot');
            const savedSystemWithoutClock = root.nativeServices.config.documents.layout.widgets
                .filter(function(item) { return item.slot === 'system' && item.moduleId !== 'pentad.clock'; })
                .map(function(item) { return ({ moduleId: item.moduleId }); });
            if (!savedSystemWithoutClock.length) savedSystemWithoutClock.push({ moduleId: 'pentad.tools' });
            const barX = function(item) { return item ? item.mapToItem(wide, 0, 0).x : -1; };
            const groupedButtons = toolButtons && toolButtons.count === 8
                && toolButtons.itemAt(0).x === 2 && toolButtons.itemAt(1).x === 28
                && toolButtons.itemAt(2).x === 64 && toolButtons.itemAt(3).x === 92
                && toolButtons.itemAt(0).width === 24 && toolButtons.itemAt(0).height === 24;
            const checks = [
                { name: 'wide-island-physical-center', passed: Math.abs(wide.islandCenter - 1024) < 0.5 },
                { name: 'compact-island-physical-center', passed: Math.abs(compact.islandCenter - 512) < 0.5 },
                { name: 'constrained-title-width-stays-before-center', passed: (function() {
                    const title = root.findNamedItem(widthProbe, 'active-window-title');
                    if (!title) return false;
                    const titleX = title.mapToItem(widthProbe, 0, 0).x;
                    const oldWidth = Math.max(0, Math.min(320, widthProbe.centerLeft - widthProbe.horizontalInset - 60));
                    return !!title && title.visible && title.width > 0
                        && titleX + title.width <= widthProbe.centerLeft - 8
                        && titleX + oldWidth > widthProbe.centerLeft - 8;
                })() },
                { name: 'wide-bar-shows-both-wings', passed: wide.telemetryShown && wide.toolsShown, detail: root.wingState(wide) },
                { name: 'narrow-bar-keeps-telemetry-in-its-half', passed: compact.telemetryShown, detail: root.wingState(compact) },
                { name: 'shown-wings-keep-clear-of-side-content', passed: [wide, compact, widthProbe].every(root.wingsClearSides),
                    detail: [wide, compact, widthProbe].map(root.wingState).join(' ') },
                { name: 'bar-height-from-layout', passed: wide.implicitHeight === 40 },
                { name: 'preview-actions-denied', passed: !root.nativeServices.audio.active },
                { name: 'geist-font', passed: Qt.fontFamilies().indexOf('Geist') >= 0 },
                { name: 'telemetry-glyph-font', passed: Qt.fontFamilies().indexOf('Material Symbols Rounded') >= 0 },
                { name: 'tools-default-set-has-eight-repeater-controls', passed: !!toolButtons && toolButtons.count === 8 },
                { name: 'tools-toggle-capsule-geometry', passed: !!toggleCapsule && toggleCapsule.x === 0
                    && toggleCapsule.width === 54 && toggleCapsule.height === 28 },
                { name: 'tools-action-capsule-geometry', passed: !!actionCapsule && actionCapsule.x === 62
                    && actionCapsule.width === 6 * 28 && actionCapsule.height === 28 },
                { name: 'tools-controls-align-inside-separated-capsules', passed: groupedButtons },
                { name: 'active-title-width-stays-before-center', passed: !!activeTitle
                    && activeTitle.mapToItem(wide, 0, 0).x + activeTitle.width <= wide.centerLeft - 8 },
                { name: 'active-title-source-line-box-height', passed: !!activeTitle && activeTitle.height === 25 },
                { name: 'tray-cell-source-size-and-icon-size', passed: !!trayCell && trayCell.width === 24
                    && trayCell.height === 28 && !!trayIcon && trayIcon.width === 20
                    && trayIcon.height === 20 && trayIcon.pixelSize === 20 },
                { name: 'tray-divider-separates-tray-from-status', passed: !!trayWidget && !!trayDivider && trayDivider.visible
                    && !!keyboardIndicator && !!statusCluster && barX(trayDivider) > barX(trayWidget)
                    && barX(keyboardIndicator) > barX(trayDivider) && barX(statusCluster) > barX(keyboardIndicator) },
                { name: 'keyboard-indicator-shows-and-switches-layout', passed: (function() {
                    const label = root.findNamedItem(keyboardIndicator, 'bar-keyboard-label');
                    const desktop = wide.services.desktop;
                    if (!keyboardIndicator || !keyboardIndicator.visible || !label || label.text !== 'en') return false;
                    const before = desktop.commands.length;
                    const xCenter = label.y + label.baselineOffset - label.xHeight / 2;
                    const restName = keyboardIndicator.Accessible.name;
                    const restWidth = keyboardIndicator.width;
                    const restLabelY = label.y;
                    keyboardIndicator.activate();
                    const clickedLabel = label.text;
                    const steady = keyboardIndicator.width === restWidth && label.y === restLabelY
                        && label.x === Math.round(label.x);
                    return keyboardIndicator.switchable && keyboardIndicator.width >= 24
                        && label.xHeight > 0 && xCenter - keyboardIndicator.height / 2 >= 0 && xCenter - keyboardIndicator.height / 2 < 1
                        && restName === 'English (US)' && clickedLabel === 'ua' && steady
                        && desktop.commands.length === before + 1 && desktop.commands[before] === 'keyboard-layout:1';
                })() },
                // Scroll counts from the layout already requested and wraps around in both directions.
                { name: 'keyboard-indicator-scroll-steps-through-layouts', passed: (function() {
                    const desktop = wide.services.desktop;
                    const before = desktop.commands.length;
                    keyboardIndicator.step(1);
                    keyboardIndicator.step(-1);
                    keyboardIndicator.step(3);
                    return desktop.commands.slice(before).join(' ') === 'keyboard-layout:0 keyboard-layout:1 keyboard-layout:0';
                })() },
                { name: 'keyboard-indicator-right-click-lists-every-layout', passed: (function() {
                    const desktop = wide.services.desktop;
                    keyboardIndicator.requestedIndex = -1;
                    // A left click reveals the tooltip; the popover opened right after must hide it.
                    const tooltip = root.findNamedItem(keyboardIndicator, 'keyboard-tooltip');
                    tooltip.reveal(1);
                    const revealed = tooltip.requested;
                    keyboardIndicator.openMenu();
                    const tooltipHidden = !tooltip.requested && !wide.tooltip.requested;
                    const options = [];
                    const collect = function(item) {
                        if (!item) return;
                        if (item.objectName === 'keyboard-layout-option' && item.visible) options.push(item);
                        for (let i = 0; i < item.children.length; i++) collect(item.children[i]);
                    };
                    collect(keyboardIndicator.menu.contentItem);
                    const opened = keyboardIndicator.menu.opened;
                    const listed = options.map(option => option.text + (option.checked ? '*' : '')).join(' | ');
                    const before = desktop.commands.length;
                    if (options.length === 2) options[1].clicked();
                    return revealed && tooltipHidden && opened && listed === 'English (US)* | Ukrainian' && options[1].checked
                        && desktop.commands[before] === 'keyboard-layout:1' && !keyboardIndicator.menu.opened;
                })() },
                { name: 'audio-indicator-right-click-lists-devices', passed: (function() {
                    const audio = root.audioProbeServices.audio;
                    const output = root.findNamedItem(audioProbe, 'audio-indicator-output');
                    const input = root.findNamedItem(audioProbe, 'audio-indicator-input');
                    if (!output || !input) return false;
                    const indicator = output.parent;
                    indicator.openMenu();
                    const options = [];
                    const collect = function(item) {
                        if (!item) return;
                        if (item.objectName === 'audio-device-option' && item.visible) options.push(item);
                        for (let i = 0; i < item.children.length; i++) collect(item.children[i]);
                    };
                    collect(indicator.menu.contentItem);
                    const opened = indicator.menu.opened;
                    const listed = options.map(option => option.text + (option.checked ? '*' : '')).join(' | ');
                    if (options.length === 2) options[0].clicked();
                    const chosen = audio.selected.join(' ');
                    input.parent.openMenu();
                    const inputOpened = input.parent.menu.opened;
                    input.parent.menu.close();
                    return opened && listed === 'Headphones | Speakers*' && chosen === 'output:1'
                        && !indicator.menu.opened && inputOpened;
                })() },
                { name: 'microphone-indicator-names-capturing-apps', passed: (function() {
                    const tooltip = root.findNamedItem(microphoneProbe, 'microphone-tooltip');
                    const icon = root.findNamedItem(microphoneProbe, 'bar-microphone-icon');
                    if (!tooltip || !icon) return false;
                    root.pointer.mouseMove(microphoneProbe, microphoneProbe.width / 2, microphoneProbe.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                    const hovered = tooltip.visible;
                    root.pointer.mouseMove(microphoneRow, -40, microphoneProbe.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                    return microphoneProbe.objectName === 'bar-microphone-indicator' && microphoneProbe.visible
                        && microphoneRow.width === Metrics.statusIcon && microphoneProbe.height === Metrics.statusIcon
                        && tooltip.text === 'Microphone: Handy' && icon.accessibleName === tooltip.text
                        && icon.source.endsWith('/material/media/mic-symbolic.svg')
                        && Qt.colorEqual(icon.color, Theme.tokens.warning) && icon.pixelSize === Metrics.statusIcon
                        && hovered && !tooltip.visible;
                })(), detail: (function() {
                    const tooltip = root.findNamedItem(microphoneProbe, 'microphone-tooltip');
                    return JSON.stringify({ visible: microphoneProbe.visible, width: microphoneRow.width, text: tooltip ? tooltip.text : null });
                })() },
                { name: 'microphone-indicator-muted-lists-every-app', passed: (function() {
                    const audio = root.microphoneProbeServices.audio;
                    const tooltip = root.findNamedItem(microphoneProbe, 'microphone-tooltip');
                    const icon = root.findNamedItem(microphoneProbe, 'bar-microphone-icon');
                    if (!tooltip || !icon) return false;
                    audio.apps = [{ key: 'discord', label: 'Discord', icon: '' }, { key: 'handy', label: 'Handy', icon: '' }];
                    const both = tooltip.text;
                    audio.muted = true;
                    const muted = tooltip.text;
                    const mutedIcon = icon.source;
                    audio.muted = false;
                    audio.apps = [{ key: 'handy', label: 'Handy', icon: '' }];
                    return both === 'Microphone: Discord, Handy' && muted === 'Microphone muted: Discord, Handy'
                        && icon.accessibleName === 'Microphone: Handy'
                        && mutedIcon.endsWith('/material/media/mic-off-symbolic.svg')
                        && icon.source.endsWith('/material/media/mic-symbolic.svg');
                })() },
                // The icon is bundled, so it is drawn whatever icon theme the display has.
                { name: 'microphone-indicator-uses-bundled-icons', passed: (function() {
                    const audio = root.microphoneProbeServices.audio;
                    const icon = root.findNamedItem(microphoneProbe, 'bar-microphone-icon');
                    if (!icon) return false;
                    const activeSource = microphoneProbe.iconSource;
                    const activeShown = icon.visible && icon.source === activeSource && icon.imageStatus === Image.Ready;
                    audio.muted = true;
                    const mutedSource = microphoneProbe.iconSource;
                    const mutedShown = icon.visible && icon.source === mutedSource && icon.imageStatus === Image.Ready;
                    audio.muted = false;
                    return microphoneProbe.visible && activeShown && mutedShown
                        && activeSource.endsWith('/material/media/mic-symbolic.svg')
                        && mutedSource.endsWith('/material/media/mic-off-symbolic.svg')
                        && !root.findNamedItem(microphoneProbe, 'bar-microphone-glyph');
                })(), detail: (function() {
                    const icon = root.findNamedItem(microphoneProbe, 'bar-microphone-icon');
                    return JSON.stringify({ source: microphoneProbe.iconSource, icon: !!icon && icon.visible, status: icon ? icon.imageStatus : null });
                })() },
                { name: 'microphone-indicator-hidden-when-idle', passed: (function() {
                    const audio = root.microphoneProbeServices.audio;
                    // A Row lays out once per frame; force it so the width reflects the hidden icon now.
                    audio.active = false;
                    microphoneRow.forceLayout();
                    const idle = !microphoneProbe.visible && microphoneRow.width === 0;
                    audio.active = true;
                    audio.omitMicrophone = true;
                    microphoneRow.forceLayout();
                    const missing = !microphoneProbe.visible && microphoneRow.width === 0;
                    audio.omitMicrophone = false;
                    microphoneRow.forceLayout();
                    return idle && missing && microphoneProbe.visible && microphoneRow.width === Metrics.statusIcon;
                })() },
                // The preview audio service is unavailable, so every bar keeps the icon hidden; it sits before the recording icon.
                { name: 'bar-microphone-indicator-hidden-without-audio', passed: [wide, compact, widthProbe].every(function(bar) {
                    const indicator = root.findNamedItem(bar, 'bar-microphone-indicator');
                    if (!indicator || indicator.visible) return false;
                    const siblings = indicator.parent.children;
                    for (let i = 0; i < siblings.length - 1; i++)
                        if (siblings[i] === indicator) return siblings[i + 1].accessibleName === 'Recording';
                    return false;
                }) },
                // The microphone and recording icons come and go with every push-to-talk press; the wings must not.
                { name: 'privacy-icons-keep-portrait-wings-steady', passed: (function() {
                    const bar = privacyProbe;
                    const services = root.privacyProbeServices;
                    const indicator = root.findNamedItem(bar, 'bar-microphone-indicator');
                    if (!indicator) return false;
                    const row = indicator.parent;
                    // Spare room the tools wing has beyond fitting its half, as planning measures it.
                    const slack = function() {
                        const inputs = bar.wingInputs;
                        return inputs.width / 2 - inputs.island / 2 - inputs.inset - inputs.right - inputs.spacing - inputs.tools - inputs.gap;
                    };
                    // Show the tools wing with plenty of room, then narrow its half until 2 px are left over:
                    // less than one status icon, so any icon that widened planning would hide it.
                    bar.horizontalInset = bar.horizontalInset + slack() - 40;
                    bar.horizontalInset = bar.horizontalInset + slack() - 2;
                    const wings = function() { row.forceLayout(); return { telemetry: bar.telemetryShown, tools: bar.toolsShown }; };
                    const rest = wings();
                    const states = [];
                    const toggle = function(microphone, recording) {
                        services.audio.microphoneActive = microphone;
                        services.desktop.recording = recording;
                        const state = wings();
                        state.microphone = indicator.visible;
                        state.width = row.width;
                        states.push(state);
                    };
                    toggle(true, false);
                    toggle(true, true);
                    toggle(false, true);
                    toggle(false, false);
                    root.privacyProbeDetail = JSON.stringify({ inputs: bar.wingInputs, rest: rest, slack: slack(), states: states });
                    return rest.tools && states[0].microphone && !states[3].microphone
                        && states[1].width > states[0].width && states[0].width > states[3].width
                        && states.every(function(state) { return state.telemetry === rest.telemetry && state.tools === rest.tools; });
                })(), detail: root.privacyProbeDetail },
                { name: 'clock-divider-separates-status-from-system-slot', passed: !!statusCluster && !!clockDivider && clockDivider.visible
                    && !!systemSlot && barX(clockDivider) > barX(statusCluster) && barX(systemSlot) > barX(clockDivider) },
                { name: 'clock-divider-hidden-for-saved-system-without-clock', passed: !wide.systemHasClock(savedSystemWithoutClock) }
            ].concat(root.interactionChecks);
            root.pendingChecks = checks;
            wide.grabToImage(function(titleResult) {
                if (root.captureReported) return;
                checks.push({ name: 'active-title-capture', passed: titleResult.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.active-title.png') });
                root.captureBaseline = true;
                Qt.callLater(function() {
                    checks.push({ name: 'tray-divider-hidden-when-tray-empty', passed: !trayDivider.visible && trayWidget.trayItems.length === 0 });
                    capture.grabToImage(function(result) {
                        if (root.captureReported) return;
                        checks.push({ name: 'bar-capture', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')) });
                        root.reportChecks(checks);
                    });
                });
            });
        }
    }
}
