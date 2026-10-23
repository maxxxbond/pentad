import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

// The line at the bottom of the Stash: Enter keeps the draft as a note (or a link, when it is
// one), Shift+Enter starts a new line, and "+" opens the desktop's file chooser. The draft lives
// in services.stash, so it survives a switch between the overlay and the window.
Item {
    id: root
    required property var services
    property string pendingId: ''
    readonly property alias input: field
    implicitHeight: Math.max(add.height, field.implicitHeight)

    function submit() {
        const draft = root.services.stash.draft;
        if (!draft.trim() || root.pendingId) return false;
        root.pendingId = root.services.shelf.addNote(draft) || '';
        return root.pendingId !== '';
    }

    // The overlay is a layer above normal windows and would cover the portal chooser, so it
    // steps aside while the chooser is open. Locals keep the callback valid if this view is gone.
    function pickFiles() {
        const stash = root.services.stash, shelf = root.services.shelf;
        const overlay = stash.mode === 'overlay';
        if (overlay) stash.hide();
        const started = root.services.filePicker.pick({
            title: root.services.text('Додати у Сховок', 'Add to Stash'),
            multiple: true,
            done: function(result) {
                if (overlay) stash.show();
                if (result && result.ok && result.uris && result.uris.length)
                    shelf.addUris(Array.prototype.slice.call(result.uris));
            }
        });
        if (!started && overlay) stash.show();
        return started;
    }

    Connections {
        target: root.services.shelf
        function onCommandFinished(requestId, result) {
            if (requestId !== root.pendingId) return;
            root.pendingId = '';
            if (result.ok) root.services.stash.draft = '';
        }
    }

    TextArea {
        id: field
        objectName: 'stash-composer-input'
        // TextArea has no visualFocus: the edge follows focus that arrived from the keyboard.
        readonly property bool keyboardFocus: activeFocus && (focusReason === Qt.TabFocusReason
            || focusReason === Qt.BacktabFocusReason || focusReason === Qt.ShortcutFocusReason)
        anchors.left: parent.left
        anchors.right: add.left
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        implicitHeight: Math.min(Math.max(36, contentHeight + topPadding + bottomPadding), 116)
        text: root.services.stash.draft
        onTextChanged: if (root.services.stash.draft !== text) root.services.stash.draft = text
        placeholderText: root.services.text('Нотатка або посилання', 'Note or link')
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        color: Theme.tokens.text
        placeholderTextColor: Theme.tokens.textMuted
        selectionColor: Theme.tokens.accent
        selectedTextColor: Theme.tokens.surface
        font.family: Theme.tokens.fontFamily
        font.pixelSize: Metrics.textBody
        leftPadding: 12
        rightPadding: 12
        topPadding: 8
        bottomPadding: 8
        Accessible.name: placeholderText
        Keys.onPressed: event => {
            if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return;
            if (event.modifiers & Qt.ShiftModifier) return;
            root.submit();
            event.accepted = true;
        }
        // Same surface as PentadTextField, at the 8 px field radius; the edge only for keyboard focus.
        background: ContinuousSurface {
            fill: field.activeFocus ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.text, 0.06))
                : field.hovered ? Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.text, 0.05)) : Theme.tokens.surfaceRaised
            edge: field.keyboardFocus ? Theme.tokens.accent : 'transparent'
            extent: Metrics.radiusMedium
        }
    }
    PentadButton {
        id: add
        objectName: 'stash-composer-add'
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 36
        controlHeight: 36
        iconSize: Metrics.statusIcon
        iconSource: Qt.resolvedUrl('../../assets/icons/material/controls/add-symbolic.svg')
        accessibleName: root.services.text('Додати файли', 'Add files')
        requestedEnabled: !root.services.filePicker.busy
        onClicked: root.pickFiles()
    }
}
