import QtQuick
import qs.theme

// A key drawn as a physical key: a face a step lighter than the surface with a soft vertical
// gradient and a 1 px highlight along its top edge, over a darker lip, so it reads as raised.
// `look` covers the keyboard map's other states: 'flat' is a free key, sunken (a darker face with
// an inner shade along the top, no lip), and 'pressed' a held key (the inner shade, no lip, the
// face lowered by the lip). The lip lies inside the item's height, so a change of look never moves
// anything around it. `hue`, a group's colour, colours the legend and lightly tints the face and
// the lip of a raised key. Children declared inside a keycap sit on its face and move with it.
Item {
    id: root
    property string text: ''
    property color hue: 'transparent'
    property string look: 'raised'
    // The lip under a raised face, inside the height.
    property int lip: 2
    // The colour the key stands on; the lip is a shade of it.
    property color base: Theme.tokens.surfaceRaised
    // A share of the foreground laid over the face, as the state layers of the other controls.
    property real stateLayer: 0
    // The resting height: the cheatsheet's and the submap hint's keycaps.
    property int size: 24
    readonly property alias face: face
    readonly property alias legend: legendText
    default property alias content: face.data

    readonly property bool dark: Theme.config.appearance === 'dark'
    readonly property bool tinted: root.hue.a > 0 && root.look === 'raised'
    readonly property bool raised: root.look === 'raised'
    readonly property bool pressed: root.look === 'pressed'
    // The legend's colour: the hue on a tinted key, quiet on a free one.
    readonly property color ink: root.tinted ? root.hue : root.look === 'flat' ? Theme.tokens.textMuted : Theme.tokens.text
    // Raised: a face lighter than the surface, brightest at its top edge.
    readonly property color restTop: root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.07)) : Qt.lighter(Theme.tokens.surface, 1.05)
    readonly property color restBottom: root.dark ? Qt.darker(Theme.tokens.surfaceOverlay, 1.08) : Qt.tint(Theme.tokens.surface, Qt.alpha(Theme.tokens.text, 0.03))
    readonly property color restHighlight: root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.16)) : root.restTop
    readonly property color lipColor: Qt.darker(root.base, root.dark ? 3.0 : 1.22)
    // Flat: a step below the surface. Pressed: the selected tone, one step up from the raised face.
    readonly property color sunkFace: root.pressed ? (root.dark ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.text, 0.14)) : Qt.darker(Theme.tokens.surfaceOverlay, 1.04)) : Qt.darker(root.base, root.dark ? 1.2 : 1.035)
    readonly property color sunkShade: Qt.darker(root.sunkFace, root.dark ? 1.5 : 1.08)
    // The face's three gradient stops before the hue and the state layer.
    readonly property color edgeTone: root.raised ? root.restHighlight : root.sunkShade
    readonly property color topTone: root.raised ? root.restTop : root.sunkFace
    readonly property color bottomTone: root.raised ? root.restBottom : root.sunkFace

    implicitWidth: Math.max(root.size, Math.ceil(legendText.implicitWidth) + 2 * Metrics.space2)
    implicitHeight: Math.max(root.size, Math.ceil(legendText.implicitHeight) + Metrics.space1 + root.lip)

    function shade(tone) {
        const hued = root.tinted ? Qt.tint(tone, Qt.alpha(root.hue, 0.14)) : tone;
        return root.stateLayer > 0 ? Qt.tint(hued, Qt.alpha(Theme.tokens.text, root.stateLayer)) : hued;
    }

    Rectangle {
        objectName: 'keycap-lip'
        visible: root.raised && root.lip > 0
        width: root.width
        height: root.height
        radius: Metrics.radiusSmall
        color: root.tinted ? Qt.tint(root.lipColor, Qt.alpha(root.hue, 0.1)) : root.lipColor
    }
    Rectangle {
        id: face
        objectName: 'keycap-face'
        y: root.pressed ? root.lip : 0
        width: root.width
        height: Math.max(0, root.look === 'flat' ? root.height : root.height - root.lip)
        radius: Metrics.radiusSmall
        // One pixel of highlight on a raised face; an inner shade along the top of a sunken one, as
        // deep as the lip on a pressed key.
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.shade(root.edgeTone)
            }
            GradientStop {
                position: Math.min(1, (root.raised ? 1 : root.pressed ? Math.max(2, root.lip) : 2) / Math.max(1, face.height))
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
            visible: root.text !== ''
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
    }
}
