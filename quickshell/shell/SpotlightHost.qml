pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.components
import '../logic/spotlight-providers.mjs' as Search

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
            && ['calc', 'emoji', 'clipboard', 'file'].includes(spotlight.selectedResult?.category)) spotlight.activate(undefined, false, true);
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
    // A circular icon button inside the search capsule; a state layer instead of an accent fill.
    component ModeButton: ToolButton {
        id: modeButton
        property url iconSource
        property bool selected: false
        property string label: ''
        width: 36; height: 36
        focusPolicy: Qt.NoFocus
        Accessible.name: label
        ToolTip.visible: hovered
        ToolTip.text: label
        background: ContinuousSurface {
            extent: height / 2; clipContent: false
            fill: Qt.alpha(Theme.tokens.text, modeButton.selected || modeButton.down ? 0.1 : modeButton.hovered ? 0.06 : 0)
        }
        contentItem: Item {
            PentadIcon {
                anchors.centerIn: parent; pixelSize: 20
                source: modeButton.iconSource
                color: modeButton.selected ? Theme.tokens.accent : modeButton.hovered ? Theme.tokens.text : Theme.tokens.textMuted
            }
        }
    }
    function kind(result) {
        return ({ app: services.text('Застосунок', 'Application'), calc: services.text('Обчислення', 'Calculation'),
            clipboard: services.text('Буфер обміну', 'Clipboard'), emoji: 'Emoji', web: services.text('Вебпошук', 'Web search'),
            file: result?.preview?.kind === 'folder' ? services.text('Тека', 'Folder') : services.text('Файл', 'File') })[result?.category] || '';
    }
    // The theme's full-colour mime icon, or '' when the theme has none and a bundled glyph stands in.
    function fileIcon(name) { return name ? Quickshell.iconPath(name, true) : ''; }
    function kindGlyph(kind) {
        return Qt.resolvedUrl('../assets/icons/spotlight/' + (kind === 'folder' ? 'folder' : kind === 'image' ? 'image' : 'file') + '.svg');
    }
    // A file:// URL for an absolute path; each segment is encoded so '#' or '?' in names stay literal.
    function fileUrl(path) { return 'file://' + path.split('/').map(encodeURIComponent).join('/'); }
    function modifiedText(ms) {
        if (!(ms > 0)) return '';
        const language = services.config.documents.interface?.language;
        return new Date(ms).toLocaleDateString(language ? Qt.locale(language) : Qt.locale(), Locale.ShortFormat);
    }
    HoverHandler { onHoveredChanged: window.spotlight.pointerHover(hovered) }
    MouseArea { anchors.fill: parent; onClicked: window.spotlight.close() }
    Item {
        id: dock
        readonly property bool narrow: width < 400
        width: Math.max(1, Math.min(800, window.width - 32))
        height: card.y + card.height
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.min(window.height / 8, Math.max(12, window.services.config.documents.layout.barHeight + 24))
        Keys.onPressed: event => window.handleKey(event)
        MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }
        ContinuousSurface {
            id: capsule
            objectName: 'spotlight-capsule'
            width: parent.width; height: 56
            fill: Theme.tokens.surfaceRaised
            extent: height / 2; clipContent: false
            castsShadow: true
            ToolButton {
                id: home
                x: 10; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36
                focusPolicy: Qt.NoFocus
                readonly property bool nested: window.spotlight.page !== 'results'
                Accessible.name: nested ? window.services.text('Назад', 'Back') : window.services.text('Застосунки', 'Applications')
                onClicked: {
                    if (!window.spotlight.back()) window.spotlight.runAction('mode-app');
                    search.forceActiveFocus();
                }
                background: ContinuousSurface {
                    extent: height / 2; clipContent: false
                    fill: Qt.alpha(Theme.tokens.text, home.down ? 0.1 : home.hovered ? 0.06 : 0)
                }
                contentItem: Item {
                    PentadIcon {
                        anchors.centerIn: parent; pixelSize: 20
                        source: Qt.resolvedUrl(home.nested ? '../assets/icons/material/media/arrow-back-symbolic.svg'
                            : '../assets/icons/material/media/search-symbolic.svg')
                        // The search glyph turns accent while results are on their way.
                        color: window.spotlight.pending && !home.nested ? Theme.tokens.accent
                            : home.hovered ? Theme.tokens.text : Theme.tokens.textMuted
                        Behavior on color { enabled: !Theme.tokens.reducedMotion; ColorAnimation { duration: Motion.short } }
                    }
                }
            }
            PentadTextField {
                id: search
                x: home.x + home.width + 6; anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, modes.x - x - 8); height: 44
                leftPadding: 0; rightPadding: 0
                font.pixelSize: dock.narrow ? Metrics.textSection : Metrics.textTitle
                placeholderText: window.services.text('Пошук застосунків, обчислення, емодзі…', 'Search apps, calculate, emoji…')
                text: window.spotlight.query; maximumLength: 256
                background: Item {}
                onTextEdited: window.spotlight.query = text
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => window.handleKey(event)
            }
            Row {
                id: modes
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                ModeButton {
                    label: window.services.text('Буфер обміну', 'Clipboard')
                    iconSource: Qt.resolvedUrl('../assets/icons/spotlight/clipboard.svg')
                    selected: window.spotlight.query.trim() === 'cb' || window.spotlight.query.trim().startsWith('cb ')
                    onClicked: { window.spotlight.runAction('mode-clipboard'); search.forceActiveFocus(); }
                }
                ModeButton {
                    label: window.services.text('Емодзі', 'Emoji')
                    iconSource: Qt.resolvedUrl('../assets/icons/spotlight/emoji.svg')
                    selected: window.spotlight.query.trim().startsWith(':')
                    onClicked: { window.spotlight.runAction('mode-emoji'); search.forceActiveFocus(); }
                }
                ModeButton {
                    label: window.services.text('Режими та дії', 'Modes and actions')
                    iconSource: Qt.resolvedUrl('../assets/icons/spotlight/more.svg')
                    selected: window.spotlight.page === 'actions'
                    onClicked: { window.spotlight.showActions(); search.forceActiveFocus(); }
                }
            }
        }
        ContinuousSurface {
            id: card
            objectName: 'spotlight-card'
            readonly property int pad: 8
            y: capsule.height + 8
            width: parent.width
            height: body.height + 2 * pad + (message.visible ? message.height + 4 : 0)
            fill: Theme.tokens.surfaceRaised
            extent: 24; clipContent: false
            castsShadow: true
            Item {
                id: body
                // The preview pane follows the selected result, as in macOS Spotlight; narrow outputs drop it.
                readonly property bool previewing: window.spotlight.page === 'results' && !window.emojiMode
                    && !!window.spotlight.selectedResult && width >= 600
                readonly property int paneWidth: 280
                x: card.pad; y: card.pad; width: Math.max(0, parent.width - 2 * x)
                height: Math.max(0, Math.min(window.height - dock.y - card.y - 2 * card.pad - (message.visible ? 24 : 0) - 16,
                    window.spotlight.page === 'details' ? 320 : window.spotlight.page === 'actions'
                    ? window.spotlight.actions.length * 40
                    : window.emojiMode ? emojiGrid.implicitHeight
                    : list.count === 0 ? 96 : Math.max(previewing ? 336 : 0, Math.min(432, list.contentHeight))))
                SpotlightEmojiGrid {
                    id: emojiGrid
                    anchors.fill: parent
                    visible: window.emojiMode
                    spotlight: window.spotlight
                    services: window.services
                }
                ListView {
                    id: list
                    width: body.previewing ? parent.width - body.paneWidth - 17 : parent.width
                    height: parent.height; clip: true
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
                        readonly property string group: window.spotlight.group(modelData)
                        readonly property bool section: group.length > 0
                            && (index === 0 || group !== window.spotlight.group(window.spotlight.results[index - 1]))
                        readonly property bool selected: index === window.spotlight.selectedIndex
                        readonly property bool pinned: window.spotlight.history.pinned.includes(modelData.id)
                        readonly property string themedIcon: modelData.category === 'file' ? window.fileIcon(modelData.icon) : ''
                        readonly property bool appIcon: modelData.category === 'app' || themedIcon.length > 0
                        width: list.width; height: 48 + (section ? header.height : 0)
                        PentadText {
                            id: header
                            x: 12; width: parent.width - 24
                            height: visible ? (entry.index === 0 ? 24 : 32) : 0
                            visible: entry.section
                            verticalAlignment: Text.AlignVCenter
                            topPadding: entry.index === 0 ? 0 : 8
                            text: entry.group; role: 'caption'; font.weight: Font.Medium
                            color: Theme.tokens.textMuted
                            textFormat: Text.PlainText; wrapMode: Text.NoWrap; elide: Text.ElideRight
                        }
                        ItemDelegate {
                            id: row
                            y: header.height; width: parent.width; height: 48
                            hoverEnabled: true; focusPolicy: Qt.NoFocus
                            Accessible.name: entry.modelData.title
                            Accessible.description: (entry.pinned ? window.services.text('Закріплено. ', 'Pinned. ') : '')
                                + (entry.modelData.subtitle || '')
                            enabled: !window.spotlight.pending
                            leftPadding: 8; rightPadding: 12; topPadding: 0; bottomPadding: 0
                            onClicked: window.spotlight.activate(entry.index)
                            onHoveredChanged: if (hovered && !window.spotlight.pending) window.spotlight.selectedIndex = entry.index
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: { window.spotlight.selectedIndex = entry.index; window.spotlight.showActions(); search.forceActiveFocus(); }
                            }
                            contentItem: Item {
                                // Application icons keep their colours; other kinds sit in a tonal circle.
                                ContinuousSurface {
                                    id: glyph
                                    width: 32; height: 32; anchors.verticalCenter: parent.verticalCenter
                                    extent: height / 2; clipContent: false
                                    fill: entry.appIcon ? 'transparent' : Qt.alpha(Theme.tokens.text, entry.selected ? 0.1 : 0.06)
                                    PentadIcon {
                                        anchors.centerIn: parent
                                        pixelSize: entry.appIcon ? 32 : 18
                                        visible: entry.modelData.category !== 'emoji' && entry.modelData.category !== 'calc'
                                        source: entry.modelData.category === 'clipboard' ? Qt.resolvedUrl('../assets/icons/spotlight/clipboard.svg')
                                            : entry.modelData.category === 'web' ? Qt.resolvedUrl('../assets/icons/material/media/search-symbolic.svg')
                                            : entry.modelData.category === 'file' ? entry.themedIcon || window.kindGlyph(entry.modelData.preview?.kind)
                                            : window.iconSource(entry.modelData.icon)
                                        symbolic: !entry.appIcon
                                        color: entry.selected ? Theme.tokens.text : Theme.tokens.textMuted
                                    }
                                    PentadText {
                                        anchors.centerIn: parent
                                        visible: entry.modelData.category === 'emoji' || entry.modelData.category === 'calc'
                                        text: entry.modelData.category === 'emoji' ? entry.modelData.preview.content : '='
                                        font.pixelSize: entry.modelData.category === 'emoji' ? Metrics.textTitle : Metrics.textSection
                                        font.weight: Font.Medium
                                        color: entry.selected ? Theme.tokens.text : Theme.tokens.textMuted
                                    }
                                }
                                Row {
                                    x: glyph.width + 12; anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, accessory.x - x - 12)
                                    spacing: 8
                                    PentadText {
                                        id: title
                                        width: Math.min(implicitWidth, parent.width)
                                        text: entry.modelData.title
                                        font.weight: entry.selected ? Font.Medium : Font.Normal
                                        color: entry.selected ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.86)
                                        textFormat: Text.PlainText; wrapMode: Text.NoWrap; elide: Text.ElideRight
                                    }
                                    PentadText {
                                        width: Math.max(0, parent.width - title.width - parent.spacing)
                                        // The description belongs to the selected row only: less text at rest.
                                        visible: width > 24 && text.length > 0
                                        text: entry.selected && !body.previewing && ['app', 'calc', 'emoji'].includes(entry.modelData.category)
                                            ? entry.modelData.subtitle || '' : ''
                                        color: Theme.tokens.textMuted
                                        textFormat: Text.PlainText; wrapMode: Text.NoWrap; elide: Text.ElideRight
                                    }
                                }
                                Row {
                                    id: accessory
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 4; height: 4; radius: 2
                                        visible: entry.pinned && !entry.selected
                                        color: Theme.tokens.accent
                                    }
                                    // The kind is shown only where the section title does not already say it.
                                    PentadText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: text.length > 0 && (!dock.narrow || entry.selected)
                                        text: entry.selected ? window.spotlight.primaryLabel(entry.modelData)
                                            : entry.group !== window.spotlight.group({ category: entry.modelData.category })
                                            ? window.kind(entry.modelData) : ''
                                        role: 'caption'; color: Theme.tokens.textMuted
                                        textFormat: Text.PlainText; wrapMode: Text.NoWrap
                                    }
                                    PentadIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: entry.selected
                                        pixelSize: 16
                                        source: Qt.resolvedUrl('../assets/icons/spotlight/return.svg')
                                        color: Theme.tokens.textMuted
                                    }
                                }
                            }
                            background: ContinuousSurface {
                                extent: Metrics.radiusRow; clipContent: false
                                fill: entry.selected ? Theme.tokens.surfaceOverlay : 'transparent'
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
                Rectangle {
                    x: list.width + 8; width: 1; height: parent.height
                    visible: body.previewing
                    color: Qt.alpha(Theme.tokens.text, 0.08)
                }
                Item {
                    id: pane
                    objectName: 'spotlight-preview'
                    readonly property var result: window.spotlight.selectedResult
                    readonly property string category: result?.category || ''
                    readonly property var preview: result?.preview || ({})
                    readonly property bool fileImage: category === 'file' && preview.kind === 'image' && preview.size >= 0 && preview.size < 64000000
                    readonly property string themedIcon: category === 'file' ? window.fileIcon(result.icon) : ''
                    readonly property bool fileIconShown: category === 'file' && (!fileImage || picture.status === Image.Error)
                    readonly property string imageSource: fileImage ? window.fileUrl(preview.path)
                        : category === 'clipboard' ? window.spotlight.selectionImage : ''
                    x: list.width + 17; width: body.paneWidth; height: parent.height
                    visible: body.previewing
                    Column {
                        x: 8; y: 16; width: parent.width - 16
                        spacing: 0
                        Item {
                            id: hero
                            width: parent.width; height: pane.category === 'calc' ? 72 : 168
                            ContinuousSurface {
                                id: thumbnail
                                anchors.fill: parent
                                visible: pane.imageSource.length > 0
                                extent: Metrics.radiusRow
                                fill: Qt.alpha(Theme.tokens.text, 0.06)
                                Image {
                                    id: picture
                                    anchors.fill: parent
                                    source: pane.imageSource
                                    sourceSize: Qt.size(560, 336)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; cache: false
                                }
                            }
                            ContinuousSurface {
                                anchors.fill: parent
                                visible: pane.category === 'clipboard' && pane.preview.type !== 'image'
                                extent: Metrics.radiusRow
                                fill: Qt.alpha(Theme.tokens.text, 0.06)
                                PentadText {
                                    x: 12; y: 12; width: parent.width - 24; height: parent.height - 24
                                    text: pane.preview.content || ''
                                    textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; elide: Text.ElideRight
                                    color: Qt.alpha(Theme.tokens.text, 0.86)
                                }
                            }
                            PentadText {
                                anchors.centerIn: parent; width: parent.width
                                visible: pane.category === 'calc'
                                horizontalAlignment: Text.AlignHCenter
                                text: pane.category === 'calc' ? pane.result.title : ''
                                role: 'title'; font.weight: Font.DemiBold
                                textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
                            }
                            ContinuousSurface {
                                anchors.centerIn: parent; width: 72; height: 72
                                visible: pane.category === 'web' || (pane.fileIconShown && !pane.themedIcon)
                                    || (pane.category === 'clipboard' && pane.preview.type === 'image' && picture.status !== Image.Ready)
                                extent: height / 2
                                fill: Qt.alpha(Theme.tokens.text, 0.06)
                                PentadIcon {
                                    anchors.centerIn: parent; pixelSize: 32
                                    source: pane.category === 'web' ? Qt.resolvedUrl('../assets/icons/material/media/search-symbolic.svg')
                                        : pane.category === 'file' ? window.kindGlyph(pane.preview.kind)
                                        : Qt.resolvedUrl('../assets/icons/spotlight/clipboard.svg')
                                    color: Theme.tokens.textMuted
                                }
                            }
                            PentadIcon {
                                anchors.centerIn: parent; pixelSize: 72
                                visible: pane.category === 'app' || (pane.fileIconShown && pane.themedIcon.length > 0)
                                symbolic: false
                                source: pane.category === 'app' ? window.iconSource(pane.result.icon) : pane.themedIcon
                            }
                        }
                        Item { width: 1; height: 16 }
                        PentadText {
                            width: parent.width
                            visible: pane.category !== 'calc' && pane.category !== 'clipboard'
                            horizontalAlignment: Text.AlignHCenter
                            text: pane.result?.title || ''
                            role: 'section'; font.weight: Font.Medium; solid: true
                            textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
                            maximumLineCount: 2; elide: Text.ElideRight
                        }
                        Item { width: 1; height: 4 }
                        PentadText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: pane.category === 'clipboard' ? window.kind(pane.result)
                                : pane.category === 'web' ? pane.preview.metadata?.Query || '' : pane.result?.subtitle || ''
                            color: Theme.tokens.textMuted
                            textFormat: Text.PlainText; wrapMode: Text.Wrap
                            maximumLineCount: 3; elide: Text.ElideRight
                        }
                        Item { width: 1; height: facts.visible ? 16 : 0 }
                        Rectangle { width: parent.width; height: 1; visible: facts.visible; color: Qt.alpha(Theme.tokens.text, 0.08) }
                        Column {
                            id: facts
                            readonly property var rows: pane.category !== 'file' ? [] : [
                                [window.services.text('Тип', 'Kind'), window.kind(pane.result)],
                                [window.services.text('Розмір', 'Size'), Search.formatFileSize(pane.preview.size,
                                    window.services.text('Б,КБ,МБ,ГБ,ТБ', 'B,KB,MB,GB,TB').split(','))],
                                [window.services.text('Змінено', 'Modified'), window.modifiedText(pane.preview.modified)]
                            ].filter(row => row[1].length > 0)
                            width: parent.width; topPadding: 8
                            visible: rows.length > 0
                            Repeater {
                                model: facts.rows
                                delegate: Item {
                                    required property var modelData
                                    width: facts.width; height: 24
                                    PentadText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData[0]; role: 'caption'; color: Theme.tokens.textMuted
                                        textFormat: Text.PlainText
                                    }
                                    PentadText {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, parent.width - 80)
                                        horizontalAlignment: Text.AlignRight
                                        text: parent.modelData[1]; role: 'caption'
                                        textFormat: Text.PlainText; wrapMode: Text.NoWrap; elide: Text.ElideLeft
                                    }
                                }
                            }
                        }
                    }
                }
                ListView {
                    id: commands
                    anchors.fill: parent; clip: true
                    visible: window.spotlight.page === 'actions'
                    model: window.spotlight.actions
                    currentIndex: window.spotlight.actionIndex
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: ItemDelegate {
                        id: action
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === window.spotlight.actionIndex
                        width: commands.width; height: 40
                        hoverEnabled: true; focusPolicy: Qt.NoFocus
                        Accessible.name: modelData.label
                        enabled: !window.spotlight.pending || modelData.id.startsWith('mode-')
                        leftPadding: 12; rightPadding: 12; topPadding: 0; bottomPadding: 0
                        onClicked: window.spotlight.runAction(modelData.id)
                        onHoveredChanged: if (hovered) window.spotlight.actionIndex = index
                        contentItem: Item {
                            PentadText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - shortcut.width - 16)
                                text: action.modelData.label
                                font.weight: action.selected ? Font.Medium : Font.Normal
                                color: action.selected ? Theme.tokens.text : Qt.alpha(Theme.tokens.text, 0.86)
                                textFormat: Text.PlainText; wrapMode: Text.NoWrap; elide: Text.ElideRight
                            }
                            PentadText {
                                id: shortcut
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: action.modelData.shortcut
                                role: 'caption'; color: Theme.tokens.textMuted
                                textFormat: Text.PlainText; wrapMode: Text.NoWrap
                                opacity: action.selected ? 1 : 0
                            }
                        }
                        background: ContinuousSurface {
                            extent: Metrics.radiusRow; clipContent: false
                            fill: action.selected ? Theme.tokens.surfaceOverlay : 'transparent'
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
                        x: 12; y: 12; width: parent.width - 24; spacing: 12
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
                            font.pixelSize: window.spotlight.selectedResult?.category === 'calc' ? Metrics.textTitle : Metrics.textBody
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
                x: body.x + 12; y: body.y + body.height + 4; width: body.width - 24
                height: visible ? 20 : 0
                visible: !!(window.spotlight.error || window.spotlight.status)
                verticalAlignment: Text.AlignVCenter
                text: window.spotlight.error || window.spotlight.status
                role: 'caption'; color: window.spotlight.error ? Theme.tokens.error : Theme.tokens.textMuted
                wrapMode: Text.NoWrap; elide: Text.ElideRight
            }
        }
    }
    HyprlandFocusGrab {
        active: window.visible; windows: [window]
        onCleared: if (window.visible) window.spotlight.close()
    }
}
