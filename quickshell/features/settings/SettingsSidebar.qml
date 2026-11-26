pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/settings-catalog.mjs" as Catalog
import "../../logic/settings-nav.mjs" as Nav

FocusScope {
    id: root
    required property var services
    property bool collapsed: false
    property bool searchExpanded: false
    // Optional count badges per page id, for example { widgets: 12 }.
    property var badges: ({})
    readonly property real inset: Metrics.settingsInset
    readonly property bool compact: collapsed
    readonly property real preferredWidth: collapsed ? Metrics.settingsRailWidth : Metrics.settingsNavWidth
    readonly property alias searchField: search
    readonly property string iconRoot: Qt.resolvedUrl("../../assets/icons/")
    readonly property var groupModels: {
        const flat = Nav.flatPages(Catalog.pages);
        return Object.keys(Catalog.groupCaptions).map(function(group) {
            return {
                group: group,
                caption: root.services.text(Catalog.groupCaptions[group].uk, Catalog.groupCaptions[group].en),
                pages: flat.filter(function(page) { return page.group === group; }),
            };
        }).filter(function(entry) { return entry.pages.length > 0; });
    }

    implicitWidth: preferredWidth
    Accessible.name: services.text("Налаштування", "Settings")
    Accessible.role: Accessible.PageTabList

    function focusSearch() {
        searchExpanded = true;
        search.forceActiveFocus();
        search.selectAll();
    }
    function pageLabel(page) {
        return services.text(page.labelUk, page.labelEn);
    }
    function select(pageId) {
        services.settings.openPage(pageId);
    }
    function focusPage(pageId) {
        for (let g = 0; g < groups.count; ++g) {
            const group = groups.itemAt(g);
            if (!group) continue;
            for (let p = 0; p < group.pageRepeater.count; ++p) {
                const entry = group.pageRepeater.itemAt(p);
                if (entry && entry.pageId === pageId) { entry.forceActiveFocus(); root.reveal(entry); return; }
            }
        }
    }
    // Keeps an entry selected from the keyboard inside the scrolled list.
    function reveal(entry) {
        const top = entry.mapToItem(nav, 0, 0).y;
        const bottom = top + entry.height;
        if (top < navFlick.contentY) navFlick.contentY = top;
        else if (bottom > navFlick.contentY + navFlick.height) navFlick.contentY = bottom - navFlick.height;
    }
    function move(delta) {
        const current = { pageId: services.settings.pageId, tabId: services.settings.tabId, query: "" };
        const next = Nav.moveSelection(current, Catalog.pages, delta);
        if (next.pageId === "" || next.pageId === services.settings.pageId) return;
        select(next.pageId);
        Qt.callLater(function() { root.focusPage(next.pageId); });
    }

    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.WindowShortcut
        onActivated: root.focusSearch()
    }
    Connections {
        target: root.services.settings
        function onQueryChanged() {
            if (search.text !== root.services.settings.query) search.text = root.services.settings.query;
        }
    }

    // Borderless: the sidebar is a slightly lifted tonal band, not a column behind a line.
    Rectangle {
        id: band
        objectName: "settings-sidebar-band"
        anchors.fill: parent
        color: Qt.alpha(Theme.tokens.text, 0.025)
    }

    // Search: a field in the full sidebar, a 40x40 button in the rail that opens
    // the field as an overlay.
    Item {
        id: searchBlock
        x: root.inset
        y: root.inset
        z: 30
        width: root.width - 2 * root.inset
        height: root.collapsed ? Metrics.settingsRailItem : Metrics.settingsNavItem

        PentadTextField {
            id: search
            objectName: "settings-search"
            visible: !root.collapsed || root.searchExpanded
            width: root.collapsed ? 288 : parent.width
            height: root.collapsed ? Metrics.settingsRailItem : Metrics.settingsNavItem
            capsule: Metrics.settingsFieldCapsule
            leftPadding: Metrics.space3 + Metrics.statusIcon + Metrics.space1
            rightPadding: root.collapsed ? Metrics.space3 : Metrics.space6 + Metrics.space2
            placeholderText: root.services.text("Пошук", "Search")
            accessibleName: root.services.text("Пошук у налаштуваннях", "Search settings")
            text: root.services.settings.query
            onTextEdited: root.services.settings.setQuery(text)
            onActiveFocusChanged: if (!activeFocus && text === "") root.searchExpanded = false
            PentadIcon {
                x: Metrics.space3
                anchors.verticalCenter: parent.verticalCenter
                source: root.iconRoot + "material/media/search-symbolic.svg"
                pixelSize: Metrics.statusIcon
                color: Theme.tokens.textMuted
            }
            Rectangle {
                objectName: "settings-search-hint"
                visible: !root.collapsed && !search.activeFocus && search.text === ""
                width: 20
                height: 20
                radius: Metrics.radiusTag
                color: Theme.tokens.surfaceOverlay
                anchors.right: parent.right
                anchors.rightMargin: Metrics.space2
                anchors.verticalCenter: parent.verticalCenter
                PentadText {
                    anchors.centerIn: parent
                    text: "/"
                    textFormat: Text.PlainText
                    role: "caption"
                    color: Theme.tokens.textMuted
                }
            }
        }
        SettingsNavItem {
            objectName: "settings-search-icon"
            visible: root.collapsed && !root.searchExpanded
            width: Metrics.settingsRailItem
            collapsed: true
            label: root.services.text("Пошук", "Search")
            iconSource: root.iconRoot + "material/media/search-symbolic.svg"
            active: root.services.settings.query !== ""
            onClicked: root.focusSearch()
        }
    }

    Flickable {
        id: navFlick
        x: root.inset
        y: searchBlock.y + searchBlock.height + Metrics.space1
        width: root.width - 2 * root.inset
        height: Math.max(0, root.height - root.inset - y)
        contentWidth: width
        contentHeight: nav.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        FocusScope {
            id: nav
            width: navFlick.width
            height: groupColumn.implicitHeight
            Keys.onPressed: function(event) {
                if (event.modifiers !== Qt.NoModifier) return;
                if (event.key === Qt.Key_Down) root.move(1);
                else if (event.key === Qt.Key_Up) root.move(-1);
                else if (event.key === Qt.Key_Home) root.move("first");
                else if (event.key === Qt.Key_End) root.move("last");
                else return;
                event.accepted = true;
            }
            Column {
                id: groupColumn
                width: parent.width
                spacing: 0
                Repeater {
                    id: groups
                    model: root.groupModels
                    delegate: Column {
                        id: group
                        required property var modelData
                        required property int index
                        readonly property alias pageRepeater: pages
                        width: groupColumn.width
                        spacing: Metrics.space1
                        // Sentence case, medium, muted: the same caption as above a section card.
                        PentadText {
                            visible: !root.collapsed
                            width: parent.width
                            leftPadding: Metrics.space3
                            rightPadding: Metrics.space3
                            topPadding: group.index === 0 ? Metrics.space3 : Metrics.space4
                            bottomPadding: 0
                            text: group.modelData.caption
                            textFormat: Text.PlainText
                            role: "caption"
                            color: Theme.tokens.textMuted
                            font.weight: Font.Medium
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                        // Collapsed rail: groups are told apart by a gap, not a divider line.
                        Item {
                            objectName: "settings-nav-divider"
                            visible: root.collapsed && group.index > 0
                            width: Metrics.settingsRailItem
                            height: 12
                        }
                        Repeater {
                            id: pages
                            model: group.modelData.pages
                            delegate: SettingsNavItem {
                                id: entry
                                required property var modelData
                                readonly property string pageId: modelData.id
                                objectName: "settings-nav-" + modelData.id
                                width: root.collapsed ? Metrics.settingsRailItem : group.width
                                collapsed: root.collapsed
                                label: root.pageLabel(modelData)
                                iconSource: root.iconRoot + modelData.icon
                                badge: root.badges[modelData.id] !== undefined ? String(root.badges[modelData.id]) : ""
                                active: root.services.settings.pageId === modelData.id
                                    && root.services.settings.query === ""
                                onClicked: root.select(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // No footer: a theme switch would promise a light theme that is not fully implemented yet
    // (user decision, 2026-10-19). The navigation runs to the bottom inset.
}
