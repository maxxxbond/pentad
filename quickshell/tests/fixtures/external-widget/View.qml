import QtQuick
import qs.components

Item {
  id: widget
  readonly property var observedMedia: services.media ? services.media.state : null
  function togglePlayback() { return services.media.playPause(); }
  required property string instanceId
  required property var context
  required property var settings
  required property var services
  required property var controller

  implicitWidth: 280
  implicitHeight: 64

  PentadText {
    anchors.centerIn: parent
    text: settings.message
  }
}
