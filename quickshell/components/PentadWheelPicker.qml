import QtQuick
import qs.theme
import "../logic/wheel-picker.mjs" as Wheel

// A wheel picker: one or more drums side by side behind one selection band, like a time picker.
// `columns` is a list of { id, label, options, loop, width }; `value` maps a column id to its
// chosen option (a string in `options`). The owner binds `value` and updates it from edited():
//
//     PentadWheelPicker {
//         columns: [{ id: "hour", label: "Hour", options: hours, loop: true }]
//         value: ({ hour: settings.hour })
//         onEdited: (column, option) => settings.hour = option
//     }
//
// Dragging, flicking, the mouse wheel, tapping a row and the keyboard all work; see
// PentadWheelColumn for the details.
Item {
    id: root
    property var columns: []
    property var value: ({})
    property string accessibleName: ""
    signal edited(string column, string option)

    // The column with this id, for hosts and tests.
    function column(id) {
        for (let i = 0; i < columns.length; i++) {
            if (columns[i].id === id)
                return cells.itemAt(i);
        }
        return null;
    }

    implicitWidth: strip.implicitWidth
    implicitHeight: Wheel.drumHeight
    Accessible.role: Accessible.Grouping
    Accessible.name: accessibleName

    Rectangle {
        x: Metrics.space2
        y: (root.height - Wheel.itemHeight) / 2
        width: root.width - Metrics.space2 * 2
        height: Wheel.itemHeight
        radius: Metrics.radiusMedium
        color: Qt.alpha(Theme.tokens.text, 0.08)
    }

    Row {
        id: strip
        anchors.centerIn: parent
        Repeater {
            id: cells
            model: root.columns
            delegate: PentadWheelColumn {
                required property var modelData
                showBand: false
                options: modelData.options ?? []
                loop: modelData.loop === true
                width: modelData.width ?? 64
                selectedIndex: Math.max(0, options.indexOf(root.value ? root.value[modelData.id] : undefined))
                accessibleName: modelData.label ?? ""
                onMoved: index => root.edited(modelData.id, String(options[index]))
            }
        }
    }
}
