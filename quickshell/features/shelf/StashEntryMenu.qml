import QtQuick
import qs.components
import "../../logic/shelf.mjs" as ShelfLogic

// The menu of one Stash entry, shared by the Stash window and the Activity menu's Stash tab. It
// lists what applies to the entry; each host handles the chosen action itself (activated).
PentadMenu {
    id: menu
    required property var services
    property bool writable: false
    property string entryId: ''
    readonly property var shelf: services.shelf
    readonly property var entry: shelf.entries.find(item => item.id === entryId) || null

    // Opened at a click, not under an anchor: its bounds are window-local, which the cursor
    // poll's output coordinates never match, so leaving-by-pointer would close it at once.
    pointerDismiss: false
    width: 210
    entries: {
        if (!entry) return [];
        const local = ShelfLogic.shelfLocalUri(entry);
        const info = local ? shelf.files.metadata[local] : undefined;
        const download = shelf.downloads[entry.id];
        const result = [{ text: services.text('Відкрити', 'Open'), action: 'open', enabled: !(info && info.available === false) },
            { text: services.text('Копіювати', 'Copy'), action: 'copy' },
            { text: entry.pinned ? services.text('Відкріпити', 'Unpin') : services.text('Закріпити', 'Pin'), action: 'pin', enabled: writable }];
        if (local) result.push({ text: services.text('Показати теку', 'Show folder'), action: 'folder' });
        if (entry.kind === 'image' && !entry.localUri)
            result.push({ text: services.text('Завантажити', 'Download'), action: 'download', enabled: writable && !(download && download.pending) });
        result.push({ separator: true });
        // A clipboard image the Stash saved itself goes with its entry; everything else is a reference.
        result.push({ text: services.text('Прибрати', 'Remove'), action: 'remove', enabled: writable,
            description: entry.owned === true
                ? services.text('Прибрати зі Сховку й видалити збережену копію.', 'Remove from the Stash and delete the saved copy.')
                : services.text('Прибрати вибране зі Сховку. Оригінальні файли залишаться на диску.', 'Remove the selection from the Stash. Original files stay on disk.') });
        return result;
    }
}
