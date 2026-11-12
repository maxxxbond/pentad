pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// One compact level row of AudioControls: the volume/microphone slider with the mute halo,
// the device chevron and the right-click / menu-key appearance menu. `owner` is the
// AudioControls root (request state and actions live there), `menu` its appearance popover.
Row {
    id: row
    required property var owner
    required property var menu
    required property string kind
    readonly property bool isOutput: kind === "output"
    // The horizontal row is a scrubber; the upright capsule of the vertical layout stays a PentadSlider.
    readonly property var slider: owner.vertical ? levelSlider : levelScrubber
    readonly property bool endOnFill: !!slider && slider.endOnFill === true
    readonly property var device: owner.deviceFor(kind)
    readonly property bool muted: !!device && device.muted
    readonly property bool joined: menu.opened && menu.anchorItem === sliderHost
    readonly property url iconPath: isOutput
        ? Qt.resolvedUrl("../../assets/icons/material/" + (muted ? "volume-off-symbolic.svg" : "volume-up-symbolic.svg"))
        : Qt.resolvedUrl("../../assets/icons/material/media/" + (muted ? "mic-off-symbolic.svg" : "mic-symbolic.svg"))
    readonly property string levelLabel: owner.layoutManaged && owner.error ? owner.error
        : isOutput
            ? (muted ? owner.services.text("Без звуку", "Muted") : owner.services.text("Гучність", "Volume"))
            : (muted ? owner.services.text("Мікрофон вимкнено", "Microphone muted") : owner.services.text("Мікрофон", "Microphone"))
    readonly property real levelValue: owner.volumeRequest(kind) ? owner.desiredVolume(kind) : (device ? device.volume : 0)
    readonly property string levelText: device ? `${Math.round(levelValue * 100)}%` : "—"
    readonly property string levelName: isOutput ? owner.services.text("Гучність виводу", "Output volume")
        : owner.services.text("Гучність мікрофона", "Microphone level")
    readonly property bool levelEnabled: owner.services.audio.active && !owner.services.audio.safeMode && !!device
    // The device chevron sits in the capsule's own end slot, past a separator; the range stops before it.
    readonly property real trailingSlot: !owner.vertical || owner.verticalPicker ? 44 : 0
    spacing: isOutput ? 8 : 0

    Item {
        id: sliderHost
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                row.owner.showContext(row.kind, sliderHost);
                event.accepted = true;
            }
        }
        width: row.width
        height: row.owner.vertical ? row.owner.levelHeight : 48

        PentadSlider {
            id: levelSlider
            visible: row.owner.vertical
            joined: row.joined
            width: sliderHost.width
            height: sliderHost.height
            orientation: Qt.Vertical
            thick: true
            referenceStyle: true
            trailingSlot: row.trailingSlot
            muted: row.muted
            iconSource: row.iconPath
            from: 0
            to: 1
            stepSize: 0.01
            wheelStepSize: 0.02
            label: row.levelLabel
            valueKnown: !!row.device
            confirmedValue: row.device ? row.device.volume : NaN
            valueText: row.levelText
            accessibleName: row.levelName
            enabled: row.levelEnabled
            onMoved: row.owner.requestVolume(row.kind, value)
            Binding {
                target: levelSlider
                property: "value"
                value: row.levelValue
            }
        }
        // A press only grabs the bar and a click sets the value under it, as before, so touching the
        // bar never jumps the volume.
        PentadScrubber {
            id: levelScrubber
            visible: !row.owner.vertical
            joined: row.joined
            relativeDrag: true
            width: sliderHost.width
            height: sliderHost.height
            trailingSlot: row.trailingSlot
            muted: row.muted
            iconSource: row.iconPath
            from: 0
            to: 1
            stepSize: 0.01
            wheelStepSize: 0.02
            label: row.levelLabel
            valueKnown: !!row.device
            confirmedValue: row.device ? row.device.volume : NaN
            valueText: row.levelText
            accessibleName: row.levelName
            enabled: row.levelEnabled
            onMoved: function(next) { row.owner.requestVolume(row.kind, next) }
            Binding {
                target: levelScrubber
                property: "value"
                value: row.levelValue
            }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onPressed: row.owner.showContext(row.kind, sliderHost)
        }
        Button {
            id: muteButton
            objectName: "control-center-toggle-audio-" + row.kind
            x: row.owner.vertical ? (sliderHost.width - width) / 2 : 0
            y: row.owner.vertical ? sliderHost.height - height : 0
            width: 44
            height: 48
            enabled: row.owner.services.audio.active && !row.owner.services.audio.safeMode && !!row.owner.deviceFor(row.kind)
                && !(row.isOutput ? row.owner.outputMuteRequest : row.owner.inputMuteRequest)
            Accessible.name: row.isOutput
                ? (row.muted ? row.owner.services.text("Увімкнути звук", "Unmute output")
                    : row.owner.services.text("Вимкнути звук", "Mute output"))
                : (row.muted ? row.owner.services.text("Увімкнути мікрофон", "Unmute microphone")
                    : row.owner.services.text("Вимкнути мікрофон", "Mute microphone"))
            onPressed: row.owner.requestMute(row.kind)
            // A round halo around the icon says it is a button of its own, on the fill and the track alike.
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    radius: width / 2
                    color: Qt.alpha(Theme.tokens.text, muteButton.pressed ? 0.22 : 0.14)
                    opacity: muteButton.enabled && (muteButton.hovered || muteButton.pressed) ? 1 : 0
                    border.width: muteButton.activeFocus ? 2 : 0
                    border.color: Theme.tokens.accent
                    Behavior on opacity { NumberAnimation { duration: Motion.state } }
                }
            }
            contentItem: Item { }
            HoverHandler { cursorShape: muteButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        PentadButton {
            id: picker
            objectName: "control-center-details-audio-" + row.kind
            visible: !row.owner.vertical || row.owner.verticalPicker
            x: row.owner.vertical ? 0 : sliderHost.width - width
            width: row.owner.vertical ? sliderHost.width : 44
            controlHeight: row.owner.vertical ? 44 : 48
            text: ""
            chevron: "right"
            iconSize: Metrics.chevronIcon
            ink: row.endOnFill ? Theme.tokens.onAccent : Theme.tokens.text
            accessibleName: row.isOutput ? row.owner.services.text("Обрати аудіовихід", "Choose audio output")
                : row.owner.services.text("Вибір мікрофона", "Choose microphone")
            requestedEnabled: row.owner.services.audio.active
            // The same round halo as the mute button: part of the capsule, not a tile of its own.
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    radius: width / 2
                    color: Qt.alpha(Theme.tokens.text, picker.down ? 0.22 : 0.14)
                    opacity: picker.enabled && (picker.down || picker.hovered) ? 1 : 0
                    border.width: picker.visualFocus ? 2 : 0
                    border.color: Theme.tokens.accent
                    Behavior on opacity { NumberAnimation { duration: Motion.state } }
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            onPressed: row.owner.detailsRequested("audio-" + row.kind)
        }
    }
}
