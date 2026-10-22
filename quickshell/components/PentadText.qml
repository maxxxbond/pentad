import QtQuick
import qs.theme

Text {
    id: label
    property string role: "body"
    // A line stacked with others in one small component: its box ends at the pixel size, so the
    // font's descent below the last line adds no gap. Text.lineHeight cannot shrink a line box.
    property bool solid: false
    color: Theme.tokens.text
    font.family: Theme.tokens.fontFamily
    font.pixelSize: role === "caption" ? Metrics.textCaption
        : role === "section" ? Metrics.textSection
        : role === "title" ? Metrics.textTitle : Metrics.textBody
    bottomPadding: solid ? Math.min(0, font.pixelSize - Math.ceil(metrics.height)) : 0
    wrapMode: Text.Wrap

    FontMetrics { id: metrics; font: label.font }
}
