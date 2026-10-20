export function telemetryLayout(count, availableWidth) {
    if (!Number.isInteger(count) || count < 4)
        throw new TypeError("Telemetry requires at least four metric slots");
    const columns = count === 4 ? 2 : 3;
    const width = availableWidth === undefined ? columns * 80 + (columns - 1) * 8 : availableWidth;
    if (!Number.isFinite(width) || width < 0)
        throw new TypeError("Telemetry width must be finite and nonnegative");
    const gap = Math.min(8, width / (columns - 1));
    const cellWidth = (width - (columns - 1) * gap) / columns;
    const rows = Math.ceil(count / columns);
    const cells = Array.from({ length: count }, (_, slot) => {
        const row = Math.floor(slot / columns);
        const rowCount = Math.min(columns, count - row * columns);
        return {
            x: (width - rowCount * cellWidth - (rowCount - 1) * gap) / 2 + (slot % columns) * (cellWidth + gap),
            y: row * 104,
            width: cellWidth,
            height: 96,
        };
    });
    return { columns, width, height: rows * 96 + (rows - 1) * 8, cells };
}
