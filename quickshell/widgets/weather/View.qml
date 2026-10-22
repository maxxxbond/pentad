pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import qs.theme
import '../../logic/weather.mjs' as WeatherLogic

Item {
    id: root
    required property string instanceId
    required property var context
    required property var settings
    required property var services
    required property var controller
    readonly property var config: WeatherLogic.weatherConfig(settings)
    property var handle: null
    property string handleConfigKey: ''
    property var weatherState: ({ status: config ? 'loading' : 'setup', value: null, message: '' })
    property bool locationSearchOpen: false
    property string locationSaveRequestId: ''
    property string locationMessage: ''
    property bool locationSaveError: false
    width: 350
    implicitWidth: width
    implicitHeight: content.implicitHeight

    function detach() {
        if (!handle) return;
        if (root.services && root.services.weather) root.services.weather.release(handle);
        handle = null;
        handleConfigKey = '';
    }
    function attach() {
        if (!config) {
            detach();
            weatherState = { status: 'setup', value: null, message: '' };
            return;
        }
        if (!root.services || !root.services.weather) {
            detach();
            weatherState = { status: 'unavailable', value: null, message: 'Weather service is unavailable.' };
            return;
        }
        const nextKey = WeatherLogic.weatherKey(config);
        if (handle && handleConfigKey === nextKey) return;
        detach();
        handle = root.services.weather.acquire(config);
        handleConfigKey = handle ? nextKey : '';
        weatherState = handle ? root.services.weather.read(handle)
            : { status: 'unavailable', value: null, message: 'Weather service is unavailable.' };
    }
    function temperature(value) {
        return Math.round(value) + (settings.units === 'fahrenheit' ? '°F' : '°C');
    }
    function dateLabel(value) {
        const date = new Date(value + 'T12:00:00');
        return date.toLocaleDateString(Qt.locale().name, { weekday: 'short' });
    }
    function saveLocation(location) {
        if (locationSaveRequestId) return;
        if (!services || !services.config) {
            locationMessage = 'Settings service is unavailable.';
            locationSaveError = true;
            return;
        }
        if (services.preview || services.safeMode) {
            locationMessage = services.preview ? 'Preview is read only.' : 'Read only in safe mode.';
            locationSaveError = true;
            return;
        }
        const layout = services.config.documents.layout;
        if (!layout || !Array.isArray(layout.widgets)) {
            locationMessage = 'Weather settings are unavailable.';
            locationSaveError = true;
            return;
        }
        let found = false;
        const widgets = layout.widgets.map(function(widget) {
            if (widget.instanceId !== root.instanceId) return widget;
            found = true;
            const settings = Object.assign({}, widget.settings || {}, {
                city: location.name,
                country: location.country,
                region: location.region,
                latitude: location.latitude,
                longitude: location.longitude,
                timezone: location.timezone,
            });
            return Object.assign({}, widget, { settings: settings });
        });
        if (!found) {
            locationMessage = 'Weather settings could not be found.';
            locationSaveError = true;
            return;
        }
        locationSaveError = false;
        locationMessage = 'Saving…';
        locationSaveRequestId = services.config.save('layout', Object.assign({}, layout, { widgets: widgets }));
    }
    onSettingsChanged: {
        attach();
        if (locationSearchLoader.item) locationSearchLoader.item.settings = settings;
    }
    onServicesChanged: {
        attach();
        if (locationSearchLoader.item) locationSearchLoader.item.weather = services ? services.weather : null;
    }
    Component.onCompleted: attach()
    Component.onDestruction: detach()

    Connections {
        target: root.services ? root.services.weather : null
        function onStateChanged(key, state) {
            if (root.handle && key === root.handle.key) root.weatherState = state;
        }
    }
    Connections {
        target: root.services ? root.services.config : null
        function onCommandFinished(requestId, result) {
            if (requestId !== root.locationSaveRequestId) return;
            root.locationSaveRequestId = '';
            if (result.ok) {
                root.locationSearchOpen = false;
                root.locationMessage = 'Weather location saved.';
                root.locationSaveError = false;
            } else {
                root.locationMessage = result.message || result.reason || 'Could not save weather location.';
                root.locationSaveError = true;
            }
        }
    }

    Column {
        id: content
        width: root.width
        spacing: 12
        Row {
            width: parent.width
            spacing: 8
            Column {
                width: parent.width - temperatureLabel.implicitWidth - 48
                PentadText {
                    width: parent.width
                    text: root.config
                        ? [root.config.location.name, root.config.location.region, root.config.location.country]
                            .filter(function(value) { return !!value; }).join(' · ')
                        : 'Weather'
                    role: 'section'
                    solid: true
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
                PentadText {
                    width: parent.width
                    text: root.weatherState.value ? WeatherLogic.describeWeather(root.weatherState.value.code)
                        : root.weatherState.status === 'setup'
                            ? 'Choose a city below.'
                            : root.weatherState.message || (root.weatherState.status === 'loading' ? 'Loading weather…' : '')
                    role: 'caption'
                    solid: true
                    color: Theme.tokens.textMuted
                    wrapMode: Text.Wrap
                }
            }
            PentadText {
                id: temperatureLabel
                text: root.weatherState.value ? root.temperature(root.weatherState.value.temperature) : '—°'
                role: 'title'
                verticalAlignment: Text.AlignVCenter
            }
            PentadButton {
                text: '↻'
                accessibleName: 'Refresh weather'
                visible: root.config !== null
                requestedEnabled: root.handle !== null && root.weatherState.status !== 'loading'
                onPressed: if (root.handle) root.services.weather.refresh(root.handle)
            }
        }

        Row {
            width: parent.width
            spacing: 8
            PentadButton {
                id: changeCityButton
                objectName: 'weather-change-city'
                text: root.locationSearchOpen ? 'Close search' : root.config ? 'Change city' : 'Choose city'
                accessibleName: text
                requestedEnabled: !root.locationSaveRequestId
                onPressed: {
                    root.locationMessage = '';
                    root.locationSaveError = false;
                    root.locationSearchOpen = !root.locationSearchOpen;
                }
            }
            PentadText {
                width: parent.width - parent.spacing - changeCityButton.width
                text: root.locationMessage
                role: 'caption'
                color: root.locationSaveError ? Theme.tokens.error : Theme.tokens.textMuted
                wrapMode: Text.Wrap
                visible: text !== ''
            }
        }
        Loader {
            id: locationSearchLoader
            objectName: 'weather-location-search-loader'
            width: parent.width
            active: root.locationSearchOpen
            enabled: !root.locationSaveRequestId
            source: active ? Qt.resolvedUrl('LocationSearch.qml') : ''
            onLoaded: {
                item.settings = root.settings;
                item.weather = root.services ? root.services.weather : null;
            }
        }
        Connections {
            target: locationSearchLoader.item
            function onLocationSelected(location) { root.saveLocation(location); }
        }

        Row {
            width: parent.width
            visible: !!root.weatherState.value
            PentadText {
                width: parent.width / 2
                text: root.weatherState.value
                    ? 'Feels like ' + root.temperature(root.weatherState.value.apparent) : ''
                role: 'caption'
            }
            PentadText {
                width: parent.width / 2
                text: root.weatherState.value
                    ? 'Wind ' + Math.round(root.weatherState.value.windKmh) + ' km/h' : ''
                role: 'caption'
                horizontalAlignment: Text.AlignRight
            }
        }

        Row {
            width: parent.width
            spacing: 8
            visible: !!root.weatherState.value
            Repeater {
                model: root.weatherState.value ? root.weatherState.value.days : []
                delegate: Column {
                    required property var modelData
                    width: (content.width - 16) / 3
                    PentadText { text: root.dateLabel(modelData.date); role: 'caption'; solid: true; font.weight: Font.Medium }
                    PentadText { text: WeatherLogic.describeWeather(modelData.code); role: 'caption'; solid: true; elide: Text.ElideRight }
                    PentadText {
                        text: Math.round(modelData.min) + '° / ' + Math.round(modelData.max) + '°'
                        role: 'caption'
                        solid: true
                        color: Theme.tokens.textMuted
                    }
                }
            }
        }

        Row {
            width: parent.width
            visible: !!root.weatherState.value
            PentadText {
                width: parent.width - sourceLabel.implicitWidth - 8
                text: root.weatherState.status === 'stale'
                    ? 'Offline · updated ' + new Date(root.weatherState.value.updatedAt).toLocaleTimeString(Qt.locale().name, { hour: '2-digit', minute: '2-digit' })
                    : root.weatherState.status === 'loading' ? 'Updating…' : ''
                role: 'caption'
                color: root.weatherState.status === 'stale' ? Theme.tokens.warning : Theme.tokens.textMuted
            }
            PentadText { id: sourceLabel; text: 'Open-Meteo'; role: 'caption'; horizontalAlignment: Text.AlignRight }
        }
    }
}
