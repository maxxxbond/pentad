import QtQuick
import QtQuick.Window
import Quickshell

Region {
    id: root
    required property var surface
    readonly property point origin: {
        if (!surface) return Qt.point(0, 0);
        let item = surface;
        while (item) { item.x; item.y; item.width; item.height; item = item.parent; }
        return surface.mapToItem(null, 0, 0);
    }
    property real originX: origin.x
    property real originY: origin.y
    property bool active: !!surface && surface.visible
    property bool disposed: false
    property var rows: []
    property var bands: []
    property Component rowFactory: Component { Region {} }
    regions: rows

    function reposition() {
        if (!root || disposed) return;
        const x = Math.round(originX);
        const y = Math.round(originY);
        for (let i = 0; i < rows.length; i++) {
            if (!rows[i]) continue;
            rows[i].x = x + bands[i].x;
            rows[i].y = y + bands[i].y;
        }
        changed();
        requestInputMaskFrame();
    }

    function requestInputMaskFrame() {
        if (disposed || !surface) return;
        const window = surface.Window.window;
        if (window && window.visible) window.update();
    }

    function rebuild() {
        if (!root || disposed) return;
        const old = rows;
        const nextBands = [];
        if (active && surface && surface.width > 0 && surface.height > 0) {
            const w = Math.ceil(surface.width);
            for (let y = 0; y < Math.ceil(surface.height); y++) {
                let mid = Math.floor(w / 2);
                if (!surface.contains(Qt.point(mid + 0.5, y + 0.5))) {
                    mid = -1;
                    for (let x = 0; x < w; x++) {
                        if (surface.contains(Qt.point(x + 0.5, y + 0.5))) { mid = x; break; }
                    }
                    if (mid < 0) continue;
                }
                let lo = 0, hi = mid;
                while (lo < hi) {
                    const x = Math.floor((lo + hi) / 2);
                    if (surface.contains(Qt.point(x + 0.5, y + 0.5))) hi = x;
                    else lo = x + 1;
                }
                const left = lo;
                lo = mid; hi = w - 1;
                while (lo < hi) {
                    const x = Math.ceil((lo + hi) / 2);
                    if (surface.contains(Qt.point(x + 0.5, y + 0.5))) lo = x;
                    else hi = x - 1;
                }
                const band = {
                    x: left, y,
                    width: lo - left + 1, height: 1
                };
                const previous = nextBands.length ? nextBands[nextBands.length - 1] : null;
                if (previous && previous.x === band.x && previous.width === band.width
                    && previous.y + previous.height === band.y) previous.height++;
                else nextBands.push(band);
            }
        }
        const next = [];
        for (let i = 0; i < nextBands.length; i++) {
            const row = rowFactory.createObject(root, nextBands[i]);
            if (!row) {
                for (const allocated of next) allocated.destroy();
                return;
            }
            row.x += Math.round(originX);
            row.y += Math.round(originY);
            next.push(row);
        }
        rows = next;
        bands = nextBands;
        for (let i = 0; i < old.length; i++) old[i].destroy();
        changed();
        requestInputMaskFrame();
    }
    function containsPoint(x, y) {
        return rows.some(function(row) {
            return x >= row.x && x < row.x + row.width && y >= row.y && y < row.y + row.height;
        });
    }
    onOriginXChanged: reposition()
    onOriginYChanged: reposition()
    onSurfaceChanged: Qt.callLater(rebuild)
    onActiveChanged: Qt.callLater(rebuild)
    Component.onCompleted: Qt.callLater(rebuild)
    Component.onDestruction: disposed = true
    property Connections geometry: Connections {
        target: root.surface
        function onContourChanged() { Qt.callLater(root.rebuild) }
    }
}
