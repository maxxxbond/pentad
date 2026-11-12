pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import qs.components
import qs.theme

Item {
    id: root
    required property var services
    property string consumerId: "application-mixer"
    property bool presented: false
    // A host that titles the list itself, such as the bar's sound popup, hides the built-in header.
    property bool showHeader: true
    readonly property var audio: services && services.audio ? services.audio : null
    readonly property var audioState: audio && audio.state && audio.state.value ? audio.state.value : null
    readonly property var streams: audioState && Array.isArray(audioState.streams) ? audioState.streams : []
    readonly property bool unavailable: !audio || !audio.state || audio.state.kind !== "ready"
    readonly property alias listComponent: streamList
    property var streamIds: []
    property var localErrors: ({})
    property var pendingRequests: ({})
    property var latestRequests: ({})

    implicitWidth: 340
    implicitHeight: Math.min(320, (showHeader ? header.implicitHeight + 8 : 0) + Math.min(272, Math.max(44, streamColumn.implicitHeight)))
    Accessible.role: Accessible.Pane
    Accessible.name: tr("Гучність застосунків", "Application volume")

    function tr(uk, en) {
        return services && typeof services.text === "function" ? services.text(uk, en) : en
    }

    function titleFor(stream) {
        if (!stream) return tr("Невідомий потік", "Unknown stream")
        const app = String(stream.appName || "").trim()
        const label = String(stream.label || "").trim()
        const media = String(stream.mediaName || "").trim()
        return app || label || media || tr("Аудіопотік", "Audio stream")
    }

    function subtitleFor(stream) {
        const app = String(stream.appName || "").trim()
        const label = String(stream.label || "").trim()
        const media = String(stream.mediaName || "").trim()
        const values = []
        if (label && label !== app) values.push(label)
        if (media && media !== app && media !== label) values.push(media)
        return values.join(" · ")
    }

    function iconFor(stream) {
        const icon = String(stream && stream.icon || "")
        if (icon && Quickshell.hasThemeIcon(icon)) return Quickshell.iconPath(icon, true)
        return icon.includes(":") || icon.includes("/") ? icon
            : Qt.resolvedUrl("../../assets/icons/material/volume-up-symbolic.svg").toString()
    }

    function streamExists(id) {
        return streams.some(function(stream) { return String(stream.id) === id })
    }

    function requestVolume(id, value) {
        if (!audio || typeof audio.setStreamVolume !== "function" || !streamExists(id)) return
        const request = audio.setStreamVolume(id, value)
        if (request) recordRequest(request, id, "volume")
    }

    function requestMute(id) {
        if (!audio || typeof audio.toggleStreamMute !== "function" || !streamExists(id)) return
        const request = audio.toggleStreamMute(id)
        if (request) recordRequest(request, id, "mute")
    }

    function recordRequest(requestId, id, field) {
        const request = String(requestId), key = id + "\u0000" + field
        let errors = Object.assign({}, localErrors)
        delete errors[id]
        localErrors = errors
        pendingRequests = Object.assign({}, pendingRequests, { [request]: { id: id, field: field } })
        latestRequests = Object.assign({}, latestRequests, { [key]: request })
    }

    function syncConsumer() {
        const wanted = presented && visible && audio && consumerId
        if (heldAudio && (!wanted || heldAudio !== audio || heldConsumerId !== consumerId)) {
            if (typeof heldAudio.releaseMixer === "function") heldAudio.releaseMixer(heldConsumerId)
            heldAudio = null
            heldConsumerId = ""
        }
        if (wanted && !heldAudio && typeof audio.retainMixer === "function") {
            audio.retainMixer(consumerId)
            heldAudio = audio
            heldConsumerId = consumerId
        }
    }

    property var heldAudio: null
    property string heldConsumerId: ""
    onPresentedChanged: syncConsumer()
    onAudioChanged: syncConsumer()
    onConsumerIdChanged: syncConsumer()
    onVisibleChanged: syncConsumer()
    Component.onCompleted: { syncStreamIds(); syncConsumer() }
    Component.onDestruction: {
        if (heldAudio && typeof heldAudio.releaseMixer === "function")
            heldAudio.releaseMixer(heldConsumerId)
    }

    function syncStreamIds() {
        const next = streams.map(function(stream) { return String(stream.id) })
        if (next.length !== streamIds.length || next.some(function(id, index) { return id !== streamIds[index] }))
            streamIds = next
    }

    onStreamsChanged: {
        syncStreamIds()
        let errors = Object.assign({}, localErrors)
        let requests = Object.assign({}, pendingRequests)
        let latest = Object.assign({}, latestRequests)
        for (const id in errors) if (!streamExists(id)) delete errors[id]
        for (const request in requests) if (!streamExists(requests[request].id)) delete requests[request]
        for (const key in latest) if (!streamExists(key.slice(0, key.lastIndexOf("\u0000")))) delete latest[key]
        localErrors = errors
        pendingRequests = requests
        latestRequests = latest
    }

    Connections {
        target: root.audio
        ignoreUnknownSignals: true
        function onCommandFinished(requestId, result) {
            const request = String(requestId)
            if (!(request in root.pendingRequests)) return
            const entry = root.pendingRequests[request]
            const id = entry.id
            let requests = Object.assign({}, root.pendingRequests)
            delete requests[request]
            root.pendingRequests = requests
            const key = id + "\u0000" + entry.field
            if (root.latestRequests[key] !== request) return
            let latest = Object.assign({}, root.latestRequests)
            delete latest[key]
            root.latestRequests = latest
            if (!root.streamExists(id)) return
            let errors = Object.assign({}, root.localErrors)
            if (result && result.ok) delete errors[id]
            else errors[id] = result && (result.message || result.reason)
                ? String(result.message || result.reason) : root.tr("Не вдалося змінити потік", "Could not update stream")
            root.localErrors = errors
        }
    }

    Column {
        anchors.fill: parent
        spacing: Metrics.space2

        Row {
            id: header
            visible: root.showHeader
            width: parent.width
            height: implicitHeight
            spacing: Metrics.space2
            PentadIcon {
                source: Qt.resolvedUrl("../../assets/icons/material/volume-up-symbolic.svg").toString()
                pixelSize: Metrics.exposedIcon
                color: Theme.tokens.text
                anchors.verticalCenter: parent.verticalCenter
            }
            PentadText {
                text: root.tr("Гучність застосунків", "Application volume")
                role: "section"
                width: parent.width - 30
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        ScrollView {
            id: streamList
            objectName: "mixer-list"
            width: parent.width
            height: Math.min(272, Math.max(44, streamColumn.implicitHeight))
            clip: true
            contentWidth: availableWidth
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                id: streamColumn
                width: streamList.availableWidth
                spacing: Metrics.space1
                Repeater {
                    model: root.streamIds
                    delegate: Item {
                        id: streamRow
                        required property var modelData
                        readonly property string streamId: String(modelData)
                        readonly property var streamData: root.streams.find(function(stream) {
                            return String(stream.id) === streamRow.streamId
                        }) || ({})
                        readonly property string title: root.titleFor(streamData)
                        readonly property string subtitle: root.subtitleFor(streamData)
                        readonly property string errorText: root.localErrors[streamId] || ""
                        objectName: "mixer-stream-" + streamId
                        width: streamColumn.width
                        height: volumeControl.height + (errorText !== "" ? streamError.implicitHeight + 2 : 0)
                        Accessible.role: Accessible.Grouping
                        Accessible.name: title

                        // The row keeps its scrubber for the stream's lifetime id, so a passive snapshot never
                        // replaces the scrubber under a drag; the value follows the stream only while released.
                        // The application's own icon sits in the icon slot and is the mute button.
                        Item {
                            id: volumeControl
                            objectName: "mixer-volume-" + streamRow.streamId
                            readonly property alias slider: volumeSlider
                            readonly property real streamValue: Math.max(0, Math.min(1, streamRow.streamData.pendingVolume
                                ? Number(streamRow.streamData.requestedVolume) : Number(streamRow.streamData.volume))) || 0
                            width: parent.width
                            height: Metrics.controlLarge
                            PentadScrubber {
                                id: volumeSlider
                                objectName: volumeControl.objectName
                                anchors.fill: parent
                                relativeDrag: true
                                ticks: 0
                                from: 0
                                to: 1
                                stepSize: 0.01
                                wheelStepSize: 0.05
                                iconSource: root.iconFor(streamRow.streamData)
                                iconSymbolic: false
                                iconButton: true
                                iconButtonObjectName: "mixer-mute-" + streamRow.streamId
                                iconButtonEnabled: !root.unavailable && !streamRow.streamData.pendingMute
                                iconButtonName: root.tr(streamRow.streamData.muted ? "Увімкнути звук: " : "Вимкнути звук: ",
                                    streamRow.streamData.muted ? "Unmute " : "Mute ") + streamRow.title
                                onIconPressed: root.requestMute(streamRow.streamId)
                                muted: !!streamRow.streamData.muted
                                label: streamRow.title
                                valueText: Math.round(volumeControl.streamValue * 100) + "%"
                                confirmedValue: Number(streamRow.streamData.volume)
                                accessibleName: root.tr("Гучність: ", "Volume: ") + streamRow.title
                                enabled: !root.unavailable
                                Accessible.description: [streamRow.subtitle, streamRow.streamData.pendingVolume
                                    ? root.tr("Виконується", "In progress") : "", streamRow.errorText, valueText].filter(function (part) {
                                    return part !== "";
                                }).join(" · ")
                                onMoved: function(next) { root.requestVolume(streamRow.streamId, next) }
                                Binding {
                                    target: volumeSlider
                                    property: "value"
                                    value: volumeControl.streamValue
                                    when: !volumeSlider.held
                                    // Releasing the binding on press must not write the old value back.
                                    restoreMode: Binding.RestoreNone
                                }
                            }
                        }

                        PentadText {
                            id: streamError
                            visible: streamRow.errorText !== ""
                            x: Metrics.space4
                            y: volumeControl.height + 2
                            width: parent.width - Metrics.space4 * 2
                            text: streamRow.errorText
                            role: "caption"
                            color: Theme.tokens.error
                        }
                    }
                }

                Item {
                    visible: root.streams.length === 0
                    width: streamColumn.width
                    height: 44
                    PentadText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        text: root.unavailable
                            ? root.tr("Аудіо зараз недоступне", "Audio is unavailable")
                            : root.tr("Немає активних аудіопотоків", "No active audio streams")
                        role: "caption"
                        color: Theme.tokens.textMuted
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
