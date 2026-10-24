import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import "features/lock"
import "logic/lock-screen.mjs" as LockLogic

// The lock screen: a second entry point, run as its own process by `pentad lock`, so a crash or
// restart of the main shell never touches it. It has no preview or debug switch: a fixture
// draws LockSurface in a plain window instead.
//
// Exit codes tell `pentad lock` what happened: 0 after a successful unlock, anything else when
// the lock was never acquired or was lost, so the launcher can fall back to another locker.
// The launcher also waits for "locked" in the state file it names in PENTAD_LOCK_STATE: an
// instance that never writes it (a load failure leaves qs running without this root) is replaced.
ShellRoot {
    id: root

    // A running lock never reloads: a rebuilt runtime would otherwise restart it mid-password.
    settings.watchFiles: false
    property bool unlocking: false
    // The lock was granted at least once; losing it after that is reported, not retried.
    property bool held: false

    LockContext {
        id: lockContext
        watchKeyboard: !root.unlocking
    }

    LockAuth {
        id: lockAuth
        ukrainian: lockContext.ukrainian
        onUnlocked: backstop.start()
    }

    // Without the PAM service no password could ever unlock: do not lock, let hyprlock take over.
    Component.onCompleted: {
        if (lockAuth.serviceAvailable()) {
            sessionLock.locked = true;
            return;
        }
        console.warn("pentad-lock: /etc/pam.d/login is missing; not locking");
        Qt.callLater(() => Qt.exit(LockLogic.exitCodes.noPam));
    }

    FileView {
        id: stateFile
        path: Quickshell.env("PENTAD_LOCK_STATE") || ""
        blockWrites: true
        printErrors: false
    }

    function writeState(value: string): void {
        if (stateFile.path !== "")
            stateFile.setText(value);
    }

    // The only way out of the lock: PAM succeeded and the surfaces faded (or the backstop fired
    // because a stalled output never finished its fade).
    function release(): void {
        if (unlocking || !lockAuth.unlockedState)
            return;
        unlocking = true;
        // From here a new `pentad lock` must start a fresh lock instead of trusting this one.
        writeState("");
        sessionLock.locked = false;
        // Quickshell emits no lockedChanged for its own unlock; give the compositor time to
        // receive the flushed request before the process ends.
        quit.start();
    }

    // The compositor ended the lock (or never granted it) without a successful password.
    function checkLock(): void {
        if (sessionLock.locked) {
            held = true;
            return;
        }
        if (held && !unlocking) {
            console.warn("pentad-lock: the session lock ended without an unlock");
            Qt.exit(LockLogic.exitCodes.lost);
        }
    }

    WlSessionLock {
        id: sessionLock
        // Set once the PAM service is known to exist (Component.onCompleted above).
        locked: false
        onLockedChanged: Qt.callLater(root.checkLock)
        onSecureChanged: {
            if (secure && !root.unlocking) {
                console.info("pentad-lock: the compositor confirmed the lock");
                root.writeState("locked");
            }
            Qt.callLater(root.checkLock);
        }

        WlSessionLockSurface {
            id: lockSurface
            color: Theme.tokens.surface

            LockSurface {
                anchors.fill: parent
                output: lockSurface.screen ? lockSurface.screen.name : ""
                context: lockContext
                auth: lockAuth
                onFinished: root.release()
            }
        }
    }

    Timer {
        id: backstop
        interval: Motion.longDuration * 2
        onTriggered: root.release()
    }

    Timer {
        id: quit
        interval: Motion.longDuration
        onTriggered: Qt.exit(LockLogic.exitCodes.unlocked)
    }

    // Without a lock after three seconds (another locker holds it, or no ext-session-lock-v1),
    // exit so the launcher can try its fallback. Once held, keep checking that it still is.
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            if (!sessionLock.locked) {
                console.warn("pentad-lock: could not acquire the session lock");
                Qt.exit(LockLogic.exitCodes.notAcquired);
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: !root.unlocking
        onTriggered: root.checkLock()
    }
}
