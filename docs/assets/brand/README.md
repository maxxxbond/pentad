# Pentad brand assets

The Pentad mark is a stone set as a mosaic. A pentagon is divided by five straight cuts into five outer pieces, one for each section of the shell's layout (left menu, left, center, right, right menu; see `quickshell/logic/pentads.mjs`). Each cut starts at the middle of an edge and passes beside the centre, like a blade of a camera iris, so together the five pieces open a core. The core stands for what the shell is there to serve: your workspace. Inside it the same five cuts repeat at a smaller scale, and they open an eye: a small light pentagon at the very centre, where your attention goes. The pieces are rounded and stand apart with clear gaps, so the mark keeps its air at small sizes.

## Files

| File | Use |
| --- | --- |
| `mark.svg`, `mark-on-light.svg` | The colour mark, for dark and for light backgrounds |
| `lockup.svg`, `lockup-on-light.svg` | The mark with the wordmark, for dark and for light backgrounds. The README header uses these |
| `app-icon.svg`, `app-icon-light.svg` | The mark on a dark or a light plate, 512 px, for places that need an application icon. Nothing installs it yet |
| [`quickshell/assets/icons/brand/logo-symbolic.svg`](../../../quickshell/assets/icons/brand/logo-symbolic.svg) | The one-colour mark that the shell draws |

## Geometry

The outline is a regular pentagon with circumradius R, point up, with softened corners. Each cut runs from the midpoint of an edge and is tangent to a circle of radius 0.36 R around the centre. The five cuts enclose the core, a smaller pentagon rotated against the outline; inside it five smaller cuts, tangent to a circle of 0.42 of the core's radius, leave the eye. In the colour mark the gaps are 0.07 R around the outer pieces and 0.05 R inside the core, and every piece has rounded corners.

## Colour

The light comes from the upper left. Emerald, from the piece in shadow to the piece in full light:

| Background | Shadow | | | | Light |
| --- | --- | --- | --- | --- | --- |
| Dark | `#0D4A30` | `#15704A` | `#23A066` | `#58C98B` | `#B4EFCB` |
| Light | `#0B3F29` | `#125F3F` | `#1C8656` | `#3BAA72` | `#7FD3A2` |

The wordmark is `#F2F4F1` on dark backgrounds and `#171717` on light ones.

## The mark inside the shell

`logo-symbolic.svg` has no colour of its own. Every piece is black with its own `fill-opacity`, and `PentadIcon` tints the image with a theme colour, which turns those opacities into lighter and darker tones of that colour. The pieces therefore stay visible in both themes and on the accent fill.

The file is drawn on a 28 px grid, the size of `Metrics.logo`. At that size the gaps around the outer pieces widen to 0.12 R, about 1.7 px, and 0.10 R inside the core. The core is slightly larger (outer cuts tangent to 0.33 R) and so is the eye (inner cuts tangent to 0.5 of the core's radius), so the eye still shows as a dot inside a ring at 14 px. The flat bottom edge sits on a whole pixel at 28 px and at 14 px. Keep the black fill, the gaps and the square box when editing it; change the tones through `fill-opacity` only.

## Wordmark

The wordmark is "Pentad" set in Geist SemiBold and converted to outlines. The font itself is not part of these files.

## Use of the marks

The Pentad name and logo are covered by [TRADEMARK.md](../../../TRADEMARK.md), not by the GPL.
