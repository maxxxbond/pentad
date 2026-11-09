pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell.Io
import "../logic/overnight.mjs" as Night
import "../logic/bar-tools.mjs" as Tools

// Overnight mode keeps the PC running but quiet and dark until a morning time, then puts back what
// it changed. The sleep inhibitor is the one guarantee; every other step is best effort. The state
// file is written before anything changes, so a restarted shell can hold or finish the night.
QtObject {
    id: root
    property bool preview: false
    property bool safeMode: false
    property var services: null
    property string stateRoot: services && services.config ? services.config.stateRoot : ""
    readonly property string statePath: stateRoot ? stateRoot + "/overnight.json" : ""
    readonly property bool available: !preview && !safeMode && statePath !== ""
    readonly property var power: services ? services.power : null
    readonly property var audio: services ? services.audio : null
    readonly property var notifications: services ? services.notifications : null
    readonly property var settings: {
        const config = services ? services.config : null;
        const tools = config && config.documents && config.documents.layout ? config.documents.layout.barTools : null;
        return tools && tools.overnight ? tools.overnight : Tools.barToolsDefaults.overnight;
    }
    // idle, starting, active or stopping.
    property string phase: "idle"
    property bool recovered: false
    property bool recovering: false
    property bool waitingForServices: false
    property int readyTicks: 0
    property double endsAt: 0
    // The state document while the mode is on; its `applied` part is what a stop undoes.
    property var current: null
    property var queue: []
    property var step: null
    property var problems: []
    property var stopNotice: null
    property bool inhibitStarted: false
    property bool inhibitWaiting: false
    property bool inhibitStopping: false
    property int inhibitSeconds: 0
    property bool writeFailed: false
    readonly property bool active: phase === "active" || phase === "stopping"
    readonly property bool pending: phase === "starting" || phase === "stopping" || waitingForServices
        || (available && !recovered)

    function tr(uk, en) { return services && typeof services.text === "function" ? services.text(uk, en) : en; }
    function endLabel(at) {
        return at > 0 ? tr("до " + Qt.formatTime(new Date(at), "HH:mm"), "until " + Qt.formatTime(new Date(at), "HH:mm"))
            : tr("до вимкнення", "until turned off");
    }
    function profileValue() {
        const state = power ? power.profileState : null;
        return state && state.kind === "ready" ? state.value : null;
    }
    function currentProfile() { const value = profileValue(); return value ? value.actual : ""; }
    function currentMuted() {
        const state = audio ? audio.state : null;
        return state && state.kind === "ready" && state.value.output ? state.value.output.muted === true : null;
    }
    // DND is only known once the notification archive is restored; before that it reads as off.
    function currentDnd() {
        const state = notifications ? notifications.state : null;
        return state && typeof state.dnd === "boolean" && notifications.restoreComplete === true ? state.dnd : null;
    }
    function servicesReady() {
        return !!profileValue() && !!audio && audio.state.kind === "ready"
            && !!notifications && notifications.restoreComplete === true;
    }

    function toggle() {
        if (phase === "active") return stop();
        return start(settings.end);
    }

    function start(choice) {
        if (!available || !recovered || phase !== "idle") return false;
        const end = Night.overnightEnds.indexOf(choice) >= 0 ? choice : settings.end;
        remember(end);
        const now = Date.now();
        phase = "starting";
        problems = [];
        current = { version: 1, startedAt: now, endsAt: Night.endTimestamp(end, now),
            prior: { profile: currentProfile(), muted: currentMuted(), dnd: currentDnd(), razer: [] },
            applied: { profile: "", muted: null, dnd: null, razer: false, openrgb: false, command: false } };
        endsAt = current.endsAt;
        run(Night.razerReadCommand(), "razer-read", 5000);
        return true;
    }

    // The menu choice becomes the default for the next click.
    function remember(end) {
        const config = services ? services.config : null;
        if (!config || typeof config.save !== "function" || settings.end === end || !config.documents.layout) return;
        const layout = config.documents.layout;
        config.save("layout", Object.assign({}, layout, { barTools: Object.assign({}, layout.barTools,
            { overnight: Object.assign({}, settings, { end: end }) }) }));
    }

    function problem(uk, en) { problems = problems.concat([{ uk: uk, en: en }]); }

    // Called with the openrazer reading; plans the night, saves it and only then blocks sleep.
    function plan(razer) {
        const prior = current.prior;
        prior.razer = razer || [];
        const profiles = profileValue() ? profileValue().profiles : [];
        const applied = current.applied;
        if (!prior.profile || profiles.indexOf("power-saver") < 0)
            problem("немає режиму енергозбереження", "no power saver profile");
        else if (prior.profile !== "power-saver") applied.profile = "power-saver";
        if (prior.muted === null) problem("немає аудіовиходу", "no audio output");
        else if (!prior.muted) applied.muted = true;
        if (prior.dnd === null) problem("режим «Не турбувати» недоступний", "Do not disturb unavailable");
        else if (!prior.dnd) applied.dnd = true;
        applied.razer = prior.razer.length > 0;
        applied.openrgb = !!Night.openrgbCommand(settings.openrgb.start);
        applied.command = !!Night.userCommand(settings.commands.start);
        // The planned changes are saved first; a restore only undoes what still holds its value.
        if (!writeState(Night.serializeState(current))) {
            abort(tr("Не вдалося записати файл стану", "Could not write the state file"));
            return;
        }
        acquire();
    }

    function writeState(text) {
        writeFailed = false;
        stateFile.setText(text);
        return !writeFailed;
    }

    function acquire() {
        inhibitSeconds = Night.remainingSeconds(endsAt, Date.now());
        inhibitStarted = false;
        inhibitWaiting = true;
        inhibitProcess.running = true;
    }

    // Sleep could not be blocked: nothing has changed yet, so only the state file goes.
    function abort(reason) {
        writeState("");
        current = null;
        endsAt = 0;
        queue = [];
        phase = "idle";
        notify(tr("Нічний режим не ввімкнено", "Overnight mode not turned on"), reason);
    }

    function inhibitConfirmed() {
        inhibitWaiting = false;
        if (recovering) {
            recovering = false;
            phase = "active";
            armEnd();
            return;
        }
        if (phase !== "starting") return;
        const applied = current.applied;
        const steps = [];
        if (applied.profile) steps.push({ step: "profile", value: applied.profile });
        if (applied.muted) steps.push({ step: "muted", value: true });
        if (applied.dnd) steps.push({ step: "dnd", value: true });
        if (applied.razer) steps.push({ step: "razer", value: current.prior.razer.map(function(entry) {
            return { serial: entry.serial, brightness: 0 };
        }) });
        if (applied.openrgb) steps.push({ step: "openrgb", value: settings.openrgb.start });
        if (applied.command) steps.push({ step: "command", value: settings.commands.start });
        queue = steps;
        next();
    }

    function inhibitExited() {
        inhibitStarted = false;
        inhibitSettle.stop();
        if (inhibitStopping) {
            inhibitStopping = false;
            finishStop();
        } else if (inhibitWaiting) {
            inhibitWaiting = false;
            if (recovering) {
                recovering = false;
                phase = "active";
                stopNotice = { uk: "Не вдалося заблокувати сон", en: "Could not block sleep" };
                stopWhenReady();
            } else abort(tr("Не вдалося заблокувати сон (systemd-inhibit)", "Could not block sleep (systemd-inhibit)"));
        } else if (phase === "active") {
            stopNotice = Night.isExpired(endsAt, Date.now()) ? null
                : { uk: "Блокування сну припинилося", en: "The sleep block ended" };
            stop();
        }
    }

    function stop() {
        if (phase !== "active" || !current) return false;
        phase = "stopping";
        waitingForServices = false;
        readyTimer.stop();
        endTimer.stop();
        problems = [];
        queue = Night.restorePlan(current, { profile: currentProfile(), muted: currentMuted(), dnd: currentDnd() }, settings);
        next();
        return true;
    }

    // After a restart the other services need a moment before their values can be compared.
    function stopWhenReady() {
        waitingForServices = true;
        readyTicks = 0;
        readyTimer.restart();
    }

    function release() {
        if (inhibitStarted && inhibitProcess.running) {
            inhibitStopping = true;
            inhibitProcess.signal(2);
        } else finishStop();
    }

    function finishStop() {
        writeState("");
        current = null;
        endsAt = 0;
        phase = "idle";
        const failed = problems.map(function(item) { return tr(item.uk, item.en); });
        const notice = stopNotice;
        stopNotice = null;
        if (failed.length || notice)
            notify(tr("Нічний режим вимкнено", "Overnight mode off"), [notice ? tr(notice.uk, notice.en) : ""]
                .concat(failed.length ? [tr("Не відновлено: ", "Not restored: ") + failed.join(", ")] : [])
                .filter(Boolean).join(". "));
    }

    function finishStart() {
        // The final document drops the steps that did not apply, so a stop leaves them alone.
        writeState(Night.serializeState(current));
        phase = "active";
        armEnd();
        dpmsDelay.interval = Math.max(0, current.startedAt + 1000 - Date.now());
        dpmsDelay.restart();
    }

    function summary() {
        const skipped = problems.map(function(item) { return tr(item.uk, item.en); });
        notify(tr("Нічний режим увімкнено ", "Overnight mode on ") + endLabel(endsAt),
            skipped.length ? tr("Пропущено: ", "Skipped: ") + skipped.join("; ") : "");
    }

    // Runs the queued steps one at a time; the start and the stop share it.
    function next() {
        if (phase !== "starting" && phase !== "stopping") return;
        if (!queue.length) {
            step = null;
            if (phase === "starting") finishStart();
            else release();
            return;
        }
        step = Object.assign({ retried: false, requestId: "" }, queue[0]);
        queue = queue.slice(1);
        perform();
    }

    function perform() {
        const name = step.step;
        stepDeadline.restart();
        if (name === "profile") step.requestId = power ? power.setProfile(step.value) : "";
        else if (name === "muted") step.requestId = audio && typeof audio.setMuted === "function" ? audio.setMuted("output", step.value) : "";
        else if (name === "dnd") {
            if (notifications) notifications.setDnd(step.value);
            stepDone(currentDnd() === step.value, "");
            return;
        } else if (name === "razer") {
            run(Night.razerSetCommand(step.value), "step", 5000);
            return;
        } else if (name === "openrgb" || name === "command") {
            const argv = name === "openrgb" ? Night.openrgbCommand(step.value) : Night.userCommand(step.value);
            if (argv) run(argv, "step", name === "openrgb" ? 20000 : 12000);
            else stepDone(name === "command", "");
            return;
        }
        if (!step.requestId) stepDone(false, "unavailable");
    }

    function requestFinished(requestId, result) {
        if (!step || !step.requestId || step.requestId !== requestId) return;
        // Power rejects a second operation while one is in flight; it gets one more try.
        if (!result.ok && result.reason === "busy" && !step.retried) {
            step.retried = true;
            step.requestId = "";
            retryTimer.restart();
            return;
        }
        stepDone(result.ok === true, result.reason || "");
    }

    function stepDone(ok, reason) {
        if (!step) return;
        stepDeadline.stop();
        retryTimer.stop();
        const name = step.step;
        step = null;
        if (!ok) {
            const starting = phase === "starting";
            const labels = {
                profile: starting ? ["профіль живлення не змінено", "power profile not changed"] : ["профіль живлення", "power profile"],
                muted: starting ? ["звук не вимкнено", "sound not muted"] : ["звук", "sound"],
                dnd: starting ? ["режим «Не турбувати» не ввімкнено", "Do not disturb not turned on"] : ["режим «Не турбувати»", "Do not disturb"],
                razer: starting ? ["підсвітку Razer не вимкнено", "Razer lighting not turned off"] : ["підсвітка Razer", "Razer lighting"],
                openrgb: reason === "missing" ? ["OpenRGB не встановлено", "OpenRGB not installed"]
                    : starting ? ["профіль OpenRGB не застосовано", "OpenRGB profile not applied"] : ["профіль OpenRGB", "OpenRGB profile"],
                command: starting ? ["команда запуску не вдалася", "start command failed"] : ["команда завершення", "end command"]
            }[name];
            problem(labels[0], labels[1]);
            if (starting) {
                const applied = current.applied;
                if (name === "profile") applied.profile = "";
                else if (name === "muted" || name === "dnd") applied[name] = null;
                else applied[name] = false;
            }
        }
        next();
    }

    function armEnd() {
        endTimer.stop();
        if (phase !== "active" || endsAt === 0) return;
        const left = endsAt - Date.now();
        if (left <= 0) {
            stop();
            return;
        }
        // Short hops keep the end on time when the wall clock jumps.
        endTimer.interval = Math.max(1, Math.min(left, 60000));
        endTimer.start();
    }

    function notify(title, body) {
        run(["notify-send", "-a", "Pentad", title].concat(body ? [body] : []), "notice", 5000);
    }

    function run(argv, purpose, limit) {
        const worker = workerComponent.createObject(root, { argv: argv, purpose: purpose, limit: limit });
        if (!worker) {
            workerDone(null, purpose, -1, "");
            return;
        }
        worker.running = true;
    }

    function finishWorker(worker, code, started) {
        if (worker.settled) return;
        worker.settled = true;
        worker.deadline.stop();
        const purpose = worker.purpose;
        const output = worker.stdout.text;
        worker.destroy();
        workerDone(started, purpose, code, output);
    }

    function workerDone(started, purpose, code, output) {
        if (purpose === "razer-read") {
            if (phase !== "starting" || !current) return;
            const razer = code === 0 ? Night.parseRazer(output) : null;
            if (!razer) problem("OpenRazer недоступний", "OpenRazer unavailable");
            plan(razer);
        } else if (purpose === "step") stepDone(code === 0, started ? "exit" : "missing");
    }

    function recover(text) {
        if (recovered) return;
        recovered = true;
        const parsed = Night.parseState(text);
        if (!parsed.ok) {
            run(["mv", "-f", statePath, statePath + ".broken"], "notice", 5000);
            notify(tr("Нічний режим: файл стану пошкоджено", "Overnight mode: the state file is damaged"),
                tr("Його збережено як overnight.json.broken", "It was kept as overnight.json.broken"));
            return;
        }
        if (!parsed.value) return;
        current = parsed.value;
        endsAt = current.endsAt;
        if (Night.isExpired(endsAt, Date.now())) {
            phase = "active";
            stopWhenReady();
        } else {
            phase = "starting";
            recovering = true;
            acquire();
        }
    }

    // Read once, synchronously, when the service starts; every write is synchronous and atomic, so
    // the file is on disk before the step it describes.
    property FileView stateFile: FileView {
        path: root.available ? root.statePath : ""
        preload: false
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaveFailed: root.writeFailed = true
    }
    Component.onCompleted: if (available) recover(stateFile.text())
    property Process inhibitProcess: Process {
        command: Night.inhibitCommand(root.inhibitSeconds)
        onStarted: {
            root.inhibitStarted = true;
            root.inhibitSettle.restart();
        }
        onExited: root.inhibitExited()
        onRunningChanged: if (!running && root.inhibitWaiting && !root.inhibitStarted) root.inhibitExited()
    }
    // systemd-inhibit exits at once when logind refuses the lock; a short wait tells that from success.
    property Timer inhibitSettle: Timer {
        interval: 500
        onTriggered: if (root.inhibitWaiting && root.inhibitProcess.running) root.inhibitConfirmed()
    }
    property Timer inhibitStartDeadline: Timer {
        interval: 8000
        running: root.inhibitWaiting && !root.inhibitStarted
        onTriggered: {
            if (!root.inhibitWaiting) return;
            // Not started means no pid yet; terminating is safe where a signal would not be.
            root.inhibitProcess.running = false;
            root.inhibitExited();
        }
    }
    property Timer inhibitStopDeadline: Timer {
        interval: 5000
        running: root.inhibitStopping
        onTriggered: if (root.inhibitProcess.running) root.inhibitProcess.signal(9)
    }
    property Timer endTimer: Timer {
        repeat: false
        onTriggered: {
            if (root.phase === "active" && Night.isExpired(root.endsAt, Date.now())) root.stop();
            else root.armEnd();
        }
    }
    property Timer readyTimer: Timer {
        interval: 250
        repeat: true
        onTriggered: {
            root.readyTicks++;
            if (!root.servicesReady() && root.readyTicks < 40) return;
            root.readyTimer.stop();
            root.waitingForServices = false;
            root.stop();
        }
    }
    property Timer retryTimer: Timer {
        interval: 1000
        onTriggered: if (root.step && !root.step.requestId) root.perform()
    }
    property Timer stepDeadline: Timer {
        interval: 25000
        onTriggered: root.stepDone(false, "timeout")
    }
    property Timer dpmsDelay: Timer {
        onTriggered: {
            if (root.phase !== "active") return;
            root.run(Night.dpmsOffCommand(), "notice", 5000);
            root.summary();
        }
    }
    property Connections powerResults: Connections {
        target: root.power
        ignoreUnknownSignals: true
        function onCommandFinished(requestId, result) { root.requestFinished(requestId, result); }
    }
    property Connections audioResults: Connections {
        target: root.audio
        ignoreUnknownSignals: true
        function onCommandFinished(requestId, result) { root.requestFinished(requestId, result); }
    }
    property Component workerComponent: Component {
        Process {
            id: worker
            required property var argv
            required property string purpose
            required property int limit
            property bool settled: false
            property bool startedOnce: false
            command: argv
            stdout: StdioCollector {}
            property Timer deadline: Timer {
                interval: worker.limit
                running: true
                onTriggered: {
                    if (worker.startedOnce && worker.running) worker.signal(9);
                    else worker.running = false;
                    root.finishWorker(worker, -1, worker.startedOnce);
                }
            }
            onStarted: startedOnce = true
            onExited: function(code, status) { root.finishWorker(worker, code, true); }
            onRunningChanged: if (!running && !startedOnce) root.finishWorker(worker, -1, false)
        }
    }
}
