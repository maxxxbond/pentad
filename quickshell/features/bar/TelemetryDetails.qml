pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.components
import "../../logic/telemetry.mjs" as Telemetry
import "../../logic/telemetry-layout.mjs" as Layout

Item {
    id: root
    required property var services
    property var value: null
    readonly property var memory: value ? value.memory : null
    readonly property var gpus: value && value.gpus ? value.gpus : []
    readonly property alias gpuDelegates: gpuRepeater
    readonly property int metricCount: Math.max(1, gpus.length) + 3
    readonly property var grid: Layout.telemetryLayout(metricCount, width)
    readonly property int columns: grid.columns
    readonly property real cellWidth: grid.cells[0].width
    implicitWidth: Layout.telemetryLayout(metricCount).width
    implicitHeight: grid.height

    function slotX(slot) { return grid.cells[slot].x; }
    function text(uk, en) {
        return typeof services.text === "function" ? services.text(uk, en) : en;
    }
    function percent(ratio) {
        return Number.isFinite(ratio) ? Math.round(ratio * 100) + "%" : "—";
    }
    function gb(bytes) {
        return Number.isFinite(bytes) ? (bytes / 1073741824).toFixed(1).replace(/\.0$/, "") : "—";
    }

    component ResourceGauge: Item {
        id: resource
        required property string label
        required property int slot
        property string detail: ""
        property string description: detail
        property var ratio: null
        x: root.slotX(slot)
        y: root.grid.cells[slot].y
        width: root.cellWidth
        height: 96
        Accessible.role: Accessible.StaticText
        Accessible.name: label + ": " + root.percent(ratio) + ". " + description

        Item {
            width: Math.max(0, Math.min(76, parent.width))
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            Shape {
                id: ring
                objectName: "telemetry-resource-gauge"
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property real fraction: Number.isFinite(resource.ratio)
                    ? Math.max(0, Math.min(1, resource.ratio)) : 0
                property real displayedFraction: fraction
                Behavior on displayedFraction {
                    enabled: !Motion.reducedMotion && Number.isFinite(resource.ratio)
                    NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
                }
                ShapePath {
                    fillColor: Theme.tokens.surfaceRaised
                    strokeColor: Theme.tokens.surfaceOverlay
                    strokeWidth: 3
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: Math.max(0, ring.width / 2 - 2); radiusY: radiusX
                        startAngle: -90; sweepAngle: 360
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: ring.displayedFraction > 0 ? Qt.alpha(Theme.tokens.text, 0.7) : "transparent"
                    strokeWidth: 3
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.width / 2; centerY: ring.height / 2
                        radiusX: Math.max(0, ring.width / 2 - 2); radiusY: radiusX
                        startAngle: -90; sweepAngle: 360 * ring.displayedFraction
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                PentadText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: resource.label
                    role: "caption"
                    color: Theme.tokens.textMuted
                }
                PentadText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.percent(Number.isFinite(resource.ratio) ? ring.displayedFraction : null)
                    role: "title"
                    font.weight: Font.Medium
                    font.features: ({ tnum: 1 })
                    color: Number.isFinite(resource.ratio) ? Theme.tokens.text : Theme.tokens.textMuted
                }
            }
        }
        PentadText {
            y: 80
            width: parent.width
            visible: text.length > 0
            text: resource.detail
            role: "caption"
            color: Theme.tokens.textMuted
            font.features: ({ tnum: 1 })
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.NoWrap
        }
    }

    Item {
        id: layout
        anchors.fill: parent
        ResourceGauge {
            slot: 0
            label: "CPU"
            ratio: root.value ? root.value.cpuPercent : null
        }
        Repeater {
            id: gpuRepeater
            model: Math.max(1, root.gpus.length)
            delegate: ResourceGauge {
                required property int index
                readonly property var modelData: root.gpus[index] || null
                slot: index + 1
                label: root.gpus.length > 1 && modelData ? "GPU " + modelData.id.replace(/^card/, "") : "GPU"
                ratio: modelData ? modelData.load : null
                detail: modelData && modelData.memory ? root.gb(modelData.memory.used) + "/" + root.gb(modelData.memory.total) + " GB" : "—"
                description: modelData && modelData.memory ? "VRAM: " + detail : root.text("Датчики недоступні", "Sensors unavailable")
            }
        }
        ResourceGauge {
            slot: Math.max(1, root.gpus.length) + 1
            label: "RAM"
            ratio: root.memory && root.memory.total > 0 ? root.memory.used / root.memory.total : null
            detail: root.memory ? root.gb(root.memory.used) + "/" + root.gb(root.memory.total) + " GB" : "—"
            description: detail + (root.memory ? " · " + root.gb(root.memory.total - root.memory.used)
                + root.text(" GB вільно", " GB free") : "")
        }
        Item {
            id: networkCell
            objectName: "telemetry-network-cell"
            x: root.slotX(root.metricCount - 1)
            y: root.grid.cells[root.metricCount - 1].y
            width: root.cellWidth
            height: 96
            Item {
                id: networkCircle
                objectName: "telemetry-network-circle"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(0, Math.min(76, parent.width))
                height: width
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Theme.tokens.surfaceRaised
                        strokeColor: "transparent"
                        strokeWidth: 3
                        PathAngleArc {
                            centerX: networkCircle.width / 2; centerY: networkCircle.height / 2
                            radiusX: Math.max(0, networkCircle.width / 2 - 2); radiusY: radiusX
                            startAngle: 0; sweepAngle: 360
                        }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    spacing: 2
                    Repeater {
                        model: ["receive", "send"]
                        delegate: Row {
                            required property string modelData
                            readonly property bool receiving: modelData === "receive"
                            width: parent.width
                            spacing: 2
                            PentadText {
                                id: direction
                                role: "caption"
                                text: parent.receiving ? "↓" : "↑"
                                color: Theme.tokens.textMuted
                            }
                            PentadText {
                                objectName: parent.receiving ? "telemetry-download" : "telemetry-upload"
                                width: parent.width - direction.width - parent.spacing
                                role: "caption"
                                font.features: ({ tnum: 1 })
                                wrapMode: Text.NoWrap
                                text: Telemetry.compactDetailByteRate(root.value
                                    ? parent.receiving ? root.value.rxBytesPerSecond : root.value.txBytesPerSecond : null)
                                Accessible.name: (parent.receiving ? root.text("Отримання: ", "Download: ")
                                    : root.text("Надсилання: ", "Upload: ")) + Telemetry.byteRate(root.value
                                        ? parent.receiving ? root.value.rxBytesPerSecond : root.value.txBytesPerSecond : null)
                            }
                        }
                    }
                }
            }
            PentadText {
                y: 80
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.text("Мережа", "Network")
                role: "caption"
                color: Theme.tokens.textMuted
            }
        }
    }
}
