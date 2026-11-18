import QtQuick

// The `services` object one widget view or controller receives. It forwards the members of the
// shared container (services/Services.qml) except `worker`, and swaps `capabilities` for a
// facade fixed to this instance. `chat` spends provider keys on behalf of an instance id it is
// told, so only built-in instances get it. The container itself is held by closures, not by a
// property: adopt() is called once by the host (PluginHost, PlacementController).
// tests/quickshell/widget-services.test.mjs keeps the lists in step with Services.qml.
QtObject {
    id: facade
    readonly property var forwarded: ['safeMode', 'preview', 'apiVersion', 'state', 'calendarSources', 'hyprland', 'audio', 'power', 'network', 'session', 'weather', 'tray', 'settings', 'media', 'artwork', 'lyrics', 'visualizer', 'brightnessAdapters', 'desktop', 'popups', 'navigation', 'spotlight', 'screenshot', 'workspaceHeld', 'activity', 'clock', 'config', 'organizer', 'notifications', 'overnight', 'quickSettings', 'systemSettings', 'networkSettings', 'shelf', 'stash', 'cheatsheet', 'submap', 'keybinds', 'toolWorkspace', 'fileInput', 'fileTools', 'filePicker', 'wallpaper', 'toolPreviews', 'plugins']
    readonly property var forwardedFunctions: ['text', 'brightnessFor', 'releaseBrightness']
    readonly property var builtinOnly: ['chat']
    readonly property var withheld: ['worker']

    property var safeMode
    property var preview
    property var apiVersion
    property var state
    property var calendarSources
    property var hyprland
    property var audio
    property var power
    property var network
    property var session
    property var weather
    property var chat: null
    property var tray
    property var settings
    property var media
    property var artwork
    property var lyrics
    property var visualizer
    property var brightnessAdapters
    property var desktop
    property var popups
    property var navigation
    property var spotlight
    property var screenshot
    property var workspaceHeld
    property var activity
    property var clock
    property var config
    property var organizer
    property var notifications
    property var overnight
    property var quickSettings
    property var systemSettings
    property var networkSettings
    property var shelf
    property var stash
    property var cheatsheet
    property var submap
    property var keybinds
    property var toolWorkspace
    property var fileInput
    property var fileTools
    property var filePicker
    property var wallpaper
    property var toolPreviews
    property var plugins
    // Null when the host has no capability service, so `services.capabilities &&` still guards.
    property var capabilities: null
    property var text
    property var brightnessFor
    property var releaseBrightness
    readonly property CapabilityFacade capabilityFacade: CapabilityFacade {}

    // source() returns the shared container (or a fixture's stand-in); builtin() says whether
    // the widget comes from the built-in registry.
    function adopt(source, builtin) {
        const member = name => {
            const container = source();
            return container ? container[name] : undefined;
        };
        forwarded.forEach(name => {
            facade[name] = Qt.binding(() => member(name));
        });
        builtinOnly.forEach(name => {
            facade[name] = Qt.binding(() => builtin() === true ? member(name) || null : null);
        });
        forwardedFunctions.forEach(name => {
            facade[name] = (first, second, third) => source()[name](first, second, third);
        });
        facade.capabilities = Qt.binding(() => member('capabilities') ? facade.capabilityFacade : null);
    }
    // Host only: binds the capability facade to the service and the instance id attached there.
    function bindCapabilities(service, instanceId) {
        capabilityFacade.bind(service, instanceId);
    }
}
