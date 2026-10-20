pragma ComponentBehavior: Bound
import QtQuick
import qs.components
import '../../logic/weather.mjs' as WeatherLogic

Column {
    id: root
    objectName: 'weather-location-search'
    property var settings: ({})
    property var weather: null
    signal locationSelected(var location)
    property var results: []
    property string message: 'Enter at least 2 characters'
    property var cancellation: null
    spacing: 6

    function cancelSearch() {
        debounce.stop();
        if (cancellation) cancellation.cancel();
        cancellation = null;
    }
    function search() {
        const query = cityField.text.trim();
        results = [];
        if (query.length < 2) {
            message = 'Enter at least 2 characters';
            return;
        }
        if (!weather || typeof weather.searchCities !== 'function') {
            message = 'City search is unavailable';
            return;
        }
        message = 'Searching…';
        const token = WeatherLogic.createCancellation();
        cancellation = token;
        weather.searchCities(query, token).then(function(matches) {
            if (token.isCancelled()) return;
            if (root.cancellation !== token) return;
            root.results = matches;
            root.message = matches.length ? 'Choose a city from the list' : 'City not found';
        }).catch(function(error) {
            if (token.isCancelled()) return;
            if (root.cancellation !== token) return;
            root.results = [];
            root.message = error && error.message ? error.message : 'Could not find the city';
        });
    }
    function editQuery() {
        cancelSearch();
        results = [];
        message = cityField.text.trim().length < 2
            ? 'Enter at least 2 characters' : 'Searching…';
        if (cityField.text.trim().length >= 2) debounce.restart();
    }

    PentadText { text: 'Search for a city'; role: 'caption' }
    PentadTextField {
        id: cityField
        objectName: 'weather-city-search'
        width: root.width
        placeholderText: 'Start typing a city name'
        text: root.settings.city || ''
        accessibleName: 'Search for a weather city'
        onTextEdited: root.editQuery()
    }
    PentadText { text: root.message; role: 'caption'; wrapMode: Text.Wrap }
    Repeater {
        model: root.results
        delegate: PentadButton {
            required property var modelData
            objectName: 'weather-city-result'
            enabled: root.enabled
            width: root.width
            text: [modelData.name, modelData.region, modelData.country].filter(Boolean).join(' · ')
            accessibleName: modelData.name + ', ' + modelData.country
            onPressed: {
                const city = modelData;
                root.cancelSearch();
                root.results = [];
                root.message = [city.name, city.region, city.country].filter(Boolean).join(', ');
                root.locationSelected(city);
            }
        }
    }
    Timer {
        id: debounce
        interval: 300
        repeat: false
        onTriggered: root.search()
    }
    Component.onDestruction: cancelSearch()
}
