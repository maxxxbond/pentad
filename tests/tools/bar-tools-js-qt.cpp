#include <QCoreApplication>
#include <QDir>
#include <QJSEngine>
#include <QTextStream>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) return 2;
    QJSEngine engine;
    const QDir repo{QString::fromLocal8Bit(argv[1])};
    const char *modules[][2] = {{"Tools", "quickshell/logic/bar-tools.mjs"}, {"Config", "quickshell/logic/config.mjs"},
        {"Catalog", "quickshell/logic/settings-catalog.mjs"}};
    for (const auto &entry : modules) {
        const auto module = engine.importModule(repo.filePath(QString::fromLatin1(entry[1])));
        if (module.isError()) { QTextStream(stderr) << entry[1] << ": " << module.toString(); return 1; }
        engine.globalObject().setProperty(QString::fromLatin1(entry[0]), module);
    }
    const auto result = engine.evaluate(QStringLiteral(R"JS(
        function check(ok, message) { if (!ok) throw new Error(message); }
        const shown = Tools.visibleTools(undefined);
        check(shown.toggles.length === 2 && shown.actions.length === 6, 'default tools');
        check(Tools.parseBarTools(undefined).search.mode === 'ask', 'default search mode');
        let threw = false;
        try { Tools.parseBarTools({ show: { nope: true } }); } catch (error) { threw = true; }
        check(threw, 'unknown tool rejected');
        check(Tools.searchPlan({ search: { mode: 'direct', engine: 'bing' } }).engine.id === 'bing', 'direct plan');
        check(Tools.searchPlan(undefined).kind === 'ask', 'ask plan');
        check(Tools.enabledEngines(undefined).length === Tools.searchEngines.length, 'engines');
        check(Tools.inhibitCommand(1800)[6] === '1800' && Tools.inhibitCommand(0)[6] === 'infinity', 'inhibit command');
        check(Tools.pickerCommand('rgb')[3] === 'rgb', 'picker command');
        check(Tools.ocrScript('eng+ukr').indexOf('tesseract') > 0, 'ocr script');
        check(Tools.translateScript({ target: 'UK', languages: 'eng', provider: 'deepl' }).indexOf('DeepL-Auth-Key') > 0, 'deepl script');
        check(Tools.durationLabel(1800, function(uk, en) { return en; }) === '30 min', 'duration label');
        check(Tools.expandHome('~/a', '/home/x') === '/home/x/a', 'home expansion');
        const layout = Config.parseDocument('layout', JSON.stringify(Config.defaults.layout));
        check(layout.ok && layout.value.barTools.show.ocr === true, 'layout document with bar tools');
        check(!Config.parseDocument('layout', JSON.stringify(Object.assign({}, Config.defaults.layout, { barTools: { show: { x: true } } }))).ok, 'bad bar tools rejected');
        check(Catalog.pages.some(function(page) { return page.id === 'bar' && page.tabs.some(function(tab) { return tab.id === 'tools'; }) && page.sections.some(function(section) { return section.tab === 'tools'; }); }), 'settings page');
        'Qt bar tools: passed';
    )JS"));
    QTextStream(result.isError() ? stderr : stdout) << result.toString() << '\n';
    return result.isError() ? 1 : 0;
}
