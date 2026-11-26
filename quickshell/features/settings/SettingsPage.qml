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
    readonly property real gutter: Metrics.space5
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
    Component.onCompleted: {
        resolveTab();
        ready = true;
    }
    // A page or tab change, or coming back from search, fades the content in. Opacity only, so the
    // layout is final from the first frame; nothing fades while the page is first built.
    property bool ready: false
    function revealBody() {
        if (ready && !Motion.reducedMotion) bodyReveal.restart();
    }
    onTabIdChanged: revealBody()
    onVisibleChanged: if (visible) revealBody()
    NumberAnimation {
        id: bodyReveal
        target: body
        property: "opacity"
        from: 0
        to: 1
        duration: Motion.reveal
        easing.type: Motion.easeEnter
    }
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
    onPageIdChanged: {
        confirmingReset = false;
        revealBody();
    }
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
        // Base-4: 16 above the title, 36 title, then 12 (or the 34 px tab strip plus 4).
        height: top.y + top.height + (root.hasTabs ? tabs.height + Metrics.space1 : Metrics.space3)
        Item {
            id: top
            x: root.gutter
            y: Metrics.space4
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
                anchors.leftMargin: Metrics.space2
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
                x: root.backLabel !== "" ? crumbLabel.x + crumbLabel.width + Metrics.space2 : 0
                width: Math.max(0, top.width - x - actions.width - Metrics.space4)
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
                spacing: Metrics.space3
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
            }
        }
        PentadSmoothTabs {
            id: tabs
            objectName: "settings-page-tabs"
            x: root.gutter
            y: top.y + top.height
            width: Math.min(implicitWidth, header.width - 2 * root.gutter)
            visible: root.hasTabs
            panelHeight: 0
            fill: Theme.tokens.surfaceRaised
            activateOnPress: true
            segmentObjectName: "settings-page-tab-"
            accessibleName: root.page ? root.t(root.page.labelUk, root.page.labelEn) : root.t("Вкладки", "Tabs")
            options: root.tabList.map(function(tab) { return { value: tab.id, label: root.t(tab.labelUk, tab.labelEn) }; })
            onActivated: function(index) { root.tabId = String(root.tabList[index].id); }
        }
        // A Binding, not a plain binding: the tabs assign currentIndex themselves on a tap, which would drop a plain one.
        Binding {
            target: tabs
            property: "currentIndex"
            value: Math.max(0, root.tabList.findIndex(function(tab) { return tab.id === root.tabId; }))
        }
    }

    // The header stays put while the page scrolls: a hairline closes it off only while content is
    // scrolled underneath, so a page at rest keeps a clean top.
    Rectangle {
        objectName: "settings-page-header-rule"
        x: 0
        y: header.height - height
        width: parent.width
        height: 1
        color: Theme.tokens.outline
        opacity: scroll.ScrollBar.vertical.position > 0 ? 1 : 0
        Behavior on opacity {
            enabled: !Theme.tokens.reducedMotion
            NumberAnimation {
                duration: Motion.short
                easing.type: Motion.easeStandard
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
            topPadding: Metrics.space5
            bottomPadding: Metrics.space6
            spacing: Metrics.space5

            Repeater {
                model: root.visibleSections
                delegate: SettingsSection {
                    id: section
                    required property var modelData
                    width: body.width
                    title: root.t(modelData.source.labelUk, modelData.source.labelEn)
                    // A section made only of full-bleed editors (widget catalog, wallpaper gallery, device panels) draws no card.
                    framed: !modelData.items.every(function(item) {
                        return item.control === "catalog" || item.control === "wallpapers" || item.control === "panel";
                    })
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
            PentadButton {
                id: resetButton
                objectName: "settings-page-reset"
                // Its label starts on the rows' leading line: the capsule keeps 12 px around the text.
                x: Metrics.settingsRowInset - Metrics.space3
                visible: root.modifiedCount > 0
                controlHeight: Metrics.controlSmall
                checked: root.confirmingReset
                // Quiet until armed: no resting fill and muted ink, so it does not compete with the page title.
                restFill: "transparent"
                ink: Theme.tokens.textMuted
                text: root.confirmingReset
                    ? root.t("Підтвердити скидання (" + root.modifiedCount + ")", "Confirm reset (" + root.modifiedCount + ")")
                    : root.t("Скинути зміни (" + root.modifiedCount + ")", "Reset changes (" + root.modifiedCount + ")")
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
}
