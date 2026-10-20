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
