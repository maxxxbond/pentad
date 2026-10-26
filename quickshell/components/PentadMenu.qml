import QtQuick
import QtQuick.Controls.Basic
import qs.theme

Menu {
    id: control

    property var entries: []
    property Item intentAnchor: null
    // Leaving the menu with the pointer closes it. A menu opened at a click in a window that cannot
    // map its items to output coordinates (a floating window, a full-output overlay) turns this off
    // and closes on a press outside or Escape instead.
    property bool pointerDismiss: true
    signal activated(var entry)

    function openFor(anchor) {
        if (anchor) {
            intentAnchor = anchor
            popup(anchor, 0, anchor.height)
        }
    }

    MenuPointerIntent {
        active: control.visible
        pointerDismissEnabled: control.pointerDismiss
        anchorItem: control.intentAnchor
        surfaceItem: control.contentItem
        onDismissRequested: control.close()
    }

    padding: 4
    spacing: 0

    background: ContinuousSurface {
        fill: Theme.tokens.surfaceRaised
        extent: Metrics.radiusLarge
    }

    Instantiator {
        model: control.entries

        delegate: MenuItem {
            id: row
            required property var modelData
            readonly property bool separator: modelData.separator === true

            text: separator ? "" : (modelData.text || "")
            enabled: !separator && modelData.enabled !== false
            checkable: !separator && modelData.checkable === true
            checked: checkable && modelData.checked === true
            Accessible.description: modelData.description || ""
            implicitHeight: separator ? 7 : 30
            padding: 0
            leftPadding: separator ? 0 : 10
            rightPadding: separator ? 0 : 10

            contentItem: Item {
                Text {
                    anchors.fill: parent
                    visible: !row.separator
                    text: row.text
                    color: row.enabled ? (row.highlighted ? Theme.tokens.text : Theme.tokens.textMuted) : Theme.tokens.textMuted
                    font.family: Theme.tokens.fontFamily
                    font.pixelSize: Metrics.textBody
                    font.weight: row.checked ? Font.DemiBold : Font.Normal
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                PentadSeparator {
                    anchors.fill: parent
                    visible: row.separator
                }
            }

            background: ContinuousSurface {
                fill: !row.separator && row.highlighted ? Qt.alpha(Theme.tokens.text, 0.08) : "transparent"
                extent: Metrics.radiusMedium
                opacity: row.enabled ? 1 : 0.4
            }

            onTriggered: if (!separator) { control.close(); control.activated(modelData); }

            PentadHint {
                axis: "horizontal"
                text: row.separator ? "" : (row.modelData.description || "")
                shown: row.hovered || row.activeFocus
                delay: row.hovered ? Metrics.tooltipDelay : 0
            }
        }

        onObjectAdded: function(index, object) { control.insertItem(index, object) }
        onObjectRemoved: function(index, object) { control.removeItem(object) }
    }
}
