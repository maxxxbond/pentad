import QtQuick
import QtQuick.Effects
import Quickshell
import qs.components
import qs.theme
import '../media'
import '../../logic/media.mjs' as MediaLogic
import '../../logic/playback-clock.mjs' as PlaybackClock
import '../../logic/lyrics.mjs' as LyricsLogic
import '../../logic/clock.mjs' as ClockLogic
import '../../logic/artwork.mjs' as Artwork

Item {
    id: root
    required property var services
    property string outputId: ''
    property string consumerId: 'island:' + outputId
    property bool initialized: false
    property var acquiredServices: null
    property string acquiredConsumerId: ''
    readonly property var mediaState: services.media.state
    readonly property var timerState: services.activity.timerState
        || ClockLogic.idleTimerState()
    readonly property bool timerVisible: ['running', 'paused', 'finished'].indexOf(timerState.status) >= 0
    readonly property var player: !timerVisible && mediaState.kind === 'ready' ? mediaState.value.current : null
    readonly property bool playing: !!player && player.playback === 'playing'
    readonly property var players: mediaState.kind === 'ready' ? mediaState.value.players || [] : []
    readonly property bool canCycle: !!player && players.length > 1
    readonly property int playerIndex: player ? players.findIndex(function(item) { return item.id === player.id }) : -1
    // Source switching feedback: the track slides in from the scroll direction and the
    // artist line names the new source for a moment.
    property int switchDirection: 1
    property real switchProgress: 1
    property real wheelPending: 0
    readonly property bool sourceHintVisible: sourceHint.running && canCycle
    readonly property bool karaoke: services.activity.karaoke && !!player
    readonly property bool menuOpen: services.popups.isOpen('activity', outputId)
    readonly property var lyricsState: services.lyrics.state
    readonly property var lines: lyricsState.kind === 'ready' ? lyricsState.value.lines : []
    readonly property bool expanded: karaoke && lines.length > 0 && !menuOpen
    // The karaoke overhang lives in its own popup: Hyprland gave the bar no pointer below its 40 px,
    // however tall the layer surface and its input mask were. The bar keeps only its own height.
    readonly property var inputRegion: null
    readonly property alias overhangSurface: expandedSurface
    readonly property alias overhangRegion: contourRegion
    readonly property bool islandHovered: expanded ? expandedHover.hovered : hover.hovered
    property real hoverProgress: islandHovered ? 1 : 0
    Behavior on hoverProgress { NumberAnimation { duration: Motion.state; easing.type: Easing.OutCubic } }
    readonly property real renderedHeight: implicitHeight
    readonly property real overhangHeight: focusCard.implicitHeight + 2 * Metrics.attachedRim
    readonly property var playbackClock: PlaybackClock.createPlaybackClock()
    property double now: Date.now()
    readonly property real position: playbackClock.at(now) / 1000000
    readonly property int lineIndex: LyricsLogic.activeLyric(lines, position + services.lyrics.offsetMs / 1000)
    readonly property int gap: LyricsLogic.lyricGapSeconds(lines, position, services.lyrics.offsetMs)
    signal activated()
    function cycleSource(offset) {
        var id = MediaLogic.adjacentPlayerId(players, player ? player.id : '', offset);
        if (!id) return;
        switchDirection = offset < 0 ? -1 : 1;
        switchRequested = true;
        services.media.selectPlayer(id);
    }
    function handleWheel(wheel) {
        if (!canCycle) { wheel.accepted = false; return; }
        var pixels = wheel.pixelDelta.y || wheel.pixelDelta.x;
        var delta = pixels || wheel.angleDelta.y || wheel.angleDelta.x;
        wheel.accepted = true;
        if (!delta) return;
        if (wheelPending && (wheelPending < 0) !== (delta < 0)) wheelPending = 0;
        wheelPending += delta;
        if (Math.abs(wheelPending) < (pixels ? 40 : 120)) return;
        wheelPending = 0;
        cycleSource(delta < 0 ? 1 : -1);
    }
    implicitWidth: !player ? (timerState.status === 'idle' ? Metrics.logo : 240) : expanded ? 360 : 240
    implicitHeight: expanded ? services.config.documents.layout.barHeight : player ? 32 : Metrics.logo
    function releaseAll() {
        if (!acquiredServices || !acquiredConsumerId) return;
        if (acquiredServices.media) acquiredServices.media.release(acquiredConsumerId);
        if (acquiredServices.lyrics) acquiredServices.lyrics.release(acquiredConsumerId);
        if (acquiredServices.visualizer) acquiredServices.visualizer.release(acquiredConsumerId);
        acquiredServices = null;
        acquiredConsumerId = '';
    }
    function sync() {
        if (!initialized) return;
        if (acquiredServices !== services || acquiredConsumerId !== consumerId) releaseAll();
        if (!services || !services.media || !services.lyrics || !services.visualizer) return;
        if (!consumerId) return;
        acquiredServices = services;
        acquiredConsumerId = consumerId;
        if (visible && player) services.media.acquire(consumerId);
        else services.media.release(consumerId);
        if (visible && karaoke) services.lyrics.acquire(consumerId);
        else services.lyrics.release(consumerId);
        if (visible && playing && !Theme.tokens.reducedMotion) services.visualizer.acquire(consumerId);
        else services.visualizer.release(consumerId);
    }
    onVisibleChanged: sync()
    onPlayerChanged: { playbackClock.sync(player, Date.now()); now = Date.now(); sync() }
    readonly property string playerId: player ? player.id : ''
    property bool switchRequested: false
    onPlayerIdChanged: {
        if (!switchRequested) return;
        switchRequested = false;
        sourceHint.restart();
        if (Theme.tokens.reducedMotion) switchProgress = 1;
        else { switchProgress = 0; switchEnter.restart(); }
    }
    NumberAnimation { id: switchEnter; target: root; property: 'switchProgress'; to: 1; duration: Motion.state; easing.type: Easing.OutCubic }
    Timer { id: sourceHint; interval: 1400 }
    onKaraokeChanged: sync()
    onPlayingChanged: sync()
    onServicesChanged: sync()
    onConsumerIdChanged: sync()
    Connections { target: Theme; function onTokensChanged() { root.sync() } }
    Component.onCompleted: { initialized = true; sync(); }
    Component.onDestruction: releaseAll()
    // Karaoke lines follow the playback clock every frame; otherwise a coarse tick is enough.
    FrameAnimation {
        running: root.visible && root.playing && root.expanded && !Theme.tokens.reducedMotion
        onTriggered: root.now = Date.now()
    }
    Timer {
        interval: 1000
        running: root.visible && root.playing && (!root.expanded || Theme.tokens.reducedMotion)
        repeat: true
        onTriggered: root.now = Date.now()
    }
    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusPill
        color: root.islandHovered ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
        border.width: 0
        visible: !!root.player && !root.expanded
        Behavior on color { ColorAnimation { duration: Theme.tokens.reducedMotion ? 0 : 140 } }
    }
    MouseArea {
        anchors.fill: parent
        objectName: 'island-menu-trigger'
        enabled: !root.expanded
        acceptedButtons: Qt.LeftButton
        onPressed: root.activated()
        onWheel: function(wheel) { root.handleWheel(wheel) }
    }
    HoverHandler { id: hover; blocking: false }
    HoverHandler {
        id: expandedHover
        parent: expandedSurface
        enabled: root.expanded
        blocking: false
    }
    PentadIcon {
        objectName: 'idle-logo'
        anchors.centerIn: parent
        width: Metrics.logo
        height: Metrics.logo * 26 / 28
        source: Qt.resolvedUrl('../../assets/icons/brand/logo-symbolic.svg')
        pixelSize: Metrics.logo
        accessibleName: 'Pentad activity'
        visible: !root.player && root.timerState.status === 'idle'
    }
    Text {
        anchors.centerIn: parent
        visible: !root.player && root.timerState.status !== 'idle'
        text: root.timerState.status === 'finished' ? 'Finished'
            : ClockLogic.formatTimer(root.timerState.remainingSeconds)
                + (root.timerState.status === 'paused' ? ' · paused' : '')
        color: Qt.alpha(Theme.tokens.text, 0.8)
        font.family: Theme.tokens.fontFamily
        renderType: Text.NativeRendering
        font.pixelSize: 12
        elide: Text.ElideRight
        width: parent.width - 24
        horizontalAlignment: Text.AlignHCenter
    }
    Item {
        objectName: 'left-channel-equalizer'
        x: 8
        width: 20
        height: parent.height
        visible: !!root.player && !root.expanded
        Row {
            objectName: 'stereo-equalizer-left'
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            opacity: 1 - root.hoverProgress
            visible: opacity > 0
            transform: Translate { x: -6 * root.hoverProgress }
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    readonly property var frame: root.services.visualizer.state
                    readonly property var values: frame.kind === 'ready' ? frame.value.left || [] : []
                    width: 3
                    height: root.playing && values.length
                        ? 5 + values[Math.floor((index + 1) * values.length / 5)] * 11
                        : [5, 9, 12, 7][index]
                    radius: 1.5
                    color: Qt.alpha(Theme.tokens.text, root.playing ? 0.82 : 0.5)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
    Item {
        objectName: 'right-channel-equalizer'
        anchors.right: parent.right
        anchors.rightMargin: 8
        width: 20
        height: parent.height
        opacity: 1 - root.hoverProgress
        visible: !!root.player && !root.expanded && opacity > 0
        Row {
            objectName: 'stereo-equalizer-right'
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    readonly property var frame: root.services.visualizer.state
                    readonly property var values: frame.kind === 'ready' ? frame.value.right || [] : []
                    width: 3
                    height: root.playing && values.length
                        ? 5 + values[Math.floor((index + 1) * values.length / 5)] * 11
                        : [7, 12, 9, 5][index]
                    radius: 1.5
                    color: Qt.alpha(Theme.tokens.text, root.playing ? 0.82 : 0.5)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
    Row {
        objectName: 'island-hover-controls'
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        opacity: root.hoverProgress
        visible: !!root.player && !root.expanded && opacity > 0
        transform: Translate { x: 8 * (1 - root.hoverProgress) }
        MediaButton { diameter: 24; glyphPixelSize: 16; text: 'Previous'; glyph: 'skip_previous'; enabled: !!root.player && root.player.canPrevious; onClicked: root.services.media.command(root.player.id, 'previous') }
        MediaButton {
            diameter: 26; glyphPixelSize: 18
            prominent: true
            text: root.playing ? 'Pause' : 'Play'
            glyph: root.playing ? 'pause' : 'play_arrow'
            enabled: !!root.player && root.player.canPlayPause
            onClicked: root.services.media.command(root.player.id, 'play-pause')
        }
        MediaButton { diameter: 24; glyphPixelSize: 16; text: 'Next'; glyph: 'skip_next'; enabled: !!root.player && root.player.canNext; onClicked: root.services.media.command(root.player.id, 'next') }
    }
    Column {
        objectName: 'island-track-info'
        anchors.verticalCenter: parent.verticalCenter
        x: 36 - 22 * root.hoverProgress
        width: Math.max(0, root.width - x - 36 - 54 * root.hoverProgress)
        // The marquee clips, so its box keeps the full glyph height; overlap the boxes instead.
        spacing: -3
        visible: !!root.player && !root.expanded
        opacity: root.switchProgress
        transform: Translate { x: 14 * root.switchDirection * (1 - root.switchProgress) }
        PentadMarquee {
            width: parent.width
            height: 17
            text: root.player ? root.player.title || root.player.name : ''
            marqueeEnabled: root.islandHovered && !root.menuOpen
            xAlign: 0.5 * (1 - root.hoverProgress)
            fontSize: 13
            color: Qt.alpha(Theme.tokens.text, 0.92)
        }
        Text {
            x: (parent.width - width) * 0.5 * (1 - root.hoverProgress)
            width: Math.min(implicitWidth, parent.width)
            height: 13
            objectName: 'island-artist-or-source'
            text: !root.player ? ''
                : root.sourceHintVisible ? Artwork.formatPlayerName(root.player.name) + '  ' + (root.playerIndex + 1) + '/' + root.players.length
                : root.player.artist || 'Unknown artist'
            color: Theme.tokens.textMuted
            font.family: Theme.tokens.fontFamily
            font.pixelSize: 10
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
    PopupWindow {
        id: overhang
        objectName: 'island-overhang-window'
        visible: root.expanded && root.visible
        grabFocus: false
        color: 'transparent'
        implicitWidth: Math.max(1, Math.ceil(root.width))
        implicitHeight: Math.max(1, Math.ceil(root.overhangHeight))
        anchor.item: root
        anchor.rect.x: 0
        anchor.rect.y: 0
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        mask: SurfaceRegion { id: contourRegion; surface: expandedSurface }
        ContinuousSurface {
            id: expandedSurface
            objectName: 'island-outer-surface'
            visible: root.expanded
            y: 0
            width: root.width
            height: root.overhangHeight
            extent: Metrics.attachedRadius
            concaveShoulder: Metrics.attachedShoulder
            joinOffset: root.implicitHeight
            fill: Theme.tokens.surface
            MouseArea {
                anchors.fill: parent
                objectName: 'island-expanded-menu-trigger'
                enabled: root.expanded
                acceptedButtons: Qt.LeftButton
                onPressed: root.activated()
                onWheel: function(wheel) { root.handleWheel(wheel) }
            }
            Column {
                id: lyricColumn
                objectName: 'island-lyrics'
                x: expandedSurface.cornerGeometry.shoulder + 12
                y: Math.max(0, (parent.height - implicitHeight) / 2)
                width: parent.width - 2 * x
                spacing: 4
                opacity: 1 - root.hoverProgress
                visible: opacity > 0
                transform: Translate { y: -4 * root.hoverProgress }
                Text {
                    visible: root.lineIndex > 0
                    width: parent.width
                    text: root.lineIndex > 0 ? root.lines[root.lineIndex - 1].text : ''
                    font.family: Theme.tokens.fontFamily; font.pixelSize: 10
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.tokens.textMuted; opacity: 0.4
                    elide: Text.ElideRight
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 4; blur: 0.65 }
                }
                KaraokeLine {
                    objectName: 'island-karaoke-line'
                    width: parent.width
                    text: root.gap > 0 ? '♪ ' + root.gap : root.lineIndex >= 0 ? root.lines[root.lineIndex].text : ''
                    progress: root.gap > 0 ? 0 : LyricsLogic.lyricProgress(root.lines, root.position, root.services.lyrics.offsetMs)
                }
                Text {
                    visible: root.lineIndex + 1 < root.lines.length
                    width: parent.width
                    text: root.lineIndex + 1 < root.lines.length ? root.lines[root.lineIndex + 1].text : ''
                    font.family: Theme.tokens.fontFamily; font.pixelSize: 13
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.tokens.text; opacity: 0.68
                    elide: Text.ElideRight
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 2; blur: 0.625 }
                }
            }
            KaraokeFocusCard {
                id: focusCard
                objectName: 'island-focus-card'
                opacity: root.hoverProgress
                visible: opacity > 0
                scale: 0.97 + 0.03 * root.hoverProgress
                x: expandedSurface.cornerGeometry.shoulder + Metrics.attachedRim
                y: Metrics.attachedRim
                width: expandedSurface.cornerGeometry.bodyWidth - 2 * Metrics.attachedRim
                height: implicitHeight
                extent: Math.max(0, expandedSurface.cornerGeometry.radius - Metrics.attachedRim)
                services: root.services
                player: root.player
                consumerId: root.consumerId
            }
        }
    }
}
