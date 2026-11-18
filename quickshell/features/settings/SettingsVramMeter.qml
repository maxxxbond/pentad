pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules

// A capsule meter of the graphics memory: one segment per loaded model in the local hue, the rest
// of the used memory in a softer step of it, and the free part as the bare track. The optional
// legend names each part. Data from Rules.vramMeter().
Column {
    id: root
    required property var services
    property var meter: ({ available: false })
    property color hue: Theme.tokens.success
    property bool uk: false
    property bool legend: false
    property int barHeight: Metrics.space2
    spacing: Metrics.space2
    objectName: "settings-vram-meter"

    function t(uk, en) { return services.text(uk, en); }

    // The track is a capsule surface that masks its parts, so only the outer ends are round.
    ContinuousSurface {
        id: strip
        objectName: "settings-vram-track"
        width: root.width
        height: root.barHeight
        fill: Theme.tokens.surfaceOverlay
        extent: height / 2
        Row {
            height: strip.height
            Repeater {
                model: root.meter.available ? root.meter.models : []
                delegate: Rectangle {
                    required property var modelData
                    width: Math.max(2, Math.round(strip.width * modelData.fraction))
                    height: strip.height
                    color: root.hue
                }
            }
            Rectangle {
                width: root.meter.available ? Math.round(strip.width * root.meter.otherFraction) : 0
                height: strip.height
                color: Qt.alpha(root.hue, 0.4)
            }
        }
    }
    Flow {
        visible: root.legend && root.meter.available
        width: root.width
        spacing: Metrics.space3
        Repeater {
            model: {
                if (!root.meter.available) return [];
                const list = root.meter.models.map(function(model) { return { label: model.name, tone: 1 }; });
                if (root.meter.otherBytes > 0) list.push({ label: root.t("інше", "other") + " " + Rules.bytesText(root.meter.otherBytes, root.uk), tone: 0.4 });
                list.push({ label: root.t("вільно ", "free ") + Rules.bytesText(root.meter.freeBytes, root.uk), tone: 0 });
                return list;
            }
            delegate: Row {
                required property var modelData
                spacing: Metrics.space1
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.space2
                    height: width
                    radius: width / 2
                    color: parent.modelData.tone > 0 ? Qt.alpha(root.hue, parent.modelData.tone) : Theme.tokens.surfaceOverlay
                }
                PentadText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.label
                    textFormat: Text.PlainText
                    role: "caption"
                    color: Theme.tokens.textMuted
                    wrapMode: Text.NoWrap
                    font.features: ({ tnum: 1 })
                }
            }
        }
    }
}
