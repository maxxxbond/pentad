import QtQuick
import QtQuick.Effects
import qs.theme

// The shared drop zone: a raised card with a dashed rim inset concentric inside it, a pressed-in
// icon and title, and an optional footer under a separator that names where the drop goes.
// `destination` is a breadcrumb (["home", "projects", "design"]); its last segment is the target.
// The caller owns the DropArea and drives `active` from its containsDrag.
ContinuousSurface {
    id: root
    property bool active: false
    property url iconSource: Qt.resolvedUrl("../assets/icons/material/media/cloud-upload-symbolic.svg")
    property string title: ""
    property string hint: ""
    property string destinationLabel: ""
    property var destination: []
    property real rimInset: 8
    readonly property real contentInset: rimInset + 16
    readonly property bool showsFooter: destination.length > 0
    // Letterpress: a one-pixel copy in the page colour sits below the glyphs on a light page and
    // above them on a dark one, so they read as pressed into the card.
    readonly property bool lightPage: Theme.tokens.surface.hslLightness > 0.5
    implicitHeight: contentInset * 2 + body.implicitHeight + (showsFooter ? 24 + footer.implicitHeight : 0)
    extent: Metrics.radiusBlock
    clipContent: false
    fill: active ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
    Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }

    Component {
        id: pressedIn
        MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha(Theme.tokens.surface, 0.9)
            shadowBlur: 0
            shadowHorizontalOffset: 0
            shadowVerticalOffset: root.lightPage ? 1 : -1
            autoPaddingEnabled: true
        }
    }

    DropOutline {
        x: root.rimInset
        y: root.rimInset
        width: root.width - root.rimInset * 2
        height: root.height - root.rimInset * 2
        extent: Math.max(Metrics.radiusTag, root.extent - root.rimInset)
        active: root.active
    }

    Column {
        id: body
        x: root.contentInset
        width: root.width - root.contentInset * 2
        y: Math.round(((root.showsFooter ? footer.y - 12 : root.height - root.contentInset) + root.contentInset - implicitHeight) / 2)
        spacing: 12
        layer.enabled: true
        layer.effect: pressedIn

        PentadIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.iconSource.toString() !== ""
            source: root.iconSource
            pixelSize: 32
            color: root.active ? Theme.tokens.text : Theme.tokens.textMuted
            transform: Translate {
                y: root.active ? -2 : 0
                Behavior on y { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short; easing.type: Easing.OutCubic } }
            }
        }
        Column {
            width: parent.width
            PentadText {
                width: parent.width
                visible: text !== ""
                text: root.title
                role: "section"
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                color: root.active ? Theme.tokens.text : Theme.tokens.textMuted
                solid: true
            }
            PentadText {
                width: parent.width
                visible: text !== ""
                text: root.hint
                horizontalAlignment: Text.AlignHCenter
                color: Qt.alpha(Theme.tokens.textMuted, 0.7)
                solid: true
            }
        }
    }

    Item {
        id: footer
        visible: root.showsFooter
        x: root.contentInset
        width: root.width - root.contentInset * 2
        y: root.height - root.contentInset - implicitHeight
        implicitHeight: 17 + path.y + path.height

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.tokens.text, 0.07)
        }
        Item {
            y: 17
            width: parent.width
            height: parent.height - y
            layer.enabled: true
            layer.effect: pressedIn

            PentadText {
                id: label
                width: parent.width
                visible: text !== ""
                text: root.destinationLabel
                role: "caption"
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                color: Theme.tokens.textMuted
                solid: true
            }
            // A long path keeps its end in view and fades out on the left.
            Item {
                id: path
                y: label.visible ? label.height + 4 : 0
                width: parent.width
                height: trail.height
                clip: true
                Row {
                    id: trail
                    x: width <= path.width ? Math.round((path.width - width) / 2) : path.width - width
                    PentadText {
                        text: root.destination.slice(0, -1).map(segment => String(segment) + " / ").join("")
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap
                        color: Qt.alpha(Theme.tokens.textMuted, 0.6)
                    }
                    PentadText {
                        text: String(root.destination[root.destination.length - 1] ?? "")
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap
                        font.weight: Font.Medium
                        color: Theme.tokens.textMuted
                    }
                }
            }
        }
        // Outside the letterpress layer, so the fade itself casts no highlight.
        Rectangle {
            visible: root.showsFooter && trail.width > path.width
            y: 17 + path.y
            width: 32
            height: path.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.fill }
                GradientStop { position: 1; color: Qt.alpha(root.fill, 0) }
            }
        }
    }
}
