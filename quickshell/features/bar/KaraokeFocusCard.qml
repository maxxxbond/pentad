import QtQuick
import QtQuick.Effects
import Quickshell
import qs.components
import qs.theme
import '../media'
import '../../logic/artwork.mjs' as Artwork

ContinuousSurface {
    id: root
    required property var services
    required property var player
    property string consumerId: ''
    property var art: player ? Artwork.resolveArtwork(player.artUrl, player.url, player.name) : ({ urls: [] })
    readonly property string artworkConsumerId: (consumerId || 'karaoke') + ':focus-artwork'
    property string activeArtworkConsumerId: ''
    readonly property string artworkTrackKey: player ? JSON.stringify([player.id || '', player.trackId || '',
        player.trackRevision || '', player.title || '', player.artist || '']) : ''
    property var artState: services.artwork.stateFor(artworkConsumerId)
    readonly property string artworkSource: artState.kind === 'ready' ? artState.source : ''
    property color accent: {
        const tone = String(cover.source) ? Artwork.coverAccent(artColors.colors) : null;
        return tone ? Qt.hsla(tone.hue, tone.saturation, tone.lightness, 1) : '#adad9e';
    }
    implicitHeight: Metrics.islandReach - 2 * Metrics.attachedRim
    extent: 20
    fill: Theme.tokens.surface
    function syncArtwork() {
        // Hover fades this card in and out constantly; follow the island's visibility instead so the cover does not flash the fallback.
        if (!player || !parent || !parent.visible) {
            if (activeArtworkConsumerId) services.artwork.release(activeArtworkConsumerId);
            activeArtworkConsumerId = '';
            return;
        }
        if (activeArtworkConsumerId && activeArtworkConsumerId !== artworkConsumerId)
            services.artwork.release(activeArtworkConsumerId);
        activeArtworkConsumerId = artworkConsumerId;
        services.artwork.request(activeArtworkConsumerId, art.urls, artworkTrackKey);
    }
    onArtChanged: syncArtwork()
    onParentChanged: syncArtwork()
    Connections { target: root.parent; function onVisibleChanged() { root.syncArtwork() } }
    onArtworkConsumerIdChanged: syncArtwork()
    onArtworkTrackKeyChanged: syncArtwork()
    Component.onCompleted: syncArtwork()
    Component.onDestruction: if (activeArtworkConsumerId) services.artwork.release(activeArtworkConsumerId)
    AudioWave {
        anchors.fill: parent
        services: root.services
        consumerId: root.consumerId + ':focus-wave'
        playing: !!root.player && root.player.playback === 'playing'
        accent: root.accent
        artworkSource: cover.status === Image.Ready ? cover.source : ''
    }
    Item {
        x: 8; y: 8; width: 64; height: 64
        // Concentric with the card: its extent minus the 8 px cover inset.
        Rectangle { id: coverMask; anchors.fill: parent; radius: Math.max(0, root.extent - 8); color: 'white'; visible: false }
        ShaderEffectSource { id: coverMaskTexture; anchors.fill: parent; sourceItem: coverMask; hideSource: true; live: true; visible: false }
        Rectangle { anchors.fill: parent; radius: coverMask.radius; color: Qt.alpha(Theme.tokens.text, 0.055) }
        Item {
            id: coverSource
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Image {
                id: cover
                anchors.fill: parent
                source: root.artworkSource
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                onStatusChanged: if (status === Image.Error && String(source) === String(root.artworkSource))
                    root.services.artwork.reject(root.artworkConsumerId, source)
            }
        }
        MultiEffect {
            anchors.fill: coverSource
            source: coverSource
            maskEnabled: true
            maskSource: coverMaskTexture
            visible: cover.status === Image.Ready
        }
        PentadIcon {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            source: Qt.resolvedUrl('../../assets/icons/material/media/music-note-symbolic.svg')
            pixelSize: 32
            color: root.accent
        }
    }
    ColorQuantizer {
        id: artColors
        // ColorQuantizer reads local files only; remote artwork keeps the fallback accent.
        source: /^(file:|qrc:|\/)/.test(String(cover.source)) ? cover.source : ''
        depth: 3; rescaleSize: 64
    }
    Column {
        x: 84; y: 6
        width: Math.max(0, root.width - x - 8)
        // The marquee clips, so its box keeps the full glyph height; overlap the boxes instead.
        spacing: -4
        PentadMarquee {
            objectName: 'island-focus-title'
            width: Math.max(0, parent.width - exitButton.width - 8)
            height: 22
            text: root.player ? root.player.title : ''
            fontSize: 16
            xAlign: 0
            marqueeEnabled: root.visible
            color: Qt.alpha(Theme.tokens.text, 0.8)
        }
        Text {
            width: parent.width
            height: 14
            text: root.player ? root.player.artist : ''
            color: Theme.tokens.textMuted; font.family: Theme.tokens.fontFamily; font.pixelSize: 12
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }
    }
    MediaButton {
        id: exitButton
        objectName: 'island-focus-exit'
        anchors.right: parent.right; anchors.rightMargin: 8
        y: 6
        diameter: 20; glyphPixelSize: 14
        text: 'Disable karaoke'; glyph: 'close'
        foreground: hovered || down ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.35)
        onClicked: root.services.activity.karaoke = false
    }
    Row {
        id: transport
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
        spacing: 8
        MediaButton {
            objectName: 'island-focus-previous'
            anchors.verticalCenter: parent.verticalCenter
            diameter: 28; text: 'Previous'; glyph: 'skip_previous'
            foreground: hovered ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.82)
            enabled: !!root.player && root.player.canPrevious
            onClicked: root.services.media.command(root.player.id, 'previous')
        }
        MediaButton {
            id: playButton
            objectName: 'island-focus-play'
            diameter: 32; prominent: true; accent: root.accent
            text: root.player && root.player.playback === 'playing' ? 'Pause' : 'Play'
            glyph: root.player && root.player.playback === 'playing' ? 'pause' : 'play_arrow'
            enabled: !!root.player && root.player.canPlayPause
            background: Rectangle {
                radius: 8
                color: playButton.down ? Qt.darker(root.accent, 1.15)
                    : playButton.hovered ? Qt.lighter(root.accent, 1.15) : root.accent
                opacity: playButton.enabled ? 1 : 0.35
            }
            onClicked: root.services.media.command(root.player.id, 'play-pause')
        }
        MediaButton {
            objectName: 'island-focus-next'
            anchors.verticalCenter: parent.verticalCenter
            diameter: 28; text: 'Next'; glyph: 'skip_next'
            foreground: hovered ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.82)
            enabled: !!root.player && root.player.canNext
            onClicked: root.services.media.command(root.player.id, 'next')
        }
    }
}
