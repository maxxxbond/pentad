import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io
import qs.components
import qs.features.shelf
import qs.theme
import '../../logic/drag-drop.mjs' as DropLogic
import '../../logic/shelf.mjs' as ShelfLogic

Column {
    id: root
    required property var services
    required property var shelf
    property string outputId: "default"
    property bool readOnly: true
    property int currentIndex: 0
    property string message: ""
    property string localSendExecutable: 'localsend'
    property int dropTabIndex: -1
    signal closeRequested()
    readonly property var localSendCommand: launcher.command
    readonly property alias musicCard: card
    readonly property alias shelfGrid: files
    readonly property alias tabIndicator: marker
    readonly property var labels: ["Media", "LocalSend", "Shelf", "Cloud"]
    readonly property var currentPage: [mediaPage, localPage, shelfPage, cloudPage][currentIndex]
    readonly property bool dragHovered: files.dragHovered || localDrop.containsDrag || dropTabIndex >= 0
    readonly property bool dragOutActive: files.exportInProgress
    width: 420
    spacing: 12

    function tr(uk, en) { return typeof services.text === 'function' ? services.text(uk, en) : en; }

    function selectTab(index) {
        if (index < 0 || index >= labels.length || index === currentIndex) return;
        currentIndex = index;
        message = "";
        pageEnter.restart();
    }
    function openLocalSend(uris) {
        if (readOnly || launcher.running) return false;
        let paths = [];
        if (uris && uris.length) {
            const parsed = ShelfLogic.localFilePaths(uris);
            if (!parsed.ok) { message = 'Only local files can be shared.'; return false; }
            paths = parsed.paths;
        }
        launcher.command = [localSendExecutable].concat(paths);
        message = "";
        launcher.started = false;
        launcher.running = true;
        launchCheck.restart();
        return true;
    }
    function receiveLocalDrop(drop) {
        const offer = DropLogic.readOffer(drop, true);
        const parsed = offer.ok ? ShelfLogic.parseUriList(offer.value) : { ok: false };
        if (!parsed.ok || !openLocalSend(parsed.uris)) {
            drop.accepted = false;
            if (!readOnly) message = 'Could not hand these files to LocalSend.';
            return;
        }
        drop.accept(Qt.CopyAction);
    }
    Process {
        id: launcher
        property bool started: false
        command: ["localsend"]
        onStarted: started = true
        onExited: function(code) { if (code !== 0) root.message = "Could not open LocalSend"; }
    }
    Timer {
        id: launchCheck
        interval: 1000
        onTriggered: if (!launcher.started) root.message = "LocalSend is not installed or could not start";
    }

    Item {
        id: tabs
        objectName: "activity-tabs"
        width: parent.width
        height: 40
        Accessible.role: Accessible.PageTabList
        Rectangle {
            id: marker
            width: 24; height: 2; radius: 1
            x: (root.currentIndex + 0.5) * tabs.width / root.labels.length - width / 2
            y: 30
            color: Theme.tokens.accent
            Behavior on x { NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
        }
        Row {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            Repeater {
                model: root.labels
                delegate: Button {
                    id: tabButton
                    required property int index
                    required property string modelData
                    objectName: "activity-tab-" + index
                    width: tabs.width / root.labels.length
                    height: 32
                    text: modelData
                    Accessible.role: Accessible.PageTab
                    Accessible.name: text
                    Accessible.selected: root.currentIndex === index
                    onPressed: root.selectTab(index)
                    DropArea {
                        anchors.fill: parent
                        onEntered: drag => {
                            drag.accepted = !root.readOnly && [1, 2].indexOf(tabButton.index) >= 0
                                && (tabButton.index === 2 ? DropLogic.supportsShelfOffer(drag.formats)
                                    : !!DropLogic.offerMime(drag.formats, true));
                            if (!drag.accepted) return;
                            drag.accept(Qt.CopyAction);
                            root.dropTabIndex = tabButton.index;
                            root.selectTab(tabButton.index);
                        }
                        onExited: if (root.dropTabIndex === tabButton.index) root.dropTabIndex = -1
                        onDropped: drop => {
                            root.dropTabIndex = -1;
                            if (tabButton.index === 1) root.receiveLocalDrop(drop);
                            else {
                                files.receiveDrop(drop);
                            }
                        }
                    }
                    contentItem: Text {
                        text: parent.text
                        color: root.currentIndex === index || parent.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                        font.family: Theme.tokens.fontFamily
                        font.pixelSize: 12
                        font.weight: root.currentIndex === index ? Font.DemiBold : Font.Normal
                        renderType: Text.NativeRendering
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: ContinuousSurface {
                        extent: Metrics.radiusMicro
                        fill: "transparent"
                        edge: parent.visualFocus ? Theme.tokens.accent : "transparent"
                    }
                }
            }
        }
    }

    Item {
        id: pages
        width: parent.width
        implicitHeight: root.currentPage.implicitHeight
        height: implicitHeight
        clip: true
        NumberAnimation { id: pageEnter; target: pages; property: "opacity"; from: 0; to: 1; duration: Motion.short }
        Column {
            id: mediaPage
            width: parent.width
            visible: root.currentIndex === 0
            spacing: 12
            PentadText {
                width: parent.width
                visible: root.services.media.writable === false
                text: root.tr('Режим перегляду · керування відтворенням вимкнено', 'Preview · playback controls are disabled')
                role: 'caption'
                color: Theme.tokens.textMuted
            }
            MusicCard {
                id: card
                width: parent.width
                services: root.services
                outputId: root.outputId
                karaokeEnabled: root.services.activity.karaoke
                onKaraokeChanged: function(enabled) { root.services.activity.karaoke = enabled; }
            }
            Item {
                width: parent.width; height: 156
                visible: !card.player
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    PentadIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: Qt.resolvedUrl("../../assets/icons/material/media/music-note-symbolic.svg")
                        pixelSize: 36
                        color: Theme.tokens.textMuted
                    }
                    PentadText { text: "No media playing"; color: Theme.tokens.textMuted; renderType: Text.NativeRendering }
                }
            }
        }
        Column {
            id: localPage
            width: parent.width
            visible: root.currentIndex === 1
            spacing: 12
            ContinuousSurface {
                objectName: "activity-localsend-drop-zone"
                width: parent.width
                height: 124
                extent: Metrics.radiusBlock
                fill: localDrop.containsDrag ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.accent, 0.12)) : Theme.tokens.surfaceRaised
                edge: Qt.alpha(Theme.tokens.accent, localDrop.containsDrag ? 0.8 : 0.2)
                Behavior on fill { ColorAnimation { duration: Theme.tokens.reducedMotion ? 0 : Motion.short } }
                DropArea {
                    id: localDrop
                    anchors.fill: parent
                    onEntered: drag => {
                        drag.accepted = !root.readOnly && !launcher.running && !!DropLogic.offerMime(drag.formats, true);
                        if (drag.accepted) drag.accept(Qt.CopyAction);
                    }
                    onDropped: drop => root.receiveLocalDrop(drop)
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 10
                    PentadIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: Qt.resolvedUrl("../../assets/icons/material/media/smartphone-symbolic.svg")
                        pixelSize: 28
                        color: Theme.tokens.accent
                    }
                    PentadText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: localDrop.containsDrag ? root.tr('Відпустіть для надсилання', 'Release to share') : root.tr('Перетягніть файли сюди', 'Drop files here')
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                    }
                }
            }
            PentadText {
                width: parent.width
                text: root.tr('Пристрій отримувача оберете у LocalSend.', 'Choose the receiving device in LocalSend.')
                role: 'caption'
                color: Theme.tokens.textMuted
                horizontalAlignment: Text.AlignHCenter
            }
            PentadButton {
                id: localLaunch
                objectName: "activity-open-localsend"
                width: parent.width
                controlHeight: Metrics.controlLarge
                text: root.tr('Відкрити LocalSend', 'Open LocalSend')
                requestedEnabled: !root.readOnly && !launcher.running
                onPressed: if (root.openLocalSend()) root.closeRequested()
                contentItem: PentadText {
                    text: localLaunch.text
                    font.weight: Font.DemiBold
                    color: localLaunch.enabled ? Theme.tokens.onAccent : Theme.tokens.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: ContinuousSurface {
                    extent: Metrics.radiusBlock
                    fill: localLaunch.enabled ? (localLaunch.down ? Qt.darker(Theme.tokens.accent, 1.15)
                        : localLaunch.hovered ? Qt.lighter(Theme.tokens.accent, 1.1) : Theme.tokens.accent) : Theme.tokens.surfaceRaised
                    edge: localLaunch.visualFocus ? Theme.tokens.text : 'transparent'
                }
            }
        }

        Item {
            id: shelfPage
            width: parent.width
            visible: root.currentIndex === 2
            implicitHeight: Math.min(440, files.implicitHeight)
            height: implicitHeight
            PentadScrollView {
                id: shelfScroller
                anchors.fill: parent
                contentWidth: availableWidth
                contentHeight: files.implicitHeight
                ShelfGrid { id: files; width: shelfScroller.availableWidth; shelf: root.shelf; readOnly: root.readOnly; language: root.services?.config?.documents?.interface?.language || 'en' }
            }
        }
        Column {
            id: cloudPage
            width: parent.width
            visible: root.currentIndex === 3
            ContinuousSurface {
                width: parent.width; height: 190; extent: Metrics.radiusBlock
                fill: Theme.tokens.surfaceRaised
                Column {
                    width: parent.width - 40
                    anchors.centerIn: parent
                    spacing: 12
                    PentadIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: Qt.resolvedUrl("../../assets/icons/material/media/cloud-symbolic.svg")
                        pixelSize: 40
                        color: Theme.tokens.textMuted
                    }
                    Column {
                        width: parent.width
                        PentadText {
                            width: parent.width
                            text: "Cloud folder unavailable"
                            solid: true
                            horizontalAlignment: Text.AlignHCenter
                            renderType: Text.NativeRendering
                        }
                        PentadText {
                            width: parent.width
                            text: root.tr('Синхронізовану теку не підключено.', 'No synchronized folder connected.')
                            role: 'caption'
                            solid: true
                            color: Theme.tokens.textMuted
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }
    PentadText {
        width: parent.width
        visible: !!root.message
        text: root.message
        role: "caption"
        color: Theme.tokens.error
        renderType: Text.NativeRendering
    }
}
