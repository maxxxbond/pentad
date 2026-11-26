pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/wallpaper.mjs" as Rules

// The wallpaper folder as a grid of thumbnails. A click applies the image to the chosen
// target (every screen or one); the applied image sits inset on a tonal frame with a check.
// Thumbnails decode at card size in the background (JPEG decodes scaled, so 6K photos stay cheap).
FocusScope {
    id: root
    property var images: []
    property string current: ""
    property var screens: []
    property string target: ""
    property string folderLabel: ""
    property string allScreensLabel: "All screens"
    property string randomLabel: "Random"
    property string chooseLabel: "Choose file…"
    property string emptyTitle: "No images in this folder"
    signal chosen(string path)
    signal randomRequested()
    signal fileRequested()
    signal targetSelected(string output)

    // An applied image from outside the folder still shows, first.
    readonly property var entries: root.current && (images || []).indexOf(root.current) < 0
        ? [root.current].concat(images || []) : (images || [])
    readonly property int count: entries.length
    readonly property real gap: 8
    readonly property int columns: Math.max(2, Math.floor((width + gap) / (152 + gap)))
    readonly property real cardWidth: Math.max(1, Math.floor((width - gap * (columns - 1)) / columns))
    readonly property real cardHeight: Math.round(cardWidth * 10 / 16)
    readonly property int tabIndex: Math.max(0, entries.indexOf(current))
    readonly property alias repeater: cards
    implicitWidth: 480
    implicitHeight: toolbar.height + Metrics.space3 + (count > 0 ? grid.height : empty.height)

    function fileUrl(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/"); }
    function focusCard(index) {
        const card = cards.itemAt(Math.max(0, Math.min(count - 1, index)));
        if (card) card.forceActiveFocus(Qt.TabFocusReason);
    }

    // Outside a card the toolbar keeps the two lines of the settings grid: the screen picker starts
    // on the leading line and the actions end on the trailing one, at the height of a row's control.
    Item {
        id: toolbar
        x: Metrics.settingsRowInset
        width: parent.width - 2 * Metrics.settingsRowInset
        height: Metrics.controlSmall
        PentadSegmented {
            id: targets
            visible: root.screens.length > 1
            anchors.left: parent.left
            implicitHeight: Metrics.controlSmall
            segmentMinimumWidth: Metrics.space6 * 2
            width: Math.min(implicitWidth, parent.width - actions.width - Metrics.space3)
            options: [{ value: "", label: root.allScreensLabel }].concat(root.screens)
            value: root.target
            accessibleName: root.allScreensLabel
            enabled: root.enabled
            onActivated: function(value) { root.targetSelected(String(value)); }
        }
        Row {
            id: actions
            anchors.right: parent.right
            spacing: Metrics.space2
            PentadButton {
                objectName: "wallpaperRandom"
                controlHeight: Metrics.controlSmall
                text: root.randomLabel
                accessibleName: root.randomLabel
                requestedEnabled: root.enabled && (root.images || []).length > 1
                onClicked: root.randomRequested()
            }
            PentadButton {
                objectName: "wallpaperChoose"
                controlHeight: Metrics.controlSmall
                text: root.chooseLabel
                accessibleName: root.chooseLabel
                requestedEnabled: root.enabled
                onClicked: root.fileRequested()
            }
        }
    }

    Grid {
        id: grid
        y: toolbar.height + Metrics.space3
        width: parent.width
        visible: root.count > 0
        columns: root.columns
        spacing: root.gap
        Accessible.role: Accessible.List
        Repeater {
            id: cards
            model: root.entries
            delegate: Control {
                id: card
                required property int index
                required property string modelData
                readonly property bool selected: modelData === root.current
                readonly property string name: Rules.displayName(modelData)
                objectName: "wallpaperCard_" + index
                width: root.cardWidth
                height: root.cardHeight
                activeFocusOnTab: index === root.tabIndex || activeFocus
                Accessible.role: Accessible.RadioButton
                Accessible.name: name
                Accessible.checkable: true
                Accessible.checked: selected
                Accessible.onPressAction: root.chosen(modelData)
                Keys.onPressed: function(event) {
                    const step = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1
                        : event.key === Qt.Key_Up ? -root.columns : event.key === Qt.Key_Down ? root.columns : 0;
                    if (step !== 0) { root.focusCard(index + step); event.accepted = true; return; }
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.chosen(modelData);
                        event.accepted = true;
                    }
                }

                // The applied image sits inset on a tonal frame; the others fill the card.
                ContinuousSurface {
                    anchors.fill: parent
                    extent: Metrics.radiusCard
                    fill: card.selected ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                    edge: card.visualFocus ? Theme.tokens.accent : "transparent"
                    clipContent: false
                }
                ContinuousSurface {
                    id: frame
                    property real inset: card.selected ? 4 : 0
                    x: inset
                    y: inset
                    width: card.width - 2 * inset
                    height: card.height - 2 * inset
                    extent: Metrics.radiusCard - inset
                    fill: Theme.tokens.surfaceRaised
                    Behavior on inset { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
                    Image {
                        id: thumb
                        objectName: "wallpaperThumb"
                        anchors.fill: parent
                        source: root.fileUrl(card.modelData)
                        sourceSize: Qt.size(320, 200)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        scale: cardHover.hovered && !card.selected ? 1.04 : 1
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on scale { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
                        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
                    }
                    PentadIcon {
                        anchors.centerIn: parent
                        visible: thumb.status === Image.Error
                        source: Qt.resolvedUrl("../../assets/icons/tabler/photo-symbolic.svg")
                        pixelSize: Metrics.statusIcon
                        color: Theme.tokens.textMuted
                        Accessible.ignored: true
                    }
                    // The name appears on hover only, over a scrim that keeps it readable on any image.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 32
                        opacity: cardHover.hovered || card.visualFocus ? 1 : 0
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.alpha("#000000", 0.55) }
                        }
                        Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
                        PentadText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 8
                            text: card.name
                            textFormat: Text.PlainText
                            role: "caption"
                            solid: true
                            color: "#FFFFFF"
                            elide: Text.ElideMiddle
                            wrapMode: Text.NoWrap
                        }
                    }
                }
                Rectangle {
                    objectName: "wallpaperCheck"
                    visible: card.selected
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 10
                    width: 22
                    height: 22
                    radius: width / 2
                    color: Theme.tokens.surface
                    PentadIcon {
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl("../../assets/icons/material/controls/check-symbolic.svg")
                        pixelSize: 16
                        color: Theme.tokens.accent
                        Accessible.ignored: true
                    }
                }
                HoverHandler { id: cardHover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: root.enabled
                    onTapped: { card.forceActiveFocus(); root.chosen(card.modelData); }
                }
            }
        }
    }

    // Empty folder: say which folder, offer the file chooser.
    Rectangle {
        id: empty
        objectName: "wallpaperEmpty"
        y: toolbar.height + Metrics.space3
        visible: root.count === 0
        width: parent.width
        height: 136
        radius: Metrics.radiusCard
        color: Qt.alpha(Theme.tokens.text, 0.03)
        Column {
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 4
            PentadIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: Qt.resolvedUrl("../../assets/icons/tabler/photo-symbolic.svg")
                pixelSize: Metrics.menuIcon
                color: Theme.tokens.textMuted
                Accessible.ignored: true
            }
            Item { width: 1; height: 4 }
            PentadText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.emptyTitle
                textFormat: Text.PlainText
                font.weight: Font.Medium
                solid: true
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
            PentadText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.folderLabel
                textFormat: Text.PlainText
                role: "caption"
                color: Theme.tokens.textMuted
                solid: true
                wrapMode: Text.NoWrap
                elide: Text.ElideMiddle
            }
        }
    }
}
