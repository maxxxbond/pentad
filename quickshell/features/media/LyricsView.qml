import QtQuick
import QtQuick.Controls.Basic
import "../../logic/lyrics.mjs" as LyricsLogic
import qs.theme

Column {
    id: root
    required property var services
    required property var player
    property real positionMicros: player ? Number(player.positionMicros || 0) : 0
    property color accent: Theme.tokens.accent
    property bool karaoke: false
    property bool singalong: false
    property bool following: true
    property bool programmaticScroll: false
    property string searchQuery: ""
    property string consumerId: "media-card-" + (outputId || "default") + "-lyrics"
    property string outputId: "default"
    readonly property string lyricTrackKey: player ? JSON.stringify([
        player.id || "", player.trackId || "", player.trackRevision || "", player.title || "", player.artist || ""
    ]) : ""
    property string acquiredConsumerId: ""
    property bool consumerAcquired: false
    property bool lifecycleReady: false
    property var lyricState: {
        var value = services.lyrics.state;
        return value && value.kind === "ready" ? value.value : ({ lines: [], plain: "", instrumental: false });
    }
    property string lyricsMode: LyricsLogic.lyricsPresentation(services.lyrics.state)
    property var lines: lyricState.lines || []
    property var displayLines: {
        var query = searchQuery.trim().toLocaleLowerCase();
        if (!query) return lines;
        return lines.filter(function(line) { return String(line.text || "").toLocaleLowerCase().indexOf(query) >= 0; });
    }
    property int activeIndex: LyricsLogic.activeLyric(lines, positionMicros / 1000000 + Number(services.lyrics.offsetMs || 0) / 1000)
    spacing: 2
    height: lyricsMode === "synced" || lyricsMode === "plain" ? implicitHeight : 0

    function sync() {
        if (!lifecycleReady) return;
        if (consumerAcquired && acquiredConsumerId !== consumerId) {
            services.lyrics.release(acquiredConsumerId);
            acquiredConsumerId = "";
            consumerAcquired = false;
        }
        if (visible && player && consumerId && !consumerAcquired) {
            services.lyrics.acquire(consumerId);
            acquiredConsumerId = consumerId;
            consumerAcquired = true;
        } else if ((!visible || !player) && consumerAcquired) {
            services.lyrics.release(acquiredConsumerId);
            acquiredConsumerId = "";
            consumerAcquired = false;
        }
    }
    function lyricProgressFor(line) {
        var seconds = positionMicros / 1000000;
        var offset = Number(services.lyrics.offsetMs || 0);
        var words = line && Array.isArray(line.words) ? line.words : [];
        if (!words.length) return LyricsLogic.lyricProgress(lines, seconds, offset);
        var wordIndex = LyricsLogic.activeLyricWord(line, seconds + offset / 1000, 0);
        if (wordIndex < 0) return 0;
        var wordProgress = LyricsLogic.lyricWordProgress(line, wordIndex, seconds, offset);
        var completed = 0;
        for (var i = 0; i < wordIndex; i++) completed += String(words[i].text || "").length + 1;
        var activeLength = String(words[wordIndex].text || "").length;
        var textLength = Math.max(1, String(line.text || "").length);
        return Math.max(0, Math.min(1, (completed + activeLength * Math.max(0, wordProgress)) / textLength));
    }
    function originalIndex(line) {
        for (var i = 0; i < lines.length; i++)
            if (Number(lines[i].at) === Number(line.at) && String(lines[i].text || "") === String(line.text || "")) return i;
        return -1;
    }
    function offsetLabel() {
        var seconds = Number(services.lyrics.offsetMs || 0) / 1000;
        return (seconds > 0 ? "+" : seconds < 0 ? "−" : "") + Math.abs(seconds).toFixed(2) + "s";
    }
    function centerActive() {
        if (!following || searchQuery || activeIndex < 0) return;
        var row = lyricRepeater.itemAt(activeIndex);
        if (!row) return;
        programmaticScroll = true;
        lyricsFlick.contentY = Math.max(0, Math.min(lyricsFlick.contentHeight - lyricsFlick.height,
            row.y + row.height / 2 - lyricsFlick.height / 2));
        Qt.callLater(function() { root.programmaticScroll = false; });
    }
    function resetForTrack() {
        searchQuery = "";
        lyricsSearch.clear();
        searchBox.visible = false;
        following = true;
        lyricsFlick.contentY = 0;
    }
    function restoreFollow() {
        resumeFollow.stop();
        following = true;
        centerActive();
    }
    onVisibleChanged: sync()
    onPlayerChanged: sync()
    onLyricTrackKeyChanged: Qt.callLater(resetForTrack)
    onLyricsModeChanged: if (lyricsMode !== "synced") {
        searchQuery = "";
        Qt.callLater(function() { lyricsSearch.clear(); searchBox.visible = false; });
    }
    onOutputIdChanged: sync()
    onActiveIndexChanged: Qt.callLater(centerActive)
    onLinesChanged: Qt.callLater(centerActive)
    Component.onCompleted: { lifecycleReady = true; sync(); }
    Component.onDestruction: if (consumerAcquired) services.lyrics.release(acquiredConsumerId)

    Row {
        objectName: 'lyrics-toolbar'
        visible: root.lyricsMode === "synced"
        width: parent.width
        height: 36
        spacing: 8
        MediaButton {
            text: root.singalong ? "Switch to reading lyrics" : "Switch to sing-along lyrics"
            glyph: root.singalong ? "mic_external_on" : "format_align_left"
            accent: root.accent
            diameter: 32
            onPressed: root.singalong = !root.singalong
        }
        MediaButton {
            text: root.searchQuery.length ? "Clear lyrics search" : "Search lyrics"
            glyph: root.searchQuery.length ? "close" : "search"
            accent: root.accent
            diameter: 32
            onPressed: {
                if (root.searchQuery.length) {
                    root.searchQuery = "";
                    searchBox.visible = false;
                } else {
                    searchBox.visible = !searchBox.visible;
                    if (searchBox.visible) Qt.callLater(function() { lyricsSearch.forceActiveFocus(); });
                }
            }
        }
        Item { width: Math.max(0, parent.width - 214 - (root.following ? 0 : 104)); height: 1 }
        MediaButton { text: "Earlier by 250 milliseconds"; glyph: "remove"; accent: root.accent; diameter: 28; onPressed: root.services.lyrics.offsetMs = Math.max(-10000, root.services.lyrics.offsetMs - 250) }
        Button {
            id: offsetReset
            text: root.offsetLabel()
            Accessible.name: "Reset lyrics offset, currently " + text
            Accessible.role: Accessible.Button
            implicitWidth: 54
            implicitHeight: 28
            contentItem: Text { text: offsetReset.text; color: root.accent; font.family: "monospace"; font.pixelSize: Metrics.textCaption; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: "transparent"; radius: 6 }
            onPressed: root.services.lyrics.offsetMs = 0
        }
        MediaButton { text: "Later by 250 milliseconds"; glyph: "add"; accent: root.accent; diameter: 28; onPressed: root.services.lyrics.offsetMs = Math.min(10000, root.services.lyrics.offsetMs + 250) }
        Button {
            id: followButton
            visible: !root.following && root.lines.length > 0
            width: visible ? 96 : 0
            height: 28
            padding: 0
            text: "Follow lyrics"
            Accessible.name: text
            onPressed: root.restoreFollow()
            contentItem: Text {
                text: followButton.text
                color: followButton.hovered ? Theme.tokens.surface : root.accent
                font.family: Theme.tokens.fontFamily
                font.pixelSize: Metrics.textCaption
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 8
                color: followButton.down ? root.accent : followButton.hovered
                    ? Qt.alpha(root.accent, 0.8) : Qt.alpha(root.accent, 0.16)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.48)
            }
        }
    }
    Row {
        id: searchBox
        visible: false
        width: parent.width
        spacing: 4
        TextField {
            id: lyricsSearch
            width: parent.width - 36
            placeholderText: "Search lyrics…"
            Accessible.name: "Search lyrics"
            onTextChanged: root.searchQuery = text
        }
        MediaButton { text: "Close lyrics search"; glyph: "close"; accent: root.accent; onPressed: { lyricsSearch.clear(); searchBox.visible = false; } }
    }
    Item {
        visible: root.lyricsMode === "synced" || root.lyricsMode === "plain"
        width: parent.width
        height: Math.min(180, lyricList.implicitHeight)
        clip: true
        Flickable {
            id: lyricsFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: lyricList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onMovementStarted: {
                if (root.programmaticScroll) return;
                root.following = false;
                resumeFollow.restart();
            }
            Column {
                id: lyricList
                width: lyricsFlick.width
                spacing: 8
                Text {
                    id: plainLyrics
                    visible: root.lyricsMode === "plain"
                    width: lyricList.width
                    text: visible ? root.lyricState.plain : ""
                    textFormat: Text.PlainText
                    color: Qt.alpha(root.accent, 0.82)
                    font.family: Theme.tokens.fontFamily
                    renderType: Text.NativeRendering
                    font.pixelSize: Metrics.textSection
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    id: lyricRepeater
                    model: root.lyricsMode === "synced" ? root.displayLines : []
                    delegate: Item {
                        required property int index
                        required property var modelData
                        width: lyricList.width
                        implicitHeight: lyricText.implicitHeight + 12
                        property int sourceIndex: root.originalIndex(modelData)
                        property bool activeLine: sourceIndex === root.activeIndex
                        property real karaokeProgress: activeLine ? root.lyricProgressFor(modelData) : -1
                        Text {
                            id: lyricText
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            text: modelData.text || "♪"
                            color: parent.activeLine && !root.singalong ? root.accent : Qt.alpha(root.accent, 0.62)
                            font.family: Theme.tokens.fontFamily
                            renderType: Text.NativeRendering
                            font.pixelSize: Metrics.textSection
                            font.weight: parent.activeLine ? Font.DemiBold : Font.Medium
                            wrapMode: Text.WordWrap
                        }
                        Item {
                            anchors.left: lyricText.left
                            anchors.top: lyricText.top
                            width: root.singalong && karaokeProgress >= 0 ? Math.min(lyricText.paintedWidth, lyricText.width) * karaokeProgress : 0
                            height: lyricText.height
                            clip: true
                            visible: width > 0
                            Text { width: lyricText.width; text: modelData.text || "♪"; color: root.accent; font: lyricText.font; wrapMode: Text.WordWrap }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !!root.player && !!root.player.canSeek && !!root.player.trackId && Number(root.player.lengthMicros || 0) > 0
                            onPressed: {
                                root.services.media.seek(root.player.id, root.player.trackId,
                                    Math.round(Math.max(0, Math.min(root.player.lengthMicros, modelData.at * 1000000))), root.player.trackRevision);
                                root.restoreFollow();
                            }
                            Accessible.name: "Seek to " + (modelData.text || "lyric")
                            Accessible.role: Accessible.Button
                        }
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {
                active: hovered || pressed || lyricsFlick.moving
                visible: lyricsFlick.contentHeight > lyricsFlick.height && active
            }
        }
    }
    Timer { id: resumeFollow; interval: 7000; onTriggered: root.restoreFollow() }
}
