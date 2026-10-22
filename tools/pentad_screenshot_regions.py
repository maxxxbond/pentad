"""Content-region finder for the Pentad screenshot picker (numpy is passed in by the caller)."""

# --- content proposals -------------------------------------------------------------------------------------
# Windows come from the compositor. Inside a window the frozen pixels suggest what else can be picked:
# photos (dense edges), text blocks (sparse short edges, merged into paragraphs) and flat panels or cards.

CELL = 8
EDGE_THRESHOLD = 40
MAX_REGIONS = 600
MERGE_LEVELS = ((1, 0), (2, 1), (4, 2))
PANEL_STEP = 6
PANEL_SPREAD = 2.5

def _dilate(np, mask, across: int, down: int):
    out = mask.copy()
    rows, cols = mask.shape
    for step in range(1, across + 1):
        out[:, step:] |= mask[:, :cols - step]
        out[:, :cols - step] |= mask[:, step:]
    grown = out.copy()
    for step in range(1, down + 1):
        grown[step:, :] |= out[:rows - step, :]
        grown[:rows - step, :] |= out[step:, :]
    return grown

def _components(grid, same=None):
    """4-connected components of a boolean grid; `same` optionally restricts neighbours to equal keys."""
    from collections import deque
    rows, cols = len(grid), len(grid[0]) if grid else 0
    seen = [[False] * cols for _ in range(rows)]
    found = []
    for r0 in range(rows):
        for c0 in range(cols):
            if not grid[r0][c0] or seen[r0][c0]:
                continue
            seen[r0][c0] = True
            queue = deque([(r0, c0)])
            cells = []
            while queue:
                r, c = queue.popleft()
                cells.append((r, c))
                for rn, cn in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
                    if 0 <= rn < rows and 0 <= cn < cols and grid[rn][cn] and not seen[rn][cn] \
                            and (same is None or same[rn][cn] == same[r][c]):
                        seen[rn][cn] = True
                        queue.append((rn, cn))
            found.append(cells)
    return found

def _iou(a: dict, b: dict) -> float:
    x1, y1 = max(a["x"], b["x"]), max(a["y"], b["y"])
    x2 = min(a["x"] + a["width"], b["x"] + b["width"])
    y2 = min(a["y"] + a["height"], b["y"] + b["height"])
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    union = a["width"] * a["height"] + b["width"] * b["height"] - inter
    return inter / union if union else 0.0

