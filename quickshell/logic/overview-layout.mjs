export function workspaceColumns(width) {
    if (!Number.isFinite(width) || width <= 0) return 1;
    return Math.max(1, Math.min(3, Math.floor((width + 16) / 316)));
}

export function fitPreview(width, height, boxWidth, boxHeight) {
    if (![width, height, boxWidth, boxHeight].every(Number.isFinite)
            || width <= 0 || height <= 0 || boxWidth <= 0 || boxHeight <= 0)
        return { width: Math.max(1, boxWidth), height: Math.max(1, boxHeight) };
    const scale = Math.min(boxWidth / width, boxHeight / height);
    return { width: Math.round(width * scale), height: Math.round(height * scale) };
}

export function overviewPage(activeNumericId) {
    const id = Number(activeNumericId);
    const start = Number.isSafeInteger(id) && id > 0 && id <= 2147483647
        ? Math.floor((id - 1) / 10) * 10 + 1 : 1;
    return { start, ids: Array.from({ length: 10 }, (_, offset) => String(start + offset)) };
}

export function overviewColumns(availableWidth) {
    if (!Number.isFinite(availableWidth) || availableWidth <= 0) return 1;
    return Math.max(1, Math.min(5, Math.floor((availableWidth + 12) / 232)));
}

export function overviewSceneLayout(width, height, options = {}) {
    const w = Number.isFinite(width) ? Math.max(0, width) : 0;
    const h = Number.isFinite(height) ? Math.max(0, height) : 0;
    const gap = Math.min(20, w / 12, h / 12);
    const inset = Math.min(36, Math.max(12, Math.min(w, h) * 0.025), w / 8, h / 8);
    const innerWidth = Math.max(0, w - 2 * inset);
    const headerHeight = Math.min(56, h * 0.18);
    const pinnedHeight = options.pinned ? Math.min(36, h * 0.08) : 0;
    const footerHeight = Math.min(36, h * 0.08);
    const top = inset + headerHeight + pinnedHeight;
    const availableHeight = Math.max(0, h - top - inset - footerHeight - gap);
    const side = w >= 1000 && h >= 420 && w / h >= 2.15;
    const expanded = !!options.expanded;
    let scene, rail;
    if (side) {
        const railWidth = Math.min(innerWidth * 0.25, expanded ? 248 : 184);
        scene = { x: inset, y: top, width: Math.max(0, innerWidth - railWidth - gap), height: availableHeight };
        rail = { x: scene.x + scene.width + gap, y: top, width: railWidth, height: availableHeight };
    } else {
        const railHeight = Math.min(availableHeight * 0.36,
            Math.max(80, Math.min(expanded ? 192 : 132, h * (expanded ? 0.22 : 0.16))));
        scene = { x: inset, y: top, width: innerWidth, height: Math.max(0, availableHeight - railHeight - gap) };
        rail = { x: inset, y: scene.y + scene.height + gap, width: innerWidth, height: railHeight };
    }
    return { side, gap, inset, headerHeight, pinnedHeight, footerHeight, scene, rail };
}

export function projectWindow(client, workarea, tile) {
    const numbers = [client?.x, client?.y, client?.width, client?.height,
        workarea?.x, workarea?.y, workarea?.width, workarea?.height,
        tile?.width, tile?.height];
    if (!numbers.every(Number.isFinite) || client.width <= 0 || client.height <= 0
            || workarea.width <= 0 || workarea.height <= 0 || tile.width <= 0 || tile.height <= 0)
        return null;
    const scale = Math.min(tile.width / workarea.width, tile.height / workarea.height);
    const originX = (tile.width - workarea.width * scale) / 2;
    const originY = (tile.height - workarea.height * scale) / 2;
    const x0 = Math.max(0, originX, originX + (client.x - workarea.x) * scale);
    const y0 = Math.max(0, originY, originY + (client.y - workarea.y) * scale);
    const x1 = Math.min(tile.width, originX + workarea.width * scale,
        originX + (client.x + client.width - workarea.x) * scale);
    const y1 = Math.min(tile.height, originY + workarea.height * scale,
        originY + (client.y + client.height - workarea.y) * scale);
    if (x1 <= x0 || y1 <= y0) return null;
    const left = Math.max(0, Math.round(x0));
    const top = Math.max(0, Math.round(y0));
    return { x: left, y: top, width: Math.max(1, Math.round(x1) - left),
        height: Math.max(1, Math.round(y1) - top) };
}

