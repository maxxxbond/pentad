#include <QCoreApplication>
#include <QDir>
#include <QJSEngine>
#include <QTextStream>
#include "scriptmodel.hpp"

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) return 2;
    QJSEngine engine;
    const auto module = engine.importModule(QDir(QString::fromLocal8Bit(argv[1])).filePath("quickshell/logic/overview-presentation.mjs"));
    if (module.isError()) { QTextStream(stderr) << module.toString(); return 6; }
    engine.globalObject().setProperty("Presentation", module);
    ScriptModel model;
    auto values = [&](const QString &source) {
        const auto array = engine.evaluate("Presentation.overviewWindowIds(" + source + ")");
        QList<QJSValue> result;
        for (int i=0; i<array.property("length").toInt(); ++i) result.append(array.property(i));
        return result;
    };
    model.setValues(values("[{instanceId:'one',address:'0x1',x:0},{instanceId:'two',address:'0x2',x:10}]"));
    int removed=0, inserted=0, resets=0, updated=0;
    QObject::connect(&model, &QAbstractItemModel::rowsRemoved, [&] { ++removed; });
    QObject::connect(&model, &QAbstractItemModel::rowsInserted, [&] { ++inserted; });
    QObject::connect(&model, &QAbstractItemModel::modelReset, [&] { ++resets; });
    QObject::connect(&model, &QAbstractItemModel::dataChanged, [&] { ++updated; });
    model.setValues(values("[{instanceId:'one',address:'0x1',x:500},{instanceId:'two',address:'0x2',x:20}]"));
    if (removed || inserted || resets || updated) return 3;
    model.setValues(values("[{instanceId:'two',address:'0x2',x:20},{instanceId:'one',address:'0x1',x:500}]"));
    if (removed || inserted || resets) return 4;
    model.setValues(values("[{instanceId:'two',address:'0x2',x:20},{instanceId:'new-lifetime',address:'0x1',x:500}]"));
    if (removed != 1 || inserted != 1 || resets) {
        QTextStream(stderr) << "Lifetime replacement: removed=" << removed << " inserted=" << inserted << " resets=" << resets << '\n';
        return 5;
    }
    const auto result = engine.evaluate(QStringLiteral(R"JS(
        function check(ok,message) { if(!ok) throw new Error(message); }
        check(Presentation.workspaceGame({},[{appClass:'steam_app_730',title:'CS2'}]).title === 'CS2','game title');
        check(Presentation.workspaceGame({},[{appClass:'firefox',fullscreen:true}]) === null,'non-game fullscreen');
        check(JSON.stringify(Presentation.retainCaptureIds(['new'],['old'],['new','old'])) === '["new","old"]','retained still');
        'Qt overview identity and capture policy: passed';
    )JS"));
    QTextStream(result.isError() ? stderr : stdout) << result.toString() << '\n';
    return result.isError() ? 7 : 0;
}
