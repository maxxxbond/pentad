import QtQuick
import QtQml
import "../../logic/__NAME__.mjs" as __LOGIC__

QtObject {
    id: placementController
    required property string instanceId
    required property var settings
    required property var services

    readonly property string summary: __LOGIC__.summarize(settings)
}
