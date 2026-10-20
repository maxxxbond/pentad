import QtQuick
import qs.theme

Text {
    property string role: "body"
    color: Theme.tokens.text
    font.family: Theme.tokens.fontFamily
    font.pixelSize: role === "caption" ? Metrics.textCaption
        : role === "section" ? Metrics.textSection
        : role === "title" ? Metrics.textTitle : Metrics.textBody
    wrapMode: Text.Wrap
}
