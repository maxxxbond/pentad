pragma ComponentBehavior: Bound
import QtQuick
import qs.theme

// A key drawn as a physical key seen from above and a little in front: a top face lighter than the
// surface, with a soft vertical gradient and a 1 px highlight along its top edge, standing on its
// skirt, whose front shows under the face as a darker lip, so it reads as raised. `inset` sculpts a
// larger key (the keyboard map): the face then sits inside the skirt, which shows as a lit back
// wall above it, thin side walls and a shaded front wall below it, the way a keycap's top sits
// inside its sides; at 0 (the list keycaps) the face spans the key over the lip. `look` covers the
// map's other states: 'quiet' is a free key (the same shape, a dimmer face, a muted legend) and
// 'pressed' a held key (the face lowered by the lip, so the lip is gone, under an inner shade along
// its top, in a darker skirt). The skirt lies inside the item's height, so a change of look never
// moves anything around it. `hue`, a group's colour, colours the legend and tints the face and the
// skirt of a raised key. `icon` draws a glyph (the Super key's logo) in place of the legend; `text`
// still names the key. Children declared inside a keycap sit on its face and move with it.
Item {
    id: root
    property string text: ''
    // A symbolic SVG drawn on the face instead of the legend, in the legend's colour.
    property string icon: ''
    property int iconSize: Math.round(root.size * 0.6)
    property color hue: 'transparent'
    // The share of the hue in a tinted face, and the legend's colour on it.
    property real hueTint: 0.14
    property color hueInk: root.hue
    property string look: 'raised'
    // The front lip under a raised face, inside the height.
    property int lip: 2
    // How far the face sits inside the skirt's sides; 0 lets it span the key.
    property int inset: 0
    // A hovered sculpted key stands a pixel higher.
    property bool lifted: false
    // The colour the key stands on; the lip of an unsculpted key is a shade of it.
    property color base: Theme.tokens.surfaceRaised
    // A share of the foreground laid over the face, as the state layers of the other controls.
    property real stateLayer: 0
    // The resting height: the cheatsheet's and the submap hint's keycaps.
    property int size: 24
    readonly property alias face: face
    readonly property alias legend: legendText
    default property alias content: face.data

    readonly property bool dark: Theme.config.appearance === 'dark'
    readonly property bool sculpted: root.inset > 0
    // The back wall above the face of a sculpted key: half the side walls.
    readonly property int topInset: root.sculpted ? Math.max(1, Math.round(root.inset / 2)) : 0
    readonly property bool pressed: root.look === 'pressed'
    readonly property bool quiet: root.look === 'quiet'
    readonly property bool raised: !root.pressed
    readonly property bool tinted: root.hue.a > 0 && root.look === 'raised'
    readonly property bool hasIcon: root.icon !== ''
    // The legend's colour: the hue on a tinted key, quiet on a free one.
    readonly property color ink: root.tinted ? root.hueInk : root.quiet ? Theme.tokens.textMuted : Theme.tokens.text
    // Raised: a face lighter than the surface, brightest at its top edge.
    readonly property color restTop: root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.07)) : Qt.lighter(Theme.tokens.surface, 1.05)
    readonly property color restBottom: root.dark ? Qt.darker(Theme.tokens.surfaceOverlay, 1.08) : Qt.tint(Theme.tokens.surface, Qt.alpha(Theme.tokens.text, 0.03))
    readonly property color restHighlight: root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.16)) : root.restTop
    // Quiet: the same key a step dimmer, closer to the surface it stands on.
    readonly property color quietTop: root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.025)) : Qt.tint(Theme.tokens.surface, Qt.alpha(Theme.tokens.text, 0.02))
    readonly property color quietBottom: root.dark ? Qt.darker(Theme.tokens.surfaceOverlay, 1.2) : Qt.tint(Theme.tokens.surface, Qt.alpha(Theme.tokens.text, 0.05))
    readonly property color quietHighlight: root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.08)) : root.quietTop
    // Pressed: the selected tone, one step up from the raised face, under an inner shade.
    readonly property color pressedFace: root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.14)) : Qt.darker(Theme.tokens.surfaceOverlay, 1.04)
    readonly property color pressedShade: Qt.darker(root.pressedFace, root.dark ? 1.5 : 1.08)
    // The face's three gradient stops before the hue and the state layer.
    readonly property color edgeTone: root.pressed ? root.pressedShade : root.quiet ? root.quietHighlight : root.restHighlight
    readonly property color topTone: root.pressed ? root.pressedFace : root.quiet ? root.quietTop : root.restTop
    readonly property color bottomTone: root.pressed ? root.pressedFace : root.quiet ? root.quietBottom : root.restBottom
    // The skirt: a shade of the surface under an unsculpted key; on a sculpted one the cap's own
    // plastic, lit at the back and shaded at the front; one even shade around a pressed key.
    readonly property color lipColor: Qt.darker(root.base, root.dark ? 3.0 : 1.22)
    readonly property color skirtBack: root.pressed ? Qt.darker(root.bottomTone, root.dark ? 1.7 : 1.16) : root.sculpted ? Qt.darker(root.bottomTone, root.dark ? 1.25 : 1.08) : root.lipColor
    readonly property color skirtFront: root.pressed ? root.skirtBack : root.sculpted ? Qt.darker(root.bottomTone, root.dark ? 1.75 : 1.24) : root.lipColor
    // How far the face moves: a pressed key sinks by the lip, so as much skirt shows above it as below.
    readonly property int faceDrop: root.pressed ? root.lip - root.topInset : root.lifted && root.sculpted ? -1 : 0

    implicitWidth: Math.max(root.size, (root.hasIcon ? root.iconSize : Math.ceil(legendText.implicitWidth)) + 2 * Metrics.space2)
    implicitHeight: Math.max(root.size, (root.hasIcon ? root.iconSize : Math.ceil(legendText.implicitHeight)) + Metrics.space1 + root.lip)

    function shade(tone) {
        const hued = root.tinted ? Qt.tint(tone, Qt.alpha(root.hue, root.hueTint)) : tone;
        return root.stateLayer > 0 ? Qt.tint(hued, Qt.alpha(Theme.tokens.text, root.stateLayer)) : hued;
    }
    function skirt(tone) {
        return root.tinted ? Qt.tint(tone, Qt.alpha(root.hue, root.sculpted ? root.hueTint * 0.6 : 0.1)) : tone;
    }

    Rectangle {
        objectName: 'keycap-lip'
        visible: root.lip > 0 || root.sculpted
        width: root.width
        height: root.height
        radius: root.sculpted ? Metrics.radiusMedium : Metrics.radiusSmall
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.skirt(root.skirtBack)
            }
            GradientStop {
                position: 1
                color: root.skirt(root.skirtFront)
            }
        }
    }
    Rectangle {
        id: face
        objectName: 'keycap-face'
        x: root.inset
        y: root.topInset + root.faceDrop
        width: Math.max(0, root.width - 2 * root.inset)
        height: Math.max(0, root.height - root.topInset - root.lip)
        radius: Metrics.radiusSmall
        // One pixel of highlight on a raised face; an inner shade along the top of a pressed one, as
        // deep as the lip.
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.shade(root.edgeTone)
            }
            GradientStop {
                position: Math.min(1, (root.pressed ? Math.max(2, root.lip) : 1) / Math.max(1, face.height))
                color: root.shade(root.topTone)
            }
            GradientStop {
                position: 1
                color: root.shade(root.bottomTone)
            }
        }
        PentadText {
            id: legendText
            anchors.centerIn: parent
            visible: root.text !== '' && !root.hasIcon
            // The laid-out text runs a little wider than FontMetrics measures; the slack keeps a
            // short legend such as "Ctrl" on one line in a keycap sized from FontMetrics.
            width: Math.max(0, face.width - Metrics.space2)
            horizontalAlignment: Text.AlignHCenter
            text: root.text
            textFormat: Text.PlainText
            role: 'caption'
            color: root.ink
            font.weight: root.tinted || root.pressed ? Font.DemiBold : Font.Medium
            wrapMode: Text.WrapAnywhere
        }
        // Only a key with a glyph builds the icon, so long lists of plain keycaps stay cheap.
        Loader {
            objectName: 'keycap-icon'
            anchors.centerIn: parent
            active: root.hasIcon
            sourceComponent: PentadIcon {
                source: root.icon
                pixelSize: root.iconSize
                color: root.ink
            }
        }
    }
}
