import QtQuick
import "../logic/widget-services.mjs" as Members

// The `services` object one widget view or controller receives. A built-in widget gets the
// members of the shared container (services/Services.qml) except `worker`; an external widget
// gets only the documented widget API v1 services (Members.externalServices) and sees every
// other member as undefined (`chat` as null). Both get `capabilities` as a facade fixed to this
// instance. The container itself is held by closures, not by a property: adopt() is called once
// by the host (PluginHost, PlacementController). The lists live in logic/widget-services.mjs;
// tests/quickshell/widget-services.test.mjs keeps them in step with Services.qml and contracts.d.ts.
// TODO(isolation): an API boundary, not a sandbox; see the TODO in logic/widget-services.mjs.
QtObject {
    id: facade

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
    // the widget comes from the built-in registry. The host's entry can arrive or change after
    // adopt(), so members outside the external allowlist stay bound to builtin().
    function adopt(source, builtin) {
        const member = name => {
            const container = source();
            return container ? container[name] : undefined;
        };
        const external = name => Members.exposed(name, false);
        Members.forwarded.forEach(name => {
            facade[name] = external(name) ? Qt.binding(() => member(name)) : Qt.binding(() => builtin() === true ? member(name) : undefined);
        });
        Members.builtinOnly.forEach(name => {
            facade[name] = Qt.binding(() => builtin() === true ? member(name) || null : null);
        });
        Members.forwardedFunctions.forEach(name => {
            const forward = (first, second, third) => source()[name](first, second, third);
            facade[name] = external(name) ? forward : Qt.binding(() => builtin() === true ? forward : undefined);
        });
        facade.capabilities = Qt.binding(() => member('capabilities') ? facade.capabilityFacade : null);
    }
    // Host only: binds the capability facade to the service and the instance id attached there.
    function bindCapabilities(service, instanceId) {
        capabilityFacade.bind(service, instanceId);
    }
}
