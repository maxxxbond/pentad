pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/control-model.mjs" as Controls

// The right-click menu of one grid control: details, edit mode, look and size.
AttachedPopover {
    id: menu
    required property var services
    required property var contextInfo
    required property var contextDefinition
    required property var contextPlacement
    required property string pendingSave
    required property string menuError
    required property int chosenColumns
    signal detailsRequested(string section)
    signal editRequested()
    signal templateRequested(string template)
    signal sizeRequested(int columns, int rows)
    signal resetRequested()

    objectName: "control-center-context-menu"
    manager: menu.services.popups || null

    function templateLabel(value) {
        const labels = {
            icon: ["Іконка", "Icon"], compact: ["Компактно", "Compact"],
            tile: ["Зі станом", "With status"], row: ["Рядок", "Row"],
            vertical: ["Вертикально", "Vertical"]
        };
        const label = labels[value];
        return label ? menu.services.text(label[0], label[1]) : value;
    }

    function sizesFor(template) {
        const half = Math.ceil(menu.chosenColumns / 2);
        if (template === "tile") return [{ columns: half, rows: 2 }, { columns: menu.chosenColumns, rows: 2 }];
        if (template === "vertical") {
            const third = Controls.minimumTemplateColumns(template, menu.chosenColumns);
            return [{ columns: third, rows: 2 }, { columns: third, rows: 3 }];
        }
        if (template === "row" || template === "compact") return [{ columns: half, rows: 1 }, { columns: menu.chosenColumns, rows: 1 }];
        return [{ columns: 1, rows: 1 }, { columns: half, rows: 1 }, { columns: menu.chosenColumns, rows: 1 }];
    }

    contentItem: Column {
        spacing: 4
        width: 220
        PentadText {
            width: parent.width
            text: menu.contextInfo.title || ""
            role: "caption"
        }
        PentadButton {
            width: parent.width
            visible: !!menu.contextInfo.section
            text: menu.services.text("Деталі", "Details")
            onPressed: { menu.close(); menu.detailsRequested(menu.contextInfo.section); }
        }
        PentadButton {
            objectName: "control-center-context-edit"
            width: parent.width
            text: menu.services.text("Редагувати сітку", "Edit grid")
            onPressed: menu.editRequested()
        }
        PentadText { text: menu.services.text("Вигляд", "Appearance"); role: "caption" }
        PentadToggle {
            width: parent.width
            text: menu.services.text("Діагностика геометрії", "Geometry diagnostics")
            accessibleName: text
            checked: GeometryDiagnostics.enabled
            onToggled: GeometryDiagnostics.enabled = checked
        }
        Flow {
            width: parent.width
            spacing: 4
            Repeater {
                model: menu.contextDefinition ? menu.contextDefinition.templates : []
                PentadButton {
                    required property string modelData
                    text: menu.templateLabel(modelData)
                    checked: !!menu.contextPlacement && menu.contextPlacement.template === modelData
                    controlHeight: 28
                    requestedEnabled: !menu.pendingSave
                    onPressed: menu.templateRequested(modelData)
                }
            }
        }
        PentadText { text: menu.services.text("Розмір у клітинках", "Size in cells"); role: "caption" }
        Row {
            spacing: 4
            Repeater {
                model: menu.contextPlacement ? menu.sizesFor(menu.contextPlacement.template) : []
                PentadButton {
                    required property var modelData
                    text: modelData.columns + " × " + modelData.rows
                    controlHeight: 28
                    checked: !!menu.contextPlacement && menu.contextPlacement.columnSpan === modelData.columns
                        && menu.contextPlacement.rowSpan === modelData.rows
                    requestedEnabled: !menu.pendingSave
                    onPressed: menu.sizeRequested(modelData.columns, modelData.rows)
                }
            }
        }
        PentadButton {
            width: parent.width
            text: menu.services.text("Скинути сітку", "Reset grid")
            controlHeight: 28
            requestedEnabled: !menu.pendingSave
            onPressed: menu.resetRequested()
        }
        PentadText {
            width: parent.width
            visible: menu.menuError !== ""
            text: menu.menuError
            color: Theme.tokens.error
            wrapMode: Text.Wrap
            role: "caption"
        }
    }
}
