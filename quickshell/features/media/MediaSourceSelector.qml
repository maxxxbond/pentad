import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import "../../theme"
import "../../logic/artwork.mjs" as Artwork

// A carousel of audio sources: the current one sits in a tonal capsule, its
// neighbours lean against it and dissolve towards the edges. Hovering a side
// brings that neighbour into focus instead of painting a box behind it.
Item {
    id: root

    required property var services
    required property var players
    required property string currentId
    required property string currentName
    signal cycleRequested(int offset)

    readonly property real arrowSize: 24
    readonly property real gap: 4
    readonly property real trackWidth: Math.max(0, width - arrowSize * 2 - gap * 2)
    readonly property real lensWidth: Math.min(trackWidth * 0.46, currentLabel.implicitWidth + 28)
    readonly property real sideWidth: Math.max(0, (trackWidth - lensWidth) / 2 - gap)
    readonly property bool reducedMotion: Theme.tokens.reducedMotion
    readonly property int hoverDuration: reducedMotion ? 0 : 180
    readonly property bool previousEngaged: switchable && (previousSide.hovered || previousArrow.hovered
        || previousSide.visualFocus || previousArrow.visualFocus)
    readonly property bool nextEngaged: switchable && (nextSide.hovered || nextArrow.hovered
        || nextSide.visualFocus || nextArrow.visualFocus)
    property real slideX: 0
    property real labelOpacity: 1
    property real sideSlideX: 0
    property real sideOpacity: 1
    property int slideDirection: 1
    property string previousId: currentId
    property int requestedDirection: 0
    property bool initialized: false
    // The current source stays visible with a single player; switching affordances need two.
    readonly property bool switchable: !!players && players.length > 1

    width: parent ? parent.width : 420
    height: 28
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

    function settle() {
        labelEnter.stop();
        slideX = 0;
        labelOpacity = 1;
        sideSlideX = 0;
        sideOpacity = 1;
    }

    function handleCurrentChanged() {
        if (!initialized || !players) {
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
            settle();
            return;
        }
        labelEnter.stop();
        slideX = slideDirection * 18;
        labelOpacity = 0;
        sideSlideX = slideDirection * 12;
        sideOpacity = 0;
        labelEnter.restart();
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
    onReducedMotionChanged: if (initialized && reducedMotion) settle()

    ParallelAnimation {
        id: labelEnter
        NumberAnimation { target: root; property: "slideX"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "labelOpacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "sideSlideX"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "sideOpacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    }

    component SourceArrow: MediaButton {
        id: arrow
        required property var host
        required property bool engaged
        enabled: host.switchable
        opacity: host.switchable ? 1 : 0
        anchors.verticalCenter: parent.verticalCenter
        diameter: host.arrowSize
        glyphPixelSize: 18
        foreground: engaged ? Theme.tokens.text : Theme.tokens.textMuted
        Behavior on foreground { ColorAnimation { duration: arrow.host.hoverDuration } }
        background: Rectangle {
            radius: width / 2
            color: arrow.down ? Qt.alpha(Theme.tokens.text, 0.14)
                : arrow.hovered ? Qt.alpha(Theme.tokens.text, 0.07) : "transparent"
            border.width: arrow.visualFocus ? 2 : 0
            border.color: Theme.tokens.accent
            Behavior on color { ColorAnimation { duration: arrow.host.hoverDuration } }
        }
    }

    // A neighbouring source: blurred and fading outwards at rest, sharp and
    // pulled a few pixels towards the capsule while engaged.
    component SourceSide: Button {
        id: side
        required property var host
        required property int offset
        required property bool engaged
        property real focusLevel: engaged ? 1 : 0
        enabled: host.switchable
        opacity: host.switchable ? 1 : 0
        width: host.sideWidth
        height: host.height
        text: host.adjacentName(offset)
        Accessible.name: host.tr("Перемкнути на ", "Switch to ") + text
        Accessible.role: Accessible.Button
        hoverEnabled: true
        padding: 0
        HoverHandler {
            enabled: side.enabled
            blocking: false
            cursorShape: Qt.PointingHandCursor
        }
        Behavior on focusLevel { NumberAnimation { duration: side.host.hoverDuration; easing.type: Easing.OutCubic } }
        contentItem: Item {
            Item {
                id: sideLabel
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Text {
                    anchors.fill: parent
                    text: side.text
                    color: Theme.tokens.text
                    font.family: Theme.tokens.fontFamily
                    renderType: Text.NativeRendering
                    font.pixelSize: Metrics.textCaption
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    leftPadding: 4
                    rightPadding: 4
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            // Opaque next to the capsule, transparent at the outer edge.
            Rectangle {
                id: sideFade
                anchors.fill: parent
                visible: false
                layer.enabled: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: side.offset < 0 ? "transparent" : "white" }
                    GradientStop { position: side.offset < 0 ? 0.35 : 0.65; color: "white" }
                    GradientStop { position: 1; color: side.offset < 0 ? "white" : "transparent" }
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: sideLabel
                blurEnabled: true
                blurMax: 6
                blur: 0.45 * (1 - side.focusLevel)
                maskEnabled: true
                maskSource: sideFade
                maskThresholdMin: 0.5 - 0.5 * side.focusLevel
                maskSpreadAtMin: 1
                transform: Translate {
                    x: side.host.sideSlideX - side.offset * 4 * side.focusLevel
                }
                scale: side.down ? 0.96 : 1
                opacity: side.host.sideOpacity * (0.34 + 0.56 * side.focusLevel)
                Behavior on scale { NumberAnimation { duration: side.host.hoverDuration; easing.type: Easing.OutCubic } }
            }
        }
        background: Rectangle {
            radius: Metrics.radiusPill
            color: "transparent"
            border.width: side.visualFocus ? 2 : 0
            border.color: Theme.tokens.accent
        }
        onClicked: host.requestCycle(offset)
    }

    SourceArrow {
        id: previousArrow
        host: root
        x: 0
        engaged: root.previousEngaged
        text: root.tr("Попереднє джерело", "Previous audio source")
        glyph: "arrow_back"
        onPressed: root.requestCycle(-1)
    }

    SourceSide {
        id: previousSide
        host: root
        x: previousArrow.width + root.gap
        offset: -1
        engaged: root.previousEngaged
    }

    Rectangle {
        id: lens
        objectName: "media-source-current"
        width: root.lensWidth
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        // The capsule leans a little towards the side the pointer is about to pick.
        x: (root.width - width) / 2 + ((root.nextEngaged ? 1 : 0) - (root.previousEngaged ? 1 : 0)) * 2
        radius: Metrics.radiusPill
        color: Qt.alpha(Theme.tokens.text, 0.07)
        clip: true
        Behavior on x { NumberAnimation { duration: root.hoverDuration; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic } }

        Text {
            id: currentLabel
            text: root.currentName
            anchors.fill: parent
            leftPadding: 14
            rightPadding: 14
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

    SourceSide {
        id: nextSide
        host: root
        x: root.width - nextArrow.width - root.gap - width
        offset: 1
        engaged: root.nextEngaged
    }

    SourceArrow {
        id: nextArrow
        host: root
        x: root.width - width
        engaged: root.nextEngaged
        text: root.tr("Наступне джерело", "Next audio source")
        glyph: "arrow_forward"
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