// Cards keep their own shape (a portrait monitor, a 4:3 game next to 16:9 desktops), like
// Mission Control: every card in the grid shares one height, its width follows its aspect,
// rows stay in reading order and are centred. `aspects[i]` is height / width of card i.
export function overviewGridLayout(width, height, options = {}) {
    const w = Number.isFinite(width) ? Math.max(0, width) : 0;
    const h = Number.isFinite(height) ? Math.max(0, height) : 0;
    const count = Math.max(1, Math.floor(options.count) || 10);
    const valid = value => Number.isFinite(value) && value > 0;
    const aspect = valid(options.aspect) ? options.aspect : 9 / 16;
    const aspects = Array.from({ length: count }, (_, index) =>
        Array.isArray(options.aspects) && valid(options.aspects[index]) ? options.aspects[index] : aspect);
    const inset = Math.min(36, Math.max(12, Math.min(w, h) * 0.025), w / 8, h / 8);
    const gap = Math.max(8, Math.min(20, w / 90));
    const headerHeight = Math.min(44, h * 0.1);
    const pinnedHeight = options.pinned ? Math.min(36, h * 0.08) : 0;
    const footerHeight = Math.min(32, h * 0.07);
    const top = inset + headerHeight + pinnedHeight;
    const availableWidth = Math.max(0, w - 2 * inset);
    const availableHeight = Math.max(0, h - top - inset - footerHeight);
    const minimumCell = 190;
    const rowsOf = columns => Array.from({ length: Math.ceil(count / columns) },
        (_, row) => aspects.slice(row * columns, row * columns + columns));
    let best = { columns: 1, rowHeight: 0, score: -1 };
    for (let columns = Math.min(count, 5); columns >= 1; columns--) {
        const rows = rowsOf(columns);
        const fromHeight = (availableHeight - gap * (rows.length - 1)) / rows.length;
        const fromWidth = Math.min(...rows.map(row =>
            (availableWidth - gap * (row.length - 1)) / row.reduce((sum, value) => sum + 1 / value, 0)));
        const rowHeight = Math.max(0, Math.min(fromHeight, fromWidth));
        // Size is judged on the anchor monitor's shape; a portrait or game card is simply narrower.
        const score = rowHeight / aspect;
        if (score >= minimumCell) { best = { columns, rowHeight, score }; break; }
        if (score > best.score + 0.5) best = { columns, rowHeight, score };
    }
    const rowHeight = Math.floor(best.rowHeight);
    const rows = rowsOf(best.columns);
    const widths = rows.map(row => row.map(value => Math.floor(rowHeight / value)));
    const rowWidths = widths.map(row => row.reduce((sum, value) => sum + value, 0) + gap * (row.length - 1));
    const gridWidth = Math.max(0, ...rowWidths);
    const gridHeight = rows.length * rowHeight + (rows.length - 1) * gap;
    const cells = [];
    widths.forEach((row, rowIndex) => {
        let x = Math.floor((gridWidth - rowWidths[rowIndex]) / 2);
        for (const cellWidth of row) {
            cells.push({ x, y: rowIndex * (rowHeight + gap), width: cellWidth, height: rowHeight });
            x += cellWidth + gap;
        }
    });
    return {
        gap, inset, headerHeight, pinnedHeight, footerHeight,
        columns: best.columns, rows: rows.length,
        cellWidth: Math.floor(rowHeight / aspect), cellHeight: rowHeight, cells,
        x: inset + Math.max(0, (availableWidth - gridWidth) / 2),
        y: top + Math.max(0, (availableHeight - gridHeight) / 2),
        width: gridWidth, height: gridHeight,
    };
}

// Inverse of projectWindow: a point in a card's canvas back to global layout coordinates.
export function unprojectPoint(point, workarea, tile) {
    const numbers = [point?.x, point?.y, workarea?.x, workarea?.y, workarea?.width, workarea?.height,
        tile?.width, tile?.height];
    if (!numbers.every(Number.isFinite) || workarea.width <= 0 || workarea.height <= 0
            || tile.width <= 0 || tile.height <= 0)
        return null;
    const scale = Math.min(tile.width / workarea.width, tile.height / workarea.height);
    const originX = (tile.width - workarea.width * scale) / 2;
    const originY = (tile.height - workarea.height * scale) / 2;
    const x = Math.min(workarea.width, Math.max(0, (point.x - originX) / scale));
    const y = Math.min(workarea.height, Math.max(0, (point.y - originY) / scale));
    return { x: workarea.x + x, y: workarea.y + y };
}

// Where a dropped tiled window should land: next to the tiled window under the drop point
// (or the nearest one), on the side of that window the point is closest to.
export function dropPlacement(clients, movedAddress, workspaceId, point) {
    if (!Array.isArray(clients) || !point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) return null;
    const candidates = clients.filter(client => client && client.address !== movedAddress
        && String(client.workspaceId) === String(workspaceId) && client.mapped !== false && !client.hidden
        && !client.floating && !client.fullscreen
        && [client.x, client.y, client.width, client.height].every(Number.isFinite)
        && client.width > 0 && client.height > 0);
    if (!candidates.length) return null;
    const distance = client => {
        const dx = Math.max(client.x - point.x, 0, point.x - (client.x + client.width));
        const dy = Math.max(client.y - point.y, 0, point.y - (client.y + client.height));
        return dx * dx + dy * dy;
    };
    const target = candidates.slice().sort((a, b) => distance(a) - distance(b))[0];
    const nx = (point.x - (target.x + target.width / 2)) / target.width;
    const ny = (point.y - (target.y + target.height / 2)) / target.height;
    const direction = Math.abs(nx) >= Math.abs(ny) ? (nx < 0 ? 'l' : 'r') : (ny < 0 ? 'u' : 'd');
    return { target: target.address, direction };
}
