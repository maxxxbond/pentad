pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme
import "../../logic/settings-catalog.mjs" as Catalog
import "../../logic/settings-search.mjs" as Search

Item {
    id: root
    required property var services
    readonly property string query: services.settings.query
    readonly property string lang: services.text("uk", "en")
    readonly property real gutter: 24
    readonly property var results: Search.search(Catalog.pages, query, lang)
    readonly property var groupsModel: {
        const byPage = {};
        const order = [];
        for (const hit of results) {
            if (!byPage[hit.pageId]) {
                byPage[hit.pageId] = { pageId: hit.pageId, hits: [] };
                order.push(hit.pageId);
            }
            byPage[hit.pageId].hits.push(hit);
        }
        return order.map(function(id) {
            const page = Catalog.pages.find(function(entry) { return entry.id === id; });
            return {
                pageId: id,
                label: page ? root.services.text(page.labelUk, page.labelEn) : id,
                hits: byPage[id].hits,
            };
        });
    }

    function open(pageId, tabId) {
        services.settings.openPage(pageId, tabId);
        services.settings.setQuery("");
    }

    PentadIcon {
        objectName: "settings-search-empty"
        visible: root.results.length === 0
        anchors.centerIn: parent
        source: Qt.resolvedUrl("../../assets/icons/material/media/search-symbolic.svg")
        pixelSize: 48
        color: Theme.tokens.textMuted
        opacity: 0.6
        accessibleName: root.services.text("Нічого не знайдено", "No results")
    }

    PentadScrollView {
        anchors.fill: parent
        visible: root.results.length > 0
        contentWidth: availableWidth
        clip: true
        Column {
            id: list
            x: root.gutter
            width: Math.max(0, root.width - 2 * root.gutter)
            topPadding: root.gutter
            bottomPadding: root.gutter
            spacing: 16
            Repeater {
                model: root.groupsModel
                delegate: Column {
                    id: group
                    required property var modelData
                    width: list.width
                    spacing: 4
                    PentadText {
                        width: parent.width
                        leftPadding: 4
                        text: group.modelData.label
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8
                        font.weight: Font.Medium
                        textFormat: Text.PlainText
                        role: "caption"
                        color: Theme.tokens.textMuted
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                    ContinuousSurface {
                        id: resultCard
                        width: parent.width
                        height: hitColumn.implicitHeight + 2 * Metrics.settingsInset
                        fill: Theme.tokens.surfaceRaised
                        extent: Metrics.radiusCard
                    Column {
                        id: hitColumn
                        x: Metrics.settingsInset
                        y: Metrics.settingsInset
                        width: resultCard.width - 2 * Metrics.settingsInset
                        spacing: 0
                    Repeater {
                        model: group.modelData.hits
                        delegate: Button {
                            id: hit
                            required property var modelData
                            objectName: "settings-result-" + modelData.pageId + "-" + modelData.key
                            width: hitColumn.width
                            implicitHeight: Metrics.settingsRailItem
                            leftPadding: 12
                            rightPadding: 12
                            focusPolicy: Qt.StrongFocus
                            text: modelData.label
                            Accessible.name: group.modelData.label + ": " + modelData.label
                            Accessible.role: Accessible.Button
                            onClicked: root.open(modelData.pageId, modelData.tabId)
                            background: ContinuousSurface {
                                fill: hit.down || hit.hovered ? Theme.tokens.surfaceOverlay : "transparent"
                                edge: hit.visualFocus ? Theme.tokens.accent : "transparent"
                                extent: Metrics.radiusSmall
                            }
                            contentItem: PentadText {
                                text: hit.text
                                textFormat: Text.PlainText
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }
                    }
                    }
                    }
                }
            }
        }
    }
}
