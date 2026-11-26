pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/screenshot-settings.mjs" as Settings

// The screenshot settings dialog body: title row, sectioned form (saving, global and editor
// shortcuts, the Hyprland fragment) and an action bar. Edits land in a draft; Save validates
// and writes the `screenshots` document, Export writes the Hyprland fragment.
Item {
    id: root
    required property var services
    property bool ownerVisible: true
    signal closeRequested()

    readonly property var stored: services.config.documents.screenshots || Settings.screenshotDefaults
    property var draft: JSON.parse(JSON.stringify(stored))
    property string pendingId: ''
    property bool exporting: false
    property string message: ''
    property bool failed: false
    readonly property bool dirty: JSON.stringify(draft) !== JSON.stringify(stored)
    readonly property real gutter: 24
    readonly property real barHeight: 64

    function tr(uk, en) { return services.text(uk, en); }
    function edit(key, value) {
        draft = Object.assign({}, draft, { [key]: value });
        message = '';
        failed = false;
    }
    function shortcut(group, key, value) {
        edit(group, Object.assign({}, draft[group], { [key]: value }));
    }
    function validated() {
        try {
            const value = Settings.parseScreenshotSettings(draft);
            failed = false;
            message = '';
            return value;
        } catch (error) {
            failed = true;
            message = tr('Перевір комбінації та значення: ', 'Check shortcuts and values: ') + error.message;
            return null;
        }
    }
    function save() {
        const value = validated();
        if (value && !pendingId) pendingId = services.config.save('screenshots', value);
    }
    function exportBindings() {
        const value = validated();
        if (!value) return;
        if (services.screenshot.exportBindings(Settings.hyprlandScreenshotBindings(value))) exporting = true;
        else {
            failed = true;
            message = tr('Експорт недоступний.', 'Export is unavailable.');
        }
    }
    function restoreDefaults() {
        draft = JSON.parse(JSON.stringify(Settings.screenshotDefaults));
        failed = false;
        message = tr('Типові значення повернуто. Збережіть, щоб застосувати.', 'Defaults restored. Save to apply.');
    }

    readonly property var localLabels: ({
        select: tr('Вибір', 'Select'), brush: tr('Пензель', 'Brush'), line: tr('Лінія', 'Line'), arrow: tr('Стрілка', 'Arrow'),
        rectangle: tr('Прямокутник', 'Rectangle'), ellipse: tr('Еліпс', 'Ellipse'), text: tr('Текст', 'Text'),
        highlight: tr('Маркер', 'Highlight'), redact: tr('Приховати', 'Redact'), crop: tr('Обрізати', 'Crop'),
        undo: tr('Скасувати дію', 'Undo'), redo: tr('Повторити дію', 'Redo'), copy: tr('Копіювати', 'Copy'),
        save: tr('Зберегти', 'Save'), accept: tr('Копіювати й закрити', 'Copy and close'), cancel: tr('Закрити', 'Close'),
        delete: tr('Видалити', 'Delete')
    })
    readonly property var globalLabels: ({
        edit: tr('Область із редагуванням', 'Region and editor'), copy: tr('Швидка область', 'Quick region'),
        window: tr('Активне вікно', 'Active window'), monitor: tr('Поточний монітор', 'Current monitor')
    })
    readonly property var globalKeys: Object.keys(Settings.screenshotDefaults.globalKeys)
    readonly property var localKeys: Object.keys(Settings.screenshotDefaults.localKeys)

    Connections {
        target: root.services.config
        function onCommandFinished(id, result) {
            if (id !== root.pendingId) return;
            root.pendingId = '';
            root.failed = !result.ok;
            root.message = result.ok ? root.tr('Налаштування збережено.', 'Settings saved.') : result.message || result.reason;
            if (result.ok) root.draft = JSON.parse(JSON.stringify(root.stored));
        }
    }
    Connections {
        target: root.services.screenshot
        function onBindingsExported(result) {
            root.exporting = false;
            root.failed = !result.ok;
            root.message = result.ok ? root.tr('Фрагмент збережено: ', 'Fragment saved: ') + result.path
                : result.error || root.tr('Не вдалося експортувати.', 'Could not export.');
        }
    }

    Item {
        id: header
        objectName: "screenshot-settings-header"
        x: 0
        y: 0
        width: parent.width
        height: root.barHeight
        PentadIcon {
            id: titleIcon
            x: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl("../../assets/icons/material/screenshot-region-symbolic.svg")
            pixelSize: Metrics.statusIcon
            color: Theme.tokens.accent
        }
        PentadText {
            anchors.left: titleIcon.right
            anchors.leftMargin: 12
            anchors.right: closeButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.tr('Знімки екрана', 'Screenshots')
            textFormat: Text.PlainText
            role: "title"
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            Accessible.role: Accessible.Heading
        }
        PentadButton {
            id: closeButton
            objectName: "screenshot-settings-close"
            anchors.right: parent.right
            anchors.rightMargin: root.gutter - 4
            anchors.verticalCenter: parent.verticalCenter
            iconSource: Qt.resolvedUrl('../../assets/icons/material/close-symbolic.svg')
            iconSize: Metrics.panelIcon
            controlHeight: Metrics.controlSmall
            implicitWidth: Metrics.controlSmall
            accessibleName: root.tr('Закрити', 'Close')
            background: Rectangle {
                radius: height / 2
                color: closeButton.down ? Theme.tokens.surfaceOverlay : closeButton.hovered ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
                border.width: closeButton.visualFocus ? 2 : 0
                border.color: Theme.tokens.accent
            }
            onClicked: root.closeRequested()
        }
    }

    PentadScrollView {
        id: scroll
        x: 0
        y: header.height
        width: parent.width
        height: Math.max(0, parent.height - header.height - footer.height)
        contentWidth: availableWidth
        clip: true
        Column {
            id: body
            x: root.gutter
            width: Math.max(0, scroll.availableWidth - 2 * root.gutter)
            topPadding: 20
            bottomPadding: 24
            spacing: 24

            SettingsSection {
                width: body.width
                title: root.tr('Збереження', 'Saving')
                SettingsRow {
                    width: parent.width
                    label: root.tr('Папка', 'Folder')
                    helpText: root.tr('Абсолютний шлях. Порожнє поле означає Зображення/Pentad.', 'An absolute path. Empty means Pictures/Pentad.')
                    infoAccessibleName: root.tr('Про папку', 'About the folder')
                    PentadTextField {
                        id: directoryField
                        objectName: "screenshot-directory"
                        width: parent.width
                        implicitWidth: Metrics.settingsFieldWidth
                        implicitHeight: Metrics.controlSmall
                        capsule: Metrics.settingsFieldCapsule
                        fill: Theme.tokens.surfaceOverlay
                        text: root.draft.directory
                        accessibleName: root.tr('Папка скріншотів', 'Screenshot folder')
                        placeholderText: root.tr('Зображення/Pentad', 'Pictures/Pentad')
                        onTextEdited: root.edit('directory', text)
                    }
                }
                SettingsRow {
                    width: parent.width
                    label: root.tr('Також зберігати файл після копіювання', 'Also save a file when copying')
                    PentadToggle {
                        objectName: "screenshot-autosave"
                        implicitHeight: Metrics.controlSmall
                        checked: root.draft.autoSave
                        accessibleName: root.tr('Також зберігати файл після копіювання', 'Also save a file when copying')
                        onToggled: root.edit('autoSave', checked)
                    }
                }
            }

            SettingsSection {
                id: globalSection
                width: body.width
                title: root.tr('Глобальні комбінації', 'Global shortcuts')
                helpText: root.tr('Після зміни збережи налаштування й експортуй фрагмент. Підключи його до конфігурації Hyprland. Задані комбінації замінять попередні прив’язки.',
                    'After changing keys, save settings and export the fragment. Source it in your Hyprland configuration. The configured combinations replace their previous bindings.')
                infoAccessibleName: root.tr('Про глобальні комбінації', 'About global shortcuts')
                Repeater {
                    model: root.globalKeys
                    delegate: SettingsRow {
                        id: globalRow
                        required property string modelData
                        width: globalSection.width
                        label: root.globalLabels[modelData]
                        SettingsShortcutField {
                            objectName: "screenshot-global-" + globalRow.modelData
                            width: parent.width
                            value: root.draft.globalKeys[globalRow.modelData] || ''
                            accessibleName: globalRow.label
                            recordLabel: root.tr('Записати', 'Record')
                            cancelLabel: root.tr('Скасувати', 'Cancel')
                            clearLabel: root.tr('Очистити', 'Clear')
                            pressText: root.tr('Натисніть клавіші', 'Press keys')
                            disabledText: root.tr('Вимкнено', 'Off')
                            modifierText: root.tr('Додайте модифікатор: Super або Alt.', 'Add a modifier, like Super or Alt.')
                            invalidText: root.tr('Цю клавішу не можна призначити.', 'That key cannot be bound.')
                            clearable: true
                            onCommitted: function(shortcut) { root.shortcut('globalKeys', globalRow.modelData, shortcut); }
                        }
                    }
                }
            }

            SettingsSection {
                id: editorSection
                width: body.width
                title: root.tr('Клавіші в редакторі', 'Editor shortcuts')
                helpText: root.tr('Діють лише поки відкритий редактор, тому тут достатньо однієї клавіші. Натисніть клавішу, щоб перепризначити.',
                    'Active only while the editor is open, so a single key is enough. Click a key to rebind it.')
                infoAccessibleName: root.tr('Про клавіші редактора', 'About editor shortcuts')
                // Editor keys on the section card as a grid, two per line where there is room;
                // cells are told apart by thin separator lines. The grid keeps the rows' two lines:
                // the first label starts and the last key ends Metrics.settingsRowInset from the card.
                Item {
                    id: editorGrid
                    objectName: "screenshot-editor-grid"
                    width: parent.width
                    readonly property int columns: width >= 520 ? 2 : 1
                    readonly property real cellHeight: Metrics.settingsRowMinHeight
                    readonly property real cellWidth: width / columns
                    readonly property int rowCount: Math.ceil(root.localKeys.length / columns)
                    implicitHeight: rowCount * cellHeight
                    Repeater {
                        model: root.localKeys
                        delegate: Item {
                            id: cell
                            required property int index
                            required property string modelData
                            readonly property int row: Math.floor(index / editorGrid.columns)
                            readonly property int column: index % editorGrid.columns
                            x: column * editorGrid.cellWidth
                            y: row * editorGrid.cellHeight
                            width: editorGrid.cellWidth
                            height: editorGrid.cellHeight
                            Rectangle {
                                visible: cell.row > 0
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: cell.column === 0 ? Metrics.settingsRowInset : Metrics.space2
                                anchors.rightMargin: cell.column === editorGrid.columns - 1 ? Metrics.settingsRowInset : Metrics.space2
                                height: 1
                                color: Theme.tokens.outline
                            }
                            Rectangle {
                                visible: cell.column > 0
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: Metrics.space3
                                anchors.bottomMargin: Metrics.space3
                                width: 1
                                color: Theme.tokens.outline
                            }
                            PentadText {
                                anchors.left: parent.left
                                anchors.leftMargin: cell.column === 0 ? Metrics.settingsRowInset : Metrics.space4
                                anchors.right: keyField.left
                                anchors.rightMargin: Metrics.space2
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.localLabels[cell.modelData]
                                textFormat: Text.PlainText
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                            SettingsShortcutField {
                                id: keyField
                                objectName: "screenshot-local-" + cell.modelData
                                anchors.right: parent.right
                                anchors.rightMargin: cell.column === editorGrid.columns - 1 ? Metrics.settingsRowInset : Metrics.space4
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(150, cell.width * 0.5)
                                value: root.draft.localKeys[cell.modelData] || ''
                                accessibleName: root.localLabels[cell.modelData]
                                recordLabel: root.tr('Записати', 'Record')
                                cancelLabel: root.tr('Скасувати', 'Cancel')
                                clearLabel: root.tr('Очистити', 'Clear')
                                pressText: root.tr('Клавіша…', 'Key…')
                                disabledText: root.tr('Вимкнено', 'Off')
                                invalidText: root.tr('Цю клавішу не можна призначити.', 'That key cannot be bound.')
                                compact: true
                                clearable: true
                                requireModifier: false
                                onCommitted: function(shortcut) { root.shortcut('localKeys', cell.modelData, shortcut); }
                            }
                        }
                    }
                }
            }

            SettingsSection {
                id: fragmentSection
                width: body.width
                title: root.tr('Фрагмент Hyprland', 'Hyprland fragment')
                collapsible: true
                collapsed: true
                helpText: root.tr('Згенеровано з глобальних комбінацій. Експорт записує його у файл; підключи цей файл до своєї конфігурації Hyprland.',
                    'Generated from the global shortcuts. Export writes it to a file; source that file from your Hyprland configuration.')
                infoAccessibleName: root.tr('Про фрагмент', 'About the fragment')
                TextArea {
                    objectName: "screenshot-fragment"
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Theme.tokens.text
                    font.family: 'monospace'
                    font.pixelSize: Metrics.textCaption
                    padding: 16
                    text: {
                        try {
                            return Settings.hyprlandScreenshotBindings(root.draft);
                        } catch (_error) {
                            return root.tr('Спочатку виправ комбінації.', 'Fix shortcut values first.');
                        }
                    }
                    background: Item {}
                }
            }
        }
    }

    Item {
        id: footer
        objectName: "screenshot-settings-footer"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.barHeight
        Row {
            id: status
            anchors.left: parent.left
            anchors.leftMargin: root.gutter
            anchors.right: actions.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: root.message !== ''
            PentadIcon {
                visible: root.failed
                anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl('../../assets/icons/material/screenshot/error-symbolic.svg')
                pixelSize: Metrics.panelIcon
                color: Theme.tokens.error
            }
            PentadText {
                objectName: "screenshot-settings-message"
                width: Math.max(0, status.width - (root.failed ? Metrics.panelIcon + status.spacing : 0))
                anchors.verticalCenter: parent.verticalCenter
                text: root.message
                textFormat: Text.PlainText
                role: "caption"
                maximumLineCount: 2
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                color: root.failed ? Theme.tokens.error : Theme.tokens.textMuted
            }
        }
        Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            PentadButton {
                id: resetButton
                objectName: "screenshot-settings-reset"
                text: root.tr('Типові', 'Defaults')
                accessibleName: root.tr('Повернути типові значення', 'Restore defaults')
                controlHeight: Metrics.controlMedium
                background: Rectangle {
                    radius: height / 2
                    color: resetButton.down ? Theme.tokens.surfaceOverlay : resetButton.hovered ? Qt.alpha(Theme.tokens.text, 0.06) : "transparent"
                    border.width: resetButton.visualFocus ? 2 : 0
                    border.color: Theme.tokens.accent
                }
                onClicked: root.restoreDefaults()
            }
            PentadButton {
                objectName: "screenshot-settings-export"
                text: root.tr('Експортувати прив’язки', 'Export bindings')
                accessibleName: text
                controlHeight: Metrics.controlMedium
                pending: root.exporting
                onClicked: root.exportBindings()
            }
            // No accent flood: the primary action is told apart by tonal elevation and accent text.
            PentadButton {
                id: saveButton
                objectName: "screenshot-settings-save"
                text: root.tr('Зберегти', 'Save')
                accessibleName: text
                controlHeight: Metrics.controlMedium
                pending: root.pendingId !== ''
                requestedEnabled: root.dirty
                checked: root.dirty
                onClicked: root.save()
            }
        }
    }
}
