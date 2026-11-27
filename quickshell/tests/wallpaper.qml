import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.features.settings
import qs.services
import qs.theme
import "../shell"
import "../logic/config.mjs" as ConfigLogic
import "../logic/settings-catalog.mjs" as Catalog

// The wallpaper service, a real background window and the settings page against a fake
// config store. The harness puts blue.png, gray.png and orange.png in ~/Pictures/Wallpapers.
// With --reduced-motion every change must swap at once and no transition overlay may appear.
ShellRoot {
    id: root

    property TestEvent pointer: TestEvent {}
    property var checks: []
    property var saves: []
    readonly property string home: Quickshell.env("HOME")
    readonly property string folder: home + "/Pictures/Wallpapers"
    property string captureBase: Quickshell.env("PENTAD_ARTIFACT_PATH") || ""
    readonly property bool reducedMotion: Quickshell.env("PENTAD_GALLERY_REDUCED_MOTION") === "1"
    property int overlaysShown: 0
    property bool transitionCaptured: true

    Component.onCompleted: Theme.resolve(Object.assign({}, Theme.config, { reducedMotion: root.reducedMotion }))
    Connections {
        target: background.transitionOverlay
        function onActiveChanged() {
            if (background.transitionOverlay.active) root.overlaysShown += 1;
        }
    }

    function check(name, passed, detail) {
        checks.push({ name: name, passed: passed === true, detail: detail || "" });
    }
    function finish() {
        console.log("PENTAD_TEST " + JSON.stringify({
            status: checks.length > 0 && checks.every(function(c) { return c.passed; }) ? "pass" : "fail",
            checks: checks,
        }));
        Qt.quit();
    }
    function lastSave(name) {
        for (let i = saves.length - 1; i >= 0; i--) if (saves[i].name === name) return saves[i].document;
        return null;
    }
    function click(item) {
        root.pointer.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0);
    }
    function itemFor(key) {
        const page = Catalog.pages.find(function(entry) { return entry.id === "wallpaper"; });
        for (const section of page.sections) for (const item of section.items) if (item.key === key) return item;
        return null;
    }
    function rgbOf(hex) { return [1, 3, 5].map(function(i) { return parseInt(hex.slice(i, i + 2), 16); }); }
    function saveWallpaper(patch) {
        fakeConfig.save("wallpaper", Object.assign({}, fakeConfig.documents.wallpaper, patch));
    }

    QtObject {
        id: fakeConfig
        property var documents: {
            const docs = JSON.parse(JSON.stringify(ConfigLogic.defaults));
            return docs;
        }
        signal documentChanged(string name)
        signal commandFinished(string requestId, var result)
        // Saves land at once, like a store that accepted the write.
        function save(name, document) {
            const requestId = "fixture-save-" + (root.saves.length + 1);
            root.saves = root.saves.concat([{ name: name, document: document, requestId: requestId }]);
            const docs = Object.assign({}, documents);
            docs[name] = JSON.parse(JSON.stringify(document));
            documents = docs;
            documentChanged(name);
            Qt.callLater(function() { fakeConfig.commandFinished(requestId, { ok: true }); });
            return requestId;
        }
        function checkpoint(name) { return "fixture-checkpoint-" + name; }
        function restore(name, id) { return "fixture-restore-" + name; }
    }
    Wallpaper {
        id: wallpaper
        config: fakeConfig
        helperPath: decodeURIComponent(Qt.resolvedUrl("helpers/pentad_recolor_wallpaper.py").toString().replace(/^file:\/\//, ""))
    }
    QtObject {
        id: fakeServices
        property var config: fakeConfig
        property var wallpaper: wallpaper
        property var settings: controller
        property var plugins: QtObject { property var catalog: ({}) }
        function text(uk, en) { return en; }
    }
    SettingsController {
        id: controller
        services: fakeServices
    }

    WallpaperWindow {
        id: background
        screen: Quickshell.screens[0]
        services: fakeServices
    }

    FloatingWindow {
        id: win
        width: 720
        height: 640
        visible: true
        color: Theme.tokens.surface
        Item {
            id: scene
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
            Column {
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 16
                SettingsField {
                    id: galleryField
                    width: parent.width
                    item: root.itemFor("wallpaperPath")
                    controller: controller
                    documents: fakeConfig.documents
                    services: fakeServices
                }
                SettingsField {
                    id: swatchField
                    width: parent.width
                    item: root.itemFor("wallpaperAccent")
                    controller: controller
                    documents: fakeConfig.documents
                    services: fakeServices
                }
                SettingsField {
                    width: parent.width
                    item: root.itemFor("wallpaperTint")
                    controller: controller
                    documents: fakeConfig.documents
                    services: fakeServices
                }
            }
        }
    }

    function grab(item, suffix) {
        if (root.captureBase === "") return;
        const target = root.captureBase + suffix;
        item.grabToImage(function(result) { root.check("capture" + (suffix || ".gallery"), result.saveToFile(target), target); });
    }

    readonly property var gallery: galleryField.controlItem
    function cardFor(path) {
        if (!gallery) return null;
        const index = gallery.entries.indexOf(path);
        return index >= 0 ? gallery.repeater.itemAt(index) : null;
    }
    function frontPath() { return background.front ? background.front.path : ""; }
    function backLayer() { return background.front === background.firstLayer ? background.secondLayer : background.firstLayer; }
    function backRetired() { const back = root.backLayer(); return back.path === "" && back.shown === false; }
    // Saves the overlay, which covers the whole screen during a sweep, with the sweep held
    // halfway; then lets it finish. (The window's own content item cannot be grabbed from QML.)
    // The wipe is saved as .transition.png, the other shaders as .transition-<kind>.png.
    function grabTransition(kind) {
        const resume = function() {
            background.transitionAnimation.resume();
            root.transitionCaptured = true;
        };
        background.transitionAnimation.pause();
        background.sweepProgress = 0.5;
        if (root.captureBase === "") { resume(); return; }
        const suffix = kind === "wipe" ? ".transition.png" : ".transition-" + kind + ".png";
        const started = background.transitionOverlay.grabToImage(function(result) {
            root.check("capture" + suffix, result.saveToFile(root.captureBase + suffix), root.captureBase + suffix);
            resume();
        });
        if (!started) { root.check("capture" + suffix, false, "grabToImage refused"); resume(); }
    }
    // The change to `image` is drawn with the shader `kind`: its overlay shows while the change
    // runs (never with reduced motion), the old image stays underneath until the overlay is gone,
    // and then it is retired. `next` starts the following change.
    function sweepSteps(kind, image, next) {
        return [
            { name: kind + "-to-" + image, until: function() {
                return root.frontReady("/" + image + ".png") && (root.reducedMotion || background.transitionOverlay.active);
            }, then: function() {
                const overlay = background.transitionOverlay;
                if (root.reducedMotion) {
                    root.check("reduced-motion-" + kind + "-swaps-at-once", background.change === "none" && !overlay.active
                        && root.backRetired() && root.overlaysShown === 0, background.change + " overlays=" + root.overlaysShown);
                    return;
                }
                const back = root.backLayer();
                const effect = overlay.item ? overlay.item.effect : null;
                root.check(kind + "-overlay-shown-mid-change", background.change === kind && overlay.visible && overlay.item.visible
                    && effect !== null && effect.status === ShaderEffect.Compiled && background.transitionAnimation.running
                    && background.sweepProgress < 1, background.change + " status=" + (effect ? effect.status : "none")
                    + " progress=" + background.sweepProgress);
                root.check(kind + "-keeps-old-image-under", back.shown === true && back.path !== ""
                    && !back.path.endsWith("/" + image + ".png"), back.path);
                root.transitionCaptured = false;
                root.grabTransition(kind);
            } },
            { name: kind + "-settles", until: function() {
                return root.transitionCaptured && !background.transitionOverlay.active && root.backRetired();
            }, then: function() {
                root.check("overlay-gone-after-" + kind, background.transitionOverlay.item === null && background.sweepFrom === null
                    && background.front.shown === true && root.frontPath().endsWith("/" + image + ".png"), root.frontPath());
                next();
            } },
        ];
    }
    function switchTo(transition, image) {
        root.saveWallpaper({ transition: transition });
        wallpaper.set(root.folder + "/" + image + ".png", "");
    }
    function frontReady(suffix) {
        return background.front !== null && background.front.status === Image.Ready && frontPath().endsWith(suffix);
    }

    // Each step waits for its condition, then acts; a step that never comes true fails and ends the run.
    property var firstOrangeCard: null
    property int step: 0
    property real stepStarted: Date.now()
    property var plan: [
        { name: "folder-scanned", until: function() { return wallpaper.images.length === 3; }, then: function() {
            root.check("folder-sorted", wallpaper.images.map(function(path) { return path.split("/").pop(); }).join(",") === "blue.png,gray.png,orange.png",
                JSON.stringify(wallpaper.images));
            root.check("no-wallpaper-hides-window", background.visible === false && background.source === "");
            root.check("gallery-lists-folder", root.gallery && root.gallery.count === 3, root.gallery ? String(root.gallery.count) : "no gallery");
            root.check("swatches-ask-for-wallpaper", swatchField.controlItem && swatchField.controlItem.candidates.length === 0);
            root.firstOrangeCard = root.cardFor(root.folder + "/orange.png");
            root.click(root.cardFor(root.folder + "/blue.png"));
        } },
        { name: "click-applies-shared", until: function() { return root.frontReady("/blue.png"); }, then: function() {
            const doc = root.lastSave("wallpaper");
            root.check("saved-home-relative", doc && doc.path === "~/Pictures/Wallpapers/blue.png", JSON.stringify(doc));
            root.check("window-visible-on-background", background.visible === true);
            const size = background.front.sourceSize;
            root.check("decodes-at-screen-size", size.width === Math.round(background.width * background.pixelRatio)
                && size.height === Math.round(background.height * background.pixelRatio), size.width + "x" + size.height);
            root.check("selected-card-marked", root.cardFor(root.folder + "/blue.png").selected === true);
            root.check("cards-survive-selection", root.cardFor(root.folder + "/orange.png") === root.firstOrangeCard);
        } },
        { name: "blue-candidates", until: function() { return wallpaper.candidates.length >= 2; }, then: function() {
            const first = root.rgbOf(wallpaper.candidates[0].hex);
            const second = root.rgbOf(wallpaper.candidates[1].hex);
            root.check("dominant-hue-first", first[2] > first[0] && second[0] > second[2], JSON.stringify(wallpaper.candidates));
            root.check("swatches-show-candidates", swatchField.controlItem.repeater.count === wallpaper.candidates.length);
            root.grab(scene, "");
            root.click(swatchField.controlItem.repeater.itemAt(1));
        } },
        { name: "swatch-sets-accent", until: function() { const theme = root.lastSave("theme"); return theme !== null; }, then: function() {
            root.check("swatch-commits-theme-accent", root.lastSave("theme").accent === wallpaper.candidates[1].hex,
                JSON.stringify(root.lastSave("theme")));
            root.click(root.cardFor(root.folder + "/orange.png"));
        } },
        { name: "fade-to-orange", until: function() { return root.frontReady("/orange.png"); }, then: function() {
            const other = background.front === background.firstLayer ? background.secondLayer : background.firstLayer;
            if (root.reducedMotion)
                root.check("reduced-motion-fade-swaps-at-once", other.shown === false && other.path === "" && background.change === "none",
                    background.change);
            else root.check("old-image-stays-under-fade", other.shown === true && other.path.endsWith("/blue.png"));
        } },
        { name: "old-layer-retired", until: function() {
            const other = background.front === background.firstLayer ? background.secondLayer : background.firstLayer;
            return other.path === "" && other.shown === false;
        }, then: function() {
            wallpaper.set(root.folder + "/gray.png", "");
        } },
        { name: "neutral-gray", until: function() { return wallpaper.sampledPath.endsWith("/gray.png") && root.frontReady("/gray.png"); }, then: function() {
            root.check("neutral-image-no-candidates", wallpaper.candidates.length === 0, JSON.stringify(wallpaper.candidates));
            wallpaper.step("next", "");
        } },
        { name: "next-wraps-in-folder", until: function() { return root.frontReady("/orange.png"); }, then: function() {
            wallpaper.step("next", "");
        } },
        { name: "next-wraps-around", until: function() { return root.frontReady("/blue.png") && wallpaper.sampledPath.endsWith("/blue.png") && wallpaper.candidates.length > 0; }, then: function() {
            root.saveWallpaper({ accentFromWallpaper: true });
        } },
        { name: "auto-accent", until: function() { const theme = root.lastSave("theme"); return theme && theme.accent === wallpaper.candidates[0].hex; }, then: function() {
            const screenName = Quickshell.screens[0].name;
            wallpaper.set(root.folder + "/orange.png", screenName);
        } },
        { name: "per-screen", until: function() { return root.frontReady("/orange.png"); }, then: function() {
            const doc = fakeConfig.documents.wallpaper;
            const screenName = Quickshell.screens[0].name;
            root.check("per-screen-override", doc.outputs[screenName] === "~/Pictures/Wallpapers/orange.png" && doc.path === "~/Pictures/Wallpapers/blue.png",
                JSON.stringify(doc));
            wallpaper.set(root.folder + "/blue.png", screenName);
        } },
        { name: "shared-clears-override", until: function() { return root.frontReady("/blue.png"); }, then: function() {
            root.check("shared-image-clears-override", Object.keys(fakeConfig.documents.wallpaper.outputs).length === 0,
                JSON.stringify(fakeConfig.documents.wallpaper));
            // Keyboard: Tab lands on the applied card; arrows move, Enter applies.
            root.cardFor(root.folder + "/blue.png").forceActiveFocus(Qt.TabFocusReason);
            root.pointer.keyClick(Qt.Key_Right, Qt.NoModifier, 0);
            root.pointer.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
        } },
        { name: "keyboard-applies", until: function() { return root.frontReady("/gray.png"); }, then: function() {
            root.check("arrow-moves-focus", root.cardFor(root.folder + "/gray.png").activeFocus === true);
            const grayCard = root.cardFor(root.folder + "/gray.png");
            root.check("focus-ring-survives-apply", grayCard.visualFocus === true, "reason=" + grayCard.focusReason);
            root.click(root.cardFor(root.folder + "/blue.png"));
        } },
        { name: "back-to-blue", until: function() { return root.frontReady("/blue.png"); }, then: function() {
            root.switchTo("wipe", "orange");
        } },
    ].concat(
        root.sweepSteps("wipe", "orange", function() { root.switchTo("disc", "gray"); }),
        root.sweepSteps("disc", "gray", function() { root.switchTo("pixelate", "orange"); }),
        root.sweepSteps("pixelate", "orange", function() { root.switchTo("iris", "gray"); }),
        root.sweepSteps("iris", "gray", function() { root.switchTo("random", "blue"); }), [
        { name: "random-to-blue", until: function() {
            return root.frontReady("/blue.png") && !background.transitionOverlay.active && root.backRetired();
        }, then: function() {
            const allowed = root.reducedMotion ? ["none"] : ["fade", "wipe", "disc", "pixelate", "iris"];
            root.check(root.reducedMotion ? "reduced-motion-random-swaps-at-once" : "random-picks-animated-transition",
                allowed.indexOf(background.change) >= 0, background.change);
            root.check(root.reducedMotion ? "reduced-motion-never-shows-overlay" : "overlay-shown-for-each-shader-change",
                root.reducedMotion ? root.overlaysShown === 0 : root.overlaysShown >= 4, "overlays=" + root.overlaysShown);
            root.saveWallpaper({ tint: "theme" });
        } },
        { name: "tinted-copy", timeout: 20000, until: function() {
            return wallpaper.tintError !== "" || (root.frontReady(".jpg") && root.frontPath().indexOf(wallpaper.cacheRoot) === 0);
        }, then: function() {
            root.check("tint-renders-recolored-copy", wallpaper.tintError === "" && root.frontPath().indexOf("/pentad/wallpapers/") > 0,
                wallpaper.tintError || root.frontPath());
            root.check("accent-samples-original", wallpaper.sampledPath.endsWith("/blue.png"));
            root.grab(background.front, ".window.png");
            root.saveWallpaper({ rotate: "15m" });
        } },
        { name: "rotate-timer-runs", until: function() { return wallpaper.rotateTimer.running === true; }, then: function() {
            root.check("rotate-15m-interval", wallpaper.rotateTimer.interval === 900000, String(wallpaper.rotateTimer.interval));
            root.check("rotate-15m-not-preview", wallpaper.preview === false && wallpaper.safeMode === false);
            root.saveWallpaper({ rotate: "off" });
        } },
        { name: "rotate-off-stops-timer", until: function() { return wallpaper.rotateTimer.running === false; }, then: function() {
            root.check("rotate-off-stops-timer", wallpaper.rotateTimer.running === false, "seconds=" + wallpaper.rotateTimer.seconds);
        } },
    ])
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (root.step >= root.plan.length) {
                stop();
                Qt.callLater(root.finish);
                return;
            }
            const entry = root.plan[root.step];
            let ready = false;
            try { ready = entry.until(); } catch (error) { ready = false; }
            if (ready) {
                root.check(entry.name, true);
                root.step += 1;
                try { entry.then(); }
                catch (error) {
                    root.check(entry.name + "-action", false, String(error));
                    stop();
                    Qt.callLater(root.finish);
                    return;
                }
                root.stepStarted = Date.now();
            } else if (Date.now() - root.stepStarted > (entry.timeout || 8000)) {
                root.check(entry.name, false, "timed out; front=" + root.frontPath() + " error=" + wallpaper.error + " tint=" + wallpaper.tintError);
                stop();
                Qt.callLater(root.finish);
            }
        }
    }
}
