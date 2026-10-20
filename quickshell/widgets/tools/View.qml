import QtQuick
import qs.features.bar

ToolsWidget {
    required property string instanceId
    required property var context
    required property var settings
    required property var controller
    signal actionRequested(string action)
    onActivated: function(action) { actionRequested(action) }
}
