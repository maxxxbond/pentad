pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme

Item {
    id: root
    required property var power
    readonly property var batteryState: power ? power.batteryState : ({ kind: "unavailable" })
    readonly property var profileState: power ? power.profileState : ({ kind: "unavailable", reason: "service-missing" })
    property string pendingProfileRequest: ""
    property string profileError: ""
    width: parent ? parent.width : 320
    implicitHeight: card.implicitHeight

    Connections {
        target: root.power
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingProfileRequest) return;
            root.pendingProfileRequest = "";
            root.profileError = result.ok ? "" : `Profile change failed (${result.reason || "failed"})`;
        }
    }

    PentadCard {
        id: card
        width: root.width
        implicitHeight: content.implicitHeight + 24
        Column {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            PentadText { text: "Power"; role: "section" }
            PentadText {
                visible: root.batteryState.kind === "ready" && root.batteryState.value.battery !== null
                text: {
                    if (root.batteryState.kind !== "ready" || root.batteryState.value.battery === null) return "";
                    const battery = root.batteryState.value.battery;
                    return battery.percent === null ? `Battery · ${battery.state}`
                        : `Battery · ${Math.round(battery.percent)}% · ${battery.state}`;
                }
            }
            PentadText {
                visible: root.batteryState.kind !== "ready" || root.batteryState.value.battery === null
                text: root.power && root.power.preview ? "Preview · read only" : "No laptop battery detected"
                color: Theme.tokens.textMuted
                role: "caption"
            }
            PentadText {
                visible: root.profileState.kind !== "ready"
                text: root.profileState.reason === "preview" ? "Power profiles · preview only"
                    : "Power profiles unavailable";
                color: Theme.tokens.textMuted
                role: "caption"
                wrapMode: Text.Wrap
            }
            Flow {
                visible: root.profileState.kind === "ready"
                width: content.width
                spacing: 6
                Repeater {
                    model: root.profileState.kind === "ready" ? root.profileState.value.profiles : []
                    delegate: PentadButton {
                        required property string modelData
                        text: modelData === root.profileState.value.actual
                            ? `${modelData} · current`
                            : modelData === root.profileState.value.desired
                                && root.profileState.value.pending ? `${modelData} · applying`
                                : modelData
                        requestedEnabled: root.power.active && !root.power.safeMode
                            && !root.profileState.value.pending
                        onPressed: {
                            root.profileError = "";
                            root.pendingProfileRequest = root.power.setProfile(modelData);
                        }
                    }
                }
            }
            PentadText {
                visible: root.profileState.kind === "ready" && root.profileState.value.pending
                text: `Applying ${root.profileState.value.desired} · current ${root.profileState.value.actual}`
                color: Theme.tokens.textMuted
                role: "caption"
            }
            PentadText {
                visible: root.profileError !== ""
                text: root.profileError
                color: Theme.tokens.error
                role: "caption"
            }
        }
    }
}
