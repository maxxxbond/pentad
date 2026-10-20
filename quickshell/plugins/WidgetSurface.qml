import QtQuick
import qs.theme

// Background behind a framed widget: "none" draws nothing, "subtle" a raised fill, "solid" an overlay fill.
// The host sets `radius` (concentric: surface radius minus padding goes to the content).
Rectangle {
    property string kind: "none"
    visible: kind === "subtle" || kind === "solid"
    color: kind === "solid" ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
}
