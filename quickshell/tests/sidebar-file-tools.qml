import QtQuick
import Quickshell
import Quickshell.Io
import qs.plugins
import qs.theme
import qs.services
import qs.features.sidebar

// Drives the file and text tools through the real sidebar, reader and file-tool helper.
// Inputs are staged copies of quickshell/tests/fixtures/file-tools inside the disposable config.
ShellRoot {
    id: root
    Component.onCompleted: Theme.resolve({ appearance: Quickshell.env('PENTAD_GALLERY_APPEARANCE') || 'dark',
        accent: Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677', fontFamily: 'Geist',
        reducedMotion: Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1' })
    function helper(name) { return decodeURIComponent(Qt.resolvedUrl('helpers/' + name).toString().replace(/^file:\/\//, '')); }
    function fixture(name) { return Qt.resolvedUrl('tests/fixtures/file-tools/' + name).toString(); }
    property var fakeServices: QtObject {
        readonly property bool preview: true
        readonly property bool safeMode: true
        readonly property var config: QtObject { readonly property var documents: ({ layout: { widgets: [] } }) }
        readonly property var plugins: root.registry
        readonly property ToolWorkspace toolWorkspace: ToolWorkspace {}
        readonly property FileInput fileInput: FileInput { helperPath: root.helper('pentad_read_input.py') }
        readonly property FileTools fileTools: FileTools { helperPath: root.helper('pentad_file_tool.py') }
    }
    property Plugins registry: Plugins { safeMode: true; services: root.fakeServices }
    readonly property var newTools: ['pdf', 'images', 'image-text', 'media', 'archive', 'checksum', 'translate',
        'codec', 'timestamp', 'color', 'text-case', 'yaml']
    readonly property var names: newTools.concat(['json', 'text-cleaner'])
    property var manifests: ({})
    property var checks: []
    property int stage: 0
    property int stageTicks: 0
    property int mountIndex: 0
    property bool captureBusy: false
    property bool finished: false
    property var loadErrors: []

    FloatingWindow {
        visible: true
        implicitWidth: 390
        implicitHeight: 760
        color: Theme.tokens.surface
        SidebarView { id: sidebar; services: root.fakeServices; outputId: 'fixture-output' }
    }
    Variants {
        model: root.names
        delegate: Component {
            FileView {
                required property var modelData
                path: Qt.resolvedUrl('widgets/' + modelData + '/manifest.json')
                printErrors: false
                onLoaded: root.manifests = Object.assign({}, root.manifests, { [modelData]: JSON.parse(text()) })
                onLoadFailed: function(error) { root.loadErrors = root.loadErrors.concat([modelData + ':' + error]); }
            }
        }
    }

    function check(name, passed, detail) {
        checks = checks.concat([{ name: name, passed: !!passed, detail: passed ? undefined : String(detail === undefined ? '' : detail) }]);
        return true;
    }
    function view() {
        const host = findNamed(sidebar, 'sidebar-active-tool');
        return host && host.moduleId === fakeServices.toolWorkspace.selectedTool ? host.view : null;
    }
    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        const children = item.children || [];
        for (let index = 0; index < children.length; index++) {
            const found = findNamed(children[index], name);
            if (found) return found;
        }
        return null;
    }
    function drop(uri, toolId) {
        const offer = { formats: ['text/uri-list'], accepted: false, getDataAsString: function() { return uri + '\n'; },
            accept: function() { this.accepted = true; } };
        sidebar.handleDrop(offer, toolId);
        return offer.accepted;
    }
    function capture(suffix) {
        captureBusy = true;
        sidebar.grabToImage(function(result) {
            root.check('capture' + (suffix || '.main'), result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + (suffix || '')));
            root.captureBusy = false;
        });
        return true;
    }
    function open(id) { fakeServices.toolWorkspace.selectTool('pentad.' + id); return true; }
    // A job step: returns false while the helper is still working.
    function settled(tool) { return tool && !tool.running && (tool.result || tool.message); }
    function outputName(tool) { return tool && tool.result && tool.result.outputs && tool.result.outputs[0] ? tool.result.outputs[0].name : ''; }

    readonly property var steps: [
        function() {
            if (Object.keys(root.manifests).length !== root.names.length) return false;
            for (const name of root.names) {
                const registered = root.registry.registerManifest(root.manifests[name], Qt.resolvedUrl('widgets/' + name + '/'), true);
                if (!registered.ok) root.check('manifest-register-' + name, false, registered.errors.join('; '));
            }
            return true;
        },
        function() {
            // Mount each new tool in turn; every view must load and expose acceptInput.
            const id = root.newTools[root.mountIndex];
            if (root.fakeServices.toolWorkspace.selectedTool !== 'pentad.' + id) return root.open(id) && false;
            const tool = root.view();
            if (!tool) return root.stageTicks > 60 ? root.check('mount-' + id, false, Qt.createComponent(Qt.resolvedUrl('widgets/' + id + '/View.qml')).errorString()) && root.nextMount() : false;
            if (typeof tool.acceptInput !== 'function') root.check('mount-' + id, false, 'acceptInput missing');
            return root.nextMount();
        },
        function() { root.check('all-new-tools-mount', root.checks.every(item => item.passed)); return root.open('pdf'); },
        function() { return !!root.view() && root.check('pdf-targeted-drop-accepted', root.drop(root.fixture('pages.pdf'), 'pentad.pdf')); },
        function() {
            const tool = root.view();
            if (!tool || tool.files.length !== 1) return root.stageTicks > 100 ? root.check('pdf-file-delivered', false, sidebar.ingressError) : false;
            const ids = tool.actions.map(action => action.id);
            root.check('pdf-actions-fit-one-file', ids.indexOf('pdf.extract') >= 0 && ids.indexOf('pdf.merge') < 0, ids.join(','));
            tool.selectAction('pdf.extract');
            root.check('pdf-extract-needs-pages', !tool.check.ok);
            tool.setOption('pages', '1,3');
            tool.start();
            return true;
        },
        function() {
            const tool = root.view();
            if (!root.settled(tool)) return false;
            root.check('pdf-extract-publishes-new-file', root.outputName(tool) === 'pages-pages.pdf' && tool.result.outputs[0].sizeBytes > 0, tool.message || root.outputName(tool));
            return root.capture('');
        },
        function() { return root.open('images'); },
        function() { return !!root.view() && root.open('pdf'); },
        function() {
            const tool = root.view();
            if (!tool) return false;
            root.check('pdf-state-survives-switching', tool.files.length === 1 && root.outputName(tool) === 'pages-pages.pdf');
            tool.selectAction('pdf.lock');
            root.check('pdf-lock-needs-password', !tool.check.ok);
            tool.setOption('password', 'two words');
            tool.start();
            return true;
        },
        function() {
            const tool = root.view();
            if (!root.settled(tool)) return false;
            const locked = tool.result && tool.result.outputs ? tool.result.outputs[0] : null;
            root.check('pdf-lock-publishes-protected-copy', root.outputName(tool) === 'pages-protected.pdf', tool.message);
            if (!locked) return true;
            tool.acceptInput([Object.assign({ compatibleTypes: ['application/pdf'] }, locked)], 'replace');
            tool.selectAction('pdf.unlock');
            root.check('pdf-password-is-not-kept-between-actions', !tool.options.password);
            tool.setOption('password', 'wrong');
            tool.start();
            return true;
        },
        function() {
            const tool = root.view();
            if (!root.settled(tool)) return false;
            root.check('pdf-wrong-password-is-reported', tool.message === 'Wrong password', tool.message);
            return root.check('pdf-rejects-image-drop-start', root.drop(root.fixture('photo.png'), 'pentad.pdf'));
        },
        function() {
            if (sidebar.fileReadRequestId) return false;
            const tool = root.view();
            root.check('pdf-rejects-incompatible-file', !!sidebar.ingressError && tool && tool.files.length === 1 && tool.files[0].name === 'pages-protected.pdf', sidebar.ingressError);
            root.fakeServices.toolWorkspace.clearIngress();
            sidebar.ingressError = '';
            return root.open('images');
        },
        function() { return !!root.view() && root.drop(root.fixture('photo.png'), 'pentad.images'); },
        function() {
            const tool = root.view();
            if (!tool || tool.files.length !== 1) return root.stageTicks > 100 ? root.check('image-file-delivered', false, sidebar.ingressError) : false;
            tool.selectAction('image.convert');
            tool.setOption('format', 'webp');
            tool.start();
            return true;
        },
        function() {
            const tool = root.view();
            if (!root.settled(tool)) return false;
            root.check('image-convert-publishes-webp', root.outputName(tool) === 'photo.webp', tool.message);
            root.check('image-result-can-be-handed-off', tool.handoffTargets.indexOf('pentad.checksum') >= 0, tool.handoffTargets.join(','));
            return root.capture('.images.png');
        },
        function() { return root.open('image-text'); },
        function() { return !!root.view() && root.drop(root.fixture('qr.png'), 'pentad.image-text'); },
        function() {
            const tool = root.view();
            if (!tool || tool.files.length !== 1) return root.stageTicks > 100 ? root.check('qr-file-delivered', false, sidebar.ingressError) : false;
            tool.selectAction('image.barcode');
            tool.start();
            return true;
        },
        function() {
            const tool = root.view();
            if (!root.settled(tool)) return false;
            root.check('qr-image-is-read', tool.result && tool.result.text === 'pentad fixture', tool.message || (tool.result && tool.result.text));
            return root.capture('.image-text.png');
        },
        function() { return root.open('archive'); },
        function() { return !!root.view() && root.drop(root.fixture('sample.zip'), 'pentad.archive'); },
        function() {
            const tool = root.view();
            if (!tool || tool.files.length !== 1) return root.stageTicks > 100 ? root.check('zip-file-delivered', false, sidebar.ingressError) : false;
            root.check('archive-defaults-to-extract', tool.actionId === 'archive.extract', tool.actionId);
            tool.start();
            return true;
        },
        function() {
            const tool = root.view();
            if (!root.settled(tool)) return false;
            const output = tool.result && tool.result.outputs ? tool.result.outputs[0] : null;
            return root.check('zip-extracts-to-new-folder', output && output.kind === 'folder' && output.name === 'sample', tool.message || JSON.stringify(output));
        },
        function() { return root.open('checksum'); },
        function() { return !!root.view() && root.drop(root.fixture('photo.png'), 'pentad.checksum'); },
        function() {
            const tool = root.view();
            if (!tool || tool.files.length !== 1) return root.stageTicks > 100 ? root.check('checksum-file-delivered', false, sidebar.ingressError) : false;
            tool.setOption('expected', 'deadbeef');
            tool.start();
            return true;
        },
        function() {
            const tool = root.view();
            if (!root.settled(tool)) return false;
            root.check('checksum-hashes-and-compares', tool.result && tool.result.match === false
                && tool.result.text === '279634751fb38a980a842e2f17a28a90a48e259cdfd511ee82047a418955b4b0  photo.png', tool.message || (tool.result && tool.result.text));
            return root.capture('.checksum.png');
        },
        function() { return root.open('codec'); },
        function() {
            const tool = root.view();
            if (!tool) return false;
            tool.acceptInput([{ kind: 'text', mimeType: 'text/plain', value: 'Grüße 😀' }], 'replace');
            tool.mode = 'base64';
            tool.run(false);
            root.check('codec-encodes-utf8-base64', tool.result === 'R3LDvMOfZSDwn5iA', tool.result || tool.message);
            return root.open('text-case');
        },
        function() {
            const tool = root.view();
            if (!tool) return false;
            tool.acceptInput([{ kind: 'text', mimeType: 'text/plain', value: 'Привіт, Pentad tools' }], 'replace');
            tool.convert('slug');
            root.check('text-case-slugs-ukrainian', tool.result === 'pryvit-pentad-tools', tool.result || tool.message);
            return root.capture('.text-tools.png');
        },
        function() { return root.open('color'); },
        function() {
            const tool = root.view();
            if (!tool) return false;
            tool.acceptInput([{ kind: 'color', mimeType: 'text/x-color', value: '#ff0000' }], 'replace');
            tool.convert();
            root.check('color-converts-hex', tool.formats && /oklch/.test(tool.formats.oklch), tool.message);
            return root.open('timestamp');
        },
        function() {
            const tool = root.view();
            if (!tool) return false;
            tool.acceptInput([{ kind: 'text', mimeType: 'text/plain', value: '1700000000' }], 'replace');
            tool.convert();
            root.check('timestamp-converts-epoch', tool.rows.some(row => /2023-11-14T22:13:20/.test(row.value)), JSON.stringify(tool.rows));
            return root.open('yaml');
        },
        function() {
            const tool = root.view();
            if (!tool) return false;
            tool.acceptInput([{ kind: 'text', mimeType: 'text/plain', value: 'a: 1\n' }], 'replace');
            tool.convert(true);
            return true;
        },
        function() {
            const tool = root.view();
            if (!tool || tool.running) return false;
            root.check('yaml-converts-to-json', /"a":\s*1/.test(tool.result), tool.result || tool.message);
            return root.finish();
        },
    ]
    function nextMount() {
        mountIndex++;
        stageTicks = 0;
        return mountIndex >= newTools.length;
    }
    function finish() {
        if (finished) return true;
        finished = true;
        console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.length && checks.every(item => item.passed) ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
        return true;
    }
    Timer {
        interval: 50; repeat: true; running: !root.finished
        property int ticks: 0
        onTriggered: {
            if (root.captureBusy) return;
            if (++ticks > 480) {
                root.check('sidebar-file-tools-timeout', false, 'stuck at step ' + root.stage + ' manifests '
                    + Object.keys(root.manifests).join(',') + ' step type ' + typeof root.steps[root.stage] + ' errors ' + root.loadErrors.join(' | '));
                root.finish();
                return;
            }
            root.stageTicks++;
            if (root.steps[root.stage]()) { root.stage++; root.stageTicks = 0; }
            if (root.stage >= root.steps.length) root.finish();
        }
    }
}
