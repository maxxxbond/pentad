import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import QtTest
import qs.theme
import qs.services
import qs.features.bar
import qs.components

ShellRoot {
    id: root
    property Services nativeServices: Services { preview: true; safeMode: true }
    property bool ready: false
    property bool captureReported: false
    property int samplePhase: 0
    property var originalMetrics: []
    property var updateChecks: []
    property int tooltipPhase: 0
    property bool tooltipCapturePending: false
    property int audioTooltipPhase: 0
    property bool audioTooltipCapturePending: false
    property bool audioRapidUpdateIssued: false
    property bool audioTooltipDone: false
    property var audioTooltipGeometry: null
    property TestEvent pointer: TestEvent {}
    readonly property var baselineTelemetry: ({
        cpuPercent: 0.12, gpuPercent: null, memory: { used: 4 * 1073741824, total: 16 * 1073741824 },
        rxBytesPerSecond: 1024, txBytesPerSecond: 2048
    })
    property var fixtureTelemetry: baselineTelemetry
    property QtObject fixtureAudio: QtObject {
        signal commandFinished(string requestId, var result)
        property var state: ({ kind: 'ready', value: {
            output: { label: 'Speakers', volume: 0.09, muted: false },
            input: { label: 'Microphone', volume: 0.75, muted: false }
        } })
        property real contextualFeedbackUntil: 0
        property int requestIndex: 0
        property var requests: []
        function toggleMute(kind) {
            requestIndex++;
            requests = requests.concat([{ id: 'fixture-audio-' + requestIndex, action: 'toggleMute', kind: kind }]);
            return 'fixture-audio-' + requestIndex;
        }
        function cycleDefault(kind, steps) {
            requestIndex++;
            requests = requests.concat([{ id: 'fixture-audio-' + requestIndex, action: 'cycleDefault', kind: kind, steps: steps }]);
            return 'fixture-audio-' + requestIndex;
        }
        function adjustVolume(kind, steps) {
            requestIndex++;
            requests = requests.concat([{ id: 'fixture-audio-' + requestIndex, action: 'adjustVolume', kind: kind, steps: steps }]);
            return 'fixture-audio-' + requestIndex;
        }
    }
    property QtObject fixtureHyprland: QtObject {
        readonly property var state: ({ kind: 'unavailable', reason: 'baseline-fixture' })
        function focusWorkspace(id) { return root.nativeServices.hyprland.focusWorkspace(id); }
    }
    property QtObject fixtureTray: QtObject {
        readonly property var state: ({ kind: 'unavailable', reason: 'baseline-fixture' })
        function nativeItemFor(id) { return null; }
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
        readonly property var config: root.nativeServices.config
        readonly property var plugins: root.fixturePlugins
        readonly property var clock: root.fakeClock
        readonly property var tray: root.fixtureTray
        readonly property var audio: root.fixtureAudio
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
            readonly property var state: ({ kind: 'ready', value: { recording: false, keyboardLayout: 'EN', telemetry: root.fixtureTelemetry } })
        }
    }

    function report(checks) {
        if (captureReported) return;
        captureReported = true;
        const passed = checks.every(function(item) { return item.passed === true; });
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
    function findNamedItem(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const items = item.children || [];
        for (let i = 0; i < items.length; i++) {
            const found = findNamedItem(items[i], name);
            if (found) return found;
        }
        return null;
    }
    function findText(item, value) {
        if (!item) return null;
        if (item.text === value) return item;
        for (let i = 0; i < (item.children || []).length; i++) {
            const found = findText(item.children[i], value);
            if (found) return found;
        }
        return null;
    }
    function setOutput(label, volume, muted) {
        fixtureAudio.state = { kind: 'ready', value: {
            output: { label: label, volume: volume, muted: muted },
            input: fixtureAudio.state.kind === 'ready' ? fixtureAudio.state.value.input
                : { label: 'Microphone', volume: 0.75, muted: false }
        } };
    }
    function audioTooltipSnapshot(tooltip) {
        const popup = tooltip.window;
        const captureItem = popup.captureItem;
        const title = root.findNamedItem(captureItem, 'tooltip-title');
        const detail = root.findNamedItem(captureItem, 'tooltip-detail');
        if (!title || !detail) return null;
        const titleGlobal = title.mapToGlobal(0, 0);
        const detailGlobal = detail.mapToGlobal(0, 0);
        return {
            width: popup.width, height: popup.height,
            titleX: titleGlobal.x, titleY: titleGlobal.y, titleWidth: title.width, titleHeight: title.height,
            detailX: detailGlobal.x, detailY: detailGlobal.y, detailWidth: detail.width, detailHeight: detail.height
        };
    }
    function audioTooltipGeometryMatches(tooltip) {
        const current = root.audioTooltipSnapshot(tooltip);
        const baseline = root.audioTooltipGeometry;
        if (!current || !baseline) return false;
        return Object.keys(baseline).every(function(key) { return Math.abs(current[key] - baseline[key]) < 0.1; });
    }
    function captureAudioTooltip(name, nextPhase, tooltip) {
        if (root.audioTooltipCapturePending) return;
        root.audioTooltipCapturePending = true;
        tooltip.window.captureItem.grabToImage(function(result) {
            const artifact = Quickshell.env('PENTAD_ARTIFACT_PATH');
            const saved = !!artifact && result.saveToFile(artifact + '.audio-' + name + '.png');
            root.updateChecks.push({ name: 'audio-' + name + '-status-popup-captured', passed: saved });
            root.audioTooltipCapturePending = false;
            root.audioTooltipPhase = nextPhase;
        });
    }
    TestCase {
        id: visualTestCase
        name: 'BarVisualInput'
        when: false
        function sendWheel(item) {
            return mouseWheel(item, item.width / 2, item.height / 2,
                0, 120, Qt.NoButton, Qt.NoModifier, 0);
        }
    }
    function logoGeometryMatches(bar) {
        const logo = findNamedItem(bar, 'idle-logo');
        return !!logo && logo.width === 28 && Math.abs(logo.height - 26) < 0.01;
    }
    // Without the side wings the centre row once collapsed to zero height and the island was not drawn.
    function islandPlacement(bar) {
        const logo = findNamedItem(bar, 'idle-logo');
        if (!logo) return 'no idle logo';
        const centre = logo.mapToItem(bar, logo.width / 2, logo.height / 2);
        return JSON.stringify({ centreY: centre.y, barHeight: bar.height, renderedHeight: bar.renderedHeight });
    }
    function islandSitsInside(bar) {
        const logo = findNamedItem(bar, 'idle-logo');
        if (!logo) return false;
        const centre = logo.mapToItem(bar, logo.width / 2, logo.height / 2);
        return Math.abs(centre.y - bar.height / 2) < 1.5 && bar.renderedHeight === bar.height;
    }
    function previewToolsAreDisabled(bar) {
        const tools = findNamedItem(bar, 'quick-tools-widget');
        return !!tools && [2, 3].every(function(index) {
            const action = tools.buttonRepeater.itemAt(index);
            return action && action.actionAvailable === false && Math.abs(action.opacity - 0.45) < 0.01;
        });
    }
    Component.onCompleted: {
        const appearance = Quickshell.env('PENTAD_GALLERY_APPEARANCE') === 'light' ? 'light' : 'dark';
        const requestedAccent = Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677';
        const accent = /^#[0-9a-f]{6}$/i.test(requestedAccent) ? requestedAccent : '#869677';
        Theme.resolve({ appearance: appearance, accent: accent, fontFamily: 'Geist',
            reducedMotion: Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1' });
    }

    FloatingWindow {
        visible: true
        implicitWidth: 2048
        implicitHeight: 140
        color: '#111311'
        Item {
            id: capture
            width: 2048; height: 140
            Rectangle { anchors.fill: parent; color: '#111311' }
            BarFace { id: wide; x: 0; y: 0; width: 2048; height: 40; horizontalInset: 16; services: root.fixtureServices; outputId: 'wide' }
            BarFace { id: compact; x: 0; y: 80; width: 1024; height: 40; horizontalInset: 16; services: root.fixtureServices; outputId: 'compact' }
        }
    }

    FloatingWindow {
        id: tooltipFixtureWindow
        visible: true
        implicitWidth: 1280
        implicitHeight: 180
        color: '#111311'
        BarFace {
            id: tooltipBar
            x: 0; y: 0; width: 1280; height: 40
            horizontalInset: 16
            services: root.fixtureServices
            outputId: 'tooltip-fixture'
            Item {
                id: tooltipAnchor
                objectName: 'bar-tooltip-fixture-anchor'
                x: root.tooltipPhase === 4 ? tooltipBar.width - width : 0
                y: 0
                width: 24; height: 40
                PentadToolTip {
                    id: barTooltip
                    objectName: 'bar-tooltip-fixture'
                    text: root.tooltipPhase >= 1 && root.tooltipPhase <= 4
                        ? 'The audio output is controlled by the selected device' : 'Discord'
                    detail: root.tooltipPhase >= 1 && root.tooltipPhase <= 4 ? 'USB interface · 48 kHz' : ''
                    delay: 0
                    visible: root.tooltipPhase < 3 || root.tooltipPhase === 4
                }
            }
        }
    }

    Text {
        id: expectedLongTitle
        visible: false
        width: barTooltip.window.labelWidth
        text: 'The audio output is controlled by the selected device'
        font.family: Theme.tokens.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
        wrapMode: Text.WordWrap
        maximumLineCount: 2
    }
    Text {
        id: expectedLongDetail
        visible: false
        width: barTooltip.window.labelWidth
        text: 'USB interface · 48 kHz'
        font.family: Theme.tokens.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        maximumLineCount: 2
    }

    Timer {
        interval: 100
        repeat: true
        running: !root.ready
        onTriggered: {
            if (!root.clockManifest.loaded) return;
            root.fixturePlugins.registerManifest(JSON.parse(root.clockManifest.text()), Qt.resolvedUrl('widgets/clock/'), true);
            root.fixturePlugins.reconcile(root.nativeServices.config.documents.layout.widgets || []);
            root.ready = true;
            stop();
        }
    }
    Timer {
        interval: 700
        repeat: true
        running: root.ready && !root.captureReported
        onTriggered: {
            const telemetry = root.findNamedItem(wide, 'telemetry-widget');
            if (root.samplePhase === 0) {
                root.originalMetrics = [0, 1, 2, 3].map(function(i) { return telemetry.metricRepeater.itemAt(i); });
                root.fixtureTelemetry = { cpuPercent: 0.99, gpuPercent: 0.5,
                    memory: { used: 8 * 1073741824, total: 16 * 1073741824 },
                    rxBytesPerSecond: 1048576, txBytesPerSecond: 1048576 };
                root.samplePhase = 1;
                return;
            }
            if (root.samplePhase === 1) {
                root.updateChecks = [
                    { name: 'telemetry-sample-retains-all-four-indicator-objects', passed: [0, 1, 2, 3].every(function(i) {
                        return root.originalMetrics[i] === telemetry.metricRepeater.itemAt(i);
                    }) },
                    { name: 'retained-indicators-update-numbers-and-sectors', passed: telemetry.metricRepeater.itemAt(0).labelText === '99'
                        && telemetry.metricRepeater.itemAt(0).metricRatio === 0.99
                        && telemetry.metricRepeater.itemAt(1).labelText === '50'
                        && telemetry.metricRepeater.itemAt(2).labelText === '2.0M'
                        && telemetry.metricRepeater.itemAt(3).labelText === '50' }
                ];
                root.fixtureTelemetry = root.baselineTelemetry;
                root.samplePhase = 2;
                return;
            }
            if (root.tooltipCapturePending) return;
            if (root.tooltipPhase < 6) {
                const popup = barTooltip.window;
                const popupTop = popup.captureItem.mapToGlobal(0, 0);
                const screen = tooltipFixtureWindow.screen;
                const screenLeft = screen ? Number(screen.x || 0) : 0;
                const screenWidth = screen ? screen.width : 1280;
                if (root.tooltipPhase === 0) {
                    if (!barTooltip.requested || barTooltip.exposure < 0.95) return;
                    const seam = tooltipBar.mapToGlobal(0, tooltipBar.height);
                    const discordLabel = root.findText(popup.captureItem, 'Discord');
                    root.updateChecks = root.updateChecks.concat([
                        { name: 'tooltip-uses-real-bar-face-ancestor', passed: barTooltip.bar === tooltipBar
                            && tooltipBar.objectName === 'pentad-bar-face' },
                        { name: 'discord-tooltip-uses-fixed-compact-preset', passed: popup.implicitWidth === Metrics.barTooltipCompactWidth
                            && popup.implicitHeight === Metrics.barTooltipCompactHeight
                            && barTooltip.activeBarSizeMode === 'compact',
                            detail: JSON.stringify({ size: [popup.implicitWidth, popup.implicitHeight], mode: barTooltip.activeBarSizeMode }) },
                        { name: 'discord-text-fits-between-shoulders', passed: barTooltip.currentText === 'Discord'
                            && barTooltip.currentDetail === ''
                            && popup.geometry.contentRight - popup.geometry.contentLeft >= 2 * popup.barTextPadding
                            && popup.labelWidth <= popup.geometry.contentRight - popup.geometry.contentLeft
                                - 2 * popup.barTextPadding,
                            detail: JSON.stringify({ labelWidth: popup.labelWidth,
                                padding: popup.barTextPadding,
                                contentLeft: popup.geometry.contentLeft, contentRight: popup.geometry.contentRight }) },
                        { name: 'discord-label-is-not-elided', passed: !!discordLabel && discordLabel.truncated === false,
                            detail: JSON.stringify(discordLabel ? { width: discordLabel.width,
                                implicitWidth: discordLabel.implicitWidth, truncated: discordLabel.truncated } : null) },
                        { name: 'left-edge-tooltip-remains-on-screen', passed: popupTop.x >= screenLeft
                            && popupTop.x + popup.width <= screenLeft + screenWidth + 1,
                            detail: JSON.stringify({ x: popupTop.x, width: popup.width, screenLeft: screenLeft,
                                screenWidth: screenWidth, hostWindowX: tooltipFixtureWindow.contentItem.mapToGlobal(0, 0).x,
                                anchorX: popup.anchor.rect.x, triggerCenterX: popup.triggerCenterX,
                                popupScreenX: popup.screen ? popup.screen.x : null,
                                barGlobalX: tooltipBar.mapToGlobal(0, 0).x }) },
                        { name: 'popup-is-anchored-at-bar-bottom', passed: Math.abs(popupTop.y - seam.y) <= 2,
                            detail: JSON.stringify({ popupY: popupTop.y, barBottomY: seam.y }) }
                    ]);
                    popup.captureItem.grabToImage(function(result) {
                        root.updateChecks.push({ name: 'native-discord-popup-captured',
                            passed: result.saveToFile(Quickshell.env('PENTAD_TOOLTIP_CAPTURE_PATH')) });
                        root.tooltipCapturePending = false;
                        root.tooltipPhase = 1;
                    });
                    root.tooltipCapturePending = true;
                    return;
                }
                if (root.tooltipPhase === 1) {
                    if (!barTooltip.requested || barTooltip.exposure < 0.95 || barTooltip.progress < 0.99) return;
                    root.updateChecks.push({ name: 'automatic-tooltip-size-stays-locked-during-visible-session',
                        passed: barTooltip.currentText === expectedLongTitle.text
                            && barTooltip.currentDetail === expectedLongDetail.text
                            && barTooltip.activeBarSizeMode === 'compact'
                            && popup.width === Metrics.barTooltipCompactWidth
                            && popup.height === Metrics.barTooltipCompactHeight,
                        detail: JSON.stringify({ size: [popup.width, popup.height],
                            measuredTextHeight: expectedLongTitle.implicitHeight + expectedLongDetail.implicitHeight
                                + 3 + 2 * popup.barVerticalPadding,
                            labelWidth: popup.labelWidth, currentText: barTooltip.currentText,
                            currentDetail: barTooltip.currentDetail }) });
                    popup.captureItem.grabToImage(function(result) {
                        root.updateChecks.push({ name: 'native-long-detail-popup-captured',
                            passed: result.saveToFile(Quickshell.env('PENTAD_TOOLTIP_LONG_CAPTURE_PATH')) });
                        root.tooltipCapturePending = false;
                        root.tooltipPhase = 2;
                    });
                    root.tooltipCapturePending = true;
                    return;
                }
                if (root.tooltipPhase === 2) {
                    root.tooltipPhase = 3;
                    return;
                }
                if (root.tooltipPhase === 3) {
                    if (barTooltip.exposure > 0.001) return;
                    root.updateChecks.push({ name: 'automatic-tooltip-size-unlocks-after-dismissal',
                        passed: barTooltip.exposure <= 0.001 && barTooltip.activeBarSizeMode === 'status',
                        detail: 'exposure=' + barTooltip.exposure + ', next=' + barTooltip.activeBarSizeMode });
                    root.tooltipPhase = 4;
                    return;
                }
                if (root.tooltipPhase === 4) {
                    if (!barTooltip.requested || barTooltip.exposure < 0.95 || barTooltip.progress < 0.99) return;
                    root.updateChecks.push({ name: 'next-automatic-session-selects-status-preset',
                        passed: barTooltip.currentText === expectedLongTitle.text
                            && barTooltip.currentDetail === expectedLongDetail.text
                            && barTooltip.activeBarSizeMode === 'status'
                            && popup.width === Metrics.barTooltipStatusWidth
                            && popup.height === Metrics.barTooltipStatusHeight,
                        detail: JSON.stringify({ size: [popup.width, popup.height], mode: barTooltip.activeBarSizeMode,
                            currentText: barTooltip.currentText, currentDetail: barTooltip.currentDetail }) });
                    root.updateChecks.push({ name: 'right-edge-tooltip-remains-on-screen', passed: popupTop.x >= screenLeft
                        && popupTop.x + popup.width <= screenLeft + screenWidth + 1,
                        detail: JSON.stringify({ x: popupTop.x, width: popup.width, screenLeft: screenLeft,
                            screenWidth: screenWidth, hostWindowX: tooltipFixtureWindow.contentItem.mapToGlobal(0, 0).x,
                            anchorX: popup.anchor.rect.x, popupScreenX: popup.screen ? popup.screen.x : null,
                            barGlobalX: tooltipBar.mapToGlobal(0, 0).x, triggerCenterX: popup.triggerCenterX,
                            contentLeft: popup.geometry.contentLeft, contentRight: popup.geometry.contentRight }) });
                    root.updateChecks.push({ name: 'right-edge-trigger-projects-into-contour',
                        passed: popup.triggerCenterX >= 0 && popup.triggerCenterX <= popup.width });
                    popup.captureItem.grabToImage(function(result) {
                        root.updateChecks.push({ name: 'native-right-edge-popup-captured',
                            passed: result.saveToFile(Quickshell.env('PENTAD_TOOLTIP_EDGE_CAPTURE_PATH')) });
                        root.tooltipCapturePending = false;
                        root.tooltipPhase = 5;
                    });
                    root.tooltipCapturePending = true;
                    return;
                }
                if (root.tooltipPhase === 5) {
                    if (barTooltip.exposure > 0.001) return;
                    root.updateChecks.push({ name: 'tooltip-fade-completes-for-current-motion-setting',
                        passed: barTooltip.exposure <= 0.001, detail: 'exposure=' + barTooltip.exposure });
                    root.tooltipPhase = 6;
                    return;
                }
            }
            if (!root.audioTooltipDone) return;
            const status = root.findNamedItem(wide, 'bar-status-cluster');
            const checks = root.updateChecks.concat([
                { name: 'scene-is-2048x140', passed: capture.width === 2048 && capture.height === 140 },
                { name: 'wide-bar-is-2048x40-at-y0', passed: wide.x === 0 && wide.y === 0 && wide.width === 2048 && wide.height === 40 },
                { name: 'compact-bar-is-1024x40-at-y80', passed: compact.x === 0 && compact.y === 80 && compact.width === 1024 && compact.height === 40 },
                { name: 'wide-island-is-physically-centered', passed: Math.abs(wide.islandCenter - 1024) < 0.5 },
                { name: 'compact-island-is-physically-centered', passed: Math.abs(compact.islandCenter - 512) < 0.5 },
                { name: 'compact-island-sits-inside-the-bar', passed: root.islandSitsInside(compact), detail: root.islandPlacement(compact) },
                { name: 'compact-bar-shows-telemetry-wing', passed: compact.telemetryShown && compact.centerLeft >= compact.horizontalInset,
                    detail: JSON.stringify({ telemetry: compact.telemetryShown, tools: compact.toolsShown, centerLeft: compact.centerLeft,
                        centerRight: compact.centerRight, rightContentLeft: compact.rightContentLeft }) },
                { name: 'default-bar-is-40-high', passed: wide.implicitHeight === 40 && compact.implicitHeight === 40 },
                { name: 'workspace-source-matches-unavailable-baseline', passed: wide.workspaceState.kind === 'unavailable' && !wide.workspaceSwitcher.visible },
                { name: 'telemetry-fixture-values-match-reference', passed: root.fixtureServices.desktop.state.value.telemetry.cpuPercent === 0.12
                    && root.fixtureServices.desktop.state.value.telemetry.gpuPercent === null
                    && root.fixtureServices.desktop.state.value.telemetry.memory.used === 4 * 1073741824
                    && root.fixtureServices.desktop.state.value.telemetry.memory.total === 16 * 1073741824
                    && root.fixtureServices.desktop.state.value.telemetry.rxBytesPerSecond === 1024
                    && root.fixtureServices.desktop.state.value.telemetry.txBytesPerSecond === 2048 },
                { name: 'keyboard-layout-matches-reference', passed: root.fixtureServices.desktop.state.value.keyboardLayout === 'EN' },
                { name: 'idle-logo-uses-native-28x26-artwork-box', passed: root.logoGeometryMatches(wide) },
                { name: 'preview-denies-desktop-tool-actions', passed: root.previewToolsAreDisabled(wide) },
                { name: 'preview-only-data-sources', passed: root.nativeServices.preview === true && root.nativeServices.safeMode === true },
                { name: 'status-icons-start-on-whole-scene-pixels', passed: Math.abs(status.mapToItem(capture, 0, 0).x % 1) < 0.001 },
                { name: 'theme-reduced-motion-matches-request', passed: Theme.tokens.reducedMotion
                    === (Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1') },
                { name: 'composited-capture-limitation-recorded', passed: true,
                    detail: 'Private KWin disables grim screencopy; popup captures use the native popup scene item and seam coordinates are checked separately.' }
            ]);
            capture.grabToImage(function(result) {
                if (root.captureReported) return;
                checks.push({ name: 'static-bar-pair-captured', passed: result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH')) });
                root.report(checks);
            });
        }
    }
    Timer {
        id: audioTooltipTimer
        interval: 120
        repeat: true
        running: root.ready && root.tooltipPhase >= 6 && !root.audioTooltipDone && !root.captureReported
        onTriggered: {
            if (root.audioTooltipCapturePending) return;
            const status = root.findNamedItem(tooltipBar, 'bar-status-cluster');
            const tooltip = root.findNamedItem(status, 'audio-tooltip-output');
            const indicator = root.findNamedItem(status, 'audio-indicator-output');
            if (!tooltip || !indicator) {
                root.updateChecks.push({ name: 'production-audio-tooltip-is-findable', passed: false });
                root.audioTooltipDone = true;
                stop();
                return;
            }
            const popup = tooltip.window;
            const title = root.findNamedItem(popup.captureItem, 'tooltip-title');
            const detail = root.findNamedItem(popup.captureItem, 'tooltip-detail');
            const sizeIsStable = popup.width === Metrics.barTooltipStatusWidth
                && popup.height === Metrics.barTooltipStatusHeight
                && tooltip.activeBarSizeMode === 'status';
            const geometryStable = root.audioTooltipGeometryMatches(tooltip);
            const checkGeometry = function(name, textIsLatest, requireStableTextRows) {
                const rowRects = title && detail && title.width > 0 && detail.width > 0
                    && Math.abs(title.height - root.audioTooltipGeometry.titleHeight) < 0.1
                    && Math.abs(detail.height - root.audioTooltipGeometry.detailHeight) < 0.1
                    && (!requireStableTextRows || (Math.abs(title.mapToGlobal(0, 0).y - root.audioTooltipGeometry.titleY) < 0.1
                        && Math.abs(detail.mapToGlobal(0, 0).y - root.audioTooltipGeometry.detailY) < 0.1));
                root.updateChecks.push({ name: name, passed: sizeIsStable && geometryStable && rowRects && textIsLatest,
                    detail: JSON.stringify({ size: [popup.width, popup.height], mode: tooltip.activeBarSizeMode,
                        title: title ? { text: title.text, truncated: title.truncated, y: title.mapToGlobal(0, 0).y,
                            width: title.width, height: title.height } : null,
                        detail: detail ? { text: detail.text, truncated: detail.truncated,
                            y: detail.mapToGlobal(0, 0).y, width: detail.width, height: detail.height } : null,
                        stable: geometryStable }) });
            };
            const artifact = Quickshell.env('PENTAD_ARTIFACT_PATH');
            if (root.audioTooltipPhase === 0) {
                root.pointer.mouseMove(indicator, indicator.width / 2, indicator.height / 2,
                    0, Qt.NoButton, Qt.NoModifier);
                if (!tooltip.requested || tooltip.exposure < 0.95 || tooltip.currentDetail !== '9%') return;
                root.updateChecks.push({ name: 'production-audio-tooltip-uses-fixed-status-preset',
                    passed: sizeIsStable && tooltip.animateContent === false,
                    detail: JSON.stringify({ width: popup.width, height: popup.height, mode: tooltip.activeBarSizeMode,
                        animateContent: tooltip.animateContent }) });
                root.updateChecks.push({ name: 'audio-9-percent-fits-within-fixed-status-preset',
                    passed: tooltip.currentDetail === '9%' && detail && detail.text === '9%'
                        && detail.truncated === false && title.height === title.font.pixelSize && detail.height === detail.font.pixelSize,
                    detail: JSON.stringify({ size: [popup.width, popup.height], titleHeight: title ? title.height : null,
                        detailHeight: detail ? detail.height : null, text: tooltip.currentDetail }) });
                captureAudioTooltip('09', 1, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 1) {
                root.audioTooltipGeometry = root.audioTooltipSnapshot(tooltip);
                root.setOutput('Speakers', 0.10, false);
                root.audioTooltipPhase = 2;
                return;
            }
            if (root.audioTooltipPhase === 2) {
                if (tooltip.currentDetail !== '10%' || tooltip.progress !== 1) return;
                checkGeometry('audio-10-percent-keeps-fixed-status-geometry',
                    detail && detail.text === '10%' && detail.truncated === false, true);
                captureAudioTooltip('10', 3, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 3) {
                root.setOutput('Speakers', 0.99, false);
                root.audioTooltipPhase = 4;
                return;
            }
            if (root.audioTooltipPhase === 4) {
                if (tooltip.currentDetail !== '99%' || tooltip.progress !== 1) return;
                checkGeometry('audio-99-percent-keeps-fixed-status-geometry',
                    detail && detail.text === '99%' && detail.truncated === false, true);
                captureAudioTooltip('99', 5, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 5) {
                if (!root.audioRapidUpdateIssued) {
                    root.audioRapidUpdateIssued = true;
                    root.setOutput('Speakers', 0.10, false);
                    root.setOutput('Speakers', 0.99, false);
                    root.setOutput('Speakers', 0.10, false);
                    root.setOutput('Speakers', 1.00, false);
                    return;
                }
                if (tooltip.currentDetail !== '100%' || tooltip.progress !== 1) return;
                checkGeometry('rapid-audio-reversals-show-latest-100-percent-without-slide',
                    detail && detail.text === '100%' && detail.truncated === false, true);
                captureAudioTooltip('100', 6, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 6) {
                root.setOutput('Studio Speakers with an intentionally long device name for ellipsis', 1.00, false);
                root.audioTooltipPhase = 7;
                return;
            }
            if (root.audioTooltipPhase === 7) {
                if (tooltip.currentDetail !== '100%') return;
                checkGeometry('long-device-name-elides-title-only', !!title && title.truncated === true
                    && detail && detail.truncated === false && detail.text === '100%', true);
                captureAudioTooltip('long-device', 8, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 8) {
                const before = root.fixtureAudio.requests.length;
                root.pointer.mouseClick(indicator, indicator.width / 2, indicator.height / 2,
                    Qt.LeftButton, Qt.NoModifier, 0);
                root.setOutput('Studio Speakers', 0.25, true);
                root.updateChecks.push({ name: 'real-audio-indicator-click-uses-mocked-toggle-command',
                    passed: root.fixtureAudio.requests.length === before + 1
                        && root.fixtureAudio.requests[root.fixtureAudio.requests.length - 1].action === 'toggleMute' });
                root.audioTooltipPhase = 9;
                return;
            }
            if (root.audioTooltipPhase === 9) {
                if (tooltip.currentDetail !== '25%') return;
                checkGeometry('muted-output-keeps-fixed-status-geometry', detail
                    && detail.text === '25%' && detail.truncated === false, true);
                captureAudioTooltip('muted', 10, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 10) {
                root.fixtureAudio.state = { kind: 'unavailable', reason: 'fixture-unavailable' };
                root.audioTooltipPhase = 11;
                return;
            }
            if (root.audioTooltipPhase === 11) {
                if (tooltip.currentText !== 'Audio unavailable' || tooltip.currentDetail !== '') return;
                root.updateChecks.push({ name: 'unavailable-audio-retains-status-preset',
                    passed: sizeIsStable && !!title && title.text === 'Audio unavailable',
                    detail: JSON.stringify({ text: tooltip.currentText, size: [popup.width, popup.height] }) });
                captureAudioTooltip('unavailable', 12, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 12) {
                root.setOutput('Speakers', 1.00, false);
                const before = root.fixtureAudio.requests.length;
                const wheelAvailable = typeof visualTestCase.sendWheel === 'function';
                if (wheelAvailable) {
                    root.pointer.mouseMove(indicator, indicator.width / 2, indicator.height / 2,
                        0, Qt.NoButton, Qt.NoModifier);
                    visualTestCase.sendWheel(indicator);
                }
                const request = root.fixtureAudio.requests.length > before
                    ? root.fixtureAudio.requests[root.fixtureAudio.requests.length - 1] : null;
                if (request) root.fixtureAudio.commandFinished(request.id, { ok: false, reason: 'failed' });
                root.updateChecks.push({ name: 'real-audio-wheel-emits-mocked-device-cycle',
                    passed: wheelAvailable && !!request && request.action === 'cycleDefault',
                    detail: JSON.stringify({ wheelAvailable: wheelAvailable, request: request }) });
                root.audioTooltipPhase = 13;
                return;
            }
            if (root.audioTooltipPhase === 13) {
                if (tooltip.currentDetail !== 'Could not change audio') return;
                checkGeometry('command-error-keeps-fixed-status-geometry', detail
                    && detail.text === 'Could not change audio' && detail.truncated === false, true);
                captureAudioTooltip('error', 14, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 14) {
                root.pointer.mouseMove(tooltipBar, Math.min(600, tooltipBar.width / 2), tooltipBar.height / 2,
                    0, Qt.NoButton, Qt.NoModifier);
                root.updateChecks.push({ name: 'audio-feedback-hold-keeps-tooltip-after-pointer-leaves',
                    passed: tooltip.requested && tooltip.currentDetail === 'Could not change audio' });
                root.audioTooltipPhase = 15;
                return;
            }
            if (root.audioTooltipPhase === 15) {
                if (tooltip.requested || tooltip.exposure > 0.05) return;
                root.updateChecks.push({ name: 'audio-tooltip-dismisses-after-feedback-hold',
                    passed: !tooltip.requested && tooltip.exposure <= 0.05 });
                root.pointer.mouseMove(indicator, indicator.width / 2, indicator.height / 2,
                    0, Qt.NoButton, Qt.NoModifier);
                root.audioTooltipPhase = 16;
                return;
            }
            if (root.audioTooltipPhase === 16) {
                if (!tooltip.requested || tooltip.exposure < 0.95 || tooltip.currentDetail !== '100%') return;
                checkGeometry('audio-tooltip-reopens-with-latest-value-and-same-geometry',
                    detail && detail.text === '100%' && detail.truncated === false, true);
                captureAudioTooltip('reopen', 17, tooltip);
                return;
            }
            if (root.audioTooltipPhase === 17) {
                root.audioTooltipDone = true;
                stop();
            }
        }
    }
    Timer {
        interval: 25000
        running: root.ready && !root.captureReported
        onTriggered: root.report([{ name: 'visual-capture-deadline', passed: false,
            detail: JSON.stringify({ tooltipPhase: root.tooltipPhase, audioTooltipPhase: root.audioTooltipPhase,
                samplePhase: root.samplePhase, tooltip: { requested: barTooltip.requested,
                    exposure: barTooltip.exposure, mode: barTooltip.activeBarSizeMode,
                    currentText: barTooltip.currentText, currentDetail: barTooltip.currentDetail,
                    popupVisible: barTooltip.window.visible,
                    captureSize: [barTooltip.window.captureItem.width, barTooltip.window.captureItem.height],
                    anchorRect: [barTooltip.window.anchor.rect.x, barTooltip.window.anchor.rect.y,
                        barTooltip.window.anchor.rect.width, barTooltip.window.anchor.rect.height] },
                audioDone: root.audioTooltipDone, checks: root.updateChecks }) }]);
    }
}
