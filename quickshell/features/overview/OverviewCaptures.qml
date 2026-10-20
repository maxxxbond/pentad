pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import '../../logic/overview-layout.mjs' as Layout
import '../../logic/overview-presentation.mjs' as Presentation

Item {
    id: pool
    required property var services
    required property var clients
    required property var captureIds
    property var frames: ({})
    property var retainedIds: []
    x: -4096; y: -4096; width: 1; height: 1
    function frameFor(id) { return frames[id] || null; }
    function reconcile() {
        if (!Array.isArray(clients) || !Array.isArray(captureIds)) return;
        retainedIds = Presentation.retainCaptureIds(captureIds, retainedIds, Presentation.overviewWindowIds(clients));
    }
    onCaptureIdsChanged: reconcile()
    onClientsChanged: reconcile()
    Component.onCompleted: reconcile()
    Repeater {
        model: ScriptModel { values: pool.retainedIds }
        onItemAdded: (index, item) => { pool.frames = Object.assign({}, pool.frames, { [item.modelData]: item }); }
        onItemRemoved: (index, item) => {
            if (pool.frames[item.modelData] !== item) return;
            const next = Object.assign({}, pool.frames); delete next[item.modelData]; pool.frames = next;
        }
        delegate: Item {
            id: entry
            required property string modelData
            readonly property var client: pool.clients.find(client => client.instanceId === modelData) || null
            readonly property var ref: client ? ({ address: client.address, instanceId: client.instanceId }) : null
            readonly property var source: ref && pool.services?.hyprland && !pool.services.preview && !pool.services.safeMode
                ? pool.services.hyprland.captureSourceFor(ref) : null
            property bool ready: false
            property string capturedShape: ''
            readonly property string shape: client ? Math.round(client.width || 0) + 'x' + Math.round(client.height || 0) : ''
            readonly property alias texture: frozen
            function fitToClient() {
                const size = Layout.fitPreview(Math.max(1, client?.width || 1), Math.max(1, client?.height || 1), 1536, 1024);
                width = size.width; height = size.height;
                capturedShape = shape;
            }
            Component.onCompleted: fitToClient()
            // A move or retile changes the window's size; the frozen frame would be stretched,
            // so take a fresh one once the new geometry has settled.
            onShapeChanged: if (ready && shape !== capturedShape) recaptureDelay.restart()
            Timer {
                id: recaptureDelay
                interval: 260
                onTriggered: {
                    entry.fitToClient();
                    capture.captureFrame();
                    refreezeDelay.restart();
                }
            }
            Timer {
                id: refreezeDelay
                interval: 120
                onTriggered: frozen.scheduleUpdate()
            }
            ScreencopyView {
                id: capture
                anchors.fill: parent
                captureSource: entry.source
                paintCursor: false; live: false
                onHasContentChanged: if (hasContent) {
                    frozen.scheduleUpdate();
                    entry.ready = true;
                }
            }
            // Mipmapped so a 1536 px frame shown at card size is filtered instead of aliased.
            ShaderEffectSource {
                id: frozen
                anchors.fill: parent
                sourceItem: capture
                hideSource: true; live: false
                mipmap: true
                smooth: true
            }
        }
    }
}
