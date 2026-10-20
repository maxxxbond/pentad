pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components
import qs.theme

Row {
    id: root
    required property var services
    signal activated()
    spacing: Metrics.statusGap
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    function activate() { activated(); }

    Item {
        id: networkIndicator
        readonly property var networkState: root.services.network.state
        implicitWidth: Metrics.statusIcon
        implicitHeight: Metrics.statusIcon
        anchors.verticalCenter: parent.verticalCenter
        visible: true
        PentadIcon {
            anchors.fill: parent
            pixelSize: Metrics.statusIcon
            accessibleName: "Network"
            source: {
                if (networkIndicator.networkState.kind !== "ready") return Qt.resolvedUrl("../../assets/icons/material/wifi-off-symbolic.svg");
                const value = networkIndicator.networkState.value;
                if (value.primary === "wired") return Qt.resolvedUrl("../../assets/icons/material/network-wired-symbolic.svg");
                if (value.primary === "wifi" && value.connected) return Qt.resolvedUrl("../../assets/icons/material/wifi-symbolic.svg");
                return Qt.resolvedUrl("../../assets/icons/material/wifi-off-symbolic.svg");
            }
        }
        MouseArea { anchors.fill: parent; onPressed: root.activate() }
        PentadToolTip {
            objectName: "network-tooltip"
            visible: networkMouse.containsMouse
            text: networkIndicator.networkState.kind === "ready"
                ? (networkIndicator.networkState.value.label || "Disconnected") : "Network unavailable"
        }
        MouseArea { id: networkMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }

    Repeater {
        model: ["output", "input"]
        delegate: Item {
            id: audioIndicator
            required property string modelData
            property real wheelRemainder: 0
            property string commandId: ""
            property string feedbackError: ""
            readonly property var audioState: root.services.audio.state
            readonly property bool available: audioState.kind === "ready"
            readonly property var device: available ? audioState.value[modelData] : null
            implicitWidth: 24
            implicitHeight: Metrics.panelControl
            anchors.verticalCenter: parent.verticalCenter
            visible: true
            readonly property string microphoneIcon: modelData === "input"
                ? Quickshell.iconPath(device && !device.muted
                    ? "microphone-sensitivity-high-symbolic"
                    : "microphone-disabled-symbolic", true) : ""
            PentadIcon {
                anchors.centerIn: parent
                width: Metrics.statusIcon
                height: Metrics.statusIcon
                pixelSize: Metrics.statusIcon
                accessibleName: (audioIndicator.modelData === "input" ? "Audio input" : "Audio output")
                    + (audioIndicator.device ? " · " + audioIndicator.device.label
                        + (audioIndicator.device.muted ? " · " + (typeof root.services.text === "function" ? root.services.text("Звук вимкнено", "Muted") : "Muted") : "") : "")
                visible: modelData !== "input" || !!parent.microphoneIcon
                source: audioIndicator.modelData === "input" ? audioIndicator.microphoneIcon
                    : Qt.resolvedUrl("../../assets/icons/" + (audioIndicator.device && !audioIndicator.device.muted
                        ? (audioIndicator.device.icon || "material/volume-outline-symbolic.svg")
                        : "material/volume-outline-off-symbolic.svg"))
            }
            Text {
                anchors.fill: parent
                visible: modelData === "input" && !microphoneIcon
                text: device && !device.muted ? "mic" : "mic_off"
                color: Qt.alpha(Theme.tokens.text, 0.8)
                font.family: "Material Symbols Rounded"
                font.pixelSize: Metrics.statusIcon
                font.weight: Font.Medium
                font.variableAxes: ({ FILL: 1, wght: 500, GRAD: 0, opsz: Metrics.statusIcon })
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Accessible.name: modelData === "input" ? "Audio input" : "Audio output"
            }
            MouseArea {
                id: audioMouse
                objectName: "audio-indicator-" + modelData
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                onClicked: {
                    audioIndicator.feedbackError = "";
                    root.services.audio.contextualFeedbackUntil = Date.now() + 5000;
                    audioTooltip.reveal(1);
                    audioIndicator.commandId = root.services.audio.toggleMute(audioIndicator.modelData);
                }
                onWheel: function(wheel) {
                    const rawSteps = wheel.angleDelta.y !== 0
                        ? wheel.angleDelta.y / 120 : wheel.pixelDelta.y / 40;
                    if (Math.sign(rawSteps) !== Math.sign(wheelRemainder)) wheelRemainder = 0;
                    wheelRemainder += rawSteps;
                    const wholeSteps = Math.trunc(wheelRemainder);
                    wheelRemainder -= wholeSteps;
                    if (wholeSteps) {
                        audioIndicator.feedbackError = "";
                        root.services.audio.contextualFeedbackUntil = Date.now() + 5000;
                        audioTooltip.reveal(wholeSteps);
                        audioIndicator.commandId = root.services.audio.cycleDefault(audioIndicator.modelData, wholeSteps);
                    }
                    wheel.accepted = true;
                }
                onExited: wheelRemainder = 0
                onEntered: audioIndicator.feedbackError = ""
            }
            Connections {
                target: root.services.audio
                function onCommandFinished(requestId, result) {
                    if (requestId !== audioIndicator.commandId) return;
                    audioIndicator.commandId = "";
                    root.services.audio.contextualFeedbackUntil = Date.now() + 250;
                    if (!result.ok) {
                        audioIndicator.feedbackError = result.reason === "unavailable"
                            ? "No other device available" : "Could not change audio";
                        audioTooltip.reveal(audioTooltip.direction);
                    }
                }
            }
            PentadToolTip {
                id: audioTooltip
                objectName: "audio-tooltip-" + audioIndicator.modelData
                visible: audioMouse.containsMouse && !audioMouse.pressed
                sizeMode: "status"
                animateContent: false
                text: audioIndicator.device ? audioIndicator.device.label
                    : (audioIndicator.modelData === "input" ? "Microphone unavailable" : "Audio unavailable")
                detail: audioIndicator.feedbackError || (audioIndicator.device
                    ? Math.round((audioIndicator.device.requestedVolume ?? audioIndicator.device.volume) * 100) + "%"
                    : "")
            }
        }
    }

    Item {
        id: batteryIndicator
        readonly property var powerState: root.services.power.state
        readonly property var battery: powerState.kind === "ready" ? powerState.value.battery : null
        implicitWidth: powerState.kind !== "ready" || battery ? Metrics.statusIcon : 0
        implicitHeight: Metrics.statusIcon
        anchors.verticalCenter: parent.verticalCenter
        visible: powerState.kind !== "ready" || !!battery
        PentadIcon {
            anchors.fill: parent
            pixelSize: Metrics.statusIcon
            accessibleName: !parent.battery || parent.battery.percent === null
                ? "Battery charge unknown" : `Battery ${Math.round(parent.battery.percent)}%`
            source: {
                const b = parent.battery;
                if (!b) return Qt.resolvedUrl("../../assets/icons/material/battery-unknown-symbolic.svg");
                if (b.state === "charging") return Qt.resolvedUrl("../../assets/icons/material/battery-charging-full-symbolic.svg");
                if (b.percent === null) return Qt.resolvedUrl("../../assets/icons/material/battery-unknown-symbolic.svg");
                if (b.percent < 15) return Qt.resolvedUrl("../../assets/icons/material/battery-1-bar-symbolic.svg");
                if (b.percent < 40) return Qt.resolvedUrl("../../assets/icons/material/battery-2-bar-symbolic.svg");
                if (b.percent < 65) return Qt.resolvedUrl("../../assets/icons/material/battery-3-bar-symbolic.svg");
                return Qt.resolvedUrl("../../assets/icons/material/battery-full-symbolic.svg");
            }
        }
        MouseArea { id: batteryMouse; anchors.fill: parent; hoverEnabled: true; onPressed: root.activate() }
        PentadToolTip {
            objectName: "battery-tooltip"
            visible: batteryMouse.containsMouse
            text: batteryIndicator.battery && batteryIndicator.battery.percent !== null
                ? Math.round(batteryIndicator.battery.percent) + "%" : "Battery unavailable"
        }
    }
}
