import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import "../../logic/pentads.mjs" as Pentads
import "../../logic/settings-bindings.mjs" as Bindings

// Margin and padding box model drawn to scale (unit px per px). Radii stay concentric:
// surface = card radius, content = card radius - padding, margin box = surface + margin.
ColumnLayout {
    id: root
    // The `_margin` item of the frame group and the documents it is read from.
    property var item: null
    property var documents: ({})
    property var services: null
    // Direct values override the document (used by tests and fixtures).
    property var marginOverride: undefined
    property var paddingOverride: undefined
    property var backgroundOverride: undefined

    readonly property real unit: 1.5
    readonly property real contentWidth: 112
    readonly property real contentHeight: 40
    readonly property int margin: marginOverride !== undefined ? marginOverride : read("_margin", Pentads.frameLimits.margin.default)
    readonly property int padding: paddingOverride !== undefined ? paddingOverride : read("_padding", Pentads.frameLimits.padding.default)
    readonly property string background: backgroundOverride !== undefined ? backgroundOverride : read("_bg", Pentads.defaultBackground)
    readonly property real surfaceRadius: Metrics.radiusCard * unit
    readonly property real contentRadius: Pentads.innerRadius(padding, Metrics.radiusCard) * unit
    readonly property real marginRadius: surfaceRadius + margin * unit
    readonly property int innerRadiusValue: Pentads.innerRadius(padding, Metrics.radiusCard)

    function t(uk, en) { return services && services.text ? services.text(uk, en) : en; }
    function read(key, fallback) {
        if (!item) return fallback;
        return Bindings.readValue(documents, { document: item.document, path: item.path.replace(/_[a-z]+$/, key), default: fallback });
    }

    spacing: 8
    Accessible.role: Accessible.Graphic
    Accessible.name: t("Рамка", "Frame")
    Accessible.description: t("Відступ " + margin + ", внутрішній " + padding + ", радіус " + innerRadiusValue + " px",
        "Margin " + margin + ", padding " + padding + ", inner radius " + innerRadiusValue + " px")

    Item {
        Layout.alignment: Qt.AlignHCenter
        // Fixed to the largest frame so the layout does not jump while sliders move.
        implicitWidth: root.contentWidth + 2 * (Pentads.frameLimits.margin.max + Pentads.frameLimits.padding.max) * root.unit
        implicitHeight: root.contentHeight + 2 * (Pentads.frameLimits.margin.max + Pentads.frameLimits.padding.max) * root.unit
        Rectangle {
            id: marginBox
            anchors.centerIn: parent
            width: surface.width + 2 * root.margin * root.unit
            height: surface.height + 2 * root.margin * root.unit
            radius: root.marginRadius
            color: Qt.alpha(Theme.tokens.warning, 0.12)
            Behavior on width { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
            Rectangle {
                id: surface
                anchors.centerIn: parent
                width: root.contentWidth + 2 * root.padding * root.unit
                height: root.contentHeight + 2 * root.padding * root.unit
                radius: root.surfaceRadius
                color: root.background === "solid" ? Theme.tokens.surfaceOverlay
                    : root.background === "subtle" ? Theme.tokens.surfaceRaised : Qt.alpha(Theme.tokens.text, 0.05)
                Rectangle {
                    anchors.centerIn: parent
                    width: root.contentWidth
                    height: root.contentHeight
                    radius: root.contentRadius
                    color: Theme.tokens.accent
                    opacity: 0.35
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Repeater {
            model: [
                { color: Theme.tokens.warning, text: root.t("Відступ ", "Margin ") + root.margin + " px" },
                { color: Theme.tokens.textMuted, text: root.t("Внутрішній ", "Padding ") + root.padding + " px" },
                { color: Theme.tokens.accent, text: root.t("Радіус ", "Inner radius ") + root.innerRadiusValue + " px = " + Metrics.radiusCard + " − " + root.padding }
            ]
            delegate: Row {
                required property var modelData
                spacing: 6
                Rectangle {
                    width: 8
                    height: 8
                    radius: Metrics.radiusMicro / 2
                    color: parent.modelData.color
                    anchors.verticalCenter: parent.verticalCenter
                }
                PentadText {
                    text: parent.modelData.text
                    textFormat: Text.PlainText
                    role: "caption"
                    color: Theme.tokens.textMuted
                    wrapMode: Text.NoWrap
                }
            }
        }
    }
}
