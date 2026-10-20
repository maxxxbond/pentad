import QtQuick
import QtQuick.Effects
import qs.theme

// The shared floating-surface shadow. Use as `layer.effect` on an item that has the surface's silhouette.
MultiEffect {
    shadowEnabled: true
    shadowColor: "#000000"
    shadowOpacity: Metrics.overlayShadowOpacity
    shadowBlur: 1
    // A CSS blur of 18 px is a Gaussian with sigma 9; MultiEffect's blurMax measures about four sigma.
    blurMax: Metrics.overlayShadowBlur * 2
    shadowVerticalOffset: Metrics.overlayShadowOffset
}
