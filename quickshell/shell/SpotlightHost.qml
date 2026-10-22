pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.components

PanelWindow {
    id: window
    required property var services
    readonly property var spotlight: services.spotlight
    readonly property bool emojiMode: spotlight.page === 'results' && /^\s*:/.test(spotlight.query)
    property int focusGeneration: 0
    screen: Quickshell.screens.find(screen => screen.name === spotlight.outputName) || null
    visible: spotlight.visible
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    color: 'transparent'
    WlrLayershell.namespace: 'pentad-spotlight'
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onVisibleChanged: {
        services.popups.hostVisibility('spotlight', visible);
        const generation = ++focusGeneration;
        if (visible) Qt.callLater(() => {
            if (window.visible && generation === window.focusGeneration) search.forceActiveFocus();
        });
    }
    Component.onDestruction: services.popups.hostVisibility('spotlight', false)

    function iconSource(name) {
        name = name || '';
        if (name.startsWith('/') || name.startsWith('file:')) return name;
        return Quickshell.iconPath(name || 'application-x-executable', true)
            || Quickshell.iconPath('application-x-executable');
    }
    function handleKey(event) {
        const ctrl = !!(event.modifiers & Qt.ControlModifier);
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        const alt = !!(event.modifiers & Qt.AltModifier);
        if (event.key === Qt.Key_Escape) { if (!spotlight.back()) spotlight.close(); }
        else if (ctrl && event.key === Qt.Key_K) spotlight.showActions();
        else if (ctrl && event.key === Qt.Key_Space) spotlight.showDetails();
        else if (ctrl && shift && event.key === Qt.Key_P) spotlight.pin();
        else if (ctrl && event.key === Qt.Key_Delete && spotlight.selectedResult?.category === 'clipboard') spotlight.activate(undefined, true);
        else if (ctrl && event.key === Qt.Key_C && !search.selectedText
            && ['calc', 'emoji', 'clipboard'].includes(spotlight.selectedResult?.category)) spotlight.activate(undefined, false, true);
        else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9
            && !spotlight.pending && event.key - Qt.Key_1 < spotlight.results.length) spotlight.activate(event.key - Qt.Key_1);
        else if (emojiMode && !ctrl && !shift && !alt
            && [Qt.Key_Down, Qt.Key_Up].includes(event.key))
            emojiGrid.move(event.key === Qt.Key_Down ? 'down' : 'up');
        else if (emojiMode && !ctrl && !shift && !alt && !search.selectedText
            && search.cursorPosition === search.length
            && [Qt.Key_Left, Qt.Key_Right].includes(event.key))
            emojiGrid.move(event.key === Qt.Key_Left ? 'left' : 'right');
        else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) spotlight.move(1);
        else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) spotlight.move(-1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (spotlight.page === 'actions') spotlight.runAction(spotlight.actions[spotlight.actionIndex]?.id);
            else spotlight.activate();
        } else return;
        event.accepted = true;
    }
    MouseArea { anchors.fill: parent; onClicked: window.spotlight.close() }
    Item {
        id: dock
        readonly property real inset: width < 480 ? 20 : 28
        width: Math.max(1, Math.min(720, window.width - 32))
        height: body.y + body.height + (message.visible ? 48 : 24)
        anchors.horizontalCenter: parent.horizontalCenter
        containmentMask: glassSurface
        y: Math.min(window.height / 8, Math.max(12, window.services.config.documents.layout.barHeight + 24))
        Keys.onPressed: event => window.handleKey(event)
        ContinuousSurface {
            id: glassSurface
            anchors.fill: parent
            fill: Qt.alpha(Qt.tint(Theme.tokens.surfaceRaised, Qt.alpha(Theme.tokens.text, 0.025)), 0.97)
            edge: Qt.alpha(Theme.tokens.text, 0.16)
            extent: 24; clipContent: false
            castsShadow: true
        }
        Rectangle {
            x: 32; y: 0; width: Math.max(0, parent.width - 64); height: 1
            color: Qt.alpha(Theme.tokens.text, 0.1)
        }
        MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }
        ToolButton {
            id: home
            x: dock.inset; y: 24; width: 32; height: 40
            focusPolicy: Qt.NoFocus
            Accessible.name: window.services.text('Застосунки', 'Applications')
            onClicked: { window.spotlight.runAction('mode-app'); search.forceActiveFocus(); }
            background: Item {}
            contentItem: Item {
                PentadIcon {
                    anchors.centerIn: parent; pixelSize: 20
                    source: Qt.resolvedUrl('../assets/icons/material/media/search-symbolic.svg')
                    color: Theme.tokens.textMuted
                }
            }
        }
        PentadTextField {
            id: search
            x: dock.inset + (dock.width < 360 ? 32 : 44); y: 22
            width: Math.max(0, parent.width - x - dock.inset - (dock.width < 360 ? 112 : 132)); height: 44
            leftPadding: 0; rightPadding: 0
            font.pixelSize: dock.width < 360 ? 20 : 22
            placeholderText: window.services.text('Пошук…', 'Search…')
            text: window.spotlight.query; maximumLength: 256
            background: Item {}
            onTextEdited: window.spotlight.query = text
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => window.handleKey(event)
        }
        ToolButton {
            id: clipboardMode
            readonly property bool selected: window.spotlight.query.trim() === 'cb' || window.spotlight.query.trim().startsWith('cb ')
            anchors.right: parent.right; anchors.rightMargin: dock.inset + (dock.width < 360 ? 72 : 84)
            y: 26; width: dock.width < 360 ? 32 : 36; height: 36
            focusPolicy: Qt.NoFocus
            Accessible.name: window.services.text('Буфер обміну', 'Clipboard')
            ToolTip.visible: hovered
            ToolTip.text: Accessible.name
            onClicked: { window.spotlight.runAction('mode-clipboard'); search.forceActiveFocus(); }
            background: ContinuousSurface {
                extent: 12; clipContent: false
                fill: Qt.alpha(Theme.tokens.accent, clipboardMode.selected ? 0.13 : clipboardMode.hovered ? 0.06 : 0)
            }
            contentItem: PentadIcon {
                anchors.centerIn: parent; pixelSize: 20
                source: Qt.resolvedUrl('../assets/icons/spotlight/clipboard.svg')
                color: clipboardMode.selected ? Theme.tokens.accent : Theme.tokens.textMuted
            }
        }
        ToolButton {
            id: emojiModeButton
            readonly property bool selected: window.spotlight.query.trim().startsWith(':')
            anchors.right: parent.right; anchors.rightMargin: dock.inset + (dock.width < 360 ? 36 : 42)
            y: 26; width: dock.width < 360 ? 32 : 36; height: 36
            focusPolicy: Qt.NoFocus
            Accessible.name: window.services.text('Емодзі', 'Emoji')
            ToolTip.visible: hovered
            ToolTip.text: Accessible.name
            onClicked: { window.spotlight.runAction('mode-emoji'); search.forceActiveFocus(); }
            background: ContinuousSurface {
                extent: 12; clipContent: false
                fill: Qt.alpha(Theme.tokens.accent, emojiModeButton.selected ? 0.13 : emojiModeButton.hovered ? 0.06 : 0)
            }
            contentItem: PentadIcon {
                anchors.centerIn: parent; pixelSize: 20
                source: Qt.resolvedUrl('../assets/icons/spotlight/emoji.svg')
                color: emojiModeButton.selected ? Theme.tokens.accent : Theme.tokens.textMuted
            }
        }
        ToolButton {
            id: menu
            anchors.right: parent.right; anchors.rightMargin: dock.inset
            y: 26; width: dock.width < 360 ? 32 : 36; height: 36
            focusPolicy: Qt.NoFocus
            Accessible.name: window.services.text('Режими та дії', 'Modes and actions')
            ToolTip.visible: hovered
            ToolTip.text: Accessible.name
            onClicked: { window.spotlight.showActions(); search.forceActiveFocus(); }
            background: ContinuousSurface {
                extent: 12; clipContent: false
                fill: Qt.alpha(Theme.tokens.accent, menu.hovered ? 0.06 : 0)
            }
            contentItem: Item {
                Row {
                    anchors.centerIn: parent; spacing: 3
                    Repeater { model: 3; Rectangle { width: 3; height: 3; radius: 1.5; color: menu.hovered ? Theme.tokens.text : Theme.tokens.textMuted } }
                }
            }
        }
        Rectangle {
            x: dock.inset; y: 84; width: parent.width - 2 * x; height: 1
            color: Qt.alpha(Theme.tokens.text, 0.07)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40; height: 1
                visible: window.spotlight.pending
                color: Theme.tokens.accent
            }
        }
        Item {
            id: body
            x: dock.inset; y: 104; width: Math.max(0, parent.width - 2 * x)
            height: Math.max(0, Math.min(window.height - dock.y - y - (message.visible ? 60 : 36),
                window.spotlight.page === 'details' ? 320 : window.spotlight.page === 'actions'
                ? window.spotlight.actions.length * 44
                : window.emojiMode ? emojiGrid.implicitHeight
                : Math.max(120, Math.min(416, window.spotlight.results.length * 52 + 16))))
            SpotlightEmojiGrid {
                id: emojiGrid
                anchors.fill: parent
                visible: window.emojiMode
                spotlight: window.spotlight
                services: window.services
            }
            ListView {
                id: list
                anchors.fill: parent; clip: true
                visible: window.spotlight.page === 'results' && !window.emojiMode
                model: window.spotlight.results
                currentIndex: window.spotlight.selectedIndex
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool section: index > 0
                        && window.spotlight.group(modelData) !== window.spotlight.group(window.spotlight.results[index - 1])
                    readonly property bool selected: index === window.spotlight.selectedIndex
                    width: list.width; height: 52 + (section ? 12 : 0)
                    Rectangle {
                        x: 44; y: 5; width: parent.width - 56; height: 1
                        visible: entry.section; color: Qt.alpha(Theme.tokens.text, 0.06)
                    }
                    ItemDelegate {
                        id: row
                        y: entry.section ? 12 : 0; width: parent.width; height: 52
                        hoverEnabled: true; focusPolicy: Qt.NoFocus
                        Accessible.name: entry.modelData.title
                        Accessible.description: (window.spotlight.history.pinned.includes(entry.modelData.id)
                            ? window.services.text('Закріплено. ', 'Pinned. ') : '') + (entry.modelData.subtitle || '')
                        enabled: !window.spotlight.pending
                        leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                        onClicked: window.spotlight.activate(entry.index)
                        onHoveredChanged: if (hovered && !window.spotlight.pending) window.spotlight.selectedIndex = entry.index
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: { window.spotlight.selectedIndex = entry.index; window.spotlight.showActions(); search.forceActiveFocus(); }
                        }
                        contentItem: Item {
                            Rectangle {
                                width: 2; height: 18; radius: 1
                                anchors.verticalCenter: parent.verticalCenter
                                visible: entry.selected; color: Theme.tokens.accent
                            }
                            PentadIcon {
                                x: 12; anchors.verticalCenter: parent.verticalCenter; pixelSize: 22
                                visible: entry.modelData.category !== 'emoji' && entry.modelData.category !== 'calc'
                                source: window.iconSource(entry.modelData.category === 'clipboard' ? 'edit-paste-symbolic'
                                    : entry.modelData.category === 'web' ? 'web-browser-symbolic' : entry.modelData.icon)
                                symbolic: true
                                preserveLuminance: entry.modelData.category === 'app'
                                color: Qt.alpha(Theme.tokens.text, entry.selected ? 0.9 : 0.55)
                            }
                            PentadText {
                                x: 12; width: 22; anchors.verticalCenter: parent.verticalCenter
                                visible: entry.modelData.category === 'emoji' || entry.modelData.category === 'calc'
                                text: entry.modelData.category === 'emoji' ? entry.modelData.preview.content : '='
                                font.pixelSize: 22; color: Theme.tokens.textMuted
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Column {
                                x: 48; anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - 80)
                                PentadText {
                                    width: parent.width; text: entry.modelData.title
                                    font.weight: entry.selected ? Font.Medium : Font.Normal
                                    font.pixelSize: 16
                                    solid: true
                                    color: entry.selected ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.76)
                                    textFormat: Text.PlainText; wrapMode: Text.NoWrap; elide: Text.ElideRight
                                }
                                PentadText {
                                    width: parent.width; text: entry.modelData.subtitle || ''
                                    visible: entry.selected && text.length > 0
                                    textFormat: Text.PlainText
                                    role: 'caption'; solid: true; color: Theme.tokens.textMuted
                                    wrapMode: Text.NoWrap; elide: Text.ElideRight
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4; height: 4; radius: 2
                                visible: window.spotlight.history.pinned.includes(entry.modelData.id)
                                color: Theme.tokens.accent
                            }
                        }
                        background: ContinuousSurface {
                            extent: 12; clipContent: false
                            fill: Qt.alpha(Theme.tokens.accent, entry.selected ? 0.08 : 0)
                        }
                    }
                }
                PentadText {
                    anchors.centerIn: parent; width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    visible: list.count === 0 && !window.spotlight.searchPending
                    text: window.services.text('Нічого не знайдено', 'No results')
                    color: Theme.tokens.textMuted
                }
            }
            ListView {
                id: commands
                anchors.fill: parent; clip: true
                visible: window.spotlight.page === 'actions'
                model: window.spotlight.actions
                currentIndex: window.spotlight.actionIndex
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: ItemDelegate {
                    id: action
                    required property var modelData
                    required property int index
                    width: commands.width; height: 44
                    focusPolicy: Qt.NoFocus
                    Accessible.name: modelData.label
                    enabled: !window.spotlight.pending || modelData.id.startsWith('mode-')
                    onClicked: window.spotlight.runAction(modelData.id)
                    contentItem: Row {
                        spacing: 16
                        PentadText { width: parent.width - shortcut.implicitWidth - 16; text: action.modelData.label; textFormat: Text.PlainText }
                        PentadText {
                            id: shortcut; text: action.modelData.shortcut
                            role: 'caption'; color: Theme.tokens.textMuted
                            opacity: action.index === window.spotlight.actionIndex || action.hovered ? 1 : 0
                        }
                    }
                    background: Item {
                        Rectangle {
                            width: 2; height: 16; radius: 1
                            anchors.verticalCenter: parent.verticalCenter
                            visible: action.index === window.spotlight.actionIndex
                            color: Theme.tokens.accent
                        }
                    }
                }
            }
                Flickable {
                    id: details
                    anchors.fill: parent; clip: true
                    visible: window.spotlight.page === 'details'
                    contentWidth: width; contentHeight: detailContent.implicitHeight + 24
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Column {
                        id: detailContent
                        x: 16; y: 12; width: parent.width - 32; spacing: 12
                        PentadText {
                            width: parent.width; text: window.spotlight.selectedResult?.title || ''
                            role: 'title'; textFormat: Text.PlainText
                        }
                        Image {
                            width: parent.width; height: 200; visible: source.toString().length > 0
                            source: window.spotlight.previewImage
                            fillMode: Image.PreserveAspectFit; cache: false
                        }
                        PentadText {
                            width: parent.width; text: window.spotlight.selectedResult?.preview?.content || ''
                            textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
                            font.pixelSize: window.spotlight.selectedResult?.category === 'calc' ? 28 : Metrics.textBody
                        }
                        Repeater {
                            model: Object.entries(window.spotlight.selectedResult?.preview?.metadata || {})
                            delegate: Row {
                                required property var modelData
                                width: detailContent.width; spacing: 12
                                PentadText { width: 100; text: parent.modelData[0]; role: 'caption'; color: Theme.tokens.textMuted; textFormat: Text.PlainText }
                                PentadText { width: parent.width - 112; text: parent.modelData[1]; role: 'caption'; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere }
                            }
                        }
                    }
                }
            }
        PentadText {
            id: message
            x: body.x; y: body.y + body.height + 12; width: body.width
            height: visible ? 20 : 0
            visible: !!(window.spotlight.error || window.spotlight.status)
            text: window.spotlight.error || window.spotlight.status
            role: 'caption'; color: window.spotlight.error ? Theme.tokens.error : Theme.tokens.textMuted
            wrapMode: Text.NoWrap; elide: Text.ElideRight
        }
    }
    HyprlandFocusGrab {
        active: window.visible; windows: [window]
        onCleared: if (window.visible) window.spotlight.close()
    }
}
