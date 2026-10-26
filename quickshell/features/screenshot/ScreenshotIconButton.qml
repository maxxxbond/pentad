import QtQuick
import QtQuick.Controls.Basic
import qs.theme
import qs.components

PentadButton {
    id: control
    property string iconSource: ''
    property string helpText: accessibleName
    property bool emphasized: false
    property bool confirmed: false
    // The tip clears the toolbar edge: the toolbar padding plus a 6 px gap.
    property bool tipBeside: false
    property real tipOffset: 12
    readonly property color stateAccent: confirmed ? Theme.tokens.success : error ? Theme.tokens.error : Theme.tokens.accent
    property color foreground: confirmed || error || checked || emphasized ? stateAccent : visualFocus ? Theme.tokens.text : hovered || down ? Qt.alpha(Theme.tokens.text, 0.8) : Theme.tokens.textMuted
    readonly property color stateFill: visualFocus ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(stateAccent, 0.24)) : down ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(stateAccent, 0.18)) : checked || emphasized || confirmed ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(stateAccent, hovered ? 0.18 : 0.10)) : hovered ? Theme.tokens.surfaceOverlay : 'transparent'
    controlHeight: Metrics.controlSmall
    implicitWidth: text ? buttonContent.implicitWidth + 16 : controlHeight
    scale: down && !Theme.tokens.reducedMotion ? 0.97 : 1
    Behavior on scale {
        NumberAnimation {
            duration: Motion.short
        }
    }
    contentItem: Item {
        id: buttonContent
        implicitWidth: Metrics.exposedIcon + (control.text ? label.implicitWidth + 8 : 0)
        implicitHeight: Metrics.exposedIcon
        opacity: control.enabled || control.pending ? 1 : 0.35
        Row {
            anchors.centerIn: parent
            spacing: 8
            PentadIcon {
                source: control.iconSource
                pixelSize: Metrics.exposedIcon
                color: control.foreground
            }
            PentadText {
                id: label
                visible: !!control.text
                text: control.text
                color: control.visualFocus ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.8)
                wrapMode: Text.NoWrap
            }
        }
        Rectangle {
            visible: control.pending
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Metrics.exposedIcon
            height: 2
            color: control.stateAccent
            SequentialAnimation on opacity {
                running: control.pending && !Theme.tokens.reducedMotion
                loops: Animation.Infinite
                NumberAnimation {
                    from: 0.35
                    to: 1
                    duration: 800
                }
                NumberAnimation {
                    from: 1
                    to: 0.35
                    duration: 800
                }
            }
        }
    }
    background: ContinuousSurface {
        extent: height / 2
        fill: control.stateFill
        Behavior on fill {
            enabled: !Theme.tokens.reducedMotion
            ColorAnimation {
                duration: Motion.short
            }
        }
        opacity: control.enabled || control.pending ? 1 : 0.35
    }

    ToolTip {
        id: tip
        visible: (control.hovered || control.visualFocus) && !!control.helpText
        delay: control.hovered ? 450 : 0
        text: control.helpText
        padding: 0
        leftPadding: 10
        rightPadding: 10
        topPadding: 4
        bottomPadding: 4
        margins: 8
        contentItem: PentadText {
            role: 'caption'
            solid: true
            wrapMode: Text.NoWrap
            font.weight: Font.Medium
            text: tip.text
        }
        background: ContinuousSurface {
            extent: height / 2
            fill: Theme.tokens.surface
        }
        // Below (or beside, for a vertical toolbar), flipped when the window edge leaves no room.
        onAboutToShow: {
            const at = control.mapToItem(null, 0, 0);
            const w = implicitWidth, h = implicitHeight;
            if (control.tipBeside) {
                const after = at.x + control.width + control.tipOffset + w + margins <= control.Window.width;
                x = after ? control.width + control.tipOffset : -w - control.tipOffset;
                y = (control.height - h) / 2;
            } else {
                const below = at.y + control.height + control.tipOffset + h + margins <= control.Window.height;
                x = (control.width - w) / 2;
                y = below ? control.height + control.tipOffset : -h - control.tipOffset;
            }
        }
    }
}
