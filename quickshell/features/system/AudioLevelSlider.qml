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
    readonly property alias slider: levelSlider
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
            joined: row.menu.opened && row.menu.anchorItem === sliderHost
            width: sliderHost.width
            height: sliderHost.height
            orientation: row.owner.vertical ? Qt.Vertical : Qt.Horizontal
            thick: true
            referenceStyle: true
            trailingInset: !row.owner.vertical ? 44 : row.owner.verticalPicker ? 40 : 0
            muted: !!row.owner.deviceFor(row.kind) && row.owner.deviceFor(row.kind).muted
            iconSource: row.isOutput
                ? Qt.resolvedUrl("../../assets/icons/material/" + (muted ? "volume-off-symbolic.svg" : "volume-up-symbolic.svg"))
                : Qt.resolvedUrl("../../assets/icons/material/media/" + (muted ? "mic-off-symbolic.svg" : "mic-symbolic.svg"))
            from: 0
            to: 1
            stepSize: 0.01
            wheelStepSize: 0.02
            label: row.owner.layoutManaged && row.owner.error ? row.owner.error
                : row.isOutput
                    ? (muted ? row.owner.services.text("Без звуку", "Muted") : row.owner.services.text("Гучність", "Volume"))
                    : (muted ? row.owner.services.text("Мікрофон вимкнено", "Microphone muted") : row.owner.services.text("Мікрофон", "Microphone"))
            valueKnown: !!row.owner.deviceFor(row.kind)
            confirmedValue: row.owner.deviceFor(row.kind) ? row.owner.deviceFor(row.kind).volume : NaN
            valueText: row.owner.deviceFor(row.kind)
                ? `${Math.round((row.owner.volumeRequest(row.kind) ? row.owner.desiredVolume(row.kind) : row.owner.deviceFor(row.kind).volume) * 100)}%`
                : "—"
            accessibleName: row.isOutput ? row.owner.services.text("Гучність виводу", "Output volume")
                : row.owner.services.text("Гучність мікрофона", "Microphone level")
            enabled: row.owner.services.audio.active && !row.owner.services.audio.safeMode && !!row.owner.deviceFor(row.kind)
            onMoved: row.owner.requestVolume(row.kind, value)
            Binding {
                target: levelSlider
                property: "value"
                value: row.owner.volumeRequest(row.kind) ? row.owner.desiredVolume(row.kind)
                    : (row.owner.deviceFor(row.kind) ? row.owner.deviceFor(row.kind).volume : 0)
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
                ? (levelSlider.muted ? row.owner.services.text("Увімкнути звук", "Unmute output")
                    : row.owner.services.text("Вимкнути звук", "Mute output"))
                : (levelSlider.muted ? row.owner.services.text("Увімкнути мікрофон", "Unmute microphone")
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
            x: row.owner.vertical ? (sliderHost.width - width) / 2 : sliderHost.width - width
            width: 44
            controlHeight: row.owner.vertical ? 44 : 48
            text: ""
            accessibleName: row.isOutput ? row.owner.services.text("Обрати аудіовихід", "Choose audio output")
                : row.owner.services.text("Вибір мікрофона", "Choose microphone")
            requestedEnabled: row.owner.services.audio.active
            contentItem: Item {
                PentadChevron {
                    anchors.centerIn: parent
                    color: Theme.tokens.text
                    engaged: picker.hovered || picker.visualFocus || picker.down
                }
            }
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    radius: width / 2
                    color: Qt.alpha(Theme.tokens.text, picker.down ? 0.22 : 0.14)
                    opacity: picker.down || picker.hovered ? 1 : 0
                    border.width: picker.activeFocus ? 2 : 0
                    border.color: Theme.tokens.accent
                    Behavior on opacity { NumberAnimation { duration: Motion.state } }
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            onPressed: row.owner.detailsRequested("audio-" + row.kind)
        }
    }
}
