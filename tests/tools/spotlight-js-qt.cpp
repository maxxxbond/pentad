#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJSEngine>
#include <QTextStream>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc != 3) return 2;
    QJSEngine engine;
    const auto module = engine.importModule(QDir(QString::fromLocal8Bit(argv[1]))
        .filePath("quickshell/logic/spotlight-providers.mjs"));
    if (module.isError()) { QTextStream(stderr) << module.toString(); return 1; }
    QFile fixture(QString::fromLocal8Bit(argv[2]));
    if (!fixture.open(QIODevice::ReadOnly)) return 2;
    engine.globalObject().setProperty("Search", module);
    const auto dispatch = engine.importModule(QDir(QString::fromLocal8Bit(argv[1]))
        .filePath("quickshell/logic/spotlight-dispatch.mjs"));
    if (dispatch.isError()) { QTextStream(stderr) << dispatch.toString(); return 1; }
    engine.globalObject().setProperty("Dispatch", dispatch);
    engine.globalObject().setProperty("fixture", QString::fromUtf8(fixture.readAll()));
    const auto result = engine.evaluate(QStringLiteral(R"JS(
        function check(ok, message) { if (!ok) throw new Error(message); }
        const records = JSON.parse(fixture);
        const options = {locales:['en_US.UTF-8'], layouts:['de,ua'], displayLocale:'uk'};
        check(Dispatch.moveGridSelection(8,12,5,'down') === 11, 'partial emoji row');
        check(Dispatch.moveGridSelection(11,12,5,'down') === 11, 'grid end');
        check(Dispatch.moveGridSelection(11,12,5,'up') === 6, 'grid column');
        check(Search.resolveEmojiLanguages(options).includes('uk'), 'Ukrainian keyboard language');
        check(Search.searchEmojiRecords(':по', records, options).length > 0, 'screenshot query :по');
        const fire = Search.searchEmojiRecords(':вогонь', records, options)[0];
        check(fire.preview.content === '🔥', 'Ukrainian name');
        check(fire.id === 'emoji-1F525', 'Qt and Node must use the same Unicode identity');
        check(fire.preview.metadata.CodePoint === 'U+1F525', 'Unicode details');
        check(Search.searchEmojiRecords(':fire', records, options).length > 0, 'English fallback');
        check(Search.searchEmojiRecords(':feuer', records, options).length > 0, 'German layout');
        check(Search.searchEmojiRecords(':по', {}, options).length === 0, 'empty data');
        check(Search.searchEmojiRecords(':по', records, options, {aborted:true}).length === 0, 'cancel');
        'Qt Spotlight emoji: passed';
    )JS"));
    QTextStream(result.isError() ? stderr : stdout) << result.toString() << '\n';
    return result.isError() ? 1 : 0;
}
