#include <QCoreApplication>
#include <QDir>
#include <QJSEngine>
#include <QJSValue>
#include <QTextStream>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QJSEngine engine;
    const QDir root(argc > 1 ? QString::fromLocal8Bit(argv[1]) : QDir::currentPath());
    const char *modules[] = {"screenshot", "screenshot-settings", "screenshot-windows", "config", "screenshot-toolbar"};
    const char *names[] = {"Model", "Settings", "Windows", "Config", "Toolbar"};
    for (int i = 0; i < 5; ++i) {
        const QString path = root.filePath(QStringLiteral("quickshell/logic/") + modules[i] + ".mjs");
        const QJSValue module = engine.importModule(path);
        if (module.isError()) {
            QTextStream(stderr) << path << ':' << module.property("lineNumber").toInt()
                                << ' ' << module.toString() << '\n';
            return 1;
        }
        engine.globalObject().setProperty(names[i], module);
    }
    const auto result = engine.evaluate(QStringLiteral(R"JS(
        function check(ok, message) { if (!ok) throw new Error(message); }
        let doc = Model.createDocument(100, 80);
        doc = Model.setCrop(doc, {x:2.5,y:1.2,width:10.1,height:8.5});
        doc = Model.addAnnotation(doc, {id:'arrow',type:'arrow',x:70,y:20,width:-40,height:0});
        doc = Model.updateAnnotation(doc,'arrow',{color:'#00ff00'});
        check(Model.undo(doc).annotations[0].color === '#ff0000', 'undo');
        check(Model.redo(Model.undo(doc)).annotations[0].color === '#00ff00', 'redo');
        check(Model.hitTest(doc,{x:50,y:20}) === 'arrow', 'directed arrow hit');
        const exported = Model.exportDocument(doc);
        check(exported.crop.x === 2 && exported.crop.width === 11, 'fractional crop');
        exported.annotations[0].points.push({x:1,y:1});
        check(doc.annotations[0].points.length === 0, 'export isolation');
        check(Model.deleteAnnotation(doc,'arrow').annotations.length === 0, 'delete');
        const settings = Settings.parseScreenshotSettings({localKeys:{brush:'ctrl+shift+b'}});
        check(settings.localKeys.brush === 'Ctrl+Shift+B', 'normalize shortcut');
        check(Settings.matchesScreenshotShortcut(66,0x06000000,settings.localKeys.brush), 'match shortcut');
        check(Settings.hyprlandScreenshotBindings(settings).includes('pentad:screenshot-edit'), 'bindings');
        check(Config.parseDocument('screenshots','{}').ok, 'config import');
        const snapshot = {desktop:{outputs:[{id:'1',name:'DP-1',x:0,y:0,width:100,height:80,activeWorkspaceId:'1'}]},
          clients:[{address:'0xa',workspaceId:'1',x:10,y:10,width:30,height:20,mapped:true}],activeAddress:'0xa'};
        check(Windows.activeWindowCrop(snapshot,'DP-1',150,120).width === 45, 'window projection');
        const dock = Toolbar.dockFromPointer({x:100,y:100,width:200,height:100},{x:150,y:260},300,10);
        const placed = Toolbar.dockGeometry({x:100,y:100,width:200,height:100},{width:800,height:600},300,40,dock);
        check(dock.edge === 'bottom' && !dock.inside && placed.horizontal && placed.x + 10 === 150, 'toolbar dock');
        'Qt screenshot modules: passed';
    )JS"));
    QTextStream(result.isError() ? stderr : stdout) << result.toString() << '\n';
    return result.isError() ? 1 : 0;
}
