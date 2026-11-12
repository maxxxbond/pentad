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
    // The full shell services for the Stash tab: the activity facade carries no Stash, text or tool workspace.
    required property var stashServices
    property string outputId: "default"
    property bool readOnly: true
    property int currentIndex: 0
    property string message: ""
    property string localSendExecutable: 'localsend'
    property int dropTabIndex: -1
    // The bar holds a file over the activity side: the drop zones are awake before the pointer arrives.
    property bool dragAwake: false
    // True for a moment after files were handed to LocalSend: its drop zone shows the check.
    property bool localHandedOff: false
    signal closeRequested()
    readonly property var localSendCommand: launcher.command
    readonly property alias musicCard: card
    // The bar's drag ingress hands drops over the activity side to this.
    readonly property alias shelfGrid: quick
    readonly property alias tabIndicator: tabs.indicator
    readonly property var labels: [tr("Медіа", "Media"), "LocalSend", tr("Сховок", "Stash"), tr("Хмара", "Cloud")]
    readonly property var currentPage: [mediaPage, localPage, quick, cloudPage][currentIndex]
    readonly property bool dragHovered: quick.dragHovered || localDrop.containsDrag || dropTabIndex >= 0
    readonly property bool dragOutActive: quick.exportInProgress
    width: 420
    spacing: 12

    // The activity facade has no text(); the full services the Stash tab receives carry the shell language.
    function tr(uk, en) { return stashServices.text(uk, en); }

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
        localHandedOff = true;
        localHandoffShown.restart();
    }
    Timer {
        id: localHandoffShown
        interval: 2600
        onTriggered: root.localHandedOff = false
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
        width: parent.width
        height: tabs.height
        PentadSegmented {
            id: tabs
            objectName: "activity-tabs"
            width: parent.width
            fill: Theme.tokens.surfaceRaised
            tabList: true
            activateOnPress: true
            segmentObjectName: "activity-tab-"
            accessibleName: root.tr("Активності", "Activities")
            options: root.labels.map(function(label, i) { return { value: i, label: label }; })
            value: root.currentIndex
            onActivated: function(v) { root.selectTab(v); }
        }
        Row {
            x: tabs.x + tabs.inset
            y: tabs.y
            height: tabs.height
            layoutDirection: tabs.rtl ? Qt.RightToLeft : Qt.LeftToRight
            Repeater {
                model: root.labels.length
                delegate: DropArea {
                    id: tabDrop
                    required property int index
                    width: tabs.segmentWidth
                    height: tabs.height
                    onEntered: drag => {
                        drag.accepted = !root.readOnly && [1, 2].indexOf(tabDrop.index) >= 0
                            && (tabDrop.index === 2 ? DropLogic.supportsShelfOffer(drag.formats)
                                : !!DropLogic.offerMime(drag.formats, true));
                        if (!drag.accepted) return;
                        drag.accept(Qt.CopyAction);
                        root.dropTabIndex = tabDrop.index;
                        root.selectTab(tabDrop.index);
                    }
                    onExited: if (root.dropTabIndex === tabDrop.index) root.dropTabIndex = -1
                    onDropped: drop => {
                        root.dropTabIndex = -1;
                        if (tabDrop.index === 1) root.receiveLocalDrop(drop);
                        else quick.receiveDrop(drop);
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
            PentadFileDrop {
                objectName: "activity-localsend-drop-zone"
                width: parent.width
                height: 200
                awake: root.dragAwake || root.dragHovered
                active: localDrop.containsDrag
                phase: root.localHandedOff ? "done" : "idle"
                iconSource: Qt.resolvedUrl("../../assets/icons/material/media/smartphone-symbolic.svg")
                title: root.localHandedOff ? root.tr('Передано в LocalSend', 'Handed to LocalSend')
                    : localDrop.containsDrag ? root.tr('Відпустіть для надсилання', 'Release to share')
                    : root.tr('Перетягніть файли сюди', 'Drop files here')
                hint: root.localHandedOff ? root.tr('Оберіть пристрій у LocalSend', 'Pick the device in LocalSend')
                    : root.tr('Пристрій отримувача оберете в LocalSend', 'You pick the receiving device in LocalSend')
                DropArea {
                    id: localDrop
                    anchors.fill: parent
                    onEntered: drag => {
                        drag.accepted = !root.readOnly && !launcher.running && !!DropLogic.offerMime(drag.formats, true);
                        if (drag.accepted) drag.accept(Qt.CopyAction);
                    }
                    onDropped: drop => root.receiveLocalDrop(drop)
                }
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

        StashQuick {
            id: quick
            objectName: "stash-quick"
            width: parent.width
            visible: root.currentIndex === 2
            services: root.stashServices
            readOnly: root.readOnly
            dragAwake: root.dragAwake || root.dragHovered
            onCloseRequested: root.closeRequested()
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
