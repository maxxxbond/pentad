pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// One audio device section of AudioControls (output or input): the default-device selector,
// the compact device list, request status and the volume row. `owner` is the AudioControls
// root, which keeps all request state and actions.
Column {
    id: section
    required property var owner
    required property string kind
    readonly property var device: owner.deviceFor(kind)
    readonly property var devices: owner.devicesFor(kind)
    spacing: 6

            PentadText {
                visible: !section.owner.compact
                text: section.kind === "output" ? "Output" : "Input"
                role: "section"
            }
            PentadComboBox {
                id: selector
                visible: !section.owner.compact
                width: section.width
                fill: Theme.tokens.surfaceOverlay
                model: section.devices
                textRole: "label"
                displayText: currentIndex >= 0 && currentIndex < section.devices.length
                    ? (section.devices[currentIndex].shortLabel || section.devices[currentIndex].label)
                    : (section.kind === "output" ? section.owner.services.text("Немає пристроїв виводу", "No output devices")
                        : section.owner.services.text("Немає пристроїв вводу", "No input devices"))
                currentIndex: section.devices.findIndex(function(item) {
                    return section.device && item.id === section.device.id;
                })
                enabled: section.owner.services.audio.active && !section.owner.services.audio.safeMode && section.devices.length > 0
                Accessible.name: section.kind === "output" ? "Default audio output" : "Default audio input"
                Accessible.description: section.device ? section.device.label : ""
                onActivated: function(index) { section.owner.requestDefault(section.kind, index); }
                PentadHint {
                    text: section.device ? section.device.label : ""
                    shown: (selector.hovered || selector.activeFocus) && !selector.popup.visible
                }
                delegate: ItemDelegate {
                    id: deviceOption
                    required property int index
                    required property var modelData
                    readonly property bool selected: !!section.device && modelData.id === section.device.id
                    width: ListView.view ? ListView.view.width : selector.width
                    implicitHeight: 52
                    highlighted: selector.highlightedIndex === index
                    Accessible.name: modelData.label
                    Accessible.description: selected ? section.owner.services.text("Вибрано", "Selected") : ""
                    // The row layer of PentadComboBox, concentric with its list.
                    background: ContinuousSurface {
                        fill: deviceOption.highlighted || deviceOption.hovered ? Qt.alpha(Theme.tokens.text, deviceOption.selected ? 0.12 : 0.07)
                            : deviceOption.selected ? Qt.alpha(Theme.tokens.text, 0.08) : "transparent"
                        extent: Metrics.radiusPopover - 6
                    }
                    PentadHint {
                        axis: "horizontal"
                        text: deviceOption.modelData.label
                        shown: deviceOption.hovered || deviceOption.activeFocus
                    }
                    contentItem: Row {
                        spacing: 10
                        PentadIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            source: Qt.resolvedUrl("../../assets/icons/" + (deviceOption.modelData.icon
                                || (section.kind === "input" ? "material/media/mic-symbolic.svg" : "material/volume-up-symbolic.svg")))
                            pixelSize: Metrics.menuIcon
                            color: deviceOption.selected ? Theme.tokens.accent : Theme.tokens.textMuted
                            Accessible.ignored: true
                        }
                        Text {
                            width: Math.max(0, parent.width - Metrics.menuIcon - 38)
                            anchors.verticalCenter: parent.verticalCenter
                            text: deviceOption.modelData.shortLabel || deviceOption.modelData.label
                            elide: Text.ElideRight
                            color: Theme.tokens.text
                            font.family: Theme.tokens.fontFamily
                            font.pixelSize: Metrics.textBody
                            Accessible.ignored: true
                        }
                        PentadIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: deviceOption.selected
                            source: Qt.resolvedUrl("../../assets/icons/material/screenshot/check-symbolic.svg")
                            pixelSize: Metrics.textBody
                            color: Theme.tokens.accent
                            Accessible.ignored: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: {
                            selector.currentIndex = deviceOption.index;
                            selector.activated(deviceOption.index);
                            selector.popup.close();
                        }
                    }
                }
            }
            Repeater {
                model: section.owner.compact ? section.devices : []
                delegate: SelectorOption {
                    required property var modelData
                    required property int index
                    width: section.width
                    text: modelData.shortLabel || modelData.label
                    tooltipText: modelData.label
                    iconSource: Qt.resolvedUrl("../../assets/icons/" + (modelData.icon
                        || (section.kind === "input" ? "material/media/mic-symbolic.svg" : "material/volume-up-symbolic.svg")))
                    selected: !!section.device && modelData.id === section.device.id
                    accessibleName: modelData.label + (section.device && modelData.id === section.device.id
                        ? section.owner.services.text(" · вибрано", " · selected") : "")
                    enabled: !!section && section.owner.services.audio.active && !section.owner.services.audio.safeMode
                        && !(section.kind === "output" ? section.owner.outputDefaultRequest : section.owner.inputDefaultRequest)
                    onPressed: section.owner.requestDefault(section.kind, index)
                }
            }
            PentadText {
                visible: section.owner.compact && section.devices.length === 0
                text: section.kind === "output"
                    ? section.owner.services.text("Немає аудіовиходів", "No audio outputs")
                    : section.owner.services.text("Немає мікрофонів", "No microphones")
                role: "caption"
                color: Theme.tokens.textMuted
            }
            PentadText {
                visible: section.kind === "output" ? !!section.owner.outputDefaultRequest : !!section.owner.inputDefaultRequest
                text: section.owner.defaultStatus(section.kind)
                color: Theme.tokens.textMuted
                role: "caption"
            }
            Row {
                id: volumeRow
                visible: !section.owner.compact
                width: section.width
                spacing: 8
                PentadButton {
                    id: muteButton
                    text: ""
                    accessibleName: section.kind === "output" ? "Toggle output mute" : "Toggle input mute"
                    contentItem: Text {
                        text: section.kind === "output"
                        ? (section.device && section.device.muted ? "volume_off" : "volume_up")
                        : (section.device && section.device.muted ? "mic_off" : "mic")
                        color: parent.enabled ? Theme.tokens.text : Theme.tokens.textMuted
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: Metrics.statusIcon
                        font.weight: Font.Medium
                        font.variableAxes: ({ FILL: 1, wght: 500, GRAD: 0, opsz: Metrics.statusIcon })
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    requestedEnabled: section.owner.services.audio.active && !section.owner.services.audio.safeMode && !!section.device
                    pending: section.kind === "output" ? !!section.owner.outputMuteRequest : !!section.owner.inputMuteRequest
                    onPressed: section.owner.requestMute(section.kind)
                }
                PentadSlider {
                    id: volumeSlider
                    visible: !section.owner.compact || section.kind === "input"
                    width: visible ? Math.max(0, section.width - muteButton.width - volumeValue.width - 2 * volumeRow.spacing) : 0
                    from: 0
                    to: 1
                    stepSize: 0.01
                    wheelStepSize: 0.02
                    accessibleName: section.kind === "output" ? "Output volume" : "Input volume"
                    enabled: section.owner.services.audio.active && !section.owner.services.audio.safeMode && !!section.device
                    onMoved: section.owner.requestVolume(section.kind, value)
                    Binding {
                        target: volumeSlider
                        property: "value"
                        value: section.owner.volumeRequest(section.kind)
                            ? section.owner.desiredVolume(section.kind)
                            : (section.device ? section.device.volume : 0)
                    }
                }
                PentadText {
                    id: volumeValue
                    visible: volumeSlider.visible
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    horizontalAlignment: Text.AlignRight
                    text: {
                        const actual = section.device ? Math.round(section.device.volume * 100) : 0;
                        const desired = Math.round(section.owner.desiredVolume(section.kind) * 100);
                        return section.owner.volumeRequest(section.kind)
                            ? `${desired}% → ${actual}%` : `${actual}%`;
                    }
                    role: "caption"
                }
            }
            Rectangle {
                width: section.width
                height: 1
                color: Theme.tokens.outline
                opacity: 0.35
                visible: !section.owner.compact && section.kind === "output"
            }
}
