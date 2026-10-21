import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import Quickshell
import qs.components
import "../../logic/artwork.mjs" as Artwork
import "../../logic/lyrics.mjs" as LyricsLogic
import "../../logic/media.mjs" as MediaLogic
import "../../theme"

Column {
    id: root
    required property var services
    property string outputId: "default"
    property string mediaConsumerId: "media-card-" + (outputId || "default")
    property string artworkConsumerId: mediaConsumerId + "-artwork"
    property string activeArtworkConsumerId: ""
    property string acquiredMediaConsumerId: ""
    property bool mediaConsumerAcquired: false
    property bool mediaLifecycleReady: false
    property bool karaokeEnabled: false
    signal karaokeChanged(bool enabled)
    property var mediaState: services.media.state
    property var mediaValue: mediaState && mediaState.kind === "ready" ? mediaState.value : ({ players: [], current: null, selectedId: "" })
    property var players: mediaValue.players || []
    property var player: mediaValue.current
    property bool lyricsOpen: true
    property string lyricsMode: LyricsLogic.lyricsPresentation(services.lyrics.state)
    property var lyricsState: services.lyrics.state
    property string lyricsTooltip: {
        if (lyricsMode === "loading") return "Loading lyrics…";
        if (lyricsMode === "instrumental") return "Instrumental track";
        if (lyricsState.kind === "error") {
            if (lyricsState.reason === "start-failed") return "Lyrics request could not start.";
            if (lyricsState.reason === "timeout") return "Lyrics request timed out. Reopen to retry.";
            if (lyricsState.reason === "invalid-response") return "Lyrics response was invalid. Reopen to retry.";
            if (lyricsState.exitCode === 6) return "Lyrics DNS lookup failed (curl 6).";
            if (lyricsState.exitCode === 7) return "Lyrics connection failed (curl 7).";
            if (lyricsState.exitCode === 28) return "Lyrics request timed out (curl 28).";
            if (lyricsState.exitCode === 60) return "Lyrics TLS certificate check failed (curl 60).";
            if (lyricsState.httpStatus >= 400) return "Lyrics service returned HTTP " + lyricsState.httpStatus + ".";
            return "Lyrics request failed. Reopen to retry.";
        }
        if (lyricsState.kind === "unavailable") {
            if (lyricsState.reason === "rate-limited") return "Lyrics provider rate limited requests. Try later.";
            if (lyricsState.reason === "preview") return "Lyrics lookup is disabled in preview.";
            if (lyricsState.reason === "safe-mode") return "Lyrics lookup is disabled in safe mode.";
            if (lyricsState.reason === "not-loaded") return "Open lyrics to look up this track.";
            if (lyricsState.reason === "no-track") return "Track title or artist is unavailable.";
        }
        if (lyricsMode === "missing") return "No matching lyrics found.";
        return "Song lyrics";
    }
    property real clockNow: Date.now()
    readonly property real rawPositionMicros: player ? Math.min(Number(player.lengthMicros || Number.MAX_VALUE), Math.max(0, Number(player.positionMicros || 0) + (player.playback === "playing" ? Math.max(0, clockNow - Number(player.positionUpdatedAt || clockNow)) * 1000 : 0))) : 0
    readonly property string positionKey: player ? JSON.stringify([player.id || "", player.trackId || "", player.trackRevision || ""]) : ""
    property string shownPositionKey: ""
    // Spotify reports a lagging position between polls; while playing, ignore small
    // backward steps so the bar and the clock don't jitter back and forth.
    property real positionMicros: 0
    function followPosition() {
        var raw = rawPositionMicros;
        var backwards = positionMicros - raw;
        var jitter = player && player.playback === "playing" && positionKey === shownPositionKey
            && backwards > 0 && backwards < 1500000;
        shownPositionKey = positionKey;
        if (!jitter) positionMicros = raw;
    }
    onRawPositionMicrosChanged: followPosition()
    onPositionKeyChanged: followPosition()
    property var art: player ? Artwork.resolveArtwork(player.artUrl, player.url, player.name) : ({ urls: [], mark: "" })
    property string artworkTrackKey: player ? JSON.stringify([player.id || "", player.trackId || "",
        player.trackRevision || "", player.title || "", player.artist || ""]) : ""
    property var artState: services.artwork.stateFor(artworkConsumerId)
    property color artAccent: {
        const tone = String(cover.source) ? Artwork.coverAccent(artColors.colors) : null;
        return tone ? Qt.hsla(tone.hue, tone.saturation, tone.lightness, 1) : "#adad9e";
    }
    spacing: 12
    width: 420
    visible: !!player

    function syncMediaConsumer() {
        if (!mediaLifecycleReady) return;
        if (mediaConsumerAcquired && acquiredMediaConsumerId !== mediaConsumerId) {
            services.media.release(acquiredMediaConsumerId);
            acquiredMediaConsumerId = "";
            mediaConsumerAcquired = false;
        }
        if (visible && mediaConsumerId && !mediaConsumerAcquired) {
            services.media.acquire(mediaConsumerId);
            acquiredMediaConsumerId = mediaConsumerId;
            mediaConsumerAcquired = true;
        } else if (!visible && mediaConsumerAcquired) {
            services.media.release(acquiredMediaConsumerId);
            acquiredMediaConsumerId = "";
            mediaConsumerAcquired = false;
        }
    }
    function syncArtwork() {
        if (!mediaLifecycleReady) return;
        if (!visible || !player) {
            if (activeArtworkConsumerId) services.artwork.release(activeArtworkConsumerId);
            activeArtworkConsumerId = "";
            return;
        }
        if (activeArtworkConsumerId && activeArtworkConsumerId !== artworkConsumerId)
            services.artwork.release(activeArtworkConsumerId);
        activeArtworkConsumerId = artworkConsumerId;
        services.artwork.request(activeArtworkConsumerId, art.urls, artworkTrackKey);
    }
    onVisibleChanged: { syncMediaConsumer(); syncArtwork(); }
    onOutputIdChanged: syncMediaConsumer()
    onArtworkConsumerIdChanged: syncArtwork()
    onArtworkTrackKeyChanged: syncArtwork()
    Component.onCompleted: { followPosition(); mediaLifecycleReady = true; syncMediaConsumer(); syncArtwork(); }
    Component.onDestruction: {
        if (mediaConsumerAcquired) services.media.release(acquiredMediaConsumerId);
        if (activeArtworkConsumerId) services.artwork.release(activeArtworkConsumerId);
    }

    Timer {
        interval: 100
        repeat: true
        running: root.visible && !!root.player && root.player.playback === "playing" && !Theme.tokens.reducedMotion
        onTriggered: root.clockNow = Date.now()
    }
    onPlayerChanged: clockNow = Date.now()
    onArtChanged: syncArtwork()

    MediaSourceSelector {
        width: parent.width
        services: root.services
        players: root.players
        currentId: root.player ? String(root.player.id) : String(root.mediaValue.selectedId || "")
        currentName: root.player ? Artwork.formatPlayerName(root.player.name) : ""
        onCycleRequested: function(offset) { root.cyclePlayer(offset); }
    }
    ContinuousSurface {
        objectName: 'music-player-surface'
        width: parent.width
        height: 143
        extent: Metrics.radiusBlock
        fill: Theme.tokens.surface
        clipContent: true
        AudioWave {
            anchors.fill: parent
            services: root.services
            consumerId: root.mediaConsumerId + "-visualizer"
            playing: root.player && root.player.playback === "playing"
            accent: root.artAccent
            artworkSource: root.artState.kind === "ready" ? root.artState.source : ""
        }
        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            Item {
                objectName: 'music-player-cover'
                width: 112; height: 112
                anchors.verticalCenter: parent.verticalCenter
                ContinuousSurface { id: coverMask; anchors.fill: parent; extent: Math.max(0, Metrics.radiusBlock - 12); fill: "white"; visible: false }
                ShaderEffectSource { id: coverMaskTexture; anchors.fill: parent; sourceItem: coverMask; hideSource: true; live: true; visible: false }
                Item {
                    id: coverSource
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: root.artState.kind === "ready" ? root.artState.source : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: 512
                        sourceSize.height: 512
                        onStatusChanged: if (status === Image.Error && String(source) === String(root.artState.source))
                            root.services.artwork.reject(root.artworkConsumerId, source)
                    }
                    ColorQuantizer {
                        id: artColors
                        // ColorQuantizer reads local files only; remote artwork keeps the fallback accent.
                        source: /^(file:|qrc:|\/)/.test(String(cover.source)) ? cover.source : ''
                        depth: 3
                        rescaleSize: 64
                    }
                }
                ContinuousSurface {
                    anchors.fill: parent
                    extent: Math.max(0, Metrics.radiusBlock - 12)
                    fill: Qt.alpha(Theme.tokens.text, 0.055)
                    z: 2
                    visible: cover.status !== Image.Ready
                    PentadIcon {
                        objectName: 'music-cover-fallback'
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl('../../assets/icons/material/media/'
                            + (root.art.mark === 'youtube' ? 'play-arrow' : root.art.mark === 'instagram' ? 'photo-camera' : 'music-note')
                            + '-symbolic.svg')
                        color: root.artAccent
                        pixelSize: 40
                    }
                }
                MultiEffect {
                    anchors.fill: coverSource
                    source: coverSource
                    maskEnabled: true
                    maskSource: coverMaskTexture
                    visible: cover.status === Image.Ready
                }
            }
            Column {
                objectName: 'music-player-controls'
                width: parent.width - 124
                height: implicitHeight
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Row {
                    width: parent.width
                    height: 26
                    spacing: 8
                    Text {
                        width: parent.width - 52 - 2 * parent.spacing
                        height: parent.height
                        text: root.player ? root.player.title || "Untitled" : ""
                        color: Theme.tokens.text
                        font.family: Theme.tokens.fontFamily
                        renderType: Text.NativeRendering
                        font.pixelSize: Metrics.textSection
                        font.weight: Font.Normal
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    MediaButton {
                        text: "Song lyrics"
                        glyph: "lyrics"
                        selected: root.lyricsOpen
                        accent: root.lyricsMode === "synced" || root.lyricsMode === "plain"
                            ? root.artAccent : Theme.tokens.textMuted
                        diameter: 26
                        cornerRadius: 13
                        glyphPixelSize: 15
                        Accessible.name: root.lyricsTooltip === "Song lyrics"
                            ? "Song lyrics" : "Song lyrics. " + root.lyricsTooltip
                        onPressed: root.lyricsOpen = !root.lyricsOpen
                    }
                    MediaButton {
                        text: "Karaoke in Dynamic Island"
                        glyph: "mic"
                        selected: root.karaokeEnabled
                        accent: root.artAccent
                        diameter: 26
                        cornerRadius: 13
                        glyphPixelSize: 15
                        onPressed: { root.karaokeEnabled = !root.karaokeEnabled; root.karaokeChanged(root.karaokeEnabled); }
                    }
                }
                Text {
                    width: parent.width
                    height: 13
                    text: root.player ? root.player.artist || "Unknown artist" : ""
                    color: Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    renderType: Text.NativeRendering
                    font.pixelSize: Metrics.textCaption
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                Row {
                    id: timeRow
                    objectName: 'music-player-time-row'
                    width: parent.width
                    height: 44
                    spacing: 8
                    Text {
                        width: parent.width - timeRow.spacing - playButton.width
                        height: parent.height
                        text: root.formatTime(root.positionMicros) + " / " + root.formatTime(root.player ? root.player.lengthMicros || 0 : 0)
                        color: Theme.tokens.textMuted
                        font.family: Theme.tokens.fontFamily
                        renderType: Text.NativeRendering
                        font.pixelSize: Metrics.textBody
                        font.features: ({ tnum: 1 })
                        font.capitalization: Font.MixedCase
                        verticalAlignment: Text.AlignBottom
                        bottomPadding: 4
                    }
                    MediaButton {
                        id: playButton
                        text: root.player && root.player.playback === "playing" ? "Pause" : "Play"
                        glyph: root.player && root.player.playback === "playing" ? "pause" : "play_arrow"
                        prominent: true
                        diameter: 40
                        glyphPixelSize: 24
                        cornerRadius: 12
                        pausedProminent: !root.player || root.player.playback !== "playing"
                        accent: root.artAccent
                        enabled: !!root.player && !!root.player.canPlayPause
                        onPressed: root.services.media.command(root.player.id, "play-pause")
                    }
                }
                Row {
                    objectName: 'music-player-seek-row'
                    width: parent.width
                    height: 24
                    spacing: 6
                    MediaButton {
                        text: "Previous track"
                        glyph: "skip_previous"
                        accent: root.artAccent
                        diameter: 24
                        glyphPixelSize: 20
                        enabled: !!root.player && !!root.player.canPrevious
                        onPressed: root.services.media.command(root.player.id, "previous")
                    }
                    WaveSeek {
                        width: parent.width - 60
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        player: root.player
                        services: root.services
                        positionMicros: root.positionMicros
                        accent: root.artAccent
                    }
                    MediaButton {
                        text: "Next track"
                        glyph: "skip_next"
                        accent: root.artAccent
                        diameter: 24
                        glyphPixelSize: 20
                        enabled: !!root.player && !!root.player.canNext
                        onPressed: root.services.media.command(root.player.id, "next")
                    }
                }
            }
        }
    }
    LyricsView {
        x: 12
        width: parent.width - 24
        visible: root.lyricsOpen
        services: root.services
        player: root.player
        positionMicros: root.positionMicros
        karaoke: root.karaokeEnabled
        accent: root.artAccent
        outputId: root.outputId
    }

    function sourceAt(offset) {
        if (!players.length) return "";
        var index = players.findIndex(function(item) { return item.id === mediaValue.selectedId; });
        if (index < 0 && player) index = players.findIndex(function(item) { return item.id === player.id; });
        if (index < 0) index = 0;
        return Artwork.formatPlayerName(players[(index + offset + players.length) % players.length].name);
    }
    function cyclePlayer(offset) {
        var id = MediaLogic.adjacentPlayerId(players, player ? player.id : mediaValue.selectedId, offset);
        if (id) services.media.selectPlayer(id);
    }
    function formatTime(micros) {
        var seconds = Math.max(0, Math.floor(Number(micros || 0) / 1000000));
        var minutes = Math.floor(seconds / 60);
        return String(minutes).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
    }
}
