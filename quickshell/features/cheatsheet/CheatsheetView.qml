pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/keybinds.mjs' as KeybindsLogic
import '../../logic/cheatsheets.mjs' as CheatsheetsLogic
import '../../logic/keyboard-map.mjs' as KeyboardMap

// The keybind cheatsheet: a header with the list or keyboard switch, "Show all" and close; the
// sheet selector; the search; a row of filter chips; then the bind groups as cards in one to three
// columns, under the keyboard map in the keyboard view. The state lives in services.cheatsheet;
// the binds come from services.keybinds, which reads them from Hyprland only while needed.
FocusScope {
    id: root
    required property var services
    readonly property var cheatsheet: services.cheatsheet
    readonly property var keybinds: services.keybinds
    readonly property var bindState: keybinds ? keybinds.state : null
    readonly property bool liveBindings: cheatsheet.sheet === 'live'
    readonly property string stateKind: liveBindings ? (bindState ? bindState.kind : 'loading') : 'ready'
    readonly property var allGroups: liveBindings ? (stateKind === 'ready' && bindState.value ? bindState.value.groups : []) : CheatsheetsLogic.groupsFor(cheatsheet.sheet, root.tr)
    // The sheet after "Show all" and before the search and the filters: what the map and the chips describe.
    readonly property var sheetGroups: KeybindsLogic.filterBinds(allGroups, '', {
        showAll: cheatsheet.showAll
    })
    readonly property bool duplicatesOn: liveBindings && cheatsheet.duplicates
    readonly property var groups: KeybindsLogic.filterBinds(allGroups, cheatsheet.query, {
        showAll: cheatsheet.showAll,
        mods: cheatsheet.mods,
        key: cheatsheet.key,
        duplicates: duplicatesOn
    })
    readonly property int shownCount: KeybindsLogic.countBinds(groups)
    // Counted on the visible set, so it never promises rows that "Show all" is hiding.
    readonly property int duplicateCount: liveBindings ? KeybindsLogic.countBinds(KeybindsLogic.filterBinds(sheetGroups, '', {
        showAll: true,
        duplicates: true
    })) : 0
    // The modifiers the sheet's binds use, plus any still selected, in display order.
    readonly property var modifierChips: {
        const used = KeybindsLogic.modifierCounts(sheetGroups, {
            showAll: true
        }).map(item => item.name);
        return KeybindsLogic.MODIFIER_NAMES.filter(name => used.indexOf(name) >= 0 || cheatsheet.mods.indexOf(name) >= 0);
    }
    readonly property bool duplicatesChip: liveBindings && (duplicateCount > 0 || duplicatesOn)
    readonly property bool chipsShown: modifierChips.length > 0 || duplicatesChip || cheatsheet.key !== ''
    // The map needs the room of two group columns (keys of about 30 px); a narrower card keeps the list.
    readonly property bool keyboardUsable: stateKind === 'ready' && columnCount > 1 && KeyboardMap.usable(sheetGroups)
    readonly property bool keyboardShown: keyboardUsable && cheatsheet.view === 'keys'
    // The live list first, then the reference for the focused app, then the other references.
    readonly property var sheetOptions: {
        const context = cheatsheet.contextSheet;
        const sheets = CheatsheetsLogic.sheets(root.tr);
        const fitting = sheets.filter(sheet => sheet.id === context).map(sheet => ({
                    value: sheet.id,
                    label: sheet.label,
                    marked: true,
                    description: root.tr('для програми у фокусі', 'for the focused app')
                }));
        return [{
                value: 'live',
                label: root.tr('Поточні клавіші', 'Live bindings')
            }].concat(fitting, sheets.filter(sheet => sheet.id !== context).map(sheet => ({
                    value: sheet.id,
                    label: sheet.label
                })));
    }
    readonly property bool compactReferences: bodyWidth < sheetSelector.implicitWidth
    readonly property int edge: Metrics.space3
    readonly property int cardGap: Metrics.space2
    readonly property int keycapHeight: 24
    readonly property real bodyWidth: Math.max(0, width - 2 * edge)
    readonly property int columnCount: KeybindsLogic.columnCount(bodyWidth)
    readonly property real columnWidth: Math.max(0, Math.floor((bodyWidth - (columnCount - 1) * cardGap) / columnCount))
    readonly property var columns: KeybindsLogic.layoutColumns(groups, columnCount)
    // Where the groups start inside the scrolled body: under the map in the keyboard view.
    readonly property real listTop: keyboardShown && keyboardLoader.item ? keyboardLoader.height + cardGap : 0
    readonly property bool filtering: cheatsheet.query.trim() !== '' || cheatsheet.mods.length > 0 || cheatsheet.key !== '' || duplicatesOn
    readonly property string message: stateKind === 'loading' ? root.tr('Читаю прив’язки клавіш…', 'Reading key bindings…')
        : stateKind === 'unavailable' ? root.tr('Hyprland не відповідає', 'Hyprland is not answering')
        : groups.length ? '' : filtering ? root.tr('Нічого не знайдено', 'Nothing found')
        : allGroups.length ? root.tr('Жодна прив’язка не має опису', 'No binding has a description')
        : root.tr('Прив’язок клавіш немає', 'There are no key bindings')
    // Any change of what the list shows takes it back to its top (under the map, which stays in place).
    readonly property string filterKey: [cheatsheet.query, cheatsheet.mods.join('+'), cheatsheet.key, duplicatesOn, cheatsheet.showAll].join('\u0001')
    readonly property alias searchField: search
    readonly property alias showAllToggle: showAll
    readonly property alias viewSwitcher: viewSwitch
    readonly property alias chips: chipRow
    readonly property alias flickable: flick
    signal closeRequested

    onAllGroupsChanged: flick.contentY = 0
    onFilterKeyChanged: flick.contentY = keyboardShown ? Math.max(0, Math.min(flick.contentY, listTop)) : 0
    // Switching views starts at the top, with the map in sight.
    onKeyboardShownChanged: {
        flick.contentY = 0;
        if (keyboardShown)
            pickLayer();
    }
    Component.onCompleted: pickLayer()

    implicitWidth: 920
    implicitHeight: scroller.y + Math.max(160, flick.contentHeight) + edge

    function tr(uk, en) {
        return root.services.text(uk, en);
    }
    function scrollBy(delta) {
        flick.contentY = Math.max(0, Math.min(flick.contentY + delta, flick.contentHeight - flick.height));
    }
    // The keyboard view starts on the sheet's busiest modifier layer when no chip is selected; once
    // per opening and sheet, so clearing the chips afterwards stays cleared when the card resizes.
    property string pickedSheet: ''
    function pickLayer() {
        if (!root.keyboardShown || root.pickedSheet === root.cheatsheet.sheet)
            return;
        const layers = KeyboardMap.layers(root.sheetGroups);
        if (!layers.length)
            return;
        root.pickedSheet = root.cheatsheet.sheet;
        if (root.cheatsheet.mods.length === 0)
            root.cheatsheet.setMods(layers[0].mods);
    }
    function cycleSheet(step) {
        const values = root.sheetOptions.map(option => option.value);
        const index = Math.max(0, values.indexOf(root.cheatsheet.sheet));
        root.cheatsheet.selectSheet(values[(index + step + values.length) % values.length]);
    }
    function printable(event) {
        const code = event.text.length ? event.text.charCodeAt(0) : 0;
        return code >= 32 && code !== 127 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
    }

    // Esc clears the search and the key and duplicate filters first, then closes; arrows and Page
    // keys scroll while typing; Ctrl+Tab goes through the sheets; typing anywhere goes to the search.
    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            root.cycleSheet(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
        } else if (event.key === Qt.Key_Escape) {
            if (root.cheatsheet.clearable)
                root.cheatsheet.clearSearch();
            else
                root.closeRequested();
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            root.scrollBy(event.key === Qt.Key_Down ? 48 : -48);
        } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
            root.scrollBy((event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(48, flick.height - 48));
        } else if (!search.activeFocus && root.printable(event)) {
            search.forceActiveFocus();
            search.insert(search.cursorPosition, event.text);
        } else {
            return;
        }
        event.accepted = true;
    }

    Connections {
        target: root.cheatsheet
        // A new sheet resets the chips; pick its layer once its groups are in.
        function onSheetChanged() {
            Qt.callLater(root.pickLayer);
        }
    }

    Item {
        id: header
        x: root.edge
        y: root.edge
        width: root.bodyWidth
        height: 36
        // On a narrow card the count gives way before the title is clipped.
        readonly property real titleRoom: header.width - actions.width - Metrics.space3
        readonly property bool countFits: title.implicitWidth + Metrics.space2 + countLabel.implicitWidth <= titleRoom
        PentadText {
            id: title
            objectName: 'cheatsheet-title'
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, header.titleRoom - (header.countFits ? countLabel.implicitWidth + Metrics.space2 : 0)))
            text: root.tr('Шпаргалка клавіш', 'Keybind cheatsheet')
            role: 'section'
            font.weight: Font.DemiBold
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
        PentadText {
            id: countLabel
            x: title.x + title.width + Metrics.space2
            visible: header.countFits
            anchors.baseline: title.baseline
            text: root.stateKind === 'ready' && root.shownCount > 0 ? root.shownCount : ''
            role: 'caption'
            color: Theme.tokens.textMuted
            font.features: ({
                    tnum: 1
                })
            wrapMode: Text.NoWrap
        }
        Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.space3
            PentadSegmented {
                id: viewSwitch
                objectName: 'cheatsheet-view-switch'
                anchors.verticalCenter: parent.verticalCenter
                visible: root.keyboardUsable
                width: 2 * (Metrics.controlSmall + Metrics.space2) + 2 * viewSwitch.inset
                height: Metrics.controlSmall
                segmentObjectName: 'cheatsheet-view-'
                accessibleName: root.tr('Вигляд', 'View')
                options: [
                    {
                        value: 'list',
                        label: root.tr('Список', 'List'),
                        icon: Qt.resolvedUrl('../../assets/icons/material/media/format-align-left-symbolic.svg'),
                        iconOnly: true
                    },
                    {
                        value: 'keys',
                        label: root.tr('Клавіатура', 'Keyboard'),
                        icon: Qt.resolvedUrl('../../assets/icons/material/keyboard-symbolic.svg'),
                        iconOnly: true
                    }
                ]
                value: root.keyboardShown ? 'keys' : 'list'
                onActivated: value => root.cheatsheet.setView(value)
            }
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
        x: root.edge
        y: header.y + header.height + Metrics.space2
        width: root.bodyWidth
        visible: !root.compactReferences
        tabList: true
        segmentObjectName: 'cheatsheet-sheet-'
        accessibleName: root.tr('Довідник', 'Reference sheet')
        options: root.sheetOptions
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
        visible: root.compactReferences
        accessibleName: root.tr('Довідник', 'Reference sheet')
        model: sheetSelector.options
        textRole: 'label'
        valueRole: 'value'
        currentIndex: sheetSelector.selectedIndex
        onActivated: index => root.cheatsheet.selectSheet(model[index].value)
    }
    PentadText {
        id: referenceNote
        x: root.edge
        y: sheetSelector.y + sheetSelector.height + Metrics.space2
        width: root.bodyWidth
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
        x: root.edge
        y: referenceNote.y + (referenceNote.visible ? referenceNote.implicitHeight + Metrics.space2 : 0)
        width: root.bodyWidth
        height: 36
        leftPadding: Metrics.space3 + Metrics.panelIcon + Metrics.space2
        focus: true
        text: root.cheatsheet.query
        onTextChanged: if (root.cheatsheet.query !== text)
            root.cheatsheet.query = text
        placeholderText: root.tr('Пошук за клавішею або дією', 'Search by key or action')
        PentadIcon {
            x: Metrics.space3
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl('../../assets/icons/material/media/search-symbolic.svg')
            color: Theme.tokens.textMuted
        }
    }
    // Filters: the modifiers (all selected ones must be held; the exact layer in the keyboard
    // view), the duplicates of the live list, and the key picked on the map. Clicks leave the
    // keyboard in the search; Tab reaches each chip.
    Flow {
        id: chipRow
        objectName: 'cheatsheet-chips'
        x: root.edge
        y: search.y + search.height + Metrics.space2
        width: root.bodyWidth
        visible: root.chipsShown
        spacing: Metrics.space1
        Repeater {
            model: root.modifierChips
            delegate: PentadChip {
                required property string modelData
                objectName: 'cheatsheet-mod-' + modelData.toLowerCase()
                text: modelData
                focusPolicy: Qt.TabFocus
                checked: root.cheatsheet.mods.indexOf(modelData) >= 0
                Accessible.name: root.tr('Модифікатор ' + modelData, 'Modifier ' + modelData)
                onToggled: root.cheatsheet.toggleModifier(modelData)
            }
        }
        PentadChip {
            objectName: 'cheatsheet-duplicates'
            visible: root.duplicatesChip
            text: root.tr('Дублікати', 'Duplicates')
            count: root.duplicateCount
            focusPolicy: Qt.TabFocus
            checked: root.duplicatesOn
            Accessible.name: root.tr('Лише дублікати', 'Duplicates only')
            onToggled: root.cheatsheet.duplicates = !root.cheatsheet.duplicates
        }
        PentadChip {
            objectName: 'cheatsheet-key-chip'
            visible: root.cheatsheet.key !== ''
            removable: true
            text: root.cheatsheet.key
            focusPolicy: Qt.TabFocus
            Accessible.name: root.tr('Клавіша ' + root.cheatsheet.key + ': прибрати фільтр', 'Key ' + root.cheatsheet.key + ': remove the filter')
            onToggled: root.cheatsheet.toggleKey(root.cheatsheet.key)
        }
    }
    PentadScrollView {
        id: scroller
        x: Metrics.space1
        y: (chipRow.visible ? chipRow.y + chipRow.height : search.y + search.height) + root.edge
        width: root.width - 2 * x
        height: Math.max(0, root.height - y - root.edge)
        Flickable {
            id: flick
            objectName: 'cheatsheet-list'
            clip: true
            contentWidth: width
            contentHeight: root.listTop + Math.max(columnsRow.implicitHeight, root.message !== '' ? 160 : 0)
            boundsBehavior: Flickable.StopAtBounds
            // The keyboard map, built only for the keyboard view.
            Loader {
                id: keyboardLoader
                x: root.edge - scroller.x
                width: root.bodyWidth
                active: root.keyboardShown
                sourceComponent: Item {
                    id: keyboardCard
                    implicitHeight: keyboardMap.implicitHeight + 2 * Metrics.space2
                    ContinuousSurface {
                        objectName: 'cheatsheet-keyboard-card'
                        anchors.fill: parent
                        fill: Theme.tokens.surfaceRaised
                        extent: Metrics.radiusCard
                        clipContent: false
                    }
                    CheatsheetKeyboard {
                        id: keyboardMap
                        x: Math.max(0, Math.floor((keyboardCard.width - width) / 2))
                        y: Metrics.space2
                        width: Math.min(keyboardCard.width - 2 * Metrics.space2, implicitWidth)
                        services: root.services
                        groups: root.sheetGroups
                        mods: root.cheatsheet.mods
                        onModifierToggled: name => root.cheatsheet.toggleModifier(name)
                        onKeyActivated: label => root.cheatsheet.toggleKey(label)
                    }
                }
            }
            Row {
                id: columnsRow
                x: root.edge - scroller.x
                y: root.listTop
                spacing: root.cardGap
                Repeater {
                    model: root.columns
                    delegate: Column {
                        id: column
                        required property var modelData
                        width: root.columnWidth
                        spacing: root.cardGap
                        Repeater {
                            model: column.modelData
                            delegate: CheatsheetGroupCard {
                                required property var modelData
                                services: root.services
                                group: modelData
                                keycapHeight: root.keycapHeight
                                width: column.width
                            }
                        }
                    }
                }
            }
            Column {
                objectName: 'cheatsheet-empty'
                x: Math.round((flick.width - width) / 2)
                y: root.listTop + Math.max(0, Math.round((Math.max(160, flick.height - root.listTop) - height) / 2))
                width: Math.min(flick.width - 48, 420)
                visible: root.message !== ''
                spacing: Metrics.space2
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
        }
    }
}
