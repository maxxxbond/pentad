pragma ComponentBehavior: Bound
import QtQuick
import qs.theme
import '../../logic/screenshot.mjs' as Model

Item {
    id: root
    required property var document
    required property string imagePath
    property var windowRegions: []
    // Suggestions found in the frozen pixels (photos, text blocks, panels); see tools/pentad_screenshot.py.
    property var contentRegions: []
    property var kindLabels: ({})
    // What can be chosen under the pointer, smallest first, and which of those the pointer currently selects.
    property var hoverChain: []
    property int hoverLevel: 0
    property string hoverKey: ''
    property string tool: 'select'
    property string color: '#ff5252'
    property real strokeWidth: 4
    property real fontSize: 24
    property bool selecting: false
    property bool interactive: true
    property string selectedId: ''
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    property var draft: null
    property var gesture: null
    property var hoverWindow: null
    property string hoverTitle: ''
    property string hoverHandle: ''
    readonly property var draftCrop: draft && draft.kind === 'crop' ? draft.rect : null
    readonly property var cropView: viewRect(document.crop)
    readonly property bool imageReady: frozenImage.status === Image.Ready
    readonly property real baseScale: Math.min(width / Math.max(1, document.width), height / Math.max(1, document.height))
    readonly property real imageScale: baseScale * zoom
    readonly property real offsetX: (width - document.width * imageScale) / 2 + panX
    readonly property real offsetY: (height - document.height * imageScale) / 2 + panY
    signal edited(var next)
    signal cropChosen(var rect)
    signal textRequested(var point, string id)
    signal operationError(string message)
    signal imageFailed()

    function imagePoint(x, y) { if (!(imageScale > 0)) return {x: 0, y: 0}; return Model.viewToImage({x: x, y: y}, {scale: imageScale, offsetX: offsetX, offsetY: offsetY}); }
    function viewPoint(point) { if (!(imageScale > 0)) return {x: 0, y: 0}; return Model.imageToView(point, {scale: imageScale, offsetX: offsetX, offsetY: offsetY}); }
    function clampPoint(point) { return {x: Math.max(0, Math.min(document.width, point.x)), y: Math.max(0, Math.min(document.height, point.y))}; }
    function rectFrom(a, b) { return {x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), width: Math.abs(b.x - a.x), height: Math.abs(b.y - a.y)}; }
    function contains(rect, point) { return point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height; }
    function regionRect(region) { return region && region.rect ? region.rect : region; }
    function regionEntryAt(point) {
        const regions = windowRegions || [];
        for (let i = regions.length - 1; i >= 0; i--) {
            const rect = regionRect(regions[i]);
            if (rect && contains(rect, point)) return regions[i];
        }
        return null;
    }
    function regionAt(point) { return regionRect(regionEntryAt(point)); }
    function area(rect) { return rect.width * rect.height; }
    function inside(inner, outer, slack) {
        return inner.x >= outer.x - slack && inner.y >= outer.y - slack
            && inner.x + inner.width <= outer.x + outer.width + slack && inner.y + inner.height <= outer.y + outer.height + slack;
    }
    // Everything choosable at a point: content inside the topmost window, that window, then the whole screen.
    function candidatesAt(point) {
        const entry = regionEntryAt(point);
        const windowRect = regionRect(entry);
        const chain = [];
        for (const region of contentRegions || []) {
            if (!contains(region, point) || (windowRect && !inside(region, windowRect, 6))) continue;
            chain.push({ rect: region, kind: region.kind,
                label: (kindLabels[region.kind] || '') + ' · ' + Math.round(region.width) + ' × ' + Math.round(region.height) });
        }
        chain.sort(function(a, b) { return area(a.rect) - area(b.rect); });
        if (windowRect) chain.push({ rect: windowRect, kind: 'window', label: entry.title ? String(entry.title) : (kindLabels.window || '') });
        if (chain.length) chain.push({ rect: { x: 0, y: 0, width: document.width, height: document.height }, kind: 'screen', label: kindLabels.screen || '' });
        return chain;
    }
    function applyHover() {
        const entry = hoverChain.length ? hoverChain[Math.max(0, Math.min(hoverLevel, hoverChain.length - 1))] : null;
        hoverWindow = entry ? entry.rect : null;
        hoverTitle = entry ? entry.label : '';
    }
    function updateHover(point) {
        const chain = candidatesAt(point);
        const key = chain.map(function(item) { return item.rect.x + ',' + item.rect.y + ',' + item.rect.width + ',' + item.rect.height; }).join('|');
        if (key !== hoverKey) { hoverKey = key; hoverLevel = 0; }
        hoverChain = chain;
        applyHover();
    }
    // Wheel while choosing: up grows the suggestion to the next bigger thing, down shrinks it again.
    function stepHover(direction) {
        if (!hoverChain.length) return false;
        const next = Math.max(0, Math.min(hoverChain.length - 1, hoverLevel + direction));
        if (next === hoverLevel) return true;
        hoverLevel = next;
        applyHover();
        return true;
    }
    function viewRect(rect) { return rect ? {x: offsetX + rect.x * imageScale, y: offsetY + rect.y * imageScale, width: rect.width * imageScale, height: rect.height * imageScale} : null; }
    function sizeLabel(rect) { return rect ? Math.round(rect.width) + ' × ' + Math.round(rect.height) : ''; }
    function resizeHandle(point) {
        const handle = cropHandle(point);
        return handle === 'move' && tool !== 'crop' ? '' : handle;
    }
    function handleCursor(handle) {
        if (handle === 'nw' || handle === 'se') return Qt.SizeFDiagCursor;
        if (handle === 'ne' || handle === 'sw') return Qt.SizeBDiagCursor;
        if (handle === 'n' || handle === 's') return Qt.SizeVerCursor;
        if (handle === 'e' || handle === 'w') return Qt.SizeHorCursor;
        return Qt.SizeAllCursor;
    }
    function cropHandle(point) {
        const c = document.crop;
        const tolerance = 11 / imageScale;
        const left = Math.abs(point.x - c.x) <= tolerance;
        const right = Math.abs(point.x - c.x - c.width) <= tolerance;
        const top = Math.abs(point.y - c.y) <= tolerance;
        const bottom = Math.abs(point.y - c.y - c.height) <= tolerance;
        if (left && top) return 'nw';
        if (right && top) return 'ne';
        if (left && bottom) return 'sw';
        if (right && bottom) return 'se';
        if (left && point.y >= c.y && point.y <= c.y + c.height) return 'w';
        if (right && point.y >= c.y && point.y <= c.y + c.height) return 'e';
        if (top && point.x >= c.x && point.x <= c.x + c.width) return 'n';
        if (bottom && point.x >= c.x && point.x <= c.x + c.width) return 's';
        return contains(c, point) ? 'move' : '';
    }
    function cropForGesture(g, point) {
        const c = g.original;
        const dx = point.x - g.start.x, dy = point.y - g.start.y;
        if (g.handle === 'move') return {x: Math.max(0, Math.min(document.width - c.width, c.x + dx)), y: Math.max(0, Math.min(document.height - c.height, c.y + dy)), width: c.width, height: c.height};
        let x1 = c.x, y1 = c.y, x2 = c.x + c.width, y2 = c.y + c.height;
        if (g.handle.indexOf('w') >= 0) x1 += dx;
        if (g.handle.indexOf('e') >= 0) x2 += dx;
        if (g.handle.indexOf('n') >= 0) y1 += dy;
        if (g.handle.indexOf('s') >= 0) y2 += dy;
        return rectFrom(clampPoint({x:x1,y:y1}), clampPoint({x:x2,y:y2}));
    }
    function translated(a, dx, dy) {
        const left=Math.min(a.x,a.x+a.width),right=Math.max(a.x,a.x+a.width);
        const top=Math.min(a.y,a.y+a.height),bottom=Math.max(a.y,a.y+a.height);
        dx=Math.max(-left,Math.min(document.width-right,dx));
        dy=Math.max(-top,Math.min(document.height-bottom,dy));
        const patch = {x: a.x + dx, y: a.y + dy};
        if (a.points && a.points.length) patch.points = a.points.map(function(p) { return {x:p.x + dx,y:p.y + dy}; });
        return patch;
    }
    function cancelGesture() { gesture = null; draft = null; layer.requestPaint(); }
    function deleteSelected() {
        if (!selectedId) return;
        try { edited(Model.deleteAnnotation(document, selectedId)); }
        catch (error) { operationError(String(error)); }
        selectedId = '';
    }
    function resetView() { zoom = 1; panX = 0; panY = 0; }
    function repaint() { layer.requestPaint(); }
    // Suggestions arrive after the overlay is already up; refresh what is under a pointer that is not moving.
    onContentRegionsChanged: if (selecting && !gesture && pointer.containsMouse) updateHover(clampPoint(imagePoint(pointer.mouseX, pointer.mouseY)))
    onDocumentChanged: layer.requestPaint()
    onDraftChanged: layer.requestPaint()
    onSelectedIdChanged: layer.requestPaint()
    onImageScaleChanged: layer.requestPaint()
    onOffsetXChanged: layer.requestPaint()
    onOffsetYChanged: layer.requestPaint()

    Rectangle { anchors.fill: parent; color: Theme.tokens.surface }
    Image {
        id: frozenImage
        x: root.offsetX; y: root.offsetY
        width: root.document.width * root.imageScale
        height: root.document.height * root.imageScale
        source: root.imagePath ? encodeURI('file://' + root.imagePath) : ''
        fillMode: Image.Stretch
        smooth: true
        cache: false
        onStatusChanged: if (status === Image.Error) root.imageFailed()
    }
    Canvas {
        id: layer
        anchors.fill: parent
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext('2d');
            ctx.clearRect(0, 0, width, height);
            if (!root.document || !root.document.crop) return;
            const crop = root.draft && root.draft.kind === 'crop' ? root.draft.rect : root.document.crop;
            const full = root.selecting && !(root.draft && root.draft.kind === 'crop');
            ctx.save();
            ctx.translate(root.offsetX, root.offsetY);
            ctx.scale(root.imageScale, root.imageScale);
            if (!full && crop.width > 0 && crop.height > 0) {
                ctx.save();
                ctx.beginPath(); ctx.rect(crop.x, crop.y, crop.width, crop.height); ctx.clip();
                for (const a of root.document.annotations) {
                    let item = a;
                    if (root.draft && root.draft.kind === 'move' && root.draft.id === a.id)
                        item = Object.assign({}, a, root.translated(a, root.draft.dx, root.draft.dy));
                    root.paintAnnotation(ctx, item);
                }
                if (root.draft && root.draft.kind === 'annotation') root.paintAnnotation(ctx, root.draft.annotation);
                ctx.restore();
            }
            ctx.restore();
            if (root.selectedId) {
                const a = root.document.annotations.find(function(item) { return item.id === root.selectedId; });
                if (a) {
                    const x = root.offsetX+Math.min(a.x,a.x+a.width)*root.imageScale;
                    const y = root.offsetY+Math.min(a.y,a.y+a.height)*root.imageScale;
                    ctx.strokeStyle = Theme.tokens.accent; ctx.lineWidth = 1;
                    ctx.setLineDash([5,4]); ctx.strokeRect(x-3,y-3,Math.max(6,Math.abs(a.width)*root.imageScale+6),Math.max(6,Math.abs(a.height)*root.imageScale+6)); ctx.setLineDash([]);
                }
            }
        }
    }
    ScreenshotFrame {
        anchors.fill: parent
        visible: root.imageReady
        rect: root.selecting ? root.viewRect(root.draftCrop || root.hoverWindow) : root.viewRect(root.draftCrop) || root.cropView
        kind: root.selecting ? (root.draftCrop ? 'region' : root.hoverWindow ? 'window' : 'none') : 'selection'
        animate: !root.gesture
        handles: !root.selecting
        sizeText: !root.selecting && root.draftCrop ? root.sizeLabel(root.draftCrop) : ''
    }
    ScreenshotCrosshair {
        anchors.fill: parent
        visible: root.selecting && root.imageReady && pointer.containsMouse
        pointX: pointer.mouseX
        pointY: pointer.mouseY
        camera: !!root.hoverWindow && !root.gesture
        label: {
            if (root.draftCrop) return root.sizeLabel(root.draftCrop);
            if (camera) return root.hoverTitle;
            const p = root.clampPoint(root.imagePoint(pointer.mouseX, pointer.mouseY));
            return Math.floor(p.x) + ', ' + Math.floor(p.y);
        }
    }
    function paintAnnotation(ctx, a) {
        if (!a) return;
        ctx.save();
        ctx.strokeStyle = a.color || color;
        ctx.fillStyle = a.color || color;
        ctx.lineWidth = a.strokeWidth || strokeWidth;
        ctx.lineJoin = 'round'; ctx.lineCap = 'round';
        const x = a.x, y = a.y, x2 = x + a.width, y2 = y + a.height;
        if (a.type === 'brush' && a.points && a.points.length) {
            ctx.beginPath(); ctx.moveTo(a.points[0].x,a.points[0].y);
            for (let i=1;i<a.points.length;i++) ctx.lineTo(a.points[i].x,a.points[i].y);
            if (a.points.length === 1) ctx.lineTo(a.points[0].x+0.01,a.points[0].y);
            ctx.stroke();
        } else if (a.type === 'line' || a.type === 'arrow') {
            ctx.beginPath(); ctx.moveTo(x,y); ctx.lineTo(x2,y2); ctx.stroke();
            if (a.type === 'arrow') {
                const angle = Math.atan2(a.height,a.width), length = Math.max(12,(a.strokeWidth || strokeWidth)*4);
                ctx.beginPath(); ctx.moveTo(x2,y2);
                ctx.lineTo(x2-length*Math.cos(angle-Math.PI/6),y2-length*Math.sin(angle-Math.PI/6));
                ctx.moveTo(x2,y2);
                ctx.lineTo(x2-length*Math.cos(angle+Math.PI/6),y2-length*Math.sin(angle+Math.PI/6)); ctx.stroke();
            }
        } else if (a.type === 'rectangle' || a.type === 'redact' || a.type === 'highlight') {
            if (a.type === 'highlight') { ctx.globalAlpha = 0.3; ctx.fillRect(x,y,a.width,a.height); }
            else if (a.type === 'redact') ctx.fillRect(x,y,a.width,a.height);
            else ctx.strokeRect(x,y,a.width,a.height);
        } else if (a.type === 'ellipse') {
            ctx.beginPath(); ctx.save(); ctx.translate(x+a.width/2,y+a.height/2);
            ctx.scale(Math.max(0.01,a.width/2),Math.max(0.01,a.height/2)); ctx.arc(0,0,1,0,Math.PI*2); ctx.restore(); ctx.stroke();
        } else if (a.type === 'text') {
            ctx.font = String(a.fontSize || fontSize) + 'px ' + Theme.tokens.fontFamily;
            ctx.textBaseline = 'top';
            const lines = String(a.text || '').split('\n');
            for (let i=0;i<lines.length;i++) ctx.fillText(lines[i],x,y+i*(a.fontSize || fontSize)*1.2);
        }
        ctx.restore();
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.interactive && root.imageScale > 0
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: root.selecting ? Qt.BlankCursor : root.gesture && root.gesture.kind === 'new-crop' ? Qt.CrossCursor : root.gesture && root.gesture.kind === 'crop' ? root.handleCursor(root.gesture.handle) : root.hoverHandle ? root.handleCursor(root.hoverHandle) : root.tool === 'crop' ? Qt.CrossCursor : root.tool === 'select' ? Qt.ArrowCursor : Qt.CrossCursor
        onPositionChanged: function(mouse) {
            const p = root.clampPoint(root.imagePoint(mouse.x,mouse.y));
            if (!root.gesture) {
                if (root.selecting) root.updateHover(p);
                else { root.hoverWindow = null; root.hoverTitle = ''; }
                root.hoverHandle = root.selecting ? '' : root.resizeHandle(p);
                return;
            }
            const g = root.gesture;
            if (g.kind === 'pan') { root.panX = g.panX + mouse.x-g.viewX; root.panY = g.panY+mouse.y-g.viewY; return; }
            if (g.kind === 'new-crop') root.draft = {kind:'crop',rect:root.rectFrom(g.start,p)};
            else if (g.kind === 'crop') root.draft = {kind:'crop',rect:root.cropForGesture(g,p)};
            else if (g.kind === 'move') root.draft = {kind:'move',id:g.id,dx:p.x-g.start.x,dy:p.y-g.start.y};
            else if (g.kind === 'draw') {
                let a = Object.assign({},g.annotation);
                if (a.type === 'brush') {
                    // Skip sub-pixel jitter and keep the stroke well inside the model's point limits.
                    const points = a.points, last = points[points.length - 1];
                    if (points.length < 2000 && Math.hypot(p.x - last.x, p.y - last.y) * root.imageScale >= 1.5) points.push(p);
                    else if (points.length >= 2000 && Math.hypot(p.x - last.x, p.y - last.y) * root.imageScale >= 1.5) points[points.length - 1] = p;
                    a.points = points;
                    const bounds = {x:Math.min(a.x,p.x),y:Math.min(a.y,p.y),right:Math.max(a.x+a.width,p.x),bottom:Math.max(a.y+a.height,p.y)};
                    a.x=bounds.x; a.y=bounds.y; a.width=bounds.right-bounds.x; a.height=bounds.bottom-bounds.y;
                    g.annotation = a;
                } else if (a.type === 'line' || a.type === 'arrow') { a.width=p.x-g.start.x; a.height=p.y-g.start.y; }
                else Object.assign(a,root.rectFrom(g.start,p));
                root.draft = {kind:'annotation',annotation:a};
            }
        }
        onPressed: function(mouse) {
            const p = root.clampPoint(root.imagePoint(mouse.x,mouse.y));
            if (mouse.button === Qt.MiddleButton) { root.gesture={kind:'pan',viewX:mouse.x,viewY:mouse.y,panX:root.panX,panY:root.panY}; return; }
            if (root.selecting || mouse.button === Qt.RightButton) { root.gesture={kind:'new-crop',start:p,window:root.selecting ? root.hoverWindow : root.regionAt(p)}; return; }
            if (root.tool === 'crop') {
                const handle = root.cropHandle(p);
                root.gesture = handle ? {kind:'crop',handle:handle,start:p,original:root.document.crop} : {kind:'new-crop',start:p};
                return;
            }
            const handle = root.resizeHandle(p);
            if (handle) { root.gesture={kind:'crop',handle:handle,start:p,original:root.document.crop}; return; }
            if (!root.contains(root.document.crop,p)) return;
            if (root.tool === 'select') {
                const id = Model.hitTest(root.document,p,8/root.imageScale);
                root.selectedId = id || '';
                if (id) root.gesture={kind:'move',start:p,id:id};
                return;
            }
            if (root.tool === 'text') { root.textRequested(p,''); return; }
            const a={id:'a-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,7),type:root.tool,x:p.x,y:p.y,width:0,height:0,points:root.tool==='brush'?[p]:[],text:'',color:root.color,strokeWidth:root.strokeWidth,fontSize:root.fontSize};
            root.gesture={kind:'draw',start:p,annotation:a};
            root.draft={kind:'annotation',annotation:a};
        }
        onReleased: function(mouse) {
            const g=root.gesture;
            if (!g) return;
            const p=root.clampPoint(root.imagePoint(mouse.x,mouse.y));
            root.gesture=null;
            try {
                if (g.kind==='new-crop') {
                    let r=root.rectFrom(g.start,p);
                    if (r.width<3/root.imageScale && r.height<3/root.imageScale && g.window) r=g.window;
                    if (r.width>1 && r.height>1) {
                        root.edited(Model.setCrop(root.document,r));
                        if (root.selecting) { root.selecting=false; root.cropChosen(r); }
                    }
                } else if (g.kind==='crop' && root.draft && root.draft.rect.width>1 && root.draft.rect.height>1)
                    root.edited(Model.setCrop(root.document,root.draft.rect));
                else if (g.kind==='move' && root.draft && (root.draft.dx || root.draft.dy)) {
                    const a=root.document.annotations.find(function(item){return item.id===g.id;});
                    if (a) root.edited(Model.updateAnnotation(root.document,g.id,root.translated(a,root.draft.dx,root.draft.dy)));
                } else if (g.kind==='draw' && root.draft) {
                    const a=root.draft.annotation;
                    if (a.type==='brush' || Math.hypot(a.width,a.height)>1/root.imageScale) root.edited(Model.addAnnotation(root.document,a));
                }
            } catch (error) { root.operationError(String(error)); }
            root.draft=null;
        }
        onCanceled: root.cancelGesture()
        onWheel: function(wheel) {
            if (root.selecting && !root.gesture) {
                if (root.stepHover(wheel.angleDelta.y > 0 ? 1 : -1)) { wheel.accepted = true; return; }
            }
            const before=root.imagePoint(wheel.x,wheel.y);
            const next=Math.max(0.25,Math.min(8,root.zoom*(wheel.angleDelta.y>0?1.15:1/1.15)));
            if (next===root.zoom) return;
            root.zoom=next;
            root.panX=wheel.x-(root.width-root.document.width*root.imageScale)/2-before.x*root.imageScale;
            root.panY=wheel.y-(root.height-root.document.height*root.imageScale)/2-before.y*root.imageScale;
            wheel.accepted=true;
        }
        onDoubleClicked: function(mouse) {
            if (root.tool !== 'select') return;
            const p=root.clampPoint(root.imagePoint(mouse.x,mouse.y));
            const id=Model.hitTest(root.document,p,8/root.imageScale);
            const a=root.document.annotations.find(function(item){return item.id===id;});
            if (a && a.type==='text') root.textRequested({x:a.x,y:a.y},a.id);
        }
    }
}
