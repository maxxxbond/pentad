# SmoothUI Scrubber

Source: https://smoothui.dev/docs/components/scrubber (registry item `https://smoothui.dev/r/scrubber.json`), component `Scrubber`.
Copyright (c) Eduardo Calvo and the SmoothUI contributors, MIT. License: `LICENSES/smoothui-MIT.txt`. The upstream copyright year is not in the registry item; confirm it against the SmoothUI repository's LICENSE before a release.

Pentad redraws the design and motion of this React component in QML as `quickshell/components/PentadScrubber.qml`: the 36 px tonal bar, the 14 % fill, nine tick marks, the label on the left and the value on the right, and the 4 × 22 capsule that rides the fill edge and springs from 0.7 × scale and 15 % opacity to full size and 80 % opacity under the pointer or a drag. No upstream code is copied.

Changes: the bar and its fill are full capsules instead of 8 px rounded rectangles, with the text inset to clear the ends; colours, text size and the value's font come from Pentad's theme tokens; the capsule's spring (duration 0.25 s, bounce 0.1) is converted to stiffness and damping by `springFromDuration` in `quickshell/logic/spring.mjs` and stepped by `PentadSpring`; the 150 ms `cubic-bezier(0.23, 1, 0.32, 1)` glide of the fill and capsule is a `NumberAnimation` with the same curve; reduced motion makes both land at once; a keyboard focus ring and Qt accessibility roles replace the ARIA attributes.
