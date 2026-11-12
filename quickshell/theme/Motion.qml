pragma Singleton
import QtQuick
import QtQml

QtObject {
    readonly property int shortDuration: 160
    readonly property int mediumDuration: 240
    readonly property int longDuration: 320
    readonly property int standardDuration: 260
    readonly property int pressDuration: 60
    readonly property int stateDuration: 140
    readonly property int revealDuration: 200
    // A fill or a marker gliding to a new value along a bar (the scrubber); 150 ms with the ease-out-expo-like
    // curve of the motion study it was drawn from.
    readonly property int glideDuration: 150
    // Named curves: use these instead of an Easing literal.
    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeEnter: Easing.OutCubic
    readonly property int easeExit: Easing.InCubic
    // Springs for SpringAnimation { spring; damping }. Snappy is for presses, handles and toggles;
    // soft is for surfaces and fills settling. A spring has no duration, so its Behavior or
    // animation must be disabled while reducedMotion is true.
    readonly property real springSnappy: 6.0
    readonly property real springSnappyDamping: 0.6
    readonly property real springSoft: 3.5
    readonly property real springSoftDamping: 0.55
    readonly property bool reducedMotion: Theme.tokens.reducedMotion
    readonly property int reducedDuration: 0
    readonly property int short: Theme.tokens.reducedMotion ? reducedDuration : shortDuration
    readonly property int medium: Theme.tokens.reducedMotion ? reducedDuration : mediumDuration
    readonly property int long: Theme.tokens.reducedMotion ? reducedDuration : longDuration
    readonly property int standard: reducedMotion ? reducedDuration : standardDuration
    readonly property int press: reducedMotion ? reducedDuration : pressDuration
    readonly property int state: reducedMotion ? reducedDuration : stateDuration
    readonly property int reveal: reducedMotion ? reducedDuration : revealDuration
}
