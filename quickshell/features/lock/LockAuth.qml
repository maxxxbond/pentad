import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import '../../logic/lock-screen.mjs' as LockLogic

// One PAM conversation shared by every screen. The decisions live in logic/lock-screen.mjs;
// this file only carries them out and keeps the typed text for as short a time as it can.
Scope {
    id: root

    property var state: LockLogic.initialAuth()
    readonly property bool busy: LockLogic.busy(state)
    readonly property bool unlockedState: state.phase === "unlocked"
    readonly property bool asking: state.phase === "prompt"
    readonly property int attempts: state.attempts
    // Text typed so far, mirrored so every screen shows the same dots.
    property string draft: ""

    signal unlocked

    property string secret: ""

    function apply(next: var): void {
        const wasUnlocked = root.state.phase === "unlocked";
        if (next.attempts !== root.state.attempts)
            root.draft = "";
        root.state = next;
        if (!LockLogic.busy(next) || next.phase === "unlocked")
            watchdog.stop();
        if (next.phase === "unlocked") {
            root.secret = "";
            root.draft = "";
            if (!wasUnlocked)
                root.unlocked();
        }
    }

    function submit(typed: string): void {
        const step = LockLogic.submit(root.state, typed.length > 0);
        if (step.action === "none")
            return;
        root.apply(step.state);
        watchdog.restart();
        if (step.action === "respond") {
            root.draft = "";
            pam.respond(typed);
            return;
        }
        root.secret = typed;
        root.draft = "";
        if (!pam.start()) {
            root.secret = "";
            root.apply(LockLogic.startFailed(root.state));
        }
    }

    function cancel(): void {
        if (!root.asking)
            return;
        pam.abort();
        root.secret = "";
        root.apply(LockLogic.cancelled(root.state));
    }

    function noticeText(): string {
        if (root.state.notice === "pam")
            return root.state.pamNotice;
        const pair = LockLogic.noticeText(root.state.notice);
        return root.ukrainian ? pair.uk : pair.en;
    }

    property bool ukrainian: false
    // PamContext passes its directory to pam_start_confdir, which then reads every include from
    // that directory only. The vendor copy in /usr/lib/pam.d would skip the administrator's
    // /etc/pam.d policy, so without /etc/pam.d/login the lock is not taken at all.
    function serviceAvailable(): bool {
        // text() reads synchronously with blockLoading; `loaded` alone may not be set yet.
        etcLogin.text();
        return etcLogin.loaded;
    }

    FileView {
        id: etcLogin
        path: "/etc/pam.d/login"
        blockLoading: true
        printErrors: false
    }

    PamContext {
        id: pam
        config: "login"
        configDirectory: "/etc/pam.d"
        // No user: Quickshell authenticates the account that owns this process, never one named
        // by an environment variable.

        onPamMessage: {
            const step = LockLogic.message(root.state, {
                text: message,
                isError: messageIsError,
                responseRequired: responseRequired,
                responseVisible: responseVisible
            });
            root.apply(step.state);
            if (step.action === "respond-secret") {
                respond(root.secret);
                root.secret = "";
            } else if (step.action === "ask") {
                root.secret = "";
                root.draft = "";
            }
        }

        onCompleted: result => {
            root.secret = "";
            root.apply(LockLogic.completed(root.state, result));
        }
    }

    // A PAM module that never answers (a fingerprint reader, a stalled network login) is aborted.
    Timer {
        id: watchdog
        interval: 30000
        onTriggered: {
            if (!LockLogic.busy(root.state) || root.state.phase === "unlocked")
                return;
            pam.abort();
            root.secret = "";
            root.apply(LockLogic.timedOut(root.state));
        }
    }
}
