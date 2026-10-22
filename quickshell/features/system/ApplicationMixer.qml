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
    implicitHeight: Math.min(320, header.implicitHeight + 8 + Math.min(272, Math.max(44, streamColumn.implicitHeight)))
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
        spacing: 8

        Row {
            id: header
            width: parent.width
            height: implicitHeight
            spacing: 8
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
                spacing: 6
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
                        objectName: "mixer-stream-" + streamId
                        width: streamColumn.width
                        height: subtitle !== "" || (root.localErrors[streamId] || "") !== "" ? 84 : 68
                        Accessible.role: Accessible.Grouping
                        Accessible.name: title

                        Row {
                            id: titleRow
                            x: 0; y: 2
                            width: parent.width
                            height: streamRow.subtitle !== "" ? 28 : 22
                            spacing: 8
                            PentadIcon {
                                source: root.iconFor(streamRow.streamData)
                                pixelSize: Metrics.panelIcon
                                color: Theme.tokens.textMuted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                width: parent.width - 74
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0
                                PentadText {
                                    width: parent.width
                                    text: streamRow.title
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    role: "body"
                                    solid: true
                                }
                                PentadText {
                                    visible: streamRow.subtitle !== ""
                                    width: parent.width
                                    text: streamRow.subtitle
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    role: "caption"
                                    solid: true
                                    color: Theme.tokens.textMuted
                                }
                            }
                            PentadButton {
                                objectName: "mixer-mute-" + streamRow.streamId
                                width: Metrics.controlMedium
                                controlHeight: Metrics.controlMedium
                                anchors.verticalCenter: parent.verticalCenter
                                accessibleName: root.tr(streamRow.streamData.muted ? "Увімкнути звук: " : "Вимкнути звук: ",
                                    streamRow.streamData.muted ? "Unmute " : "Mute ") + streamRow.title
                                requestedEnabled: !root.unavailable && !streamRow.streamData.pendingMute
                                checked: !!streamRow.streamData.muted
                                contentItem: PentadIcon {
                                    source: Qt.resolvedUrl("../../assets/icons/material/" + (streamRow.streamData.muted
                                        ? "volume-off-symbolic.svg" : "volume-up-symbolic.svg")).toString()
                                    pixelSize: Metrics.panelIcon
                                    color: parent.enabled ? Theme.tokens.text : Theme.tokens.textMuted
                                    Accessible.ignored: true
                                }
                                onPressed: root.requestMute(streamRow.streamId)
                            }
                        }

                        Row {
                            id: volumeRow
                            x: 0; y: streamRow.subtitle !== "" ? 32 : 24
                            width: parent.width
                            height: 34
                            spacing: 8
                            PentadRangeControl {
                                id: volumeControl
                                objectName: "mixer-volume-" + streamRow.streamId
                                width: parent.width - valueLabel.implicitWidth - 14
                                height: parent.height
                                presentation: "range-horizontal"
                                definition: ({
                                    label: root.tr("Гучність: ", "Volume: ") + streamRow.title,
                                    capabilities: { range: { from: 0, to: 1, step: 0.01, action: "stream-volume", unit: "%", scale: 100 } }
                                })
                                controlState: ({
                                    available: !root.unavailable,
                                    value: streamRow.streamData.pendingVolume ? Number(streamRow.streamData.requestedVolume)
                                        : Number(streamRow.streamData.volume),
                                    confirmedValue: Number(streamRow.streamData.volume),
                                    pending: !!streamRow.streamData.pendingVolume,
                                    error: root.localErrors[streamRow.streamId] || ""
                                })
                                Accessible.name: root.tr("Гучність: ", "Volume: ") + streamRow.title
                                Component.onCompleted: slider.objectName = objectName
                                onCommandRequested: function(action, value) { root.requestVolume(streamRow.streamId, value) }
                            }
                            PentadText {
                                id: valueLabel
                                width: implicitWidth
                                text: Math.round(Math.max(0, Math.min(1, streamRow.streamData.pendingVolume
                                    ? Number(streamRow.streamData.requestedVolume) : Number(streamRow.streamData.volume))) * 100) + "%"
                                role: "caption"
                                color: Theme.tokens.textMuted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        PentadText {
                            visible: (root.localErrors[streamRow.streamId] || "") !== ""
                            x: 0; y: streamRow.subtitle !== "" ? 66 : 60
                            width: parent.width
                            text: root.localErrors[streamRow.streamId] || ""
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
