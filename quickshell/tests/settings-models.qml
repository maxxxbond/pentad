import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.features.settings
import qs.services
import qs.theme
import "../logic/config.mjs" as ConfigLogic
import "../logic/models.mjs" as Models

// The Models settings page against a fake worker that answers with the model shapes of a real
// local Ollama (2026-11-18) and a fake config store: the empty page, adding providers (an
// insecure URL, then a valid one), a key that goes only to `secret.store`, role pickers, warm-up,
// the local and mixed hero, grants, local-only with a conflict retry, clearing the cache, removing
// a provider, a broken models.json, safe mode and polling only while the page is shown. Nothing
// reaches Ollama, the keyring, the network or the user's files.
ShellRoot {
    id: root

    property TestEvent pointer: TestEvent {}
    property var checks: []
    property bool safe: false
    readonly property string secretValue: "sk-or-fixture-SECRET-0123456789"
    property string captureBase: Quickshell.env("PENTAD_ARTIFACT_PATH") || ""
    property int pendingCaptures: 0

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail === undefined ? "" : typeof detail === "string" ? detail : JSON.stringify(detail) });
    }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(c) { return c.passed; }) ? "pass" : "fail",
            checks: checks,
        }));
        Qt.quit();
    }
    function findBy(item, predicate) {
        if (!item) return null;
        if (predicate(item)) return item;
        for (const child of item.children || []) {
            const found = root.findBy(child, predicate);
            if (found) return found;
        }
        return null;
    }
    function findNamed(item, name) {
        return root.findBy(item, function(candidate) { return candidate.objectName === name; });
    }
    function named(name) {
        return findNamed(scene, name);
    }
    function click(item) {
        root.pointer.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
    }
    function grab(suffix) {
        if (root.captureBase === "") return;
        const target = suffix === "" ? root.captureBase : root.captureBase + "." + suffix + ".png";
        root.pendingCaptures++;
        scene.grabToImage(function(result) {
            root.check("capture-" + (suffix || "page"), result.saveToFile(target), target);
            root.pendingCaptures--;
        });
    }
    function grabItem(item, suffix) {
        if (root.captureBase === "" || !item) return;
        const target = root.captureBase + "." + suffix + ".png";
        root.pendingCaptures++;
        item.grabToImage(function(result) {
            root.check("capture-" + suffix, result.saveToFile(target), target);
            root.pendingCaptures--;
        });
    }
    function requests(op) {
        return fakeWorker.requests.filter(function(entry) { return entry.op === op; });
    }
    function savedModels() {
        return fakeConfig.saved.filter(function(entry) { return entry.name === "models"; });
    }
    function lastModels() {
        const list = savedModels();
        return list.length ? list[list.length - 1].document : null;
    }
    function scrollTo(item) {
        if (!item) return;
        const flick = root.findBy(page, function(candidate) {
            return candidate.contentY !== undefined && candidate.contentHeight !== undefined && candidate.contentItem !== undefined;
        });
        if (!flick) return;
        const y = flick.contentY + item.mapToItem(flick, 0, 0).y - 120;
        flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
    }

    // The resident worker, faked with the answers of a real machine: qwen3.5:9b loaded and fully in
    // VRAM, a 17 GB card, a relayed cloud model, and a keyring that is a plain map.
    QtObject {
        id: fakeWorker
        property string state: "ready"
        property bool ollamaUp: true
        property int serial: 0
        property var requests: []
        property var keyring: ({})
        property int cacheEntries: 4
        property int cacheBytes: 12 * 1024 * 1024
        readonly property var ollamaModels: [
            { name: "qwen3.8:latest", sizeBytes: 17700000000, parameterSize: "27B", capabilities: ["completion", "tools"] },
            { name: "gpt-oss:120b-cloud", sizeBytes: 384, capabilities: ["completion", "tools", "thinking"] },
            { name: "embeddinggemma-2:270m", sizeBytes: 300000000, capabilities: ["embedding"] },
            { name: "qwen3.5:9b", sizeBytes: 6600000000, capabilities: ["completion", "vision", "tools", "thinking"] },
            { name: "qwen3.5:0.8b", sizeBytes: 1300000000, capabilities: ["completion", "vision", "tools", "thinking"] }
        ]
        function accepts(op) { return true; }
        function recover() { return false; }
        function cancel(id) {}
        function request(op, payload, callbacks) {
            const id = ++serial;
            requests = requests.concat([{ id: id, op: op, payload: JSON.parse(JSON.stringify(payload || {})) }]);
            Qt.callLater(function() { fakeWorker.respond(op, payload || {}, callbacks || {}); });
            return id;
        }
        function respond(op, payload, callbacks) {
            const done = function(value) { callbacks.onResult({ ok: true, value: value, cached: false }); };
            const fail = function(reason, message) { callbacks.onResult({ ok: false, reason: reason, message: message || reason }); };
            const local = payload.provider && String(payload.provider.baseUrl).indexOf("http://127.0.0.1") === 0;
            if (op === "llm.models") {
                if (local && !ollamaUp) fail("unavailable", "Connection refused");
                else done({ models: local ? ollamaModels : [{ name: "openai/gpt-5-mini" }, { name: "anthropic/claude-sonnet-4.5" }] });
            } else if (op === "llm.loaded") {
                done({ supported: true, models: [{ name: "qwen3.5:9b", sizeBytes: 6600000000, vramBytes: 6600000000,
                    expiresAt: new Date(Date.now() + 4 * 60000 - 1000).toISOString() }] });
            } else if (op === "system.vram") {
                done({ available: true, source: "sysfs", totalBytes: 17000000000, usedBytes: 7400000000,
                    gpus: [{ vendor: "AMD", totalBytes: 17000000000, usedBytes: 7400000000, source: "sysfs" }] });
            } else if (op === "worker.stats") {
                done({ completed: 3, failed: 0, running: 0, queued: 0,
                    cache: { enabled: true, entries: cacheEntries, bytes: cacheBytes, maxBytes: 64 * 1024 * 1024, maxEntries: 1000 } });
            } else if (op === "worker.clear-cache") {
                const removed = cacheEntries;
                cacheEntries = 0;
                cacheBytes = 0;
                done({ removed: removed, cache: { enabled: true, entries: 0, bytes: 0, maxBytes: 64 * 1024 * 1024, maxEntries: 1000 } });
            } else if (op === "secret.status") {
                done({ status: keyring[payload.ref] ? "stored" : "missing" });
            } else if (op === "secret.store") {
                const next = Object.assign({}, keyring);
                next[payload.ref] = payload.value;
                keyring = next;
                done({ status: "stored" });
            } else if (op === "secret.clear") {
                const next = Object.assign({}, keyring);
                delete next[payload.ref];
                keyring = next;
                done({ status: "missing" });
            } else if (op === "llm.warm") {
                done({ warmed: true, loadMs: 4600, wallMs: 4700 });
            } else fail("unsupported", op);
        }
    }

    // The config store, faked: saves land in memory and on a "disk" copy; a conflict on demand.
    QtObject {
        id: fakeConfig
        property var documents: Object.assign({}, ConfigLogic.defaults, { models: Models.parseModels({}) })
        property var documentStates: ({ models: { kind: "ready" } })
        property var disk: null
        property int conflictsLeft: 0
        property int conflicts: 0
        property int reloads: 0
        property int serial: 0
        property var saved: []
        signal commandFinished(string requestId, var result)
        function save(name, value) {
            const requestId = "fixture-save-" + (++serial);
            const text = JSON.stringify(value);
            Qt.callLater(function() {
                if (fakeConfig.conflictsLeft > 0) {
                    fakeConfig.conflictsLeft--;
                    fakeConfig.conflicts++;
                    fakeConfig.commandFinished(requestId, { ok: false, reason: "conflict", message: "Changed on disk" });
                    return;
                }
                const parsed = ConfigLogic.parseDocument(name, text);
                if (!parsed.ok) {
                    fakeConfig.commandFinished(requestId, parsed);
                    return;
                }
                fakeConfig.saved = fakeConfig.saved.concat([{ name: name, text: text, document: parsed.value }]);
                const next = Object.assign({}, fakeConfig.documents);
                next[name] = parsed.value;
                fakeConfig.documents = next;
                fakeConfig.commandFinished(requestId, { ok: true });
            });
            return requestId;
        }
        function reload(name) {
            const requestId = "fixture-read-" + (++serial);
            Qt.callLater(function() {
                fakeConfig.reloads++;
                if (fakeConfig.disk && name === "models") {
                    const next = Object.assign({}, fakeConfig.documents);
                    next.models = fakeConfig.disk;
                    fakeConfig.documents = next;
                    fakeConfig.disk = null;
                }
                fakeConfig.commandFinished(requestId, { ok: true });
            });
            return requestId;
        }
        function checkpoint(name) { return "fixture-checkpoint-" + name; }
        function restore(name, id) { return "fixture-restore-" + name; }
    }
    QtObject {
        id: fakePlugins
        property int revision: 0
        property var catalog: ({
            "pentad.chat": { builtin: true, manifest: { id: "pentad.chat", name: "Chat", capabilities: ["llm.chat"] } },
            "example.summarizer": { builtin: false, manifest: { id: "example.summarizer", name: "Summarizer", capabilities: ["llm.chat"] } },
            "example.receipts": { builtin: false, manifest: { id: "example.receipts", name: "Receipt reader", capabilities: ["image.ocr", "llm.chat"] } },
            "example.clock": { builtin: false, manifest: { id: "example.clock", name: "Clock" } }
        })
    }
    Capabilities {
        id: capabilityService
        preview: false
        safeMode: root.safe
        worker: fakeWorker
        models: fakeConfig.documents.models
    }
    ModelSettings {
        id: modelState
        preview: false
        safeMode: root.safe
        config: fakeConfig
        capabilities: capabilityService
        pollInterval: 400
    }
    QtObject {
        id: fakeServices
        property var config: fakeConfig
        property var plugins: fakePlugins
        property var settings: controller
        property var capabilities: capabilityService
        property var modelSettings: modelState
        property bool safeMode: root.safe
        property bool preview: false
        property bool ukrainian: true
        function text(uk, en) { return ukrainian ? uk : en; }
    }
    SettingsController {
        id: controller
        services: fakeServices
    }

    FloatingWindow {
        id: win
        implicitWidth: 1000
        implicitHeight: 1560
        visible: true
        color: Theme.tokens.surface

        Item {
            id: scene
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
            SettingsSidebar {
                id: sidebar
                x: 0
                y: 0
                width: preferredWidth
                height: parent.height
                services: fakeServices
                collapsed: false
            }
            SettingsPage {
                id: page
                x: sidebar.width + 1
                width: parent.width - x
                height: parent.height
                services: fakeServices
            }
            Loader {
                id: sheetLoader
                anchors.fill: parent
                z: 10
                active: controller.flow === "model-provider"
                sourceComponent: SettingsProviderSheet { services: fakeServices }
            }
        }

        TestCase {
            id: testCase
            name: "settings-models"
            when: false

            function picker(role) { return root.named("settings-model-picker-combo-" + role); }
            function entryIndex(role, value) {
                const owner = root.named("settings-model-picker-" + role);
                return owner ? owner.entries.findIndex(function(entry) { return entry.value === value; }) : -1;
            }
            function pick(role, value) {
                const combo = picker(role);
                const index = entryIndex(role, value);
                if (combo && index >= 0) combo.activated(index);
                wait(60);
                return index;
            }
            function settle() {
                for (let i = 0; i < 20 && root.pendingCaptures > 0; i++) wait(50);
            }

            function test_all() {
                Theme.resolve(Object.assign({}, ConfigLogic.defaults.theme, {
                    appearance: Quickshell.env("PENTAD_GALLERY_APPEARANCE") || "dark",
                    reducedMotion: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
                }));
                controller.openPage("models");
                wait(150);

                // Empty: no provider, every role empty.
                const hero = root.named("settings-models-hero");
                root.check("page-opens-with-the-hero", controller.pageId === "models" && hero !== null);
                root.check("empty-headline", root.named("settings-models-headline").text === "Моделей"
                    && root.named("settings-models-headline-accent").text === "ще немає.", root.named("settings-models-headline").text);
                root.check("empty-installed-note", root.named("settings-installed-models-note").text === "Локальний Ollama не підключено.");
                root.check("empty-pickers-show-none", picker("chat") !== null && picker("chat").displayText === "Не вибрано");
                root.check("acquired-while-shown", modelState.consumers > 0 && root.requests("system.vram").length > 0);
                root.check("empty-has-no-provider-card", root.findBy(page, function(item) {
                    return String(item.objectName).indexOf("settings-provider-card-") === 0;
                }) === null);
                root.grab("empty");
                settle();

                // Add provider: an insecure URL is refused inline, a loopback one is saved.
                const addOllama = root.named("settings-provider-add-ollama");
                root.click(addOllama);
                wait(250);
                let sheetPopup = sheetLoader.item;
                root.check("add-sheet-opens-with-the-preset", controller.flow === "model-provider" && sheetPopup !== null
                    && sheetPopup.draft.kind === "ollama" && sheetPopup.draft.baseUrl === "http://127.0.0.1:11434"
                    && root.findNamed(sheetPopup, "settings-provider-sheet-title").text === "Новий провайдер");
                const url = root.findNamed(sheetPopup, "settings-provider-url");
                url.text = "http://192.168.1.5:11434";
                url.textEdited();
                wait(30);
                const save = root.findNamed(sheetPopup, "settings-provider-save");
                root.check("insecure-url-is-refused-inline", sheetPopup.urlError().indexOf("https://") >= 0 && url.error === true
                    && save.enabled === false, sheetPopup.urlError());
                root.grab("sheet-invalid");
                settle();
                url.text = "not a url";
                url.textEdited();
                wait(20);
                root.check("garbage-url-is-refused-inline", sheetPopup.urlError().indexOf("http(s)") >= 0);
                url.text = "http://127.0.0.1:11434";
                url.textEdited();
                wait(20);
                root.check("valid-url-clears-the-error", sheetPopup.urlError() === "" && save.enabled === true);
                root.click(save);
                wait(300);
                const afterAdd = root.lastModels();
                root.check("ollama-provider-saved", !!afterAdd && afterAdd.providers.length === 1 && afterAdd.providers[0].id === "local"
                    && afterAdd.providers[0].credential === "" && sheetLoader.item === null && controller.flow === "", afterAdd);
                wait(150);
                root.check("ollama-models-listed", modelState.lists.local && modelState.lists.local.state === "ready"
                    && modelState.lists.local.models.length === 5);
                root.check("ollama-card-is-running", root.named("settings-provider-status-local").text === "працює");

                // Role pickers: filtered per role, cloud relays marked, bindings saved.
                const chatOwner = root.named("settings-model-picker-chat");
                const chatValues = chatOwner.entries.map(function(entry) { return entry.value; });
                root.check("chat-picker-lists-completion-models-largest-first", JSON.stringify(chatValues) === JSON.stringify(["",
                    "local/qwen3.8:latest", "local/qwen3.5:9b", "local/qwen3.5:0.8b", "local/gpt-oss:120b-cloud", "__manual__"]), chatValues);
                root.check("cloud-relay-is-marked", chatOwner.entries[4].cloud === true);
                const embedValues = root.named("settings-model-picker-embed").entries.map(function(entry) { return entry.value; });
                root.check("embed-picker-lists-embedding-models", JSON.stringify(embedValues) === JSON.stringify(["", "local/embeddinggemma-2:270m", "__manual__"]), embedValues);
                pick("chat", "local/qwen3.5:9b");
                wait(100);
                root.check("chat-role-saved", root.lastModels().roles.chat === "local/qwen3.5:9b", root.lastModels().roles);
                root.check("chat-picker-shows-chips-and-size", picker("chat").displayText === "qwen3.5:9b"
                    && root.named("settings-model-picker-tags-chat").visible);
                pick("fast", "local/qwen3.5:0.8b");
                wait(100);
                pick("vision", "local/qwen3.5:9b");
                wait(100);
                pick("embed", "local/embeddinggemma-2:270m");
                wait(100);
                pick("translate", "local/qwen3.5:9b");
                wait(100);
                const roles = root.lastModels().roles;
                root.check("all-roles-bound-locally", roles.fast === "local/qwen3.5:0.8b" && roles.vision === "local/qwen3.5:9b"
                    && roles.embed === "local/embeddinggemma-2:270m" && roles.translate === "local/qwen3.5:9b", roles);
                // Manual entry for a model no list reports.
                pick("fast", "__manual__");
                const field = root.named("settings-model-picker-field-fast");
                root.check("manual-entry-opens", field !== null && field.visible);
                field.text = "llama3.2:1b";
                root.click(root.named("settings-model-picker-apply-fast"));
                wait(150);
                root.check("manual-model-saved", root.lastModels().roles.fast === "local/llama3.2:1b", root.lastModels().roles.fast);
                pick("fast", "local/qwen3.5:0.8b");
                wait(100);

                // Local hero with live numbers.
                modelState.poll();
                wait(150);
                root.check("local-headline", root.named("settings-models-headline").text === "Усе"
                    && root.named("settings-models-headline-accent").text === "локально.", root.named("settings-models-headline").text);
                root.check("local-subline", root.named("settings-models-subline").text.indexOf("жоден віджет не відправляє дані в хмару") >= 0
                    && root.named("settings-models-subline").text.indexOf("5 моделей") >= 0, root.named("settings-models-subline").text);
                const memory = root.named("settings-models-stat-memory");
                root.check("hero-shows-vram-of-loaded-models", memory !== null && memory.modelData.value === "6,6 ГБ", memory ? memory.modelData : null);
                root.check("hero-shows-ocr-cache", root.named("settings-models-stat-cache").modelData.value === "12 МіБ");
                root.check("installed-cards-from-the-list", root.named("settings-installed-model-qwen3.5:9b") !== null
                    && root.named("settings-installed-size-qwen3.5:9b").text === "6,6"
                    && root.named("settings-installed-size-gpt-oss:120b-cloud").text === "хмара");
                root.check("provider-card-shows-what-is-loaded", root.named("settings-provider-detail-local").text.indexOf("qwen3.5:9b у пам’яті") >= 0
                    && root.named("settings-provider-detail-local").text.indexOf("ще 4 хв") >= 0,
                    root.named("settings-provider-detail-local").text);

                // Warm the chat role.
                const warm = root.named("settings-model-warm-chat");
                root.click(warm);
                wait(150);
                const warmCall = root.requests("llm.warm");
                root.check("warm-loads-the-role-model", warmCall.length === 1 && warmCall[0].payload.model === "qwen3.5:9b"
                    && warmCall[0].payload.provider.baseUrl === "http://127.0.0.1:11434");
                root.check("warm-shows-the-load-time", root.named("settings-model-warm-note-chat").text === "теплий · 4,6 с",
                    root.named("settings-model-warm-note-chat").text);
                root.check("hero-shows-the-warm-up", root.named("settings-models-stat-warm") !== null);
                root.scrollTo(root.named("settings-models-hero"));
                wait(50);
                root.grab("");
                root.grab("local");
                settle();
                root.scrollTo(root.named("settings-model-worker"));
                wait(60);
                root.grab("local-bottom");
                settle();
                root.scrollTo(root.named("settings-models-hero"));
                wait(30);

                // A remote provider with its key in the keyring.
                root.click(root.named("settings-provider-add-openrouter"));
                wait(250);
                sheetPopup = sheetLoader.item;
                root.check("openrouter-preset", sheetPopup.draft.kind === "openai-compatible" && sheetPopup.draft.baseUrl === "https://openrouter.ai/api/v1"
                    && sheetPopup.draft.keySource === "keyring");
                const key = root.findNamed(sheetPopup, "settings-provider-key");
                key.forceActiveFocus(Qt.TabFocusReason);
                key.text = root.secretValue;
                root.check("key-field-hides-the-value", key.echoMode === TextInput.Password && key.displayText.indexOf("SECRET") < 0);
                root.grab("sheet-key");
                settle();
                root.click(root.findNamed(sheetPopup, "settings-provider-save"));
                root.check("key-field-cleared-at-once", key === null || key.text === "" || sheetLoader.item === null);
                wait(300);
                const stores = root.requests("secret.store");
                root.check("key-went-to-secret-store", stores.length === 1 && stores[0].payload.ref === "secret://pentad/providers/openrouter"
                    && stores[0].payload.value === root.secretValue);
                const leaked = fakeWorker.requests.filter(function(entry) {
                    return entry.op !== "secret.store" && JSON.stringify(entry.payload).indexOf(root.secretValue) >= 0;
                });
                root.check("key-in-no-other-request", leaked.length === 0, leaked);
                root.check("key-never-in-the-config", fakeConfig.saved.every(function(entry) { return entry.text.indexOf(root.secretValue) < 0; })
                    && JSON.stringify(fakeConfig.documents).indexOf(root.secretValue) < 0);
                root.check("key-not-kept-in-page-state", JSON.stringify([modelState.lists, modelState.keyStatus, modelState.warmth, modelState.sheet])
                    .indexOf(root.secretValue) < 0);
                const routerDoc = root.lastModels().providers.find(function(provider) { return provider.id === "openrouter"; });
                root.check("provider-references-the-keyring", !!routerDoc && routerDoc.credential === "secret://pentad/providers/openrouter"
                    && sheetLoader.item === null, routerDoc);
                wait(100);
                root.check("key-status-stored", root.named("settings-provider-key-openrouter").text === "ключ у сховищі",
                    root.named("settings-provider-key-openrouter").text);

                // Mixed hero: translation goes to OpenRouter.
                wait(150);
                pick("translate", "openrouter/openai/gpt-5-mini");
                wait(150);
                root.check("translate-bound-to-the-cloud", root.lastModels().roles.translate === "openrouter/openai/gpt-5-mini");
                root.check("mixed-headline-names-the-cloud", root.named("settings-models-headline").text === "Є"
                    && root.named("settings-models-headline-accent").text === "хмарні провайдери."
                    && root.named("settings-models-subline").text.indexOf("OpenRouter") === 0, root.named("settings-models-subline").text);
                root.check("pickers-keep-their-value-after-a-refresh", picker("chat").displayText === "qwen3.5:9b"
                    && picker("embed").displayText === "embeddinggemma-2:270m", picker("chat").displayText);
                root.check("openrouter-card-lists-its-role", root.named("settings-provider-detail-openrouter").text === "Ролі: Переклад");
                root.grab("mixed");
                settle();

                // Hover and keyboard focus on the key controls.
                const primary = root.named("settings-provider-primary-local");
                root.pointer.mouseMove(primary, primary.width / 2, primary.height / 2, 0, Qt.NoButton, Qt.NoModifier);
                wait(200);
                root.check("hover-on-a-card-button", primary.hovered === true);
                root.grab("hover");
                settle();
                picker("chat").forceActiveFocus(Qt.TabFocusReason);
                wait(150);
                root.check("keyboard-focus-ring-on-the-picker", picker("chat").visualFocus === true);
                root.grab("focus");
                settle();
                root.click(picker("chat"));
                wait(450);
                root.check("picker-opens-from-the-pointer", picker("chat").popup.visible === true);
                root.grabItem(picker("chat").popup.contentItem, "picker");
                settle();
                root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                wait(450);
                root.check("picker-closes-on-escape", picker("chat").popup.opened === false);

                // Grants: external widgets with capabilities, written to grants[moduleId].remote.
                const grants = root.named("settings-model-grants");
                root.check("grant-rows-for-external-widgets", grants.rows.length === 2 && grants.rows[0].moduleId === "example.receipts",
                    grants.rows.map(function(row) { return row.moduleId; }));
                root.scrollTo(grants);
                wait(50);
                const grantToggle = root.named("settings-model-grant-toggle-example.receipts");
                root.click(grantToggle);
                wait(150);
                root.check("grant-saved", root.lastModels().grants["example.receipts"] && root.lastModels().grants["example.receipts"].remote === true,
                    root.lastModels().grants);

                // Local only: through the generic toggle, with one conflict retried after a reload.
                const localOnlyField = root.named("settings-field-localOnly");
                const localOnlyToggle = localOnlyField.controlItem;
                fakeConfig.conflictsLeft = 1;
                fakeConfig.disk = Object.assign({}, fakeConfig.documents.models, { grants: { "example.receipts": { remote: true }, "example.other": { remote: false } } });
                const reloadsBefore = fakeConfig.reloads;
                root.click(localOnlyToggle);
                wait(300);
                root.check("local-only-saved-after-one-retry", root.lastModels().privacy.localOnly === true && fakeConfig.conflicts === 1
                    && fakeConfig.reloads === reloadsBefore + 1 && controller.error === "" && controller.pendingId === "", { error: controller.error });
                root.check("retry-keeps-the-change-made-elsewhere", !!root.lastModels().grants["example.other"]);
                const restingToggle = root.named("settings-model-grant-toggle-example.receipts");
                root.check("local-only-rests-the-grants", restingToggle !== null && restingToggle.requestedEnabled === false
                    && restingToggle.checked === true);
                root.check("local-only-blocks-the-cloud-card", root.named("settings-provider-detail-openrouter").text.indexOf("Лише локально") >= 0);
                root.grab("privacy");
                settle();
                root.click(localOnlyToggle);
                wait(200);
                root.check("local-only-off-again", root.lastModels().privacy.localOnly === false);

                // Background worker: cache and idle minutes.
                const clear = root.named("settings-model-clear-cache");
                root.scrollTo(clear);
                wait(50);
                root.check("worker-summary", root.named("settings-model-worker-summary").text === "3 задачі · кеш 12 МіБ з 64 МіБ",
                    root.named("settings-model-worker-summary").text);
                root.click(clear);
                wait(150);
                root.check("clear-cache-runs", root.requests("worker.clear-cache").length === 1
                    && root.named("settings-model-worker-summary").text.indexOf("кеш 0 Б з 64 МіБ") >= 0, root.named("settings-model-worker-summary").text);
                const idle = root.named("settings-model-idle-minutes");
                root.check("idle-minutes-from-seconds", idle.value === 10);
                idle.value = 3;
                idle.valueModified();
                wait(150);
                root.check("idle-minutes-saved-as-seconds", root.lastModels().worker.idleExitSeconds === 180);

                // Remove the cloud provider: confirm, its role empties, its key goes.
                root.scrollTo(root.named("settings-model-providers"));
                wait(50);
                root.click(root.named("settings-provider-remove-openrouter"));
                wait(80);
                const confirm = root.named("settings-provider-confirm-openrouter");
                root.check("remove-asks-first", confirm.visible === true && root.lastModels().providers.length === 2);
                root.grab("remove-confirm");
                settle();
                root.click(root.named("settings-provider-confirm-remove-openrouter"));
                wait(250);
                const removed = root.lastModels();
                root.check("remove-clears-roles", removed.providers.length === 1 && removed.roles.translate === "", removed.roles);
                const clears = root.requests("secret.clear");
                root.check("remove-clears-the-key", clears.length === 1 && clears[0].payload.ref === "secret://pentad/providers/openrouter"
                    && !fakeWorker.keyring["secret://pentad/providers/openrouter"]);

                // English.
                fakeServices.ukrainian = false;
                wait(80);
                root.check("english-headline", root.named("settings-models-headline").text === "All"
                    && root.named("settings-models-headline-accent").text === "local.", root.named("settings-models-headline").text);
                root.check("english-worker-row", root.named("settings-model-worker-summary").text.indexOf("cache") >= 0);
                fakeServices.ukrainian = true;
                wait(50);

                // Polling stops while the page is hidden.
                wait(500);
                root.check("polls-while-shown", root.requests("llm.loaded").length >= 3);
                page.visible = false;
                wait(80);
                const loadedCalls = root.requests("llm.loaded").length;
                wait(1000);
                root.check("no-polling-while-hidden", modelState.consumers === 0 && root.requests("llm.loaded").length === loadedCalls,
                    { consumers: modelState.consumers, before: loadedCalls, after: root.requests("llm.loaded").length });
                page.visible = true;
                wait(150);

                // A broken models.json: nothing is written, the hero says why.
                const savesBefore = fakeConfig.saved.length;
                fakeConfig.documentStates = { models: { kind: "invalid", reason: "invalid" } };
                wait(80);
                root.scrollTo(root.named("settings-models-hero"));
                wait(50);
                root.check("broken-headline", root.named("settings-models-headline").text === "Файл моделей"
                    && root.named("settings-models-subline").text.indexOf("models.json") >= 0, root.named("settings-models-subline").text);
                root.check("broken-disables-adding", root.named("settings-provider-add-button").enabled === false);
                root.check("broken-refuses-a-role", modelState.setRole("chat", "local", "qwen3.5:0.8b") === false);
                root.check("broken-refuses-the-generic-toggle", controller.commit(localOnlyField.item, true) === ""
                    && controller.error.indexOf("models.json") >= 0, controller.error);
                wait(80);
                root.check("broken-wrote-nothing", fakeConfig.saved.length === savesBefore);
                root.grab("broken");
                settle();
                fakeConfig.documentStates = { models: { kind: "ready" } };
                controller.error = "";
                wait(50);

                // Safe mode: no network or keyring, and the page says so.
                root.safe = true;
                const listsBefore = root.requests("llm.models").length;
                modelState.refresh(true);
                wait(150);
                root.check("safe-mode-note", root.named("settings-models-mode").visible === true
                    && root.named("settings-models-mode").text.indexOf("Безпечний режим") === 0);
                root.check("safe-mode-lists-nothing", root.requests("llm.models").length === listsBefore
                    && modelState.lists.local.state === "error" && modelState.lists.local.reason === "safe-mode");
                root.check("safe-mode-no-warm", root.named("settings-model-warm-chat").enabled === false);
                root.click(root.named("settings-provider-add-anthropic"));
                wait(250);
                sheetPopup = sheetLoader.item;
                const safeKey = root.findNamed(sheetPopup, "settings-provider-key");
                root.check("safe-mode-keyring-field-off", safeKey.enabled === false);
                root.grab("safe-mode");
                settle();
                root.pointer.keyClick(Qt.Key_Escape, Qt.NoModifier, 0);
                wait(100);
                root.check("sheet-closes-on-escape", sheetLoader.item === null && controller.flow === "");
                wait(250);

                settle();
                root.finish();
            }
        }
        Timer {
            interval: 300
            running: true
            repeat: false
            onTriggered: testCase.test_all()
        }
    }
}
