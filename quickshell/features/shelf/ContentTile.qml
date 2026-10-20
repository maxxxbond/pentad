import QtQuick
import QtQuick.Controls.Basic
import qs.components
import qs.theme

FileTile {
    id: root
    property var downloadState: ({})
    readonly property alias notePopup: note
    readonly property string localUri: entry.localUri || ''
    readonly property bool hasSecondaryAction: entry.kind === 'image' || entry.kind === 'spotify'
    readonly property string secondaryLabel: entry.kind === 'spotify' ? 'Loader · soon'
        : downloadState.pending ? 'Downloading…' : localUri ? 'Open file'
        : downloadState.error ? 'Retry download' : 'Download'
    readonly property bool secondaryEnabled: !readOnly && !downloadState.pending && entry.kind !== 'spotify'
    signal downloadRequested(string id)
    previewObjectName: 'shelf-content-preview-' + entry.id
    previewOverride: entry.kind === 'image' && !readOnly ? localUri || entry.previewUrl : ''
    fileInfo: ({ iconNames: entry.kind === 'text' ? ['text-x-generic-symbolic']
        : entry.kind === 'spotify' ? ['audio-x-generic-symbolic'] : ['web-browser-symbolic'], iconSymbolic: true })
    typeLabel: downloadState.error ? tr('Помилка завантаження', 'Download failed') : downloadState.pending ? tr('Завантаження…', 'Downloading…')
        : entry.kind === 'text' ? tr('Нотатка', 'Text note') : entry.kind === 'spotify' ? 'Spotify'
        : entry.kind === 'image' && localUri ? tr('Збережене фото', 'Saved image') : entry.uri.replace(/^https?:\/\//, '').split('/')[0]
    showFallbackIcon: entry.kind === 'image'
    exportUris: entry.kind === 'text' ? [] : [localUri || entry.uri]
    exportData: entry.kind === 'text' ? ({ 'text/plain': entry.text })
        : ({ 'text/uri-list': (localUri || entry.uri) + '\r\n', 'text/plain': localUri || entry.uri })
    openAction: () => {
        if (entry.kind === 'text') note.open();
        else root.openRequested(localUri || entry.uri);
    }
    function performSecondary() {
        if (!secondaryEnabled) return false;
        if (localUri) openRequested(localUri);
        else downloadRequested(entry.id);
        return true;
    }
    Rectangle {
        x: (parent.width - width) / 2; y: 12; width: 68; height: 76; radius: 5
        visible: root.entry.kind === 'text'
        color: Qt.alpha(Theme.tokens.text, 0.08)
        Text {
            anchors.fill: parent; anchors.margins: 8
            text: root.entry.text || ''; textFormat: Text.PlainText
            font.family: Theme.tokens.fontFamily; font.pixelSize: 9
            color: Theme.tokens.textMuted
            wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
        }
    }
    Rectangle {
        x: (parent.width - width) / 2; y: 22; width: 56; height: 56; radius: 12
        visible: root.entry.kind === 'link' || root.entry.kind === 'spotify'
        color: Qt.alpha(Theme.tokens.accent, 0.12)
        Text {
            visible: root.entry.kind === 'link'; anchors.centerIn: parent
            text: root.entry.uri.replace(/^https?:\/\/(?:www\.)?/, '').charAt(0).toUpperCase()
            font.family: Theme.tokens.fontFamily; font.pixelSize: 26; font.weight: Font.Medium
            color: Theme.tokens.textMuted
        }
        PentadIcon {
            visible: root.entry.kind === 'spotify'; anchors.centerIn: parent
            source: Qt.resolvedUrl('../../assets/icons/material/media/music-note-symbolic.svg')
            pixelSize: 28; color: Theme.tokens.accent
        }
    }
    PentadPopup {
        id: note
        objectName: 'shelf-note-' + root.entry.id
        parent: Overlay.overlay
        implicitWidth: Math.min(420, (parent ? parent.width : 440) - 32)
        implicitHeight: 300
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        modal: true
        contentItem: PentadScrollView {
            TextArea {
                objectName: 'shelf-note-text-' + root.entry.id
                text: root.entry.text || ''; textFormat: TextEdit.PlainText
                readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                color: Theme.tokens.text; font.family: Theme.tokens.fontFamily; font.pixelSize: 14
                background: null
            }
        }
    }
}
