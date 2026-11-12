pragma Singleton
import QtQuick
import QtQml

QtObject {
    readonly property int textCaption: 12
    readonly property int textBody: 14
    readonly property int textSection: 16
    readonly property int textTitle: 20
    // The spacing scale (base 4). Gaps, margins and paddings use these instead of literals.
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 24
    readonly property int space6: 32
    // State layers: the share of the foreground laid over a control's resting fill.
    readonly property real stateHover: 0.05
    readonly property real statePressed: 0.12
    readonly property real stateDisabled: 0.35
    readonly property int controlSmall: 28
    readonly property int controlMedium: 34
    readonly property int controlLarge: 44
    readonly property int radiusSmall: 6
    readonly property int radiusMedium: 8
    readonly property int radiusLarge: 16
    readonly property int radiusPill: 9999
    readonly property int radiusPopover: 16
    readonly property int radiusCard: 14
    readonly property int radiusMicro: 6
    readonly property int radiusTag: 4
    readonly property int settingsInset: 8
    readonly property int settingsNavItem: 32
    readonly property int settingsRailItem: 40
    readonly property int settingsNavWidth: 240
    readonly property int settingsRailWidth: 56
    readonly property int settingsRowMinHeight: 40
    readonly property int radiusRow: 16
    readonly property int radiusBlock: attachedRadius - activityPadding
    readonly property int panelControl: 28
    readonly property int panelFont: 14
    readonly property int panelIcon: 16
    readonly property int exposedFont: 16
    readonly property int exposedIcon: 18
    readonly property int menuIcon: 26
    readonly property int menuActionIcon: 24
    readonly property int chevronIcon: 20
    readonly property int statusIcon: 20
    readonly property int trayIcon: 20
    readonly property int logo: 28
    readonly property int tooltipDelay: 700
    readonly property int barTooltipCompactWidth: 96
    readonly property int barTooltipCompactHeight: 28
    readonly property int barTooltipLabelWidth: 160
    readonly property int barTooltipLabelHeight: 28
    readonly property int barTooltipStatusWidth: 240
    readonly property int barTooltipStatusHeight: 48
    readonly property int panelIconWeight: 300
    readonly property int metricCircle: 20
    readonly property int moduleGap: 4
    readonly property int centerGap: 4
    readonly property int statusGap: 8
    readonly property int metricGap: 4
    readonly property int metricGroupGap: 8
    readonly property int capsulePadding: 4
    readonly property int attachedShoulder: 32
    readonly property int attachedRadius: 32
    // One quiet shadow for floating shell surfaces: 0 6px 18px rgba(0,0,0,.16). The room is the
    // transparent margin a window keeps on its free edges so the blur is never clipped.
    readonly property int overlayShadowOffset: 6
    readonly property int overlayShadowBlur: 18
    readonly property real overlayShadowOpacity: 0.16
    // Measured fade: below one 8-bit level by about 30 px under the edge; 32 matches the shell's shadow allowance.
    readonly property int overlayShadowRoom: 32
    // The lock screen's clock is the one display-size text; everything else keeps the four roles.
    readonly property int lockClock: 128
    readonly property int lockCardWidth: 400
    readonly property int activityPadding: 12
    readonly property int attachedRim: 4
    // The tallest the bar's centre island draws from the top edge: the karaoke focus card and its rims.
    readonly property int islandReach: 88
}
