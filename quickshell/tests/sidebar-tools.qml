import QtQuick
import Quickshell
import Quickshell.Io
import qs.plugins
import qs.theme
import qs.services
import qs.features.sidebar
import "../logic/tool-catalog.mjs" as ToolLogic

ShellRoot {
    id: root
    Component.onCompleted: Theme.resolve({ appearance: Quickshell.env('PENTAD_GALLERY_APPEARANCE') || 'dark',
        accent: Quickshell.env('PENTAD_GALLERY_ACCENT') || '#869677', fontFamily: 'Geist',
        reducedMotion: Quickshell.env('PENTAD_GALLERY_REDUCED_MOTION') === '1' })
    property int step: 0
    property bool finished: false
    property var fakeServices: QtObject {
        readonly property bool preview: true
        readonly property bool safeMode: true
        readonly property var config: root.fakeConfig
        readonly property var plugins: root.registry
        readonly property ToolWorkspace toolWorkspace: ToolWorkspace {}
        readonly property FileInput fileInput: FileInput {
            helperPath: decodeURIComponent(Qt.resolvedUrl('helpers/pentad_read_input.py').toString().replace(/^file:\/\//, ''))
        }
    }
    property QtObject fakeConfig: QtObject {
        property int serial: 0
        property bool showWidgets: true
        readonly property var documents: ({ layout: { widgets: showWidgets ? [
            { instanceId: 'compact-fixture', moduleId: 'pentad.units', slot: 'sidebar-left', enabled: true, settings: {} },
        ] : [] } })
    }
    property Plugins registry: Plugins { safeMode: true; services: root.fakeServices }
    property var names: ['units', 'text-cleaner', 'json', 'qr', 'chat']
    property var manifests: ({})
    property bool testDraftSurvived: false
    property bool testUnsupportedReported: false
    property string testUnsupportedMessage: ''
    property bool testHandoffChooser: false
    property bool handoffValidated: false
    property bool qrProbeStarted: false
    property bool qrInputReady: false
    property bool qrFirstRunStarted: false
    property bool qrFirstRunComplete: false
    property bool qrSecondRunStarted: false
    property bool qrCancelStarted: false
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
    function fakeDrop(mime, value) {
        return { formats: [mime], accepted: false, getDataAsString: function() { return value; },
            accept: function() { this.accepted = true; } };
    }
    FloatingWindow {
        visible: true
        implicitWidth: 390
        implicitHeight: 760
        color: Theme.tokens.surface
        SidebarView { id: sidebar; services: root.fakeServices; outputId: 'fixture-output' }
    }
    Repeater {
        model: root.names
        delegate: FileView {
            required property string modelData
            path: Qt.resolvedUrl('widgets/' + modelData + '/manifest.json')
            printErrors: false
            onLoaded: root.manifests = Object.assign({}, root.manifests, { [modelData]: JSON.parse(text()) })
        }
    }
    Timer {
        interval: 40; repeat: true; running: !root.validatingCatalog
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                if (Object.keys(root.manifests).length !== root.names.length) return;
                for (const name of root.names) {
                    const manifest = root.manifests[name];
                    const registered = root.registry.registerManifest(manifest, Qt.resolvedUrl('widgets/' + name + '/'), true);
                    if (!registered.ok) { root.finish(false, [{ name: 'manifest-register-' + name, passed: false, detail: registered.errors.join('; ') }]); return; }
                }
            }
            if (root.step === 4) {
                // The list is virtualized and the bundled registry now holds more tools than fit,
                // so later rows are checked through the catalog model rather than delegates.
                const catalogVisible = root.findNamed(sidebar, 'sidebar-tool-pentad.json')
                    && sidebar.visibleTools.some(entry => entry.manifest.id === 'pentad.text-cleaner')
                    && root.findNamed(sidebar, 'sidebar-widget-compact-fixture');
                root.fakeServices.toolWorkspace.selectTool('pentad.json');
                if (!catalogVisible) { root.finish(false, [{ name: 'tool-catalog-and-compact-widget-visible', passed: false, detail: 'Catalog tool or retained widget missing' }]); return; }
            }
            if (root.step === 8) {
                const host = root.findNamed(sidebar, 'sidebar-active-tool');
                if (!host || !host.view) return;
                const drop = root.fakeDrop('text/plain;charset=utf-8', '{"ok":true}');
                sidebar.handleDrop(drop, 'pentad.json');
                if (root.fakeServices.toolWorkspace.pendingInput) sidebar.applyIncoming('replace');
                const source = root.findNamed(host.view, 'json-tool-source');
                if (!drop.accepted || !source || source.text !== '{"ok":true}') {
                    root.finish(false, [{ name: 'targeted-drop-delivers-compatible-data', passed: false, detail: JSON.stringify({ accepted: drop.accepted, text: source ? source.text : null }) }]);
                    return;
                }
                source.text = '{ "preserved": true }';
                root.fakeServices.toolWorkspace.selectTool('pentad.text-cleaner');
            }
            if (root.step === 12) {
                const cleaner = root.findNamed(sidebar, 'sidebar-active-tool');
                if (!cleaner || !cleaner.view) return;
                const unsupported = root.fakeDrop('image/png', 'opaque bytes');
                sidebar.handleDrop(unsupported, 'pentad.text-cleaner');
                root.fakeServices.toolWorkspace.selectTool('pentad.json');
            }
            if (root.step === 16) {
                const host = root.findNamed(sidebar, 'sidebar-active-tool');
                const source = host && host.view ? root.findNamed(host.view, 'json-tool-source') : null;
                const draftSurvived = source && source.text === '{ "preserved": true }';
                const unsupportedReported = !!sidebar.ingressError;
                const selectedBefore = root.fakeServices.toolWorkspace.selectedTool;
                const incompatible = root.fakeDrop('text/uri-list', 'https://example.test/a\nhttps://example.test/b');
                sidebar.handleDrop(incompatible, '');
                if (incompatible.accepted || root.fakeServices.toolWorkspace.selectedTool !== selectedBefore
                        || source.text !== '{ "preserved": true }') {
                    root.finish(false, [{ name: 'unsupported-general-drop-preserves-selection-and-draft', passed: false }]);
                    return;
                }
                const sampleUri = Qt.resolvedUrl('tests/fixtures/tool-sample.json').toString();
                const general = root.fakeDrop('text/uri-list', sampleUri + '\n');
                root.fakeServices.toolWorkspace.selectTool('');
                sidebar.handleDrop(general, '');
                if (!general.accepted || !sidebar.fileReadRequestId) return;
                root.testDraftSurvived = !!draftSurvived;
                root.testUnsupportedReported = unsupportedReported;
                root.testUnsupportedMessage = sidebar.ingressError;
            }
            if (root.step >= 20 && root.fakeServices.toolWorkspace.pendingInput && !root.testHandoffChooser) {
                root.fakeServices.toolWorkspace.selectTool('pentad.json', true);
                if (root.fakeServices.toolWorkspace.pendingInput) sidebar.applyIncoming('replace');
            }
            if (root.step === 24) {
                const host = root.findNamed(sidebar, 'sidebar-active-tool');
                const source = host && host.view ? root.findNamed(host.view, 'json-tool-source') : null;
                const fileDelivered = source && source.text === '{"fromFile":true}\n';
                const generalChooser = root.fakeServices.toolWorkspace.selectedTool === 'pentad.json';
                if (!fileDelivered || !generalChooser) {
                    root.finish(false, [{ name: 'general-file-drop-finds-compatible-reader-and-delivers-data', passed: false,
                        detail: source ? source.text : 'JSON view missing' }]);
                    return;
                }
                const result = { kind: 'text', mimeType: 'text/plain', value: 'handed off', compatibleTypes: ['text/plain'] };
                const compatible = ToolLogic.compatibleTools(ToolLogic.toolEntries(root.registry.catalog), [result])
                    .map(entry => entry.manifest.id);
                root.fakeServices.toolWorkspace.receive([result], compatible, '');
                root.testHandoffChooser = root.fakeServices.toolWorkspace.selectedTool === ''
                    && compatible.indexOf('pentad.text-cleaner') >= 0
                    && sidebar.visibleTools.some(entry => entry.manifest.id === 'pentad.text-cleaner');
                root.fakeServices.toolWorkspace.selectTool('pentad.text-cleaner', true);
            }
            if (root.step >= 28) {
                if (!root.handoffValidated) {
                    const host = root.findNamed(sidebar, 'sidebar-active-tool');
                    const source = host && host.view ? root.findNamed(host.view, 'text-cleaner-source') : null;
                    if (source && root.testHandoffChooser && root.testDraftSurvived && root.testUnsupportedReported) {
                        if (source.text !== 'handed off') {
                            root.finish(false, [{ name: 'result-handoff-opens-compatible-chooser-and-delivers', passed: false, detail: source.text }]);
                            return;
                        }
                        root.handoffValidated = true;
                        root.qrProbeStarted = true;
                        root.fakeServices.toolWorkspace.selectTool('pentad.qr');
                    }
                }
                if (root.qrProbeStarted && !root.finished) {
                    const qrHost = root.findNamed(sidebar, 'sidebar-active-tool');
                    const qr = qrHost && qrHost.view;
                    if (qr && typeof qr.generate === 'function') {
                        if (!root.qrInputReady) {
                            root.qrInputReady = qr.acceptInput([{ kind: 'text', mimeType: 'text/plain', value: 'QML runtime probe', compatibleTypes: ['text/plain'] }], '');
                        }
                        if (root.qrInputReady && !root.qrFirstRunStarted) {
                            root.qrFirstRunStarted = true;
                            qr.generate();
                        } else if (root.qrFirstRunStarted && !root.qrFirstRunComplete && qr.svg) {
                            root.qrFirstRunComplete = true;
                            root.qrSecondRunStarted = true;
                            qr.generate();
                        } else if (root.qrCancelStarted && qr.message === 'Generation cancelled.') {
                            root.finish(true, [
                                { name: 'tool-draft-survives-switching', passed: root.testDraftSurvived },
                                { name: 'incompatible-targeted-drop-explains-error', passed: root.testUnsupportedReported, detail: root.testUnsupportedMessage },
                                { name: 'general-file-drop-finds-compatible-reader-and-delivers-data', passed: true },
                                { name: 'result-handoff-opens-compatible-chooser-and-delivers', passed: root.handoffValidated },
                                { name: 'qr-process-generates-valid-svg-twice-and-cancels-cleanly', passed: true },
                            ]);
                        } else if (root.qrSecondRunStarted && qr.svg && !root.qrCancelStarted) {
                            root.qrCancelStarted = true;
                            qr.generate();
                            qr.cancel();
                        }
                    }
                }
            }
            if (root.step > 100 && !root.finished)
                root.finish(false, [{ name: 'sidebar-tools-timeout', passed: false, detail: 'Tool workspace did not mount' }]);
        }
    }
    property bool validatingCatalog: false
    property int catalogStep: 0
    property var catalogChecks: []
    property bool captureBusy: false
    property real savedCatalogY: 0
    property real savedSearchY: 0
    function checkCatalog(name, passed) {
        catalogChecks = catalogChecks.concat([{ name: name, passed: !!passed }]);
    }
    function captureCatalog(suffix) {
        captureBusy = true;
        sidebar.grabToImage(function(result) {
            root.checkCatalog('catalog-capture' + suffix, result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + suffix));
            root.captureBusy = false;
        });
    }
    Timer {
        interval: 100; repeat: true; running: root.validatingCatalog && !root.finished
        onTriggered: {
            if (root.captureBusy) return;
            const catalog = root.findNamed(sidebar, 'sidebar-catalog');
            const state = root.fakeServices.toolWorkspace;
            switch (root.catalogStep++) {
            case 0:
                root.fakeConfig.showWidgets = false;
                state.clearIngress();
                sidebar.showCatalog();
                catalog.resetFilters();
                break;
            case 1:
                root.savedSearchY = catalog.searchField.y;
                const fileImport = root.findNamed(sidebar, 'sidebar-choose-files');
                root.checkCatalog('search-import-and-rows-are-borderless', catalog.searchField.background.edge.a === 0
                    && fileImport.background.edge.a === 0 && root.findNamed(sidebar, 'sidebar-row-surface').edge.a === 0);
                root.captureCatalog('');
                break;
            case 2: {
                const favorite = root.findNamed(sidebar, 'sidebar-favorite-pentad.json');
                if (favorite) favorite.click();
                root.checkCatalog('favorite-is-independent-of-launch', favorite && !state.selectedTool && state.favorites.indexOf('pentad.json') >= 0);
                state.catalogCategory = 'Data';
                state.searchQuery = 'validate';
                break;
            }
            case 3:
                root.checkCatalog('category-and-keyword-filter-intersect', catalog.listView.count === 1 && sidebar.visibleTools[0].manifest.id === 'pentad.json');
                catalog.moveSelection(1);
                catalog.openCurrent();
                break;
            case 4:
                root.checkCatalog('keyboard-selection-opens-result', state.selectedTool === 'pentad.json');
                root.checkCatalog('catalog-open-preserves-draft', state.draftFor('pentad.json') !== '');
                root.findNamed(sidebar, 'sidebar-back-to-tools').click();
                break;
            case 5:
                root.checkCatalog('back-preserves-query-and-category', !state.selectedTool && state.searchQuery === 'validate' && state.catalogCategory === 'Data');
                state.searchQuery = 'no-such-tool';
                break;
            case 6:
                root.checkCatalog('empty-results-can-reset', catalog.listView.count === 0);
                root.captureCatalog('.empty.png');
                break;
            case 7: {
                catalog.resetFilters();
                const expanded = Object.assign({}, root.registry.catalog);
                for (let i = 0; i < 300; i++) {
                    const manifest = Object.assign({}, root.registry.catalog['pentad.json'].manifest, { id: 'fixture.tool-' + i,
                        name: 'Інструмент ' + String(i).padStart(3, '0') + ' — перевірка довгих українських назв' });
                    expanded[manifest.id] = { manifest: manifest, builtin: true };
                }
                root.registry.catalog = expanded;
                root.registry.revision++;
                break;
            }
            case 8:
                root.checkCatalog('large-catalog-is-virtualized', catalog.listView.count >= 300 && catalog.listView.contentItem.children.length < 40);
                catalog.listView.positionViewAtIndex(250, ListView.Beginning);
                break;
            case 9:
                root.checkCatalog('search-stays-fixed-while-results-scroll', catalog.searchField.y === root.savedSearchY && catalog.listView.contentY > 500);
                root.captureCatalog('.large.png');
                root.savedCatalogY = catalog.listView.contentY;
                break;
            case 10:
                catalog.openTool('pentad.json');
                break;
            case 11:
                sidebar.showCatalog();
                break;
            case 12:
                root.checkCatalog('back-restores-large-catalog-scroll', Math.abs(catalog.listView.contentY - root.savedCatalogY) < 70);
                state.catalogView = 'favorites';
                break;
            case 13:
                root.checkCatalog('favorites-view-filters-catalog', catalog.listView.count === 1 && sidebar.visibleTools[0].manifest.id === 'pentad.json');
                state.catalogView = 'recent';
                break;
            case 14:
                root.checkCatalog('recent-view-uses-usage-order', sidebar.visibleTools[0].manifest.id === 'pentad.json' && catalog.listView.count < 9);
                break;
            case 15:
                root.fakeServices.toolWorkspace.catalogView = 'all';
                sidebar.fileReadRequestId = 'busy-fixture';
                break;
            case 16:
                root.checkCatalog('pending-file-import-keeps-label-and-size', root.findNamed(sidebar, 'sidebar-import-label').text === 'Choose files'
                    && !root.findNamed(sidebar, 'sidebar-choose-files').enabled
                    && root.findNamed(sidebar, 'sidebar-choose-files').height === 56);
                sidebar.fileReadRequestId = '';
                break;
            case 17:
                root.findNamed(sidebar, 'sidebar-category-selector').choicePopover.grabFocus = false;
                root.findNamed(sidebar, 'sidebar-category-selector').click();
                break;
            case 18: {
                const selector = root.findNamed(sidebar, 'sidebar-category-selector');
                const popover = selector.choicePopover;
                root.checkCatalog('selector-viewport-fits-visible-choices', popover.contentItem.height >= popover.contentItem.implicitHeight);
                root.checkCatalog('selector-shares-attached-popover-fill', popover.opened && selector.background.fill === popover.fill);
                root.captureBusy = true;
                popover.surface.grabToImage(function(result) {
                    root.checkCatalog('catalog-selector-capture', result.saveToFile(Quickshell.env('PENTAD_ARTIFACT_PATH') + '.choices.png'));
                    root.captureBusy = false;
                });
                break;
            }
            case 19: {
                const popover = root.findNamed(sidebar, 'sidebar-category-selector').choicePopover;
                const dataChoice = root.findNamed(popover.contentItem, 'sidebar-choice-Data');
                if (dataChoice) dataChoice.click();
                root.checkCatalog('attached-selector-chooses-and-closes', dataChoice && state.catalogCategory === 'Data' && !popover.opened);
                break;
            }
            default:
                root.finished = true;
                console.log('PENTAD_TEST ' + JSON.stringify({ status: root.catalogChecks.every(check => check.passed) ? 'pass' : 'fail', checks: root.catalogChecks }));
                Qt.quit();
            }
        }
    }
    function finish(passed, checks) {
        if (finished) return;
        if (passed && !validatingCatalog) {
            catalogChecks = checks;
            validatingCatalog = true;
            return;
        }
        finished = true;
        console.log('PENTAD_TEST ' + JSON.stringify({ status: passed ? 'pass' : 'fail', checks: checks }));
        Qt.quit();
    }
}
