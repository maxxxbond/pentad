pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/settings-catalog.mjs" as Catalog
import "../../logic/settings-bindings.mjs" as Bindings
import "../../logic/settings-state.mjs" as State

Item {
    id: root
    required property var services
    property string pageId: services.settings.pageId
    property string tabId: ""
    readonly property var documents: services.config.documents
    // A page built elsewhere (for example a widget's settings page); replaces the catalog lookup.
    property var pageOverride: null
    // Non-empty label shows a back button and breadcrumb before the title.
    property string backLabel: ""
    signal back()
    readonly property var page: pageOverride !== null ? pageOverride
        : Catalog.pages.find(function(entry) { return entry.id === root.pageId; }) || null
    readonly property var tabList: page && page.tabs ? page.tabs : []
    readonly property bool hasTabs: tabList.length > 0
    readonly property real gutter: 24
    // Header API, driven by the settings controller.
    property int modifiedCount: root.page ? State.modifiedItems(root.documents, root.page).length : 0
    // "" | "saving" | "saved" | "undo"
    property string status: services.settings.status
    property bool confirmingReset: false
    signal resetRequested()
    signal undoRequested()
    onResetRequested: services.settings.resetPage(root.pageOverride !== null ? root.pageOverride : root.pageId)
    onUndoRequested: services.settings.undo()

    function t(uk, en) { return services.text(uk, en); }
    function resolveTab() {
        const tabList = page && page.tabs ? page.tabs : [];
        if (tabList.length === 0) { tabId = ""; return; }
        const wanted = pageOverride !== null ? tabId : services.settings.tabId;
        const known = tabList.some(function(tab) { return tab.id === wanted; });
        tabId = known ? wanted : tabList[0].id;
    }
    onPageChanged: resolveTab()
    Component.onCompleted: resolveTab()
    // A tab request for the page already shown (search hit, IPC alias) must switch tabs too.
    Connections {
        target: root.services.settings
        function onTabIdChanged() { if (root.pageOverride === null) root.resolveTab(); }
    }

    function findItem(key) {
        if (!page) return null;
        for (const section of page.sections)
            for (const item of section.items) if (item.key === key) return item;
        return null;
    }
    function itemVisible(item) {
        if (!item.visibleWhen) return true;
        const other = findItem(item.visibleWhen.key);
        if (!other) return true;
        return Bindings.readValue(documents, other) === item.visibleWhen.equals;
    }
    readonly property var visibleSections: {
        if (!page) return [];
        const result = [];
        for (const section of page.sections) {
            if (hasTabs && section.tab !== undefined && section.tab !== tabId) continue;
            const items = section.items.filter(function(item) { return root.itemVisible(item); });
            if (items.length > 0) result.push({ id: section.id, source: section, items: items });
        }
        return result;
    }

    onModifiedCountChanged: if (modifiedCount === 0) confirmingReset = false
    onPageIdChanged: confirmingReset = false
    Timer {
        id: confirmTimeout
        interval: 4000
        running: root.confirmingReset
        onTriggered: root.confirmingReset = false
    }

    Item {
        id: header
        objectName: "settings-page-header"
        x: 0
        y: 0
        width: parent.width
        // Base-4: 16 above the title, 36 title, then 12 (or the 36 px tab strip plus 4).
        height: top.y + top.height + (root.hasTabs ? tabs.height + 4 : 12)
        Item {
            id: top
            x: root.gutter
            y: 16
            width: header.width - 2 * root.gutter
            height: 36
            PentadButton {
                id: backButton
                objectName: "settings-page-back"
                visible: root.backLabel !== ""
                anchors.verticalCenter: parent.verticalCenter
                chevron: "left"
                controlHeight: Metrics.controlSmall
                accessibleName: root.backLabel
                onClicked: root.back()
            }
            PentadText {
                id: crumbLabel
                objectName: "settings-page-crumb"
                visible: root.backLabel !== ""
                anchors.left: backButton.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.backLabel + " ›"
                textFormat: Text.PlainText
                role: "caption"
                color: Theme.tokens.textMuted
            }
            PentadText {
                id: titleLabel
                objectName: "settings-page-title"
                anchors.verticalCenter: parent.verticalCenter
                x: root.backLabel !== "" ? crumbLabel.x + crumbLabel.width + 8 : 0
                width: Math.max(0, top.width - x - actions.width - 16)
                text: root.page ? root.t(root.page.labelUk, root.page.labelEn) : ""
                textFormat: Text.PlainText
                role: "title"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                Accessible.role: Accessible.Heading
            }
            Row {
                id: actions
                objectName: "settings-page-actions"
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                spacing: 12
                layoutDirection: Qt.LeftToRight
                PentadText {
                    id: statusLabel
                    objectName: "settings-page-status"
                    visible: root.status === "saving" || root.status === "saved"
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.status === "saving" ? root.t("Збереження…", "Saving…") : root.t("Збережено", "Saved")
                    textFormat: Text.PlainText
                    role: "caption"
                    color: root.status === "saved" ? Theme.tokens.success : Theme.tokens.textMuted
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                PentadButton {
                    id: undoButton
                    objectName: "settings-page-undo"
                    visible: root.status === "undo"
                    anchors.verticalCenter: parent.verticalCenter
                    controlHeight: Metrics.controlSmall
                    text: root.t("Скасувати", "Undo")
                    accessibleName: text
                    onClicked: root.undoRequested()
                }
                PentadButton {
                    id: resetButton
                    objectName: "settings-page-reset"
                    visible: root.modifiedCount > 0
                    anchors.verticalCenter: parent.verticalCenter
                    controlHeight: Metrics.controlSmall
                    checked: root.confirmingReset
                    text: root.confirmingReset
                        ? root.t("Підтвердити скидання " + root.modifiedCount, "Confirm reset " + root.modifiedCount)
                        : root.t("Скинути " + root.modifiedCount, "Reset " + root.modifiedCount)
                    accessibleName: text
                    onClicked: {
                        if (root.confirmingReset) {
                            root.confirmingReset = false;
                            root.resetRequested();
                        } else {
                            root.confirmingReset = true;
                        }
                    }
                    onActiveFocusChanged: if (!activeFocus) root.confirmingReset = false
                }
            }
        }
        PentadTabs {
            id: tabs
            objectName: "settings-page-tabs"
            x: root.gutter
            y: top.y + top.height
            width: header.width - 2 * root.gutter
            visible: root.hasTabs
            implicitHeight: 36
            accessibleName: root.page ? root.t(root.page.labelUk, root.page.labelEn) : "Tabs"
            // Not a binding: the bar adds its buttons one by one and resets the index, which loops with tabId.
            // The index follows tabId only once every tab exists, and user changes flow back the same way.
            property bool syncing: false
            readonly property bool complete: root.tabList.length > 0 && count === root.tabList.length
            function syncIndex() {
                if (!complete) return;
                const wanted = Math.max(0, root.tabList.findIndex(function(tab) { return tab.id === root.tabId; }));
                if (currentIndex === wanted) return;
                syncing = true;
                currentIndex = wanted;
                syncing = false;
            }
            onCompleteChanged: syncIndex()
            Connections {
                target: root
                function onTabIdChanged() { tabs.syncIndex(); }
            }
            onCurrentIndexChanged: {
                if (syncing || !complete) return;
                if (currentIndex >= 0 && currentIndex < root.tabList.length && root.tabList[currentIndex].id !== root.tabId)
                    root.tabId = root.tabList[currentIndex].id;
            }
            background: Item {}
            contentItem: Row {
                spacing: 4
                layoutDirection: tabs.mirrored ? Qt.RightToLeft : Qt.LeftToRight
                Repeater {
                    model: tabs.count
                    delegate: Button {
                        id: tabButton
                        required property int index
                        property var sourceTab: tabs.itemAt(index)
                        text: sourceTab ? sourceTab.text : ""
                        checked: index === tabs.currentIndex
                        implicitWidth: label.implicitWidth + 28
                        implicitHeight: 36
                        Accessible.role: Accessible.PageTab
                        Accessible.name: text
                        onPressed: tabs.setCurrentIndex(index)
                        background: Item {
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 2
                                color: tabButton.checked ? Theme.tokens.accent : "transparent"
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.bottomMargin: 2
                                radius: Metrics.radiusSmall
                                color: "transparent"
                                border.width: tabButton.visualFocus ? 2 : 0
                                border.color: Theme.tokens.accent
                            }
                        }
                        contentItem: Text {
                            id: label
                            text: tabButton.text
                            color: tabButton.checked || tabButton.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                            font.family: Theme.tokens.fontFamily
                            font.pixelSize: Metrics.textBody
                            font.weight: tabButton.checked ? Font.Medium : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
            Repeater {
                model: root.tabList
                delegate: TabButton {
                    required property var modelData
                    text: root.t(modelData.labelUk, modelData.labelEn)
                }
            }
        }
    }

    PentadScrollView {
        id: scroll
        x: 0
        y: header.height
        width: parent.width
        height: parent.height - header.height
        contentWidth: availableWidth
        clip: true
        Column {
            id: body
            x: root.gutter
            width: Math.max(0, scroll.availableWidth - 2 * root.gutter)
            topPadding: 20
            bottomPadding: 28
            spacing: 24

            Repeater {
                model: root.visibleSections
                delegate: SettingsSection {
                    id: section
                    required property var modelData
                    width: body.width
                    title: root.t(modelData.source.labelUk, modelData.source.labelEn)
                    // A section made only of full-bleed editors (widget catalog, wallpaper gallery) draws no card.
                    framed: !modelData.items.every(function(item) { return item.control === "catalog" || item.control === "wallpapers"; })
                    helpText: modelData.source.helpUk !== undefined || modelData.source.helpEn !== undefined
                        ? root.t(modelData.source.helpUk, modelData.source.helpEn) : ""
                    infoAccessibleName: root.t("Про цей розділ", "About this section")
                    Repeater {
                        model: section.modelData.items
                        delegate: SettingsField {
                            required property var modelData
                            width: section.width
                            item: modelData
                            controller: root.services.settings
                            documents: root.documents
                            services: root.services
                        }
                    }
                }
            }
        }
    }
}
