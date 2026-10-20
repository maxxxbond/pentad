pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import qs.components
import qs.plugins
import qs.theme
import '../../logic/sidebar.mjs' as Sidebar
import '../../logic/tool-catalog.mjs' as ToolLogic
import '../../logic/drag-drop.mjs' as DropLogic

Item {
    id: root
    required property var services
    required property string outputId
    readonly property var placements: Sidebar.sidebarPlacements(root.services.config.documents.layout.widgets, root.services.plugins.catalog)
    readonly property var activePlacement: root.placements.find(item => item.moduleId === root.toolState.selectedTool) || null
    readonly property var activeInstanceId: root.activePlacement ? root.activePlacement.instanceId : 'sidebar-tool-' + root.toolState.selectedTool
    readonly property var visiblePlacements: root.placements.filter(item => item.moduleId !== root.toolState.selectedTool)
    readonly property var toolState: root.services.toolWorkspace
    readonly property var toolEntries: { root.services.plugins.revision; return ToolLogic.toolEntries(root.services.plugins.catalog); }
    readonly property string pendingTypes: root.toolState.pendingInput
        ? (root.toolState.pendingInput.value || []).map(item => item.name || item.mimeType || item.kind).join(', ')
        : ''
    readonly property var visibleTools: {
        let entries = ToolLogic.searchTools(root.toolEntries, root.toolState.searchQuery,
            { favorites: root.toolState.favorites, recent: root.toolState.recent,
              view: root.toolState.catalogView, category: root.toolState.catalogCategory });
        if (root.toolState.pendingInput && !root.toolState.pendingInput.targetId)
            entries = entries.filter(entry => root.toolState.pendingInput.compatibleIds.indexOf(entry.manifest.id) >= 0);
        return entries;
    }
    property string ingressError: ''
    property string fileReadRequestId: ''
    property string fileReadTargetId: ''
    property var fileReadOtherItems: []
    property var dragHover: ({ compatibleIds: [], mime: '' })
    width: 390
    implicitWidth: width
    implicitHeight: 760
    height: implicitHeight

    Rectangle { anchors.fill: parent; color: Theme.tokens.surface }

    function routeItems(items, targetId) {
        const compatible = ToolLogic.compatibleTools(root.toolEntries, items).map(entry => entry.manifest.id);
        if (!compatible.length) {
            ingressError = 'No available tool accepts this input.';
            return false;
        }
        if (targetId && compatible.indexOf(targetId) < 0) {
            ingressError = 'This tool does not accept: ' + items.map(item => item.mimeType || item.kind).join(', ');
            return false;
        }
        ingressError = '';
        if (targetId) root.toolState.selectTool(targetId, true);
        else root.toolState.selectedTool = '';
        root.toolState.receive(items, compatible, targetId || '');
        if (targetId) inputDelivery.restart();
        return true;
    }
    function dragInfo(drag) {
        const mime = DropLogic.offerMime(drag.formats);
        if (!mime || typeof drag.getDataAsString !== 'function') return { mime: mime, compatibleIds: [] };
        const offer = DropLogic.readOffer(drag);
        if (!offer.ok) return { mime: '', compatibleIds: [] };
        if (!offer.value) return { mime: mime, compatibleIds: [], deferredFileCheck: true };
        if (mime !== 'text/uri-list') {
            return { mime: mime, compatibleIds: ToolLogic.compatibleTools(root.toolEntries,
                [ToolLogic.classifyText(offer.value)]).map(entry => entry.manifest.id) };
        }
        const parsed = ToolLogic.parseUriList(offer.value);
        const hasLocalFiles = parsed.ok && parsed.items.some(item => item.kind === 'file');
        return { mime: parsed.ok ? mime : '', compatibleIds: parsed.ok && !hasLocalFiles
            ? ToolLogic.compatibleTools(root.toolEntries, parsed.items).map(entry => entry.manifest.id) : [], deferredFileCheck: hasLocalFiles };
    }
    function loadUris(uris, targetId) {
        const parsed = ToolLogic.parseUriList(uris.join('\n'));
        if (!parsed.ok) { ingressError = 'The selected files could not be read.'; return false; }
        const files = parsed.items.filter(item => item.kind === 'file');
        const other = parsed.items.filter(item => item.kind !== 'file');
        if (!files.length) return routeItems(other, targetId);
        if (!root.services.fileInput) { ingressError = 'Local file reading is unavailable.'; return false; }
        if (fileReadRequestId) root.services.fileInput.cancel(fileReadRequestId);
        const entry = targetId ? root.toolEntries.find(item => item.manifest.id === targetId) : null;
        const limit = entry ? entry.manifest.tool.maxBytes : 262144;
        fileReadTargetId = targetId || '';
        fileReadOtherItems = other;
        fileReadRequestId = root.services.fileInput.readUris(files.map(item => item.uri), limit);
        return !!fileReadRequestId;
    }
    function handleDrop(drop, targetId) {
        const offer = DropLogic.readOffer(drop);
        const mime = offer.mime;
        if (!offer.ok) { ingressError = offer.reason === 'too-large' ? 'The dropped input exceeds the size limit.' : 'This data type is not supported.'; drop.accepted = false; return; }
        let items;
        if (mime === 'text/uri-list') {
            const parsed = ToolLogic.parseUriList(offer.value);
            if (!parsed.ok) { ingressError = parsed.reason === 'empty' ? '' : 'Only local files and HTTP(S) URLs are supported.'; drop.accepted = false; return; }
            if (parsed.items.some(item => item.kind === 'file')) {
                const accepted = root.loadUris(parsed.items.map(item => item.kind === 'file' ? item.uri : item.value), targetId);
                if (accepted) drop.accept(Qt.CopyAction); else drop.accepted = false;
                return;
            }
            items = parsed.items;
        } else items = [ToolLogic.classifyText(offer.value)];
        if (!root.routeItems(items, targetId)) { drop.accepted = false; return; }
        drop.accept(Qt.CopyAction);
    }
    function applyIncoming(choice) {
        const pending = root.toolState.pendingInput;
        const id = root.toolState.selectedTool;
        if (!pending || !id || pending.compatibleIds.indexOf(id) < 0) return;
        const entry = root.toolEntries.find(item => item.manifest.id === id);
        if (ToolLogic.inputBytes(pending.value) > entry.manifest.tool.maxBytes) {
            ingressError = 'The combined input exceeds this tool’s limit.';
            return;
        }
        if (!activeTool.view || typeof activeTool.view.acceptInput !== 'function'
            || !activeTool.view.acceptInput(pending.value, choice || '')) {
            ingressError = 'This tool could not read the supplied input; its draft is unchanged.';
            return;
        }
        root.toolState.clearIngress();
        ingressError = '';
    }

    Connections {
        target: root.services.fileInput || null
        function onCommandFinished(requestId, result) {
            if (requestId !== root.fileReadRequestId) return;
            const targetId = root.fileReadTargetId;
            const otherItems = root.fileReadOtherItems;
            root.fileReadRequestId = '';
            root.fileReadOtherItems = [];
            if (!result.ok) { root.ingressError = result.reason || 'Could not read selected files.'; return; }
            root.routeItems(result.items.concat(otherItems), targetId);
        }
    }
    Timer {
        id: inputDelivery
        interval: 0
        repeat: false
        onTriggered: {
            const pending = root.toolState.pendingInput;
            if (!pending || !root.toolState.selectedTool || pending.compatibleIds.indexOf(root.toolState.selectedTool) < 0) return;
            root.applyIncoming('');
        }
    }

    function chooseFiles() { fileDialog.open(); }
    function showCatalog() {
        root.toolState.selectedTool = '';
        root.ingressError = '';
    }
    FileDialog {
        id: fileDialog
        title: 'Choose files for a sidebar tool'
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            const parsed = ToolLogic.parseUriList(Array.from(selectedFiles).map(value => String(value)).join('\n'));
            if (!parsed.ok) { root.ingressError = 'The selected files could not be read.'; return; }
            root.toolState.selectedTool = '';
            root.loadUris(parsed.items.map(item => item.uri || item.value), '');
        }
    }
    ToolCatalog {
        id: catalog
        sidebar: root
        visible: !root.toolState.selectedTool
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: widgetSection.top; margins: 16; bottomMargin: widgetSection.visible ? 16 : 20 }
    }
    Item {
        id: workspaceHeader
        visible: !!root.toolState.selectedTool
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        height: visible ? 34 : 0
        SidebarButton {
            id: backButton
            objectName: 'sidebar-back-to-tools'
            text: '‹'; width: 34; accessibleName: 'Back to tools'
            onClicked: root.showCatalog()
        }
        Column {
            anchors { left: backButton.right; leftMargin: 8; right: workspaceFavorite.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 4
            PentadText {
                width: parent.width
                text: root.toolEntries.find(entry => entry.manifest.id === root.toolState.selectedTool)?.manifest.name || 'Tool'
                role: 'section'; font.weight: Font.Medium; wrapMode: Text.NoWrap; elide: Text.ElideRight
            }
            PentadText {
                readonly property string execution: root.toolEntries.find(entry => entry.manifest.id === root.toolState.selectedTool)?.manifest.tool.execution || 'local'
                visible: execution !== 'local'
                text: execution === 'ai' ? 'AI' : 'Web'
                role: 'caption'; color: Theme.tokens.textMuted
            }
        }
        SidebarButton {
            id: workspaceFavorite
            anchors.right: parent.right; width: 34
            text: root.toolState.favorites.indexOf(root.toolState.selectedTool) >= 0 ? '★' : '☆'
            accessibleName: 'Toggle favorite'
            onClicked: root.toolState.toggleFavorite(root.toolState.selectedTool)
        }
    }
    PentadScrollView {
        id: mainScroll
        visible: !!root.toolState.selectedTool
        anchors { left: parent.left; right: parent.right; top: workspaceHeader.bottom; bottom: widgetSection.top; margins: 16 }
        contentWidth: availableWidth
        contentHeight: content.implicitHeight
        Column {
            id: content
            width: mainScroll.availableWidth
            spacing: 12
            Item {
                visible: !!root.toolState.selectedTool
                width: parent.width
                implicitHeight: activeContent.implicitHeight
                Column {
                    id: activeContent
                    width: parent.width
                    spacing: 8
                    PluginHost {
                        id: activeTool
                        objectName: 'sidebar-active-tool'
                        width: parent.width
                        height: implicitHeight
                        instanceId: root.activeInstanceId
                        moduleId: root.toolState.selectedTool
                        settings: root.activePlacement ? root.activePlacement.settings : ({})
                        context: ({ slot: 'sidebar-left', outputId: root.outputId, compact: false, preview: root.services.preview })
                        services: root.services
                        registry: root.services.plugins
                        onViewChanged: inputDelivery.restart()
                    }
                    Row {
                        visible: !!root.toolState.pendingInput
                        width: parent.width; spacing: 8
                        SidebarButton { text: 'Replace'; visible: !!root.ingressError; requestedEnabled: !!root.toolState.pendingInput && root.toolState.pendingInput.compatibleIds.indexOf(root.toolState.selectedTool) >= 0; onClicked: root.applyIncoming('replace') }
                        SidebarButton { text: 'Append'; visible: !!root.ingressError && !!activeTool.view && !!activeTool.view.canAppendInput; requestedEnabled: !!root.toolState.pendingInput; onClicked: root.applyIncoming('append') }
                        SidebarButton { text: 'Cancel'; onClicked: root.toolState.clearIngress() }
                    }
                    PentadText {
                        visible: !!root.ingressError || !!root.toolState.ingressMessage
                        width: parent.width
                        text: root.ingressError || root.toolState.ingressMessage
                        role: 'caption'; color: Theme.tokens.error; wrapMode: Text.Wrap
                    }
                    DropArea {
                        width: parent.width; height: 48
                        onEntered: function(drag) {
                            const info = root.dragInfo(drag);
                            root.dragHover = info;
                            drag.accepted = !!info.mime && (info.deferredFileCheck || info.compatibleIds.indexOf(root.toolState.selectedTool) >= 0);
                            if (drag.accepted) drag.accept(Qt.CopyAction);
                        }
                        onExited: root.dragHover = ({ compatibleIds: [], mime: '' })
                        onDropped: function(drop) { root.dragHover = ({ compatibleIds: [], mime: '' }); root.handleDrop(drop, root.toolState.selectedTool); }
                        ContinuousSurface { anchors.fill: parent; extent: Metrics.radiusSmall; fill: Theme.tokens.surfaceOverlay; visible: root.dragHover.compatibleIds.indexOf(root.toolState.selectedTool) >= 0 }
                        PentadText { anchors.centerIn: parent; text: root.dragHover.compatibleIds.indexOf(root.toolState.selectedTool) >= 0 ? 'Release to load this input' : 'Drop here to check supported types'; role: 'caption'; color: Theme.tokens.textMuted }
                    }
                }
            }
        }
    }
    Column {
        id: widgetSection
        visible: root.visiblePlacements.length > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: visible ? 16 : 0 }
        height: visible ? Math.min(root.height * 0.32, widgetColumn.implicitHeight + 40) : 0
        spacing: 12
        PentadText { text: 'Widgets'; role: 'section' }
        PentadScrollView {
            id: widgetScroll
            width: parent.width
            height: Math.max(0, widgetSection.height - 44)
            contentWidth: availableWidth
            contentHeight: widgetColumn.implicitHeight
            Column {
                id: widgetColumn
                width: widgetScroll.availableWidth
                spacing: 12
                Repeater {
                    model: root.visiblePlacements
                    delegate: PentadCard {
                        required property var modelData
                        objectName: 'sidebar-placement-' + modelData.instanceId
                        // Outer margin narrows the card; inner padding adds to the card's own 12 px inset.
                        x: modelData.frame ? modelData.frame.margin : 0
                        width: widgetColumn.width - 2 * x
                        implicitHeight: widget.implicitHeight + 24 + 2 * framePadding
                        readonly property real framePadding: modelData.frame ? modelData.frame.padding : 0
                        PluginHost {
                            id: widget
                            objectName: 'sidebar-widget-' + modelData.instanceId
                            x: 12 + framePadding; y: 12 + framePadding
                            width: parent.width - 24 - 2 * framePadding
                            height: implicitHeight
                            instanceId: modelData.instanceId
                            moduleId: modelData.moduleId
                            settings: modelData.settings
                            context: ({ slot: 'sidebar-left', outputId: root.outputId, compact: false, preview: root.services.preview,
                                placementZone: modelData.zone, placementSize: modelData.size })
                            services: root.services
                            registry: root.services.plugins
                        }
                    }
                }
            }

        }
    }
}
