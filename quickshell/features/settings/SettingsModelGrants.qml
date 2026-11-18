pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import "../../logic/models-settings.mjs" as Rules

// Rows under "Local only" on the privacy card: one per external widget that declares
// capabilities, with its id, the capabilities it asks for and a switch that lets it use a cloud
// model (grants[moduleId].remote). A remote grant for a widget that is no longer installed stays
// listed so it can be withdrawn. While "Local only" is on, the switches have no effect and rest.
Item {
    id: root
    required property var services
    readonly property var ms: services ? services.modelSettings : null
    readonly property var document: ms ? ms.document : null
    readonly property var catalog: {
        const plugins = services ? services.plugins : null;
        // Read so that the rows follow a plugin (un)install.
        const revision = plugins ? plugins.revision : 0;
        return plugins && revision !== null ? plugins.catalog : ({});
    }
    readonly property var rows: Rules.grantRows(catalog, document)
    readonly property bool localOnly: !!document && !!document.privacy && document.privacy.localOnly === true
    readonly property bool writable: !!ms && ms.writableState.ok
    objectName: "settings-model-grants"
    implicitHeight: list.height

    function t(uk, en) { return services.text(uk, en); }

    Column {
        id: list
        width: root.width
        Repeater {
            model: root.rows
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool busy: !!root.ms && root.ms.busy === "grant:" + modelData.moduleId
                objectName: "settings-model-grant-" + modelData.moduleId
                width: list.width
                height: Metrics.settingsRowMinHeight
                Accessible.role: Accessible.Grouping
                Accessible.name: modelData.name

                Rectangle {
                    x: Metrics.space4
                    width: row.width - 2 * Metrics.space4
                    height: 1
                    color: Theme.tokens.outline
                }
                PentadIcon {
                    id: icon
                    x: Metrics.space5
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl("../../assets/icons/material/extension-symbolic.svg")
                    pixelSize: Metrics.panelIcon
                    color: Theme.tokens.textMuted
                    Accessible.ignored: true
                }
                Row {
                    anchors.left: icon.right
                    anchors.leftMargin: Metrics.space2
                    anchors.right: trailing.left
                    anchors.rightMargin: Metrics.space3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.space2
                    clip: true
                    PentadText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name
                        textFormat: Text.PlainText
                        font.weight: Font.Medium
                        color: row.modelData.installed ? Theme.tokens.text : Theme.tokens.textMuted
                        wrapMode: Text.NoWrap
                    }
                    PentadText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.installed ? row.modelData.moduleId : root.t("не встановлено", "not installed")
                        textFormat: Text.PlainText
                        role: "caption"
                        font.family: row.modelData.installed ? "monospace" : Theme.tokens.fontFamily
                        color: Theme.tokens.textMuted
                        wrapMode: Text.NoWrap
                    }
                }
                Row {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.space4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.space2
                    Repeater {
                        model: row.modelData.capabilities
                        delegate: SettingsModelTag {
                            required property string modelData
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            text: modelData
                        }
                    }
                    PentadText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.localOnly ? root.t("лише локально", "local only") : root.t("хмара", "cloud")
                        textFormat: Text.PlainText
                        role: "caption"
                        color: Theme.tokens.textMuted
                        wrapMode: Text.NoWrap
                    }
                    PentadToggle {
                        objectName: "settings-model-grant-toggle-" + row.modelData.moduleId
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: Metrics.controlSmall
                        accessibleName: root.t("Дозволити хмару для ", "Allow the cloud for ") + row.modelData.name
                        checked: row.modelData.remote
                        pending: row.busy
                        requestedEnabled: root.writable && !root.localOnly
                        onToggled: {
                            root.ms.setGrant(row.modelData.moduleId, checked);
                            checked = Qt.binding(function() { return row.modelData.remote; });
                        }
                    }
                }
            }
        }
    }
}
