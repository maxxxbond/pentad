import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import "../../theme"
import "../../logic/artwork.mjs" as Artwork

Row {
    id: root

    required property var services
    required property var players
    required property string currentId
    required property string currentName
    signal cycleRequested(int offset)

    readonly property real arrowWidth: Math.min(28, Math.max(20, width * 0.12))
    readonly property real gap: Math.min(4, width * 0.015)
    readonly property real sourceWidth: Math.max(0, width - arrowWidth * 2 - gap * 4)
    readonly property bool reducedMotion: Theme.tokens.reducedMotion
    property real slideX: 0
    property real labelOpacity: 1
    property real previousSlideX: 0
    property real previousOpacity: 1
    property real nextSlideX: 0
    property real nextOpacity: 1
    property int slideDirection: 1
    property string previousId: currentId
    property int requestedDirection: 0
    property bool initialized: false
    // The current source stays visible with a single player; switching affordances need two.
    readonly property bool switchable: !!players && players.length > 1

    width: parent ? parent.width : 420
    height: 28
    spacing: gap
    objectName: "media-source-selector"
    visible: !!players && players.length > 0
    clip: true

    function tr(uk, en) {
        return typeof services.text === "function" ? services.text(uk, en) : en;
    }

    function adjacentName(offset) {
        if (!players || players.length < 2) return "";
        var index = players.findIndex(function(item) { return item.id === currentId; });
        if (index < 0) index = 0;
        var item = players[(index + offset + players.length) % players.length];
        return item ? Artwork.formatPlayerName(item.name) : "";
    }

    function handleCurrentChanged() {
        if (!initialized) {
            previousId = currentId;
            return;
        }
        labelEnter.stop();
        if (!players) {
            previousId = currentId;
            return;
        }
        var oldIndex = players.findIndex(function(item) { return item.id === previousId; });
        var newIndex = players.findIndex(function(item) { return item.id === currentId; });
        if (requestedDirection) {
            slideDirection = requestedDirection;
            requestedDirection = 0;
        } else if (oldIndex >= 0 && newIndex >= 0 && players.length > 1) {
            var forward = (newIndex - oldIndex + players.length) % players.length;
            slideDirection = forward <= players.length / 2 ? 1 : -1;
        }
        previousId = currentId;
        if (reducedMotion) {
            slideX = 0;
            labelOpacity = 1;
            previousSlideX = 0;
            previousOpacity = 1;
            nextSlideX = 0;
            nextOpacity = 1;
        } else {
            slideX = slideDirection * 18;
            labelOpacity = 0;
            previousSlideX = slideDirection * 12;
            previousOpacity = 0;
            nextSlideX = slideDirection * 12;
            nextOpacity = 0;
            labelEnter.restart();
        }
    }

    function requestCycle(offset) {
        requestedDirection = offset < 0 ? -1 : 1;
        cycleRequested(requestedDirection);
    }

    onCurrentIdChanged: handleCurrentChanged()
    Component.onCompleted: {
        previousId = currentId;
        initialized = true;
    }
    onPlayersChanged: {
        if (players && players.length && !players.some(function(item) { return item.id === currentId; }))
            previousId = currentId;
    }

    ParallelAnimation {
        id: labelEnter
        NumberAnimation { target: root; property: "slideX"; to: 0; duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "labelOpacity"; to: 1; duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "previousSlideX"; to: 0; duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "previousOpacity"; to: 1; duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "nextSlideX"; to: 0; duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "nextOpacity"; to: 1; duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic }
    }

    onReducedMotionChanged: {
        if (!initialized || !reducedMotion) return;
        labelEnter.stop();
        slideX = 0;
        labelOpacity = 1;
        previousSlideX = 0;
        previousOpacity = 1;
        nextSlideX = 0;
        nextOpacity = 1;
    }

    MediaButton {
        id: previousArrow
        enabled: root.switchable
        opacity: root.switchable ? 1 : 0
        text: root.tr("Попереднє джерело", "Previous audio source")
        glyph: "arrow_back"
        diameter: root.arrowWidth
        cornerRadius: 6
        glyphPixelSize: 22
        Accessible.name: text
        background: Rectangle {
            radius: 6
            color: previousArrow.activeFocus ? Qt.alpha(Theme.tokens.accent, 0.16)
                : previousArrow.down ? Theme.tokens.surfaceOverlay
                : previousArrow.hovered ? Qt.alpha(Theme.tokens.text, 0.08) : "transparent"
            border.width: previousArrow.activeFocus ? 1 : 0
            border.color: Theme.tokens.accent
        }
        onPressed: root.requestCycle(-1)
    }

    Button {
        id: previousButton
        enabled: root.switchable
        opacity: root.switchable ? 1 : 0
        width: root.sourceWidth * 0.25
        height: root.height
        text: root.adjacentName(-1)
        Accessible.name: root.tr("Перемкнути на ", "Switch to ") + text
        Accessible.role: Accessible.Button
        hoverEnabled: true
        padding: 2
        contentItem: Item {
            clip: true
            Item {
                id: previousSourceLabel
                anchors.fill: parent
                visible: false
                Text {
                    text: previousButton.text
                    anchors.fill: parent
                    color: Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    renderType: Text.NativeRendering
                    font.pixelSize: Metrics.textCaption
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: previousSourceLabel
                blurEnabled: true
                blur: 0.3
                blurMax: 4
                transform: Translate { x: root.previousSlideX }
                opacity: root.previousOpacity * (previousButton.hovered || previousButton.activeFocus ? 0.88 : 0.48)
            }
        }
        background: Rectangle {
            radius: 6
            color: previousButton.activeFocus ? Qt.alpha(Theme.tokens.accent, 0.14)
                : previousButton.down ? Theme.tokens.surfaceOverlay
                : previousButton.hovered ? Qt.alpha(Theme.tokens.text, 0.07) : "transparent"
            border.width: previousButton.activeFocus ? 1 : 0
            border.color: Theme.tokens.accent
        }
        onClicked: root.requestCycle(-1)
    }

    Item {
        width: root.sourceWidth * 0.5
        height: root.height
        clip: true

        Text {
            text: root.currentName
            anchors.fill: parent
            transform: Translate { x: root.slideX }
            opacity: root.labelOpacity
            color: Theme.tokens.text
            font.family: Theme.tokens.fontFamily
            renderType: Text.NativeRendering
            font.pixelSize: Metrics.textCaption
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            Accessible.name: root.currentName
            Accessible.role: Accessible.StaticText
        }
    }

    Button {
        id: nextButton
        enabled: root.switchable
        opacity: root.switchable ? 1 : 0
        width: root.sourceWidth * 0.25
        height: root.height
        text: root.adjacentName(1)
        Accessible.name: root.tr("Перемкнути на ", "Switch to ") + text
        Accessible.role: Accessible.Button
        hoverEnabled: true
        padding: 2
        contentItem: Item {
            clip: true
            Item {
                id: nextSourceLabel
                anchors.fill: parent
                visible: false
                Text {
                    text: nextButton.text
                    anchors.fill: parent
                    color: Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    renderType: Text.NativeRendering
                    font.pixelSize: Metrics.textCaption
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: nextSourceLabel
                blurEnabled: true
                blur: 0.3
                blurMax: 4
                transform: Translate { x: root.nextSlideX }
                opacity: root.nextOpacity * (nextButton.hovered || nextButton.activeFocus ? 0.88 : 0.48)
            }
        }
        background: Rectangle {
            radius: 6
            color: nextButton.activeFocus ? Qt.alpha(Theme.tokens.accent, 0.14)
                : nextButton.down ? Theme.tokens.surfaceOverlay
                : nextButton.hovered ? Qt.alpha(Theme.tokens.text, 0.07) : "transparent"
            border.width: nextButton.activeFocus ? 1 : 0
            border.color: Theme.tokens.accent
        }
        onClicked: root.requestCycle(1)
    }

    MediaButton {
        id: nextArrow
        enabled: root.switchable
        opacity: root.switchable ? 1 : 0
        text: root.tr("Наступне джерело", "Next audio source")
        glyph: "arrow_forward"
        diameter: root.arrowWidth
        cornerRadius: 6
        glyphPixelSize: 22
        Accessible.name: text
        background: Rectangle {
            radius: 6
            color: nextArrow.activeFocus ? Qt.alpha(Theme.tokens.accent, 0.16)
                : nextArrow.down ? Theme.tokens.surfaceOverlay
                : nextArrow.hovered ? Qt.alpha(Theme.tokens.text, 0.08) : "transparent"
            border.width: nextArrow.activeFocus ? 1 : 0
            border.color: Theme.tokens.accent
        }
        onPressed: root.requestCycle(1)
    }

    WheelHandler {
        target: null
        property real pending: 0
        enabled: root.switchable
        onWheel: function(event) {
            var pixels = event.pixelDelta.y || event.pixelDelta.x;
            var delta = pixels || event.angleDelta.y || event.angleDelta.x;
            if (!delta) return;
            pending += delta;
            var threshold = pixels ? 40 : 120;
            if (Math.abs(pending) >= threshold) {
                root.requestCycle(pending < 0 ? 1 : -1);
                pending = 0;
            }
            event.accepted = true;
        }
    }
}
