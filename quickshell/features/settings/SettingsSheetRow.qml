import QtQuick
import qs.components
import qs.theme

// One row of a settings sheet: the name on the left, the control on the right, and an inline
// error under the control. At least Metrics.settingsRowMinHeight tall.
Item {
    id: root
    property string label: ""
    property string errorText: ""
    property real labelWidth: 112
    default property alias content: host.data
    implicitHeight: Math.max(Metrics.settingsRowMinHeight, host.childrenRect.height + (error.visible ? Metrics.space1 + error.implicitHeight : 0))
    Accessible.role: Accessible.Grouping
    Accessible.name: label

    PentadText {
        id: name
        x: 0
        y: Math.max(0, Math.round((Math.min(root.height, Metrics.settingsRowMinHeight) - height) / 2))
        width: root.labelWidth - Metrics.space3
        text: root.label
        textFormat: Text.PlainText
        font.weight: Font.Medium
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }
    Item {
        id: host
        x: root.labelWidth
        y: Math.max(0, Math.round((Metrics.settingsRowMinHeight - childrenRect.height) / 2))
        width: root.width - root.labelWidth
        height: childrenRect.height
    }
    PentadText {
        id: error
        x: root.labelWidth
        y: host.y + host.height + Metrics.space1
        width: host.width
        visible: root.errorText !== ""
        text: root.errorText
        textFormat: Text.PlainText
        role: "caption"
        color: Theme.tokens.error
    }
}
