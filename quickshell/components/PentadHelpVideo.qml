import QtQuick
import QtMultimedia

// The looping, muted clip inside a PentadInfoButton explanation; loaded by URL only when one is set.
Video {
    autoPlay: true
    muted: true
    loops: MediaPlayer.Infinite
    fillMode: VideoOutput.PreserveAspectCrop
}
