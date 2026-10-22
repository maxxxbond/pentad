import QtQuick
import qs.theme

Text {
    property string role: "body"
    // A line stacked with others in one small component: its box is exactly the pixel size.
    property bool solid: false
    color: Theme.tokens.text
    font.family: Theme.tokens.fontFamily
    font.pixelSize: role === "caption" ? Metrics.textCaption
        : role === "section" ? Metrics.textSection
        : role === "title" ? Metrics.textTitle : Metrics.textBody
    lineHeightMode: solid ? Text.FixedHeight : Text.ProportionalHeight
    lineHeight: solid ? font.pixelSize : 1
    wrapMode: Text.Wrap
}
