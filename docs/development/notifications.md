# Desktop notifications

The Quickshell service in `quickshell/services/Notifications.qml` owns one native `NotificationServer` across outputs. It registers `org.freedesktop.Notifications` only when that private/session bus name is free. Another daemon keeps ownership; Pentad reports `another-server` and can display saved history. A bounded read-only PID probe checks ownership. Preview and safe mode create no server and write no archive.

## Behavior

- Popups initially use the focused output. Removing that output reassigns them without duplicates. Each host displays at most three cards and takes no keyboard focus or exclusive screen space.
- The center groups by desktop entry/application and retains at most 100 snapshots. Presented center content becomes read. Opening the center or enabling DND suppresses popups without a later backlog; DND includes critical messages.
- Ordinary popups use the requested timeout or seven seconds by default. Critical notifications and timeout zero remain until dismissed. Timing starts on presentation; hover pauses the remaining monotonic duration.
- Replacements retain the native notification ID and refresh the existing snapshot. Actions are available only while the native object remains live. Native action invocation already dismisses nonresident notifications.
- Interactive notifications (actions or an inline reply) stay live after their popup times out or is suppressed by the open center or DND, so the center can still invoke them. At most 24 such records stay live; older ones expire natively. Plain notifications close natively exactly as before.
- Clicking a card goes to its source: it invokes the app's `default` action, focuses the matching Hyprland window (class/app id from the desktop entry or app name, a window title containing the notification title first, then most recently used) and, with neither, launches the desktop entry. The card is then dismissed and the center closes. Middle click dismisses; popups also swipe right to dismiss. `default` never appears as a button.
- Inline replies (`inline-reply` action) show a Reply button. In the center it opens a text field; a popup takes no keyboard focus, so its Reply opens the center through `requestReply()`, which unfolds the group and focuses the field there.
- Images (`image-data`/`image-path`) render as the avatar with the app icon as a badge. Only `file://` images are archived; server pixmaps are live-only.
- Transient notifications never enter history. Titles, bodies and action labels render as plain text. Only local/theme icons are resolved; fields are never executed as commands.

The archive at `${XDG_STATE_HOME:-~/.local/state}/pentad/notifications.json` contains `schemaVersion: 1`, DND and bounded snapshots. Restore removes wire IDs, sender values and actions. Existing Config/file helpers perform atomic revision-checked writes. Invalid documents and revision conflicts disable automatic writes; existing bytes remain untouched. `recoverInvalidStorage()` is an explicit service operation, with no automatic recovery UI in the center yet.

## Native API limits

The pinned Quickshell 0.3.2 revision is `4f508be500dea6e5732cc3d50382a0048b17e7b1`. Its notification source passes timeout values in milliseconds despite a seconds comment in the public header; the adapter uses the observed milliseconds and the native expiry probe covers this.

| Native close reason | Current behavior |
| --- | --- |
| 1, expired | `Notification.expire()` after popup timeout |
| 2, dismissed | `Notification.dismiss()` for user dismissal, clear and policy suppression; nonresident action invocation dismisses natively |
| 3, application close | Native `CloseNotification`, which also removes the snapshot |
| 4, undefined | Pure policy can represent this, but the public native API has no matching close method; native suppression uses reason 2 |

The public native object exposes application/desktop entry but no D-Bus sender identity. Pentad does not add a second custom notification daemon to bypass that limitation. Restored snapshots cannot invoke actions or emit close signals.

## Isolated checks

Never launch graphical fixtures on your active Wayland display to test this menu. Use the private virtual compositor wrapper, which creates its own D-Bus session, HOME/XDG directories and two virtual outputs, and removes the real display and Hyprland IPC variables:

```sh
node --test tests/quickshell/notifications.test.mjs
node scripts/test-quickshell-headless.mjs --scenario notification-popup --report /tmp/pentad-popup.json
node scripts/test-quickshell-headless.mjs --scenario control-center --report /tmp/pentad-center.json
node tests/tooling/notifications-native.mjs --qs artifacts/quickshell-runtime/bin/qs --report /tmp/pentad-native.json
```

The protocol fixture uses another private `dbus-run-session` with offscreen rendering. It verifies ownership, refusal to displace an existing owner, replacement, real action/close signals, DND, expiry and hover timing. Popup routing tests use simulated output removal. KWin's virtual backend does not implement Hyprland focus grabs, so these checks do not certify Hyprland Escape/outside-click input, physical hotplug or native fractional-scale protocol behavior.