def _find_regions(np, bgr) -> list:
    height, width, _ = bgr.shape
    rows, cols = height // CELL, width // CELL
    if rows < 4 or cols < 4:
        return []
    h, w = rows * CELL, cols * CELL
    img = bgr[:h, :w].astype(np.int32)
    gray = (img[:, :, 0] * 29 + img[:, :, 1] * 150 + img[:, :, 2] * 77) >> 8
    gx = np.abs(np.diff(gray, axis=1, prepend=gray[:, :1]))
    gy = np.abs(np.diff(gray, axis=0, prepend=gray[:1, :]))
    edge = (gx + gy) > EDGE_THRESHOLD
    density = edge.reshape(rows, CELL, cols, CELL).mean(axis=(1, 3))
    spread = gray.reshape(rows, CELL, cols, CELL).std(axis=(1, 3))
    mean = img.reshape(rows, CELL, cols, CELL, 3).mean(axis=(1, 3))
    regions: list = []

    # textured content: photos and text
    textured = density >= 0.05
    textured_rows = textured.tolist()
    # Three merge distances give the hover chain several steps: a word or icon, a line or row, a whole block.
    for across, down in MERGE_LEVELS:
        merged = _dilate(np, textured, across, down)
        for cells in _components(merged.tolist()):
            own = [(r, c) for r, c in cells if textured_rows[r][c]]
            if len(own) < 3:
                continue
            r0, r1 = min(r for r, _ in own), max(r for r, _ in own)
            c0, c1 = min(c for _, c in own), max(c for _, c in own)
            y0, y1, x0, x1 = r0 * CELL, (r1 + 1) * CELL, c0 * CELL, (c1 + 1) * CELL
            sub = edge[y0:y1, x0:x1]
            used_rows, used_cols = np.flatnonzero(sub.any(axis=1)), np.flatnonzero(sub.any(axis=0))
            if not len(used_rows) or not len(used_cols):
                continue
            ty0, ty1 = y0 + int(used_rows[0]), y0 + int(used_rows[-1]) + 1
            tx0, tx1 = x0 + int(used_cols[0]), x0 + int(used_cols[-1]) + 1
            fill = len(own) / ((r1 - r0 + 1) * (c1 - c0 + 1))
            strength = float(np.mean([density[r][c] for r, c in own]))
            rw, rh = tx1 - tx0, ty1 - ty0
            kind = "image" if strength >= 0.30 and fill >= 0.55 and rw >= 64 and rh >= 48 else "text"
            if kind == "image":
                # Text is mostly one background colour; a photo spreads over many.
                tones = (img[ty0:ty1, tx0:tx1] // 32).reshape(-1, 3)
                keys = tones[:, 0] * 64 + tones[:, 1] * 8 + tones[:, 2]
                if float(np.bincount(keys).max()) / len(keys) >= 0.45:
                    kind = "text"
            if (kind == "image" or (rw >= 12 and rh >= 8)) and rw * rh <= 0.6 * width * height:
                regions.append({"x": tx0, "y": ty0, "width": rw, "height": rh, "kind": kind})

    # flat panels: connected cells of one colour that fill a rectangle
    flat = (spread <= PANEL_SPREAD) & (density < 0.012)
    quantised = (mean // PANEL_STEP).astype(np.int32)
    keys = (quantised[:, :, 0] * 65536 + quantised[:, :, 1] * 256 + quantised[:, :, 2]).tolist()
    for cells in _components(flat.tolist(), same=keys):
        r0, r1 = min(r for r, _ in cells), max(r for r, _ in cells)
        c0, c1 = min(c for _, c in cells), max(c for _, c in cells)
        box_cells = (r1 - r0 + 1) * (c1 - c0 + 1)
        if len(cells) < 24 or len(cells) / box_cells < 0.85 or (r1 - r0 + 1) < 4 or (c1 - c0 + 1) < 6:
            continue
        if box_cells > 0.6 * rows * cols:
            continue
        colour = mean[cells[0][0]][cells[0][1]]
        y0, y1 = max(0, (r0 - 1) * CELL), min(h, (r1 + 2) * CELL)
        x0, x1 = max(0, (c0 - 1) * CELL), min(w, (c1 + 2) * CELL)
        close = (np.abs(img[y0:y1, x0:x1] - colour).max(axis=2) <= 12)
        used_rows = np.flatnonzero(close.sum(axis=1) >= 0.5 * (c1 - c0 + 1) * CELL)
        used_cols = np.flatnonzero(close.sum(axis=0) >= 0.5 * (r1 - r0 + 1) * CELL)
        if not len(used_rows) or not len(used_cols):
            continue
        py0, py1 = y0 + int(used_rows[0]), y0 + int(used_rows[-1]) + 1
        px0, px1 = x0 + int(used_cols[0]), x0 + int(used_cols[-1]) + 1
        regions.append({"x": px0, "y": py0, "width": px1 - px0, "height": py1 - py0, "kind": "panel"})

    order = {"image": 0, "text": 1, "panel": 2}
    regions.sort(key=lambda r: (-(r["width"] * r["height"]), order[r["kind"]], r["y"], r["x"]))
    kept: list = []
    for region in regions:
        if region["x"] + region["width"] > width or region["y"] + region["height"] > height:
            continue
        if all(_iou(region, other) < 0.85 for other in kept):
            kept.append(region)
        if len(kept) >= MAX_REGIONS:
            break
    return kept
