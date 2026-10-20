export function modelListHeight(entries, rowHeight = 30, separatorHeight = 9) {
    if (!entries || !Number.isFinite(entries.length) || entries.length < 0
        || Math.floor(entries.length) !== entries.length
        || !Number.isFinite(rowHeight) || rowHeight < 0
        || !Number.isFinite(separatorHeight) || separatorHeight < 0) return 0;
    let height = 0;
    for (let index = 0; index < entries.length; index++)
        height += entries[index] && entries[index].isSeparator ? separatorHeight : rowHeight;
    return height;
}
