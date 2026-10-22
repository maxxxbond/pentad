pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

Item {
    id: root
    required property var sidebar
    readonly property var state: sidebar.toolState
    readonly property var entries: sidebar.visibleTools
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
        if (results.currentIndex >= 0 && results.currentIndex < entries.length) openTool(entries[results.currentIndex].manifest.id);
    }
    function openTool(id) {
        state.catalogScrollY = results.contentY;
        state.selectTool(id, !!sidebar.toolState.pendingInput);
    }
    function description(manifest) {
        const purposes = {
            'pentad.json': 'Format and validate JSON',
            'pentad.text-cleaner': 'Clean whitespace and line breaks',
            'pentad.units': 'Convert length, mass, time and temperature',
            'pentad.qr': 'Turn text or a link into a QR code',
            'pentad.chat': 'Write, ask and explore with AI',
            'pentad.pdf': 'Compress, merge, split, rotate and protect PDFs',
            'pentad.images': 'Convert, resize, compress and clean photos',
            'pentad.image-text': 'Recognize text and read QR codes in images',
            'pentad.media': 'Compress video, make GIFs, convert and trim audio',
            'pentad.archive': 'Extract archives or pack files into ZIP and 7z',
            'pentad.checksum': 'Hash files and verify downloads',
            'pentad.translate': 'Translate text online',
            'pentad.codec': 'Base64, URL, HTML, hex and JWT',
            'pentad.timestamp': 'Convert Unix time and dates',
            'pentad.color': 'Convert HEX, RGB, HSL and OKLCH',
            'pentad.text-case': 'Change case, make slugs, count words',
            'pentad.yaml': 'Convert between YAML and JSON'
        };
        return purposes[manifest.id] || manifest.tool.category;
    }
    function symbol(id) {
        return ({ 'pentad.json': 'tools/data-object', 'pentad.text-cleaner': 'media/format-align-left',
            'pentad.units': 'tools/straighten', 'pentad.qr': 'tools/qr-code-2', 'pentad.chat': 'tools/chat-bubble',
            'pentad.pdf': 'tools/picture-as-pdf', 'pentad.images': 'tools/image', 'pentad.image-text': 'ocr',
            'pentad.media': 'tools/movie', 'pentad.archive': 'tools/folder-zip', 'pentad.checksum': 'tools/fingerprint',
            'pentad.translate': 'translate', 'pentad.codec': 'tools/code', 'pentad.timestamp': 'tools/schedule',
            'pentad.color': 'tools/palette', 'pentad.text-case': 'tools/match-case', 'pentad.yaml': 'tools/data-array' })[id] || 'tools/extension';
    }
    onVisibleChanged: if (visible) Qt.callLater(function() {
        results.contentY = Math.max(results.originY, Math.min(state.catalogScrollY,
            Math.max(results.originY, results.contentHeight - results.height)));
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
        accessibleName: label
        opened: choices.opened
        onClicked: choices.toggle()
        contentItem: Item {
            PentadText {
                anchors { left: parent.left; right: chevron.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: selector.label; wrapMode: Text.NoWrap; elide: Text.ElideRight
                color: selector.visualFocus ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.8)
            }
            PentadChevron {
                id: chevron
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                direction: "down"
                pixelSize: Metrics.panelIcon
                engaged: selector.hovered || selector.visualFocus
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
        id: header
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
        anchors { top: header.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: footer.top; bottomMargin: 12 }
        clip: true
        model: root.entries
        spacing: 4
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
                Glyph {
                    anchors.centerIn: parent; symbol: 'tools/star'; pixelSize: Metrics.panelIcon
                    color: row.favorite ? Theme.tokens.accent
                        : favoriteAction.hovered || favoriteAction.visualFocus ? Qt.alpha(Theme.tokens.text, 0.8) : Qt.alpha(Theme.tokens.textMuted, 0.5)
                }
                onClicked: root.state.toggleFavorite(row.manifest.id)
            }
            DropArea {
                anchors.fill: parent
                onEntered: function(drag) {
                    const info = root.sidebar.dragInfo(drag);
                    root.sidebar.dragHover = info;
                    drag.accepted = !!info.mime && (info.deferredFileCheck || info.compatibleIds.indexOf(row.manifest.id) >= 0);
                    if (drag.accepted) drag.accept(Qt.CopyAction);
                }
                onExited: root.sidebar.dragHover = ({ compatibleIds: [], mime: '' })
                onDropped: function(drop) { root.sidebar.dragHover = ({ compatibleIds: [], mime: '' }); root.sidebar.handleDrop(drop, row.manifest.id); }
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
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 8
        PentadText { visible: !!root.sidebar.ingressError; width: parent.width; text: root.sidebar.ingressError; role: 'caption'; color: Theme.tokens.error }
        SidebarButton { visible: !!root.sidebar.fileReadRequestId; text: 'Cancel file read'; onClicked: root.sidebar.services.fileInput.cancel(root.sidebar.fileReadRequestId) }
        Button {
            id: fileImport
            objectName: 'sidebar-choose-files'
            width: parent.width; height: 56
            enabled: !root.sidebar.fileReadRequestId
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
            onClicked: root.sidebar.chooseFiles()
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
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 20; height: 20
                    running: !!root.sidebar.fileReadRequestId
                    visible: running
                    Accessible.name: 'Reading files'
                }
                Glyph {
                    visible: !root.sidebar.fileReadRequestId
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    symbol: 'media/arrow-forward'; pixelSize: Metrics.panelIcon
                }
            }
            DropArea {
                anchors.fill: parent
                onEntered: function(drag) { const info = root.sidebar.dragInfo(drag); root.sidebar.dragHover = info; drag.accepted = !!info.mime; if (drag.accepted) drag.accept(Qt.CopyAction); }
                onExited: root.sidebar.dragHover = ({ compatibleIds: [], mime: '' })
                onDropped: function(drop) { root.sidebar.dragHover = ({ compatibleIds: [], mime: '' }); root.sidebar.handleDrop(drop, ''); }
            }
        }
    }
}
