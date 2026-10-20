# Menu motion profiling

The `menu-motion` fixture records five open/close cycles for each prepared drawer.
It keeps first-frame latency separate from subsequent frame intervals and ignores
repaints at unchanged slide progress. Raw intervals and positions are included in
the JSON report. A pass confirms fixture assertions, not a frame-rate target.
It also opens, closes and reopens a child popover at a moved anchor, checking its
input mask and keyboard focus in the private window.

Run it only in an isolated session: private Wayland, D-Bus and HOME/XDG paths,
fake services, a bounded supervisor and cleanup of every process it started.
Never run it against your own desktop.

## Design note: hidden popovers must not track animated ancestors

Closed `AttachedPopover` instances used to track every animated ancestor
position. That updated hidden popover placement, contours and input masks while
the right drawer moved, and caused frame stalls. Hiding the drawer contents,
replacing the main input mask and hiding the outer shape did not remove the
stalls; replacing the right content with the left content did. Suspending hidden
child anchor/seam tracking and disabling their input regions removed the
repeatable stalls. Opening still recomputes the current anchor, and visible child
popovers keep following it.

In a private virtual KWin with software rendering, five right-open cycles went
from a first-frame latency of 172–186 ms and a maximum later gap of 70–86 ms to
32–38 ms and 17–22 ms. These are synthetic measurements, not a verification on
real GPUs, compositors, fonts or notification data.

## Checks

Static validation (does not start Quickshell):

```sh
node --test --test-isolation=none tests/quickshell/attached-popover.test.mjs tests/quickshell/attached-popover-focus.test.mjs tests/quickshell/menu-motion.test.mjs tests/quickshell/surface-region.test.mjs tests/quickshell/popup-manager.test.mjs
node --check scripts/test-quickshell.mjs
node scripts/build-quickshell.mjs --output /tmp/pentad-menu-motion-build
```

The graphical run needs a disposable supervisor that starts the `menu-motion`
scenario in a private compositor and bounds its run time. Output scaling,
overflow on short screens, real-device controls and a live desktop are not
covered by this fixture.
