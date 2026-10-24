pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.theme
import qs.features.lock
import '../logic/lock-screen.mjs' as LockLogic

// The lock surface in a plain window, with a scripted stand-in for PAM that goes through the same
// logic as LockAuth. Nothing here locks a session or talks to PAM.
ShellRoot {
    id: root
    property var checks: []
    property int step: 0
    property bool finishedSeen: false

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail === undefined ? "" : String(detail) });
    }

    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (let index = 0; index < item.children.length; index++) {
            const found = find(item.children[index], name);
            if (found)
                return found;
        }
        return null;
    }

    Component.onCompleted: Theme.resolve({
        appearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE") === "light" ? "light" : "dark",
        accent: "#869677", fontFamily: "Geist", blur: false, schemaVersion: 1,
        reducedMotion: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    })

    LockContext {
        id: lockContext
        preview: true
    }

    // Same surface as LockAuth. "right" unlocks, "otp" asks a second question, anything else fails.
    QtObject {
        id: fakeAuth
        property var state: LockLogic.initialAuth()
        readonly property bool busy: LockLogic.busy(state)
        readonly property bool unlockedState: state.phase === "unlocked"
        readonly property bool asking: state.phase === "prompt"
        readonly property int attempts: state.attempts
        property string draft: ""
        property string held: ""
        property int answers: 0
        signal unlocked

        function apply(next) {
            if (next.attempts !== state.attempts)
                draft = "";
            const wasUnlocked = state.phase === "unlocked";
            state = next;
            if (next.phase === "unlocked" && !wasUnlocked) {
                draft = "";
                unlocked();
            }
        }
        function submit(typed) {
            const result = LockLogic.submit(state, typed.length > 0);
            if (result.action === "none")
                return;
            apply(result.state);
            if (result.action === "respond") {
                draft = "";
                apply(LockLogic.completed(state, typed === "123456" ? 0 : 1));
                return;
            }
            held = typed;
            const first = LockLogic.message(state, { text: "Password: ", isError: false, responseRequired: true, responseVisible: false });
            apply(first.state);
            if (first.action === "respond-secret")
                answers++;
            if (held === "otp") {
                const second = LockLogic.message(state, { text: "Verification code:", isError: false, responseRequired: true, responseVisible: true });
                apply(second.state);
                if (second.action === "ask")
                    draft = "";
            } else if (held === "locked") {
                apply(LockLogic.message(state, { text: "The account is locked.\n(9 minutes left)", isError: true, responseRequired: false, responseVisible: false }).state);
                apply(LockLogic.completed(state, 1));
            } else {
                apply(LockLogic.completed(state, held === "right" ? 0 : 1));
            }
            held = "";
        }
        function cancel() {
            if (asking)
                apply(LockLogic.cancelled(state));
        }
        function noticeText() {
            if (state.notice === "pam")
                return state.pamNotice;
            const pair = LockLogic.noticeText(state.notice);
            return lockContext.ukrainian ? pair.uk : pair.en;
        }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1280
        implicitHeight: 800
        color: Theme.tokens.surface
        visible: true

        LockSurface {
            id: surface
            anchors.fill: parent
            context: lockContext
            auth: fakeAuth
            onFinished: root.finishedSeen = true
        }
    }

    Timer {
        interval: 120
        repeat: true
        running: true
        onTriggered: {
            const field = root.find(surface, "lockPasswordField");
            const password = lockContext.text("Пароль", "Password");
            switch (root.step) {
            case 0:
                root.check("field-exists", field !== null);
                root.check("placeholder-names-the-password", field && field.placeholder === password, field && field.placeholder);
                root.check("no-power-buttons-without-logind", !lockContext.power.reboot && !lockContext.power.poweroff);
                fakeAuth.draft = "abc";
                break;
            case 1:
                root.check("typed-text-shows-as-dots", field && field.length === 3 && !field.visibleAnswer, field && field.length);
                fakeAuth.submit("wrong");
                break;
            case 2:
                root.check("wrong-password-counts-and-clears", fakeAuth.attempts === 1 && fakeAuth.draft === "" && field.length === 0);
                root.check("wrong-password-is-said", surface.notice === lockContext.text("Невірний пароль", "Wrong password") && surface.showNotice, surface.notice);
                root.check("wrong-password-draws-the-error-edge", field.failed);
                fakeAuth.submit("otp");
                break;
            case 3:
                root.check("password-answers-only-the-first-prompt", fakeAuth.answers === 2 && fakeAuth.asking);
                root.check("second-question-replaces-the-placeholder", field.placeholder === "Verification code:", field.placeholder);
                root.check("visible-answer-shows-text", field.visibleAnswer);
                fakeAuth.cancel();
                break;
            case 4:
                root.check("escape-returns-to-the-password", !fakeAuth.asking && field.placeholder === password);
                fakeAuth.submit("locked");
                break;
            case 5:
                root.check("pam-error-is-shown-as-one-line", surface.notice === "The account is locked. (9 minutes left)", surface.notice);
                root.check("pam-error-reads-as-an-error", fakeAuth.state.pamError && field.failed);
                if (Quickshell.env("PENTAD_ARTIFACT_PATH") !== "")
                    surface.grabToImage(result => root.check("lock-screen-captured", result.saveToFile(Quickshell.env("PENTAD_ARTIFACT_PATH"))));
                break;
            case 6:
                fakeAuth.submit("right");
                break;
            case 7:
            case 8:
            case 9:
            case 10:
                if (!root.finishedSeen)
                    break;
                // fallthrough once the fade has ended
            case 11:
                root.check("success-unlocks-and-fades", fakeAuth.unlockedState && root.finishedSeen);
                root.check("draft-is-cleared-on-unlock", fakeAuth.draft === "");
                console.log("PENTAD_TEST " + JSON.stringify({
                    status: root.checks.every(item => item.passed) ? "pass" : "fail",
                    checks: root.checks
                }));
                Qt.quit();
                return;
            }
            root.step++;
        }
    }
}
