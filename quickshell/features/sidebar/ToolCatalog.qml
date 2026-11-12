pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import '../../logic/tool-catalog.mjs' as Tools
import '../../logic/file-tools.mjs' as Files

Item {
    id: root
    required property var sidebar
    readonly property var state: sidebar.toolState
    readonly property var entries: sidebar.visibleTools
    // At rest the catalog reads as sections under pinned tiles and recent results; any filter flattens it.
    readonly property bool resting: !state.searchQuery && state.catalogView === 'all' && !state.catalogCategory && !state.pendingInput
    readonly property var rows: Tools.catalogRows(entries, { sectioned: resting })
    readonly property var pendingTiles: state.pendingInput ? Files.quickActions(state.pendingInput.value || [], sidebar.toolIds) : []
    readonly property var pinned: resting ? Tools.pinnedTools(sidebar.toolEntries, state.favorites, state.recent)
        .map(entry => ({ toolId: entry.manifest.id, label: entry.manifest.name, symbol: sidebar.toolSymbol(entry.manifest.id), purpose: sidebar.toolPurpose(entry.manifest) })) : []
    readonly property var history: resting && sidebar.services.fileTools ? sidebar.services.fileTools.history : []
    readonly property var categories: [...new Set(sidebar.toolEntries.map(entry => entry.manifest.tool.category))].sort()
    readonly property alias listView: results
    readonly property alias searchField: search
    readonly property string viewLabel: state.catalogView === 'favorites' ? 'Favorites' : state.catalogView === 'recent' ? 'Recent' : 'All tools'
    property bool keyboardSelection: false
    objectName: 'sidebar-catalog'

    function resetFilters() {
        state.searchQuery = '';
        state.catalogView = 'all';
        state.catalogCategory = '';
        search.forceActiveFocus();
    }
    function moveSelection(delta) {
        if (!results.count) return;
        keyboardSelection = true;
        results.currentIndex = Math.max(0, Math.min(results.count - 1, results.currentIndex + delta));
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }
    function openCurrent() {
        if (results.currentIndex >= 0 && results.currentIndex < rows.length) openTool(rows[results.currentIndex].manifest.id);
    }
    function openTool(id) {
        // Stored relative to the list origin: the pinned/recent header gives the list a negative originY.
        state.catalogScrollY = results.contentY - results.originY;
        state.selectTool(id, !!sidebar.toolState.pendingInput);
    }
    function description(manifest) { return sidebar.toolPurpose(manifest); }
    function symbol(id) { return sidebar.toolSymbol(id); }
    onVisibleChanged: if (visible) Qt.callLater(function() {
        results.contentY = Math.max(results.originY, Math.min(results.originY + state.catalogScrollY,
            results.originY + Math.max(0, results.contentHeight - results.height)));
    });
    Shortcut {
        sequence: 'Ctrl+F'
        enabled: root.visible
        onActivated: { search.forceActiveFocus(); search.selectAll(); }
    }
    component Glyph: PentadIcon {
        property string symbol: ''
        source: symbol ? Qt.resolvedUrl('../../assets/icons/material/' + symbol + '-symbolic.svg') : ''
        pixelSize: Metrics.statusIcon
        color: Theme.tokens.textMuted
        Accessible.ignored: true
    }
    component Selector: SidebarButton {
        id: selector
        required property string label
        required property string selectedValue
        required property var entries
        readonly property alias choicePopover: choices
        signal chosen(string value)
        // Drawn like PentadComboBox: a borderless capsule with the chevron in a round well
        // concentric with the trailing end. The list stays an attached popover, so the open
        // trigger shares its fill.
        readonly property bool engaged: hovered || visualFocus || opened
        readonly property bool mirroredLayout: LayoutMirroring.enabled
        readonly property real wellInset: 4
        readonly property real wellSize: height - 2 * wellInset
        accessibleName: label
        opened: choices.opened
        onClicked: choices.toggle()
        leftPadding: mirroredLayout ? wellSize + wellInset + 8 : 16
        rightPadding: mirroredLayout ? 16 : wellSize + wellInset + 8
        contentItem: PentadText {
            text: selector.label; wrapMode: Text.NoWrap; elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            color: selector.enabled ? Theme.tokens.text : Theme.tokens.textMuted
        }
        background: Rectangle {
            readonly property color fill: selector.opened ? Theme.tokens.surface
                : selector.down ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.text, Metrics.statePressed))
                : selector.hovered ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.text, Metrics.stateHover))
                : Theme.tokens.surfaceRaised
            radius: Metrics.radiusPill
            color: fill
            border.width: selector.visualFocus ? 1 : 0
            border.color: Theme.tokens.accent
            Rectangle {
                x: selector.mirroredLayout ? selector.wellInset : parent.width - width - selector.wellInset
                y: selector.wellInset
                width: selector.wellSize
                height: selector.wellSize
                radius: Metrics.radiusPill
                color: Qt.alpha(Theme.tokens.text, selector.engaged ? 0.12 : 0.06)
                PentadChevron {
                    anchors.centerIn: parent
                    direction: selector.opened ? "up" : "down"
                    pixelSize: Metrics.chevronIcon
                    color: selector.engaged ? Theme.tokens.text : Theme.tokens.textMuted
                    engaged: selector.engaged
                }
            }
        }
        AttachedPopover {
            id: choices
            anchorItem: selector
            manager: root.sidebar.services.popups || null
            contentItem: PentadScrollView {
                id: choiceScroll
                implicitWidth: 224
                width: implicitWidth
                implicitHeight: Math.min(240, choiceRows.implicitHeight)
                height: implicitHeight
                contentWidth: availableWidth
                contentHeight: choiceRows.implicitHeight
                clip: true
                Column {
                    id: choiceRows
                    width: choiceScroll.availableWidth
                    spacing: 4
                    Repeater {
                        model: selector.entries
                        delegate: SidebarButton {
                            required property var modelData
                            objectName: 'sidebar-choice-' + modelData.id
                            width: choiceRows.width
                            controlHeight: Metrics.controlSmall
                            text: modelData.text
                            checked: modelData.id === selector.selectedValue
                            onClicked: { selector.chosen(modelData.id); choices.close(); }
                        }
                    }
                }
            }
        }
    }
    Column {
        id: catalogHeader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 12
        Item {
            width: parent.width; height: 32
            PentadText {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: 'Tools'; role: 'title'; font.weight: Font.Medium
            }

        }
        PentadTextField {
            id: search
            objectName: 'sidebar-tool-search'
            width: parent.width
            placeholderText: 'Find a tool or action…'
            accessibleName: 'Search tools by name, category or keyword'
            leftPadding: 40; rightPadding: 40
            background: ContinuousSurface {
                objectName: 'sidebar-search-surface'
                fill: search.activeFocus ? Theme.tokens.surfaceOverlay : Theme.tokens.surfaceRaised
                extent: Metrics.radiusSmall
                Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
            }
            text: root.state.searchQuery
            onTextChanged: root.state.searchQuery = text
            Glyph { x: 12; anchors.verticalCenter: parent.verticalCenter; symbol: 'media/search' }
            SidebarButton {
                visible: !!search.text
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
                width: 32; text: ''; accessibleName: 'Clear search'
                background: ContinuousSurface { fill: parent.visualFocus || parent.hovered ? Theme.tokens.surfaceOverlay : 'transparent'; extent: Metrics.radiusSmall }
                Glyph { anchors.centerIn: parent; symbol: 'media/close'; pixelSize: Metrics.panelIcon }
                onClicked: { root.state.searchQuery = ''; search.forceActiveFocus(); }
            }
            Keys.onDownPressed: root.moveSelection(1)
            Keys.onUpPressed: root.moveSelection(-1)
            Keys.onReturnPressed: root.openCurrent()
            Keys.onEnterPressed: root.openCurrent()
            Keys.onEscapePressed: function(event) {
                if (text) root.state.searchQuery = '';
                else event.accepted = false;
            }
        }
        Row {
            width: parent.width; spacing: 8
            Selector {
                id: viewButton
                objectName: 'sidebar-view-selector'
                width: Math.min(148, (parent.width - 8) * 0.46)
                label: root.viewLabel
                selectedValue: root.state.catalogView
                entries: [{ id: 'all', text: 'All tools' }]
                    .concat(root.state.favorites.length || selectedValue === 'favorites' ? [{ id: 'favorites', text: 'Favorites' }] : [])
                    .concat(root.state.recent.length || selectedValue === 'recent' ? [{ id: 'recent', text: 'Recent' }] : [])
                onChosen: value => root.state.catalogView = value
            }
            Selector {
                id: categoryButton
                objectName: 'sidebar-category-selector'
                width: parent.width - viewButton.width - 8
                label: root.state.catalogCategory || 'All categories'
                selectedValue: root.state.catalogCategory
                entries: [{ id: '', text: 'All categories' }].concat(root.categories.map(category => ({ id: category, text: category })))
                onChosen: value => root.state.catalogCategory = value
            }
        }
        Item {
            width: parent.width
            height: inputSummary.visible ? inputSummary.implicitHeight + 4 : 18
            PentadText {
                visible: !inputSummary.visible
                text: root.entries.length + (root.entries.length === 1 ? ' tool' : ' tools')
                    + (root.state.searchQuery ? ' found' : '')
                role: 'caption'; color: Theme.tokens.textMuted; font.features: ({ tnum: 1 })
            }
            PentadText {
                id: inputSummary
                visible: !!root.state.pendingInput
                width: parent.width - cancelInput.width - 8
                text: 'Compatible with: ' + root.sidebar.pendingTypes
                role: 'caption'; color: Theme.tokens.accent; maximumLineCount: 2; elide: Text.ElideRight
            }
            SidebarButton {
                id: cancelInput
                visible: !!root.state.pendingInput
                anchors.right: parent.right
                text: 'Cancel'; controlHeight: 28
                onClicked: root.state.clearIngress()
            }
        }
    }
    ListView {
        id: results
        objectName: 'sidebar-tool-results'
        anchors { top: catalogHeader.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: catalogFooter.top; bottomMargin: 12 }
        clip: true
        model: root.rows
        spacing: 4
        section.property: root.resting ? 'section' : ''
        section.delegate: Item {
            required property string section
            width: results.width
            height: 32
            PentadText {
                x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                text: parent.section
                role: 'caption'; font.weight: Font.Medium; color: Theme.tokens.textMuted
            }
        }
        header: Column {
            width: results.width
            spacing: 8
            bottomPadding: root.pendingTiles.length || root.pinned.length || root.history.length ? 8 : 0
            Grid {
                objectName: 'sidebar-pending-actions'
                visible: root.pendingTiles.length > 0
                width: parent.width
                columns: 2; rowSpacing: 8; columnSpacing: 8
                Repeater {
                    model: root.pendingTiles
                    delegate: QuickTile {
                        required property var modelData
                        width: (results.width - 8) / 2
                        sidebar: root.sidebar
                        tile: modelData
                    }
                }
            }
            Grid {
                objectName: 'sidebar-pinned'
                visible: root.pinned.length > 0
                width: parent.width
                columns: 4; rowSpacing: 8; columnSpacing: 8
                Repeater {
                    model: root.pinned
                    delegate: QuickTile {
                        required property var modelData
                        width: (results.width - 24) / 4
                        stacked: true
                        sidebar: root.sidebar
                        tile: modelData
                        description: modelData.purpose
                    }
                }
            }
            Column {
                visible: root.history.length > 0
                width: parent.width
                spacing: 4
                PentadText { x: 14; text: 'Recent results'; role: 'caption'; font.weight: Font.Medium; color: Theme.tokens.textMuted }
                ListView {
                    objectName: 'sidebar-recent-results'
                    width: parent.width; height: 56
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.history
                    delegate: Item {
                        id: recentItem
                        required property var modelData
                        width: 56; height: 56
                        Accessible.role: Accessible.Button
                        Accessible.name: 'Open ' + modelData.name
                        FileThumb {
                            id: recentThumb
                            anchors.fill: parent
                            services: root.sidebar.services
                            uri: recentItem.modelData.uri
                            mimeType: recentItem.modelData.mimeType || ''
                            kind: recentItem.modelData.kind || 'file'
                            radius: Metrics.radiusMedium
                            scale: recentDrag.pressed ? 0.97 : 1
                        }
                        FileDragSource {
                            id: recentDrag
                            services: root.sidebar.services
                            uris: [recentItem.modelData.uri]
                            visual: recentThumb
                            onActivated: Qt.openUrlExternally(recentItem.modelData.uri)
                        }
                        PentadToolTip { visible: recentDrag.containsMouse && !recentDrag.exporting; text: recentItem.modelData.name }
                    }
                }
            }
        }
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        currentIndex: -1
        onModelChanged: { currentIndex = count ? 0 : -1; root.keyboardSelection = false; }
        Keys.onDownPressed: root.moveSelection(1)
        Keys.onUpPressed: root.moveSelection(-1)
        Keys.onReturnPressed: root.openCurrent()
        Keys.onEnterPressed: root.openCurrent()
        ScrollBar.vertical: ScrollBar {
            id: resultsBar
            policy: ScrollBar.AsNeeded
            implicitWidth: 8
            contentItem: Rectangle {
                implicitWidth: 4
                implicitHeight: 36
                radius: Metrics.radiusPill
                color: resultsBar.pressed ? Theme.tokens.accent
                    : resultsBar.hovered ? Qt.alpha(Theme.tokens.text, 0.45) : Qt.alpha(Theme.tokens.text, 0.24)
                opacity: resultsBar.active ? 1 : 0
                Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
            }
        }
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var manifest: modelData.manifest
            readonly property bool engaged: launch.hovered || launch.visualFocus || favoriteAction.hovered || favoriteAction.visualFocus
            readonly property bool favorite: root.state.favorites.indexOf(manifest.id) >= 0
            objectName: 'sidebar-tool-' + manifest.id
            width: results.width
            height: 56
            ContinuousSurface {
                anchors.fill: parent
                objectName: 'sidebar-row-surface'
                fill: root.sidebar.dragHover.compatibleIds.indexOf(row.manifest.id) >= 0 ? Theme.tokens.surfaceOverlay
                    : launch.down ? Qt.alpha(Theme.tokens.text, 0.12)
                    : launch.visualFocus || root.keyboardSelection && row.ListView.isCurrentItem ? Theme.tokens.surfaceOverlay
                    : launch.hovered || favoriteAction.hovered ? Qt.alpha(Theme.tokens.text, 0.05) : 'transparent'
                Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                extent: Metrics.radiusMedium
            }
            Button {
                id: launch
                objectName: 'sidebar-launch-' + row.manifest.id
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: favoriteAction.left; rightMargin: 4 }
                hoverEnabled: true
                Accessible.name: row.manifest.name
                Accessible.description: root.description(row.manifest) + '. ' + row.manifest.tool.execution
                PentadToolTip {
                    visible: launch.hovered || launch.visualFocus
                    text: root.description(row.manifest)
                }
                background: Item {}
                contentItem: Item {
                    Glyph { x: 14; anchors.verticalCenter: parent.verticalCenter; symbol: root.symbol(row.manifest.id); color: launch.hovered || launch.visualFocus ? Qt.alpha(Theme.tokens.text, 0.8) : Theme.tokens.textMuted }
                    Item {
                        x: 48; width: parent.width - 56; height: parent.height
                        PentadText {
                            id: toolName
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width - (executionBadge.visible ? executionBadge.implicitWidth + 8 : 0))
                            text: row.manifest.name; color: launch.visualFocus ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.8); font.weight: Font.Medium; wrapMode: Text.NoWrap; elide: Text.ElideRight
                        }
                        PentadText {
                            id: executionBadge
                            visible: row.manifest.tool.execution !== 'local'
                            anchors { left: toolName.right; leftMargin: 8; baseline: toolName.baseline }
                            text: row.manifest.tool.execution === 'ai' ? 'AI' : 'Web'
                            role: 'caption'; color: Theme.tokens.textMuted; wrapMode: Text.NoWrap
                        }
                    }
                }
                padding: 0
                scale: down ? 0.97 : 1
                Behavior on scale { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.press } }
                onClicked: root.openTool(row.manifest.id)
            }
            SidebarButton {
                id: favoriteAction
                objectName: 'sidebar-favorite-' + row.manifest.id
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                width: 32; text: ''; accessibleName: (row.favorite ? 'Remove favorite ' : 'Favorite ') + row.manifest.name
                background: ContinuousSurface { fill: favoriteAction.visualFocus || favoriteAction.hovered ? Theme.tokens.surfaceOverlay : 'transparent'; extent: Metrics.radiusSmall }
                // Only pinned tools show their star at rest; others reveal it on hover or keyboard focus.
                Glyph {
                    anchors.centerIn: parent; symbol: 'tools/star'; pixelSize: Metrics.panelIcon
                    opacity: row.favorite || row.engaged ? 1 : 0
                    Behavior on opacity { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.short } }
                    color: row.favorite ? Theme.tokens.accent
                        : favoriteAction.hovered || favoriteAction.visualFocus ? Qt.alpha(Theme.tokens.text, 0.8) : Qt.alpha(Theme.tokens.textMuted, 0.7)
                }
                onClicked: root.state.toggleFavorite(row.manifest.id)
            }
            DropArea {
                anchors.fill: parent
                onEntered: function(drag) {
                    const info = root.sidebar.enterDrag(drag);
                    drag.accepted = !!info.mime && (info.deferredFileCheck || info.compatibleIds.indexOf(row.manifest.id) >= 0);
                    if (drag.accepted) drag.accept(Qt.CopyAction);
                }
                onExited: root.sidebar.leaveDrag()
                onDropped: function(drop) { root.sidebar.dropOnTile(drop, { toolId: row.manifest.id }); }
            }
        }
        Column {
            visible: results.count === 0
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 28 }
            spacing: 12
            PentadText { width: parent.width; text: root.state.pendingInput ? 'No compatible tools found' : 'No tools found'; role: 'section'; horizontalAlignment: Text.AlignHCenter; Accessible.role: Accessible.StaticText }
            SidebarButton { objectName: 'sidebar-reset-filters'; anchors.horizontalCenter: parent.horizontalCenter; text: 'Reset filters'; onClicked: root.resetFilters() }
        }
    }
    Column {
        id: catalogFooter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 8
        PentadText { visible: !!root.sidebar.ingressError; width: parent.width; text: root.sidebar.ingressError; role: 'caption'; color: Theme.tokens.error }
        SidebarButton { visible: !!root.sidebar.fileReadRequestId; text: 'Cancel file read'; onClicked: root.sidebar.services.fileInput.cancel(root.sidebar.fileReadRequestId) }
        Button {
            id: fileImport
            objectName: 'sidebar-choose-files'
            width: parent.width; height: 56
            enabled: !root.sidebar.fileReadRequestId && !(root.sidebar.services.filePicker && root.sidebar.services.filePicker.busy)
            hoverEnabled: true
            padding: 0
            scale: down ? 0.97 : 1
            Behavior on scale { enabled: !Theme.tokens.reducedMotion; NumberAnimation { duration: Motion.press } }
            Accessible.name: 'Choose files'
            Accessible.description: 'Choose local files to find a compatible tool. You can also drop text, links or files here.'
            PentadToolTip {
                visible: fileImport.hovered || fileImport.visualFocus
                text: fileImport.Accessible.description
            }
            onClicked: root.sidebar.chooseFiles('', [], '')
            HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: fileImport.enabled }
            background: ContinuousSurface {
                extent: Metrics.radiusMedium
                objectName: 'sidebar-import-surface'
                fill: fileImport.down ? Qt.alpha(Theme.tokens.text, 0.12)
                    : root.sidebar.dragHover.mime || fileImport.visualFocus ? Theme.tokens.surfaceOverlay
                    : fileImport.hovered ? Qt.alpha(Theme.tokens.text, 0.05) : Theme.tokens.surfaceRaised
                Behavior on fill { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
            }
            contentItem: Item {
                Glyph {
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    symbol: root.sidebar.dragHover.mime ? 'tools/input' : 'tools/folder-open'
                    color: fileImport.hovered || fileImport.visualFocus ? Qt.alpha(Theme.tokens.text, 0.8) : Theme.tokens.textMuted
                }
                Column {
                    x: 52; width: parent.width - 88
                    anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    PentadText {
                        objectName: 'sidebar-import-label'
                        width: parent.width
                        text: root.sidebar.dragHover.mime ? 'Release to find a tool' : 'Choose files'
                        font.weight: Font.Medium; color: fileImport.visualFocus ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.8); wrapMode: Text.NoWrap; elide: Text.ElideRight
                    }
                }
                BusyIndicator {
                    id: importBusy
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 20; height: 20
                    running: !!root.sidebar.fileReadRequestId || !!(root.sidebar.services.filePicker && root.sidebar.services.filePicker.busy)
                    visible: running
                    Accessible.name: 'Reading files'
                }
                Glyph {
                    visible: !importBusy.running
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    symbol: 'media/arrow-forward'; pixelSize: Metrics.panelIcon
                }
            }
            DropArea {
                anchors.fill: parent
                onEntered: function(drag) { const info = root.sidebar.enterDrag(drag); drag.accepted = !!info.mime; if (drag.accepted) drag.accept(Qt.CopyAction); }
                onExited: root.sidebar.leaveDrag()
                onDropped: function(drop) { root.sidebar.dropOnTile(drop, null); }
            }
        }
    }
}
