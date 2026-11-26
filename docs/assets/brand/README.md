# Pentad brand assets

The Pentad mark is a cut stone. A pentagon is divided by five straight cuts into five outer facets, one for each section of the shell's layout (left menu, left, center, right, right menu; see `quickshell/logic/pentads.mjs`). Each cut starts at the middle of an edge and passes beside the centre, like a blade of a camera iris, so together the five facets open a core. The core stands for what the shell is there to serve: your workspace. It catches the most light and is split into three faces, as in the first Pentad mark.

## Files

| File | Use |
| --- | --- |
| `mark.svg`, `mark-on-light.svg` | The colour mark, for dark and for light backgrounds |
| `lockup.svg`, `lockup-on-light.svg` | The mark with the wordmark, for dark and for light backgrounds. The README header uses these |
| `app-icon.svg`, `app-icon-light.svg` | The mark on a dark or a light plate, 512 px, for places that need an application icon. Nothing installs it yet |
| [`quickshell/assets/icons/brand/logo-symbolic.svg`](../../../quickshell/assets/icons/brand/logo-symbolic.svg) | The one-colour mark that the shell draws |

## Geometry

The outline is a regular pentagon with circumradius R, point up, with softened corners. Each cut runs from the midpoint of an edge and is tangent to a circle of radius 0.36 R around the centre. The five cuts enclose the core, a smaller pentagon rotated against the outline; three lines from its centre to three of its corners split it into faces, with seams wider than those around the crown so the core reads as open.

## Colour

The light comes from the upper left. Emerald, from the facet in shadow to the facet in full light:

| Background | Shadow | | | | Light |
| --- | --- | --- | --- | --- | --- |
| Dark | `#0D4A30` | `#15704A` | `#23A066` | `#58C98B` | `#B4EFCB` |
| Light | `#0B3F29` | `#125F3F` | `#1C8656` | `#3BAA72` | `#7FD3A2` |

The wordmark is `#F2F4F1` on dark backgrounds and `#171717` on light ones.

## The mark inside the shell

`logo-symbolic.svg` has no colour of its own. Every facet is black with its own `fill-opacity`, and `PentadIcon` tints the image with a theme colour, which turns those opacities into lighter and darker tones of that colour. The facets therefore stay visible in both themes and on the accent fill.

The file is drawn on a 28 px grid, the size of `Metrics.logo`. The flat bottom edge sits on a whole pixel at 28 px and at 14 px, and the seams between all facets, the core included, are about one pixel wide at 28 px. Keep the black fill and the square box when editing it; change the tones through `fill-opacity` only.

## Wordmark

The wordmark is "Pentad" set in Geist SemiBold and converted to outlines. The font itself is not part of these files.

## Use of the marks

The Pentad name and logo are covered by [TRADEMARK.md](../../../TRADEMARK.md), not by the GPL.
