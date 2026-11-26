import QtQuick

// The Pentad mark in one colour. Its pieces keep the light of the colour mark: in light ink the lit pieces are the
// most opaque, in dark ink the least, so the light falls from the upper left on every surface.
PentadIcon {
    readonly property bool darkInk: color.hslLightness < 0.5
    source: Qt.resolvedUrl(darkInk ? "../assets/icons/brand/logo-symbolic-dark-ink.svg" : "../assets/icons/brand/logo-symbolic.svg")
}
