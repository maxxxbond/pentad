pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

ContinuousSurface {
    id: root
    required property var services
    property bool horizontal: true
    property string tool: 'select'
    property string selectedType: ''
    property string annotationColor: '#ff5252'
    property real strokeWidth: 4
    property real fontSize: 24
    property bool busy: false
    property string pendingAction: ''
    property bool copied: false
    property bool canUndo: false
    property bool canRedo: false
    readonly property string parameterTool: tool === 'select' ? selectedType : tool
    readonly property bool hasColor: !!parameterTool && parameterTool !== 'crop' && parameterTool !== 'select'
    readonly property bool hasWidth: hasColor && parameterTool !== 'text' && parameterTool !== 'redact'
    readonly property bool hasFontSize: parameterTool === 'text'
    readonly property int padding: 6
    readonly property real thickness: Metrics.controlSmall + 2 * padding
    readonly property real length: Math.max(body.implicitWidth, body.implicitHeight) + 2 * padding
    readonly property bool dragging: gripArea.pressed
    readonly property alias paletteMenu: colorPopup
    signal toolChosen(string tool)
    signal colorChosen(string color)
    signal widthChosen(real width)
    signal fontSizeChosen(real size)
    signal undoRequested
    signal redoRequested
    signal copyRequested
    signal saveRequested
    signal closeRequested
    signal dragged(real x, real y, real grabAlong)
    readonly property var frameTools: [
        {
            id: 'select',
            icon: 'near-me',
            uk: 'Вибір',
            en: 'Select'
        },
        {
            id: 'crop',
            icon: 'crop',
            uk: 'Обрізати',
            en: 'Crop'
        }
    ]
    readonly property var drawTools: [
        {
            id: 'brush',
            icon: 'edit',
            uk: 'Пензель',
            en: 'Brush'
        },
        {
            id: 'highlight',
            icon: 'ink-highlighter',
            uk: 'Маркер',
            en: 'Highlight'
        },
        {
            id: 'line',
            icon: 'horizontal-rule',
            uk: 'Лінія',
            en: 'Line'
        },
        {
            id: 'arrow',
            icon: 'north-east',
            uk: 'Стрілка',
            en: 'Arrow'
        },
        {
            id: 'rectangle',
            icon: 'rectangle',
            uk: 'Прямокутник',
            en: 'Rectangle'
        },
        {
            id: 'ellipse',
            icon: 'circle',
            uk: 'Еліпс',
            en: 'Ellipse'
        },
        {
            id: 'text',
            icon: 'text-fields',
            uk: 'Текст',
            en: 'Text'
        },
        {
            id: 'redact',
            icon: 'format-color-fill',
            uk: 'Приховати',
            en: 'Redact'
        }
    ]
    readonly property var inkColors: ['#ff5252', '#ffb74d', '#fff176', '#81c784', '#64b5f6', '#7986cb', '#ba68c8', '#ffffff', '#9e9e9e', '#111111']
    readonly property var strokePresets: [2, 4, 8, 12, 20]
    readonly property var fontPresets: [14, 18, 24, 36, 48]
    function icon(name) {
        return Qt.resolvedUrl('../../assets/icons/material/screenshot/' + name + '-symbolic.svg');
    }
    function help(label, action) {
        const key = services.config.documents.screenshots?.localKeys?.[action] || '';
        return label + (key ? ' · ' + key : '');
    }
    function inkOn(color) {
        const hex = String(color).replace('#', '');
        if (hex.length !== 6)
            return '#ffffff';
        const r = parseInt(hex.slice(0, 2), 16), g = parseInt(hex.slice(2, 4), 16), b = parseInt(hex.slice(4, 6), 16);
        return 0.299 * r + 0.587 * g + 0.114 * b > 150 ? '#111111' : '#ffffff';
    }
    function placePopup(popup, trigger) {
        const host = root.parent;
        const at = trigger.mapToItem(root, 0, 0);
        const w = popup.implicitWidth, h = popup.implicitHeight;
        const hostWidth = host ? host.width : w, hostHeight = host ? host.height : h;
        const clamp = function (value, low, high) {
            return Math.max(low, Math.min(high, value));
        };
        if (horizontal) {
            popup.x = clamp(at.x + trigger.width / 2 - w / 2, 8 - root.x, hostWidth - root.x - w - 8);
            popup.y = root.y + root.height + 6 + h + 8 <= hostHeight ? root.height + 6 : -h - 6;
        } else {
            popup.x = root.x + root.width + 6 + w + 8 <= hostWidth ? root.width + 6 : -w - 6;
            popup.y = clamp(at.y + trigger.height / 2 - h / 2, 8 - root.y, hostHeight - root.y - h - 8);
        }
    }
    width: horizontal ? length : thickness
    height: horizontal ? thickness : length
    extent: 14
    fill: Theme.tokens.surface
    edge: Qt.alpha(Theme.tokens.text, 0.08)
    clipContent: false
    onVisibleChanged: {
        if (!visible) {
            colorPopup.close();
            sizePopup.close();
        }
    }
    onHasColorChanged: {
        if (!hasColor)
            colorPopup.close();
    }
    onHasWidthChanged: {
        if (!hasWidth && !hasFontSize)
            sizePopup.close();
    }
    onBusyChanged: {
        if (busy) {
            colorPopup.close();
            sizePopup.close();
        }
    }
    onHorizontalChanged: {
        colorPopup.close();
        sizePopup.close();
    }

    component Divider: Rectangle {
        property bool horizontal: true
        Layout.alignment: Qt.AlignCenter
        Layout.leftMargin: horizontal ? 4 : 0
        Layout.rightMargin: horizontal ? 4 : 0
        Layout.topMargin: horizontal ? 0 : 4
        Layout.bottomMargin: horizontal ? 0 : 4
        implicitWidth: horizontal ? 1 : Metrics.controlSmall - 10
        implicitHeight: horizontal ? Metrics.controlSmall - 10 : 1
        color: Qt.alpha(Theme.tokens.text, 0.14)
    }

    GridLayout {
        id: body
        x: root.padding
        y: root.padding
        flow: root.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rows: 64
        columns: 64
        rowSpacing: 2
        columnSpacing: 2

        Item {
            id: grip
            Layout.preferredWidth: root.horizontal ? 14 : Metrics.controlSmall
            Layout.preferredHeight: root.horizontal ? Metrics.controlSmall : 14
            Accessible.name: root.services.text('Перемістити панель', 'Move toolbar')
            Grid {
                anchors.centerIn: parent
                columns: root.horizontal ? 2 : 3
                spacing: 3
                Repeater {
                    model: 6
                    Rectangle {
                        width: 3
                        height: 3
                        radius: 1.5
                        color: gripArea.pressed || gripArea.containsMouse ? Theme.tokens.text : Theme.tokens.textMuted
                    }
                }
            }
            MouseArea {
                id: gripArea
                property real grabAlong: 0
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                enabled: !root.busy
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function (mouse) {
                    const p = mapToItem(root, mouse.x, mouse.y);
                    grabAlong = root.horizontal ? p.x : p.y;
                    colorPopup.close();
                    sizePopup.close();
                }
                onPositionChanged: function (mouse) {
                    if (!pressed || !root.parent)
                        return;
                    const p = mapToItem(root.parent, mouse.x, mouse.y);
                    root.dragged(p.x, p.y, grabAlong);
                }
            }
        }

        Repeater {
            model: root.frameTools
            ScreenshotIconButton {
                required property var modelData
                iconSource: root.icon(modelData.icon)
                accessibleName: root.services.text(modelData.uk, modelData.en)
                helpText: root.help(accessibleName, modelData.id)
                checkable: true
                checked: root.tool === modelData.id
                requestedEnabled: !root.busy
                onClicked: root.toolChosen(modelData.id)
            }
        }
        Divider {
            horizontal: root.horizontal
        }
        Repeater {
            model: root.drawTools
            ScreenshotIconButton {
                required property var modelData
                iconSource: root.icon(modelData.icon)
                accessibleName: root.services.text(modelData.uk, modelData.en)
                helpText: root.help(accessibleName, modelData.id)
                checkable: true
                checked: root.tool === modelData.id
                requestedEnabled: !root.busy
                onClicked: root.toolChosen(modelData.id)
            }
        }
        Divider {
            horizontal: root.horizontal
        }

        ScreenshotIconButton {
            id: colorChip
            accessibleName: root.services.text('Колір', 'Color') + ' ' + root.annotationColor
            checked: colorPopup.visible
            requestedEnabled: root.hasColor && !root.busy
            onClicked: colorPopup.visible ? colorPopup.close() : colorPopup.open()
            contentItem: Item {
                implicitWidth: Metrics.exposedIcon
                implicitHeight: Metrics.exposedIcon
                opacity: colorChip.enabled ? 1 : 0.35
                Rectangle {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    radius: 5
                    color: root.annotationColor
                    border.width: 1
                    border.color: Qt.alpha(Theme.tokens.text, 0.35)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 4
                        color: 'transparent'
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.25)
                    }
                }
            }
        }
        ScreenshotIconButton {
            id: sizeChip
            accessibleName: root.hasFontSize ? root.services.text('Розмір тексту', 'Text size') + ' ' + root.fontSize : root.services.text('Товщина', 'Stroke width') + ' ' + root.strokeWidth
            checked: sizePopup.visible
            requestedEnabled: (root.hasWidth || root.hasFontSize) && !root.busy
            onClicked: sizePopup.visible ? sizePopup.close() : sizePopup.open()
            contentItem: Item {
                implicitWidth: Metrics.exposedIcon
                implicitHeight: Metrics.exposedIcon
                opacity: sizeChip.enabled ? 1 : 0.35
                Rectangle {
                    visible: !root.hasFontSize
                    anchors.centerIn: parent
                    readonly property real diameter: Math.max(5, Math.min(16, 3 + root.strokeWidth * 0.75))
                    width: diameter
                    height: diameter
                    radius: diameter / 2
                    color: sizeChip.checked ? Theme.tokens.accent : Theme.tokens.text
                }
                PentadText {
                    visible: root.hasFontSize
                    anchors.centerIn: parent
                    role: 'caption'
                    wrapMode: Text.NoWrap
                    font.features: ({
                            'tnum': 1
                        })
                    color: sizeChip.checked ? Theme.tokens.accent : Theme.tokens.text
                    text: Math.round(root.fontSize)
                }
            }
        }
        Divider {
            horizontal: root.horizontal
        }

        ScreenshotIconButton {
            iconSource: root.icon('undo')
            accessibleName: root.services.text('Скасувати', 'Undo')
            helpText: root.help(accessibleName, 'undo')
            requestedEnabled: root.canUndo && !root.busy
            onClicked: root.undoRequested()
        }
        ScreenshotIconButton {
            iconSource: root.icon('redo')
            accessibleName: root.services.text('Повторити', 'Redo')
            helpText: root.help(accessibleName, 'redo')
            requestedEnabled: root.canRedo && !root.busy
            onClicked: root.redoRequested()
        }
        Divider {
            horizontal: root.horizontal
        }

        ScreenshotIconButton {
            iconSource: root.icon('save')
            accessibleName: root.services.text('Зберегти', 'Save')
            helpText: root.help(accessibleName, 'save')
            pending: root.busy && root.pendingAction === 'save'
            requestedEnabled: !root.busy
            onClicked: root.saveRequested()
        }
        ScreenshotIconButton {
            emphasized: true
            confirmed: root.copied
            iconSource: root.icon(root.copied ? 'check' : 'content-copy')
            accessibleName: root.services.text('Копіювати', 'Copy')
            helpText: root.help(accessibleName, 'copy')
            pending: root.busy && root.pendingAction === 'copy'
            requestedEnabled: !root.busy
            onClicked: root.copyRequested()
        }
        ScreenshotIconButton {
            iconSource: Qt.resolvedUrl('../../assets/icons/material/media/close-symbolic.svg')
            accessibleName: root.services.text('Закрити', 'Close')
            helpText: root.help(accessibleName, 'cancel')
            requestedEnabled: !root.busy
            onClicked: root.closeRequested()
        }
    }

    PentadPopup {
        id: colorPopup
        padding: 8
        implicitWidth: 5 * Metrics.controlSmall + 4 * 4 + 16
        implicitHeight: 2 * Metrics.controlSmall + 4 + 16
        background: ContinuousSurface {
            extent: 14
            fill: Theme.tokens.surfaceRaised
            edge: Qt.alpha(Theme.tokens.text, 0.08)
        }
        contentItem: Grid {
            columns: 5
            spacing: 4
            Repeater {
                id: swatches
                model: root.inkColors
                ScreenshotIconButton {
                    id: swatchButton
                    required property string modelData
                    readonly property bool current: root.annotationColor.toLowerCase() === modelData.toLowerCase()
                    iconSource: current ? root.icon('check') : ''
                    foreground: root.inkOn(modelData)
                    accessibleName: root.services.text('Колір ', 'Color ') + modelData
                    helpText: ''
                    checked: current
                    background: Rectangle {
                        radius: height / 2
                        color: swatchButton.modelData
                        border.width: swatchButton.visualFocus || swatchButton.hovered ? 2 : 1
                        border.color: swatchButton.visualFocus || swatchButton.hovered ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.2)
                    }
                    onClicked: {
                        root.colorChosen(modelData);
                        colorPopup.close();
                    }
                }
            }
        }
        onAboutToShow: root.placePopup(colorPopup, colorChip)
        onOpened: {
            const index = root.inkColors.indexOf(root.annotationColor.toLowerCase());
            const swatch = swatches.itemAt(Math.max(0, index));
            if (swatch)
                swatch.forceActiveFocus();
        }
        onClosed: {
            if (root.visible && colorChip.enabled)
                colorChip.forceActiveFocus();
        }
    }

    PentadPopup {
        id: sizePopup
        readonly property var presets: root.hasFontSize ? root.fontPresets : root.strokePresets
        padding: 8
        implicitWidth: 5 * Metrics.controlSmall + 4 * 4 + 16
        implicitHeight: 2 * Metrics.controlSmall + 8 + 16
        background: ContinuousSurface {
            extent: 14
            fill: Theme.tokens.surfaceRaised
            edge: Qt.alpha(Theme.tokens.text, 0.08)
        }
        contentItem: Column {
            spacing: 8
            Row {
                spacing: 4
                Repeater {
                    model: sizePopup.presets
                    ScreenshotIconButton {
                        id: presetButton
                        required property real modelData
                        readonly property real current: root.hasFontSize ? root.fontSize : root.strokeWidth
                        accessibleName: String(modelData)
                        helpText: ''
                        checked: current === modelData
                        onClicked: root.hasFontSize ? root.fontSizeChosen(modelData) : root.widthChosen(modelData)
                        contentItem: Item {
                            implicitWidth: Metrics.exposedIcon
                            implicitHeight: Metrics.exposedIcon
                            Rectangle {
                                visible: !root.hasFontSize
                                anchors.centerIn: parent
                                readonly property real diameter: Math.max(4, Math.min(18, 3 + presetButton.modelData * 0.75))
                                width: diameter
                                height: diameter
                                radius: diameter / 2
                                color: presetButton.checked ? Theme.tokens.accent : Theme.tokens.text
                            }
                            PentadText {
                                visible: root.hasFontSize
                                anchors.centerIn: parent
                                role: 'caption'
                                wrapMode: Text.NoWrap
                                color: presetButton.checked ? Theme.tokens.accent : Theme.tokens.text
                                text: presetButton.modelData
                            }
                        }
                    }
                }
            }
            PentadSpinBox {
                id: sizeControl
                width: parent.width
                implicitHeight: Metrics.controlSmall
                from: root.hasFontSize ? 8 : 1
                to: root.hasFontSize ? 144 : 48
                stepSize: root.hasFontSize ? 2 : 1
                value: root.hasFontSize ? root.fontSize : root.strokeWidth
                enabled: !root.busy
                accessibleName: root.hasFontSize ? root.services.text('Розмір тексту', 'Text size') : root.services.text('Товщина', 'Stroke width')
                font.features: ({
                        'tnum': 1
                    })
                onValueModified: root.hasFontSize ? root.fontSizeChosen(value) : root.widthChosen(value)
                background: ContinuousSurface {
                    extent: 8
                    fill: sizeControl.activeFocus ? Qt.tint(Theme.tokens.surfaceOverlay, Qt.alpha(Theme.tokens.accent, 0.20)) : sizeControl.hovered ? Theme.tokens.surfaceOverlay : Theme.tokens.surface
                }
                up.indicator: PentadIcon {
                    color: sizeControl.up.pressed || sizeControl.up.hovered || sizeControl.activeFocus ? Theme.tokens.accent : Theme.tokens.textMuted
                    x: sizeControl.width - 36
                    width: 16
                    height: sizeControl.height
                    source: Qt.resolvedUrl('../../assets/icons/material/media/add-symbolic.svg')
                }
                down.indicator: PentadIcon {
                    color: sizeControl.down.pressed || sizeControl.down.hovered || sizeControl.activeFocus ? Theme.tokens.accent : Theme.tokens.textMuted
                    x: sizeControl.width - 20
                    width: 16
                    height: sizeControl.height
                    source: Qt.resolvedUrl('../../assets/icons/material/media/remove-symbolic.svg')
                }
            }
        }
        onAboutToShow: root.placePopup(sizePopup, sizeChip)
        onOpened: sizeControl.forceActiveFocus()
        onClosed: {
            if (root.visible && sizeChip.enabled)
                sizeChip.forceActiveFocus();
        }
    }
}
