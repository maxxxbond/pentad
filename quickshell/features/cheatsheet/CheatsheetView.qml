pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/keybinds.mjs' as KeybindsLogic
import '../../logic/cheatsheets.mjs' as CheatsheetsLogic

// The keybind cheatsheet: a header with "Show all" and the search, then the bind groups in one to
// three columns. The query and "Show all" live in services.cheatsheet; the binds come from
// services.keybinds, which reads them from Hyprland only while the cheatsheet is open.
FocusScope {
    id: root
    required property var services
    readonly property var cheatsheet: services.cheatsheet
    readonly property var keybinds: services.keybinds
    readonly property var bindState: keybinds ? keybinds.state : null
    readonly property bool liveBindings: cheatsheet.sheet === 'live'
    readonly property string stateKind: liveBindings ? (bindState ? bindState.kind : 'loading') : 'ready'
    readonly property var allGroups: liveBindings ? (stateKind === 'ready' && bindState.value ? bindState.value.groups : []) : CheatsheetsLogic.groupsFor(cheatsheet.sheet, root.tr)
    readonly property var groups: KeybindsLogic.filterBinds(allGroups, cheatsheet.query, {
        showAll: cheatsheet.showAll
    })
    readonly property int shownCount: KeybindsLogic.countBinds(groups)
    readonly property int columnGap: 24
    readonly property int keycapHeight: 24
    readonly property real bodyWidth: Math.max(0, width - 24)
    readonly property int columnCount: KeybindsLogic.columnCount(bodyWidth)
    readonly property real columnWidth: Math.max(0, Math.floor((bodyWidth - (columnCount - 1) * columnGap) / columnCount))
    readonly property var columns: KeybindsLogic.layoutColumns(groups, columnCount)
    readonly property string message: stateKind === 'loading' ? root.tr('Читаю прив’язки клавіш…', 'Reading key bindings…')
        : stateKind === 'unavailable' ? root.tr('Hyprland не відповідає', 'Hyprland is not answering')
        : groups.length ? '' : cheatsheet.query.trim() ? root.tr('Нічого не знайдено', 'Nothing found')
        : allGroups.length ? root.tr('Жодна прив’язка не має опису', 'No binding has a description')
        : root.tr('Прив’язок клавіш немає', 'There are no key bindings')
    readonly property alias searchField: search
    readonly property alias showAllToggle: showAll
    readonly property alias flickable: flick
    signal closeRequested

    onAllGroupsChanged: flick.contentY = 0

    implicitWidth: 920
    implicitHeight: scroller.y + Math.max(160, flick.contentHeight) + 12

    function tr(uk, en) {
        return root.services.text(uk, en);
    }
    // Keycap widths come from the font, so a group's descriptions can start on one line.
    function capWidth(label) {
        return Math.max(root.keycapHeight, Math.ceil(capMetrics.advanceWidth(label)) + 16);
    }
    function keysWidth(keys) {
        let width = 0;
        for (const key of keys)
            width += root.capWidth(key);
        return width + Math.max(0, keys.length - 1) * 4;
    }
    function scrollBy(delta) {
        flick.contentY = Math.max(0, Math.min(flick.contentY + delta, flick.contentHeight - flick.height));
    }

    // Esc clears the search first, then closes; arrows and Page keys scroll while typing.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.cheatsheet.query !== '')
                root.cheatsheet.query = '';
            else
                root.closeRequested();
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            root.scrollBy(event.key === Qt.Key_Down ? 48 : -48);
        } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
            root.scrollBy((event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(48, flick.height - 48));
        } else {
            return;
        }
        event.accepted = true;
    }

    FontMetrics {
        id: capMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textCaption
        font.weight: Font.Medium
    }
    FontMetrics {
        id: bodyMetrics
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
    }

    Item {
        id: header
        x: 12
        y: 12
        width: root.width - 24
        height: 36
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            PentadText {
                id: title
                objectName: 'cheatsheet-title'
                text: root.tr('Шпаргалка клавіш', 'Keybind cheatsheet')
                role: 'section'
                font.weight: Font.DemiBold
                wrapMode: Text.NoWrap
            }
            PentadText {
                anchors.baseline: title.baseline
                text: root.stateKind === 'ready' && root.shownCount > 0 ? root.shownCount : ''
                role: 'caption'
                color: Theme.tokens.textMuted
                wrapMode: Text.NoWrap
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            PentadToggle {
                id: showAll
                visible: root.liveBindings
                objectName: 'cheatsheet-show-all'
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr('Показати всі', 'Show all')
                accessibleName: root.tr('Показати й прив’язки без опису', 'Also show bindings without a description')
                focusPolicy: Qt.TabFocus
                checked: root.cheatsheet.showAll
                onToggled: root.cheatsheet.showAll = checked
            }
            PentadButton {
                objectName: 'cheatsheet-close'
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.controlSmall
                controlHeight: Metrics.controlSmall
                iconSize: Metrics.panelIcon
                focusPolicy: Qt.TabFocus
                iconSource: Qt.resolvedUrl('../../assets/icons/material/media/close-symbolic.svg')
                accessibleName: root.tr('Закрити', 'Close')
                onClicked: root.closeRequested()
            }
        }
    }
    PentadSegmented {
        id: sheetSelector
        objectName: 'cheatsheet-selector'
        x: 12
        y: header.y + header.height + 8
        width: root.width - 24
        visible: width >= implicitWidth
        tabList: true
        accessibleName: root.tr('Довідник', 'Reference sheet')
        options: [{ value: 'live', label: root.tr('Поточні клавіші', 'Live bindings') }].concat(CheatsheetsLogic.sheets(root.tr).map(function(sheet) {
            return { value: sheet.id, label: sheet.label };
        }))
        value: root.cheatsheet.sheet
        onActivated: value => root.cheatsheet.selectSheet(value)
    }
    PentadComboBox {
        id: compactSelector
        objectName: 'cheatsheet-compact-selector'
        x: sheetSelector.x
        y: sheetSelector.y
        width: sheetSelector.width
        height: sheetSelector.height
        visible: !sheetSelector.visible
        accessibleName: root.tr('Довідник', 'Reference sheet')
        model: sheetSelector.options
        textRole: 'label'
        valueRole: 'value'
        currentIndex: sheetSelector.selectedIndex
        onActivated: index => root.cheatsheet.selectSheet(model[index].value)
    }
    PentadText {
        id: referenceNote
        x: 12
        y: sheetSelector.y + sheetSelector.height + 8
        width: root.width - 24
        visible: !root.liveBindings
        role: 'caption'
        color: Theme.tokens.textMuted
        text: root.cheatsheet.sheet === 'neovim'
            ? root.tr('Типові клавіші Neovim. Команди — у звичайному режимі, якщо не зазначено інше; вводьте послідовно. Ваші налаштування можуть відрізнятися.', 'Default Neovim keys. Commands use Normal mode unless noted; type sequences in order. Your configuration may differ.')
            : root.cheatsheet.sheet === 'browser'
            ? root.tr('Спільні клавіші Firefox і Chromium у Linux. Налаштування браузера можуть відрізнятися.', 'Common Firefox and Chromium keys on Linux. Browser settings may differ.')
            : root.cheatsheet.sheet === 'git'
            ? root.tr('Команди вводяться в терміналі всередині репозиторію. Замініть назви файлів і гілок своїми.', 'Enter commands in a terminal inside a repository. Replace file and branch names with your own.')
            : root.cheatsheet.sheet === 'terminal'
            ? root.tr('Типові клавіші Bash і Zsh у режимі Emacs. Налаштування оболонки й термінала можуть відрізнятися.', 'Default Bash and Zsh keys in Emacs mode. Shell and terminal settings may differ.')
            : root.cheatsheet.sheet === 'kitty'
            ? root.tr('Типові клавіші kitty (kitty_mod — Ctrl+Shift). Власні прив’язки в kitty.conf можуть відрізнятися.', 'Default kitty keys (kitty_mod is Ctrl+Shift). Custom mappings in kitty.conf may differ.')
            : root.tr('Типові прив’язки Pentad та клавіші всередині оболонки. Для налаштованих прив’язок відкрийте «Поточні клавіші».', 'Default Pentad bindings and in-shell keys. See Live bindings for your configured shortcuts.')
    }
    PentadTextField {
        id: search
        objectName: 'cheatsheet-search'
        x: 12
        y: referenceNote.y + (referenceNote.visible ? referenceNote.implicitHeight + 8 : 0)
        width: root.width - 24
        height: 36
        leftPadding: 36
        focus: true
        text: root.cheatsheet.query
        onTextChanged: if (root.cheatsheet.query !== text)
            root.cheatsheet.query = text
        placeholderText: root.tr('Пошук за клавішею або дією', 'Search by key or action')
        PentadIcon {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl('../../assets/icons/material/media/search-symbolic.svg')
            color: Theme.tokens.textMuted
        }
    }
    PentadScrollView {
        id: scroller
        x: 6
        y: search.y + search.height + 12
        width: root.width - 12
        height: Math.max(0, root.height - y - 12)
        Flickable {
            id: flick
            objectName: 'cheatsheet-list'
            clip: true
            contentWidth: width
            contentHeight: columnsRow.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: columnsRow
                x: 6
                spacing: root.columnGap
                Repeater {
                    model: root.columns
                    delegate: Column {
                        id: column
                        required property var modelData
                        width: root.columnWidth
                        spacing: 20
                        Repeater {
                            model: column.modelData
                            delegate: GroupBlock {
                                required property var modelData
                                group: modelData
                                width: column.width
                            }
                        }
                    }
                }
            }
        }
    }
    Column {
        objectName: 'cheatsheet-empty'
        anchors.centerIn: scroller
        width: Math.min(scroller.width - 48, 420)
        visible: root.message !== ''
        spacing: 8
        PentadText {
            objectName: 'cheatsheet-message'
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.message
            color: Theme.tokens.textMuted
        }
        PentadText {
            objectName: 'cheatsheet-reason'
            width: parent.width
            visible: text !== ''
            horizontalAlignment: Text.AlignHCenter
            text: root.stateKind === 'unavailable' ? KeybindsLogic.reasonText(root.bindState.reason, root.tr) : ''
            role: 'caption'
            color: Theme.tokens.textMuted
        }
        PentadButton {
            objectName: 'cheatsheet-retry'
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.stateKind === 'unavailable'
            text: root.tr('Спробувати ще раз', 'Try again')
            onClicked: root.keybinds.refresh()
        }
    }

    // One group: its heading, then a row per bind with the keycaps in a column as wide as the
    // group's widest combination (at most 55 % of the column) and the description beside them.
    component GroupBlock: Column {
        id: block
        required property var group
        readonly property real keyWidth: {
            let widest = root.keycapHeight;
            for (const bind of block.group.binds)
                widest = Math.max(widest, root.keysWidth(bind.keys));
            return Math.min(widest, Math.round(block.width * 0.55));
        }
        objectName: 'cheatsheet-group-' + block.group.id
        spacing: 4
        PentadText {
            objectName: 'cheatsheet-group-title'
            width: block.width
            text: KeybindsLogic.labelFor(block.group, root.tr)
            role: 'caption'
            font.weight: Font.DemiBold
            color: Theme.tokens.textMuted
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            bottomPadding: 4
        }
        Repeater {
            model: block.group.binds
            delegate: BindRow {
                required property var modelData
                bind: modelData
                keyWidth: block.keyWidth
                width: block.width
            }
        }
    }

    component BindRow: Item {
        id: row
        required property var bind
        property real keyWidth: 0
        objectName: 'cheatsheet-row'
        implicitHeight: Math.max(caps.height, label.implicitHeight)
        height: implicitHeight
        Flow {
            id: caps
            objectName: 'cheatsheet-keys'
            width: row.keyWidth
            spacing: 4
            Repeater {
                model: row.bind.keys
                delegate: Rectangle {
                    id: cap
                    required property string modelData
                    objectName: 'cheatsheet-keycap'
                    readonly property string label: modelData
                    width: Math.min(row.keyWidth, root.capWidth(modelData))
                    height: Math.max(root.keycapHeight, capLabel.implicitHeight + 8)
                    radius: Metrics.radiusSmall
                    color: Theme.tokens.surfaceRaised
                    PentadText {
                        id: capLabel
                        anchors.centerIn: cap
                        width: Math.max(0, cap.width - 16)
                        horizontalAlignment: Text.AlignHCenter
                        text: cap.modelData
                        textFormat: Text.PlainText
                        role: 'caption'
                        font.weight: Font.Medium
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
        PentadText {
            id: label
            objectName: 'cheatsheet-description'
            x: row.keyWidth + 12
            width: Math.max(0, row.width - label.x)
            topPadding: Math.max(0, Math.round((root.keycapHeight - bodyMetrics.height) / 2))
            text: row.bind.lua && !row.bind.described ? root.tr('Функція Lua без опису', 'Lua function without a description') : row.bind.description
            textFormat: Text.PlainText
            color: row.bind.described ? Theme.tokens.text : Theme.tokens.textMuted
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
}
