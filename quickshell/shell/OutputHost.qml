pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell
import "../services"
import '../logic/menu-prebuild.mjs' as MenuPrebuild

QtObject {
    id: host
    required property Services services
    property var outputs: Quickshell.screens
    // The "speed" bar menu mode builds every bar's menus ahead of time once it has settled, one
    // surface per step so no single frame builds them all; "memory" leaves them to hover and open.
    // Switching to "memory" only stops further builds: built menus may hold a running tool job, a
    // selected tab or widget state, so they stay until the shell restarts.
    property int prebuildDelay: 2000
    property int prebuildGap: 450
    readonly property bool prebuildMenus: MenuPrebuild.prebuildEnabled(services.config.documents.interface)
    onPrebuildMenusChanged: {
        if (prebuildMenus) prebuildNext();
        else prebuildStagger.stop();
    }
    property Component surfaceComponent: Component {
        BarWindow {
            required property var modelData
            screen: modelData
            services: host.services
            menuPrebuildDelay: host.prebuildDelay
            // Deferred, so bars that settle together are built in output order.
            onMenuPrebuildDueChanged: if (menuPrebuildDue) Qt.callLater(host.prebuildNext)
        }
    }
    property Instantiator outputWindows: Instantiator {
        model: host.outputs
        asynchronous: false
        delegate: host.surfaceComponent
    }
    property Timer prebuildStagger: Timer {
        interval: host.prebuildGap
        repeat: true
        onTriggered: if (!host.prebuildOne()) stop()
    }
    // Builds the next menu that is due, if any; true when it built one.
    function prebuildOne() {
        if (!prebuildMenus) return false;
        const bars = [];
        for (let index = 0; index < outputWindows.count; index++) bars.push(outputWindows.objectAt(index));
        const next = MenuPrebuild.nextPrebuild(bars.map(bar => bar && typeof bar.prebuildMenu === 'function'
            ? { due: bar.menuPrebuildDue, prepared: bar.menusPrepared } : null));
        if (!next) return false;
        bars[next.index].prebuildMenu(next.side);
        return true;
    }
    // A running stagger picks up newly due bars on its next step.
    function prebuildNext() {
        if (!prebuildStagger.running && prebuildOne()) prebuildStagger.start();
    }
}
