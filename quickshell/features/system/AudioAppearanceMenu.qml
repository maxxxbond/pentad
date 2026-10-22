pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/control-model.mjs" as Controls

// The right-click / menu-key popover of AudioControls: jump to the device list and pick how
// the control looks. Opening and anchoring is driven by the owner through anchorItem/open/toggle.
AttachedPopover {
    id: menu
    required property var services
    property bool layoutManaged: false
    property string presentation: "range-horizontal"
    property string contextKind: "output"
    property string appearanceRequest: ""
    property string appearanceError: ""

    signal detailsRequested(string section)
    signal presentationRequested(string value)

    function savePresentation(value) {
        if (layoutManaged) { menu.close(); presentationRequested(value); return; }
        if (appearanceRequest || !Controls.supportsTemplate(Controls.builtinDefinitions["audio-output"], value)) return;
        appearanceRequest = services.config.save("layout", Object.assign({}, services.config.documents.layout,
            { audioPresentation: value }));
    }

    manager: services.popups || null
    contentItem: Column {
        width: 228
        spacing: 4
        PentadButton {
            width: parent.width
            text: menu.services.text("Обрати пристрій", "Choose device")
            onPressed: { menu.close(); menu.detailsRequested("audio-" + menu.contextKind); }
        }
        PentadText { text: menu.services.text("Вигляд", "Appearance"); role: "caption" }
        Flow {
            width: parent.width
            spacing: 4
            Repeater {
                model: [
                    { value: "range-horizontal", uk: "Горизонтально", en: "Horizontal" },
                    { value: "range-vertical", uk: "Вертикально", en: "Vertical" },
                    { value: "icon", uk: "Іконка", en: "Icon" },
                    { value: "tile", uk: "Плитка", en: "Tile" }
                ].filter(function(option) { return !menu.layoutManaged || option.value.indexOf("range-") === 0; })
                PentadButton {
                    required property var modelData
                    text: menu.services.text(modelData.uk, modelData.en)
                    controlHeight: 28
                    checked: menu.presentation === modelData.value
                    requestedEnabled: !menu.appearanceRequest
                    onPressed: menu.savePresentation(modelData.value)
                }
            }
        }
        PentadText { width: parent.width; text: menu.appearanceError; visible: text !== ""; role: "caption"; color: Theme.tokens.error }
    }

    Connections {
        target: menu.services.config
        function onCommandFinished(requestId, result) {
            if (requestId !== menu.appearanceRequest) return;
            menu.appearanceRequest = "";
            menu.appearanceError = result.ok ? "" : result.message || result.reason;
            if (result.ok) menu.close();
        }
    }
}
