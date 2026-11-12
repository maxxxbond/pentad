# Kokonut UI wheel picker

Source: [Kokonut UI](https://kokonutui.com/docs/inputs/wheel-picker), the "Wheel picker" input (motion reference: https://designbookmark.com/motion#wheel-picker).
Copyright (c) 2025 kokonutUI, MIT. License: `LICENSES/kokonutui-MIT.txt`.

Pentad re-implements the component's behaviour in QML; no React or Tailwind code is used. What is taken from the source is its numbers, so the drum moves the same way: the 36 px row, 20° between rows, the drum radius that makes neighbouring rows touch, the 1000 px perspective, the edge fade, the 4 px tap slop, the rubber-band overscroll (1.2 rows), the 80 ms velocity window, the 2 rows/s flick threshold and 0.32 s coast, the settle spring (0.4 s, 0.15 bounce), the flick spring (stiffness 140, damping 24), the wheel gain, and the keyboard map. They live in `quickshell/logic/wheel-picker.mjs`, with a header naming the source. The views are `quickshell/components/PentadWheelColumn.qml` and `PentadWheelPicker.qml`.

Changes: the browser's CSS 3D drum is drawn by placing and squashing each row with the same trigonometry instead of a 3D transform; the two stacked drums (muted, and full colour clipped to the band) are kept; the spring runs on Pentad's `PentadSpring`; colours, radii and type come from `Theme` and `Metrics`; the focus ring shows for keyboard focus only; reduced motion lands every change at once; haptics are not ported.
