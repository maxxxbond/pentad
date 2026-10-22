import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import '../logic/wallpaper.mjs' as Rules
import '../logic/wallpaper-palette.mjs' as Palette
import '../logic/theme.mjs' as ThemeRules

// Pentad's own wallpaper: which image each screen shows, the folder the picker browses,
// accent candidates sampled from the shared image and, when the tint is "theme", copies of
// the images recolored toward the current theme (cached, rebuilt when the theme changes).
// The background windows only render; this object decides.
QtObject {
    id: root
    required property var config
    property bool preview: false
    property bool safeMode: false
    property var filePicker: null
    property string helperPath: ''
    readonly property string home: Quickshell.env('HOME') || ''
    readonly property string cacheRoot: (Quickshell.env('XDG_CACHE_HOME') || home + '/.cache') + '/pentad/wallpapers'
    readonly property var document: config.documents.wallpaper || Rules.wallpaperDefaults
    readonly property var theme: config.documents.theme
    readonly property string directory: Rules.expandHome(document.directory, home)
    readonly property string sharedPath: Rules.expandHome(document.path, home)
    // Absolute paths of the images in the folder, in name order.
    property var images: []
    property string error: ''
    // Screens a picture can target: connector name and the monitor's model for a label.
    readonly property var outputs: Quickshell.screens.map(function(screen) {
        return { value: screen.name, label: screen.model ? String(screen.model).trim() : screen.name };
    })

    function pathFor(output) { return Rules.expandHome(Rules.wallpaperFor(document, output), home); }

    // What a screen actually draws: the recolored copy while one is ready, else the original.
    function displayPathFor(output) {
        const original = pathFor(output);
        if (!original || document.tint !== 'theme') return original;
        return tinted[original] || original;
    }

    function save(next) {
        if (preview || safeMode) return '';
        error = '';
        return config.save('wallpaper', next);
    }

    function set(path, output) {
        const absolute = Rules.fileUrlToPath(path);
        if (!absolute || !Rules.isImagePath(absolute)) { error = 'Not an image: ' + absolute; return ''; }
        return save(Rules.withWallpaper(document, Rules.collapseHome(absolute, home), output || ''));
    }
    function step(action, output) {
        const current = pathFor(output || '');
        const next = action === 'random' ? Rules.pickRandom(images, current)
            : Rules.stepWallpaper(images, current, action === 'previous' ? -1 : 1);
        return next ? set(next, output) : '';
    }
    function chooseFile(output) {
        if (!filePicker) return false;
        return filePicker.pick({ title: 'Choose wallpaper', multiple: false,
            filters: ['Images (' + Rules.imageExtensions.map(function(ext) { return '*.' + ext + ' *.' + ext.toUpperCase(); }).join(' ') + ')'],
            done: function(result) {
                if (result.ok && result.uris && result.uris.length) root.set(result.uris[0], output || '');
                else if (!result.ok && !result.cancelled) root.error = result.reason || 'The file chooser failed.';
            } });
    }

    property FolderListModel folder: FolderListModel {
        folder: root.safeMode || !root.directory ? '' : 'file://' + root.directory
        nameFilters: Rules.imageExtensions.concat(Rules.imageExtensions.map(function(ext) { return ext.toUpperCase(); }))
            .map(function(ext) { return '*.' + ext; })
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        onCountChanged: Qt.callLater(root.collect)
        onStatusChanged: Qt.callLater(root.collect)
    }
    function collect() {
        const list = [];
        for (let i = 0; i < folder.count; i++) list.push(String(folder.get(i, 'filePath')));
        images = list;
    }

    // Accent candidates for the shared image. Median-cut buckets hold about equal pixel
    // counts, so the quantized colors stand in for an evenly weighted sample of the image.
    readonly property string samplePath: sharedPath
    property string sampledPath: ''
    property var candidates: []
    property var lastPixels: null
    property ColorQuantizer quantizer: ColorQuantizer {
        source: root.samplePath && !root.safeMode ? 'file://' + root.samplePath.split('/').map(encodeURIComponent).join('/') : ''
        depth: 5
        rescaleSize: 128
        onColorsChanged: {
            const pixels = [];
            for (let i = 0; i < colors.length; i++)
                pixels.push(Math.round(colors[i].r * 255), Math.round(colors[i].g * 255), Math.round(colors[i].b * 255), 255);
            if (pixels.length) root.reportSample(root.samplePath, pixels);
        }
    }
    function reportSample(path, pixels) {
        if (path !== samplePath) return;
        const first = sampledPath === '';
        const changedImage = sampledPath !== path;
        sampledPath = path;
        lastPixels = pixels;
        candidates = Palette.accentCandidates(pixels, { appearance: theme.appearance });
        // Deferred: the theme write must not run inside the binding update that got us here.
        if (changedImage && !first) Qt.callLater(applyAutoAccent);
    }
    onSamplePathChanged: if (samplePath === '') { sampledPath = ''; candidates = []; }
    property Connections themeWatch: Connections {
        target: root.config
        function onDocumentChanged(name) {
            if (name !== 'theme') return;
            // Candidates depend on the appearance; recolored copies on the whole palette.
            if (root.lastPixels) root.candidates = Palette.accentCandidates(root.lastPixels, { appearance: root.theme.appearance });
            root.refreshTint();
        }
    }
    readonly property bool accentFromWallpaper: document.accentFromWallpaper === true
    onAccentFromWallpaperChanged: if (accentFromWallpaper) Qt.callLater(applyAutoAccent)
    function applyAutoAccent() {
        if (!accentFromWallpaper || !candidates.length) return '';
        return useAccent(candidates[0].hex);
    }
    function useAccent(hex) {
        if (preview || safeMode || !ThemeRules.isHexColor(hex) || String(theme.accent).toUpperCase() === hex.toUpperCase()) return '';
        return config.save('theme', Object.assign({}, theme, { accent: hex.toUpperCase() }));
    }

    // Recolored copies, keyed by original path. Jobs run one at a time.
    property var tinted: ({})
    property var tintQueue: []
    property string tintError: ''
    readonly property bool tinting: tintProcess.running
    readonly property var wantedTints: {
        if (document.tint !== 'theme') return [];
        const paths = [document.path].concat(Object.keys(document.outputs).map(function(name) { return document.outputs[name]; }))
            .filter(function(path) { return path; })
            .map(function(path) { return Rules.expandHome(path, root.home); });
        return paths.filter(function(path, index) { return paths.indexOf(path) === index; });
    }
    onWantedTintsChanged: refreshTint()
    function tintTarget(original) {
        const stops = Palette.stopsArgument(Palette.recolorStops(theme));
        const stem = original.split('/').pop().replace(/\.[^.]+$/, '').replace(/[^\w.-]+/g, '-').slice(0, 48);
        return cacheRoot + '/' + Qt.md5(original).slice(0, 12) + '-' + Qt.md5(stops).slice(0, 8) + '-' + stem + '.jpg';
    }
    function refreshTint() {
        if (preview || safeMode) return;
        const keep = {};
        const queue = [];
        wantedTints.forEach(function(original) {
            const target = tintTarget(original);
            if (tinted[original] === target) keep[original] = target;
            else queue.push({ original: original, target: target });
        });
        tinted = keep;
        tintQueue = queue;
        if (!tintProcess.running) nextTint();
    }
    function nextTint() {
        if (!tintQueue.length) return;
        const job = tintQueue[0];
        tintQueue = tintQueue.slice(1);
        tintProcess.job = job;
        // An existing copy from an earlier session is reused; the helper only runs when missing.
        tintProcess.command = ['sh', '-c', 'mkdir -p "$1" && { [ -s "$3" ] || { python3 -I "$0" "$2" "$3.part.jpg" --stops "$4" && mv -f "$3.part.jpg" "$3"; }; }',
            root.helperPath, root.cacheRoot, job.original, job.target, Palette.stopsArgument(Palette.recolorStops(root.theme))];
        tintProcess.running = true;
    }
    property Process tintProcess: Process {
        property var job: null
        stdout: StdioCollector {}
        stderr: StdioCollector { id: tintErrors }
        onExited: function(code) {
            const job = tintProcess.job;
            tintProcess.job = null;
            if (job && code === 0 && root.wantedTints.indexOf(job.original) >= 0 && root.tintTarget(job.original) === job.target) {
                root.tinted = Object.assign({}, root.tinted, { [job.original]: job.target });
                root.tintError = '';
                root.pruneTint(job);
            } else if (job && code !== 0) {
                root.tintError = code === 127 ? 'ImageMagick (magick) is not installed.' : (tintErrors.text.trim() || 'Recoloring failed.');
            }
            Qt.callLater(root.nextTint);
        }
    }
    // Older copies of the same image (other palettes) are removed once the new one exists.
    property Process pruneProcess: Process {}
    function pruneTint(job) {
        if (pruneProcess.running) return;
        const prefix = job.target.split('/').pop().slice(0, 12);
        pruneProcess.command = ['find', cacheRoot, '-maxdepth', '1', '-type', 'f', '-name', prefix + '-*',
            '!', '-name', job.target.split('/').pop(), '-delete'];
        pruneProcess.running = true;
    }
}
