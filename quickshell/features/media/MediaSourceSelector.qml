import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import "../../theme"
import "../../logic/artwork.mjs" as Artwork

// A carousel of audio sources: the current one sits in a tonal capsule, its
// neighbours are blurred and fade towards the edges. Switching slides the whole
// strip by one slot, so a neighbour glides into the capsule instead of the
// labels blinking out and back in. Hovering a side brings that neighbour into
// focus instead of painting a box behind it.
Item {
    id: root

    required property var services
    required property var players
    required property string currentId
    required property string currentName
    signal cycleRequested(int offset)

    readonly property real arrowSize: 24
    readonly property real gap: 4
    readonly property real trackX: arrowSize + gap
    readonly property real trackWidth: Math.max(0, width - trackX * 2)
    readonly property real slotSpacing: trackWidth * 0.34
    readonly property real labelWidth: trackWidth * 0.4
    readonly property real sideWidth: trackWidth * 0.3
    readonly property real lensWidth: Math.min(labelWidth, currentMetrics.advanceWidth + 28)
    readonly property bool reducedMotion: Theme.tokens.reducedMotion
    readonly property int hoverDuration: reducedMotion ? 0 : 180
    readonly property int slideDuration: reducedMotion ? 0 : 320
    readonly property bool previousEngaged: switchable && (previousSide.hovered || previousArrow.hovered
        || previousSide.visualFocus || previousArrow.visualFocus)
    readonly property bool nextEngaged: switchable && (nextSide.hovered || nextArrow.hovered
        || nextSide.visualFocus || nextArrow.visualFocus)
    // Where the strip is drawn relative to its resting place, in slots.
    property real shift: 0
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

    function currentIndex() {
        if (!players) return -1;
        return players.findIndex(function(item) { return item.id === currentId; });
    }

    // Names come from one list so the capsule and its neighbours never disagree
    // for a frame while the selection and the name update separately.
    function nameAt(offset) {
        var index = currentIndex();
        if (offset === 0)
            return index >= 0 ? Artwork.formatPlayerName(players[index].name) : currentName;
        if (!players || players.length < 2) return "";
        if (index < 0) index = 0;
        var item = players[(index + offset % players.length + players.length) % players.length];
        return item ? Artwork.formatPlayerName(item.name) : "";
    }

    function engagedAt(offset) {
        return offset === -1 ? previousEngaged : offset === 1 ? nextEngaged : false;
    }

    function handleCurrentChanged() {
        if (!initialized || !players) {
            previousId = currentId;
            return;
        }
        var direction = 0;
        var oldIndex = players.findIndex(function(item) { return item.id === previousId; });
        var newIndex = currentIndex();
        if (requestedDirection) {
            direction = requestedDirection;
            requestedDirection = 0;
        } else if (oldIndex >= 0 && newIndex >= 0 && players.length > 1) {
            var forward = (newIndex - oldIndex + players.length) % players.length;
            direction = forward <= players.length / 2 ? 1 : -1;
        }
        previousId = currentId;
        slide.stop();
        if (reducedMotion || !direction) {
            shift = 0;
            return;
        }
        // Continue from wherever an interrupted slide left the strip.
        shift = Math.max(-2, Math.min(2, shift + direction));
        slide.restart();
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
    onReducedMotionChanged: if (initialized && reducedMotion) {
        slide.stop();
        shift = 0;
    }

    NumberAnimation {
        id: slide
        target: root
        property: "shift"
        to: 0
        duration: root.slideDuration
        easing.type: Easing.OutCubic
    }

    TextMetrics {
        id: currentMetrics
        text: root.nameAt(0)
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textCaption
        font.weight: Font.DemiBold
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

    // The hit area of a neighbour; what it shows is drawn by the strip below.
    component SourceSide: Button {
        id: side
        required property var host
        required property int offset
        enabled: host.switchable
        width: host.sideWidth
        height: host.height
        x: host.trackX + host.trackWidth / 2 + offset * host.slotSpacing - width / 2
        text: host.nameAt(offset)
        Accessible.name: host.tr("Перемкнути на ", "Switch to ") + text
        Accessible.role: Accessible.Button
        hoverEnabled: true
        padding: 0
        HoverHandler {
            enabled: side.enabled
            blocking: false
            cursorShape: Qt.PointingHandCursor
        }
        contentItem: Item {}
        background: Rectangle {
            radius: Metrics.radiusPill
            color: "transparent"
            border.width: side.visualFocus ? 2 : 0
            border.color: Theme.tokens.accent
        }
        onClicked: host.requestCycle(offset)
    }

    // One name on the strip. Its look follows its distance from the capsule:
    // sharp and solid in the middle, blurred and faint one slot out, gone at two.
    component SlideLabel: Item {
        id: label
        required property var host
        required property int offset
        readonly property real slot: offset + host.shift
        readonly property real distance: Math.abs(slot)
        readonly property real centre: Math.max(0, 1 - distance)
        property real focusLevel: host.engagedAt(offset) ? 1 : 0
        readonly property real restOpacity: distance <= 1 ? 0.36 + 0.64 * centre : 0.36 * Math.max(0, 2 - distance)
        Behavior on focusLevel { NumberAnimation { duration: label.host.hoverDuration; easing.type: Easing.OutCubic } }
        width: host.labelWidth
        height: host.height
        x: host.trackWidth / 2 + slot * host.slotSpacing - width / 2 - offset * 4 * focusLevel
        visible: distance < 2 && labelText.text !== ""

        Item {
            id: labelSource
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Text {
                id: labelText
                anchors.fill: parent
                leftPadding: 14
                rightPadding: 14
                text: label.host.nameAt(label.offset)
                color: Theme.tokens.text
                font.family: Theme.tokens.fontFamily
                renderType: Text.NativeRendering
                font.pixelSize: Metrics.textCaption
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        MultiEffect {
            anchors.fill: parent
            source: labelSource
            blurEnabled: true
            blurMax: 6
            blur: 0.5 * (1 - label.centre) * (1 - label.focusLevel)
            opacity: Math.max(label.restOpacity, 0.9 * label.focusLevel)
        }
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
        Behavior on x { NumberAnimation { duration: root.hoverDuration; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: root.slideDuration; easing.type: Easing.OutCubic } }
        Accessible.name: root.currentName
        Accessible.role: Accessible.StaticText
    }

    Item {
        id: strip
        x: root.trackX
        width: root.trackWidth
        height: root.height
        visible: false
        layer.enabled: true
        SlideLabel { host: root; offset: -2 }
        SlideLabel { host: root; offset: -1 }
        SlideLabel { host: root; offset: 0 }
        SlideLabel { host: root; offset: 1 }
        SlideLabel { host: root; offset: 2 }
    }
    // Opaque around the capsule, transparent towards both arrows.
    Rectangle {
        id: stripFade
        anchors.fill: strip
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.3; color: "white" }
            GradientStop { position: 0.7; color: "white" }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    MultiEffect {
        anchors.fill: strip
        source: strip
        maskEnabled: true
        maskSource: stripFade
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    SourceSide {
        id: previousSide
        host: root
        offset: -1
    }

    SourceSide {
        id: nextSide
        host: root
        offset: 1
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
