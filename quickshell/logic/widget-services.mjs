// The members of the `services` object one widget view or controller receives
// (plugins/WidgetServices.qml), defined once for the QML facade and its tests. Qt-free.
//
// Built-in widgets (from builtin-registry.json) get every forwarded member of the shared
// container (services/Services.qml). External widgets get only `externalServices`: the
// documented `WidgetServices` of widget API v1 (packages/widget-api/v1/contracts.d.ts). Every
// other member is host-internal and is undefined for them; `chat` is null.
//
// TODO(isolation): this is an API boundary, not a sandbox. Widgets run in-process as trusted
// user code and can still walk QML parents or start processes. Run external widgets out of
// process (a separate Quickshell/QML engine or a helper process speaking the capability
// protocol) so the allowlist and remote consent become a real security boundary.

// Container properties forwarded to built-in widgets.
export const forwarded = Object.freeze(['safeMode', 'preview', 'apiVersion', 'state', 'calendarSources', 'hyprland',
  'audio', 'power', 'network', 'session', 'weather', 'tray', 'settings', 'media', 'artwork', 'lyrics', 'visualizer',
  'brightnessAdapters', 'desktop', 'popups', 'navigation', 'spotlight', 'screenshot', 'workspaceHeld', 'activity',
  'clock', 'config', 'organizer', 'notifications', 'overnight', 'quickSettings', 'systemSettings', 'networkSettings',
  'shelf', 'stash', 'cheatsheet', 'submap', 'keybinds', 'toolWorkspace', 'fileInput', 'fileTools', 'filePicker',
  'wallpaper', 'toolPreviews', 'plugins']);
// Container functions forwarded to built-in widgets.
export const forwardedFunctions = Object.freeze(['text', 'brightnessFor', 'releaseBrightness']);
// Forwarded to built-in widgets only, and null for every other widget: `chat` spends provider
// keys on behalf of an instance id it is told.
export const builtinOnly = Object.freeze(['chat']);
// Never forwarded, to any widget.
export const withheld = Object.freeze(['worker']);
// Everything an external widget receives. `capabilities` is the per-instance facade
// (plugins/CapabilityFacade.qml), never the container's service.
export const externalServices = Object.freeze(['apiVersion', 'preview', 'safeMode', 'text', 'audio', 'media',
  'toolWorkspace', 'capabilities']);

// Whether a widget sees `name`; `builtin` is true only for entries from the built-in registry.
export function exposed(name, builtin) {
  if (withheld.indexOf(name) >= 0) return false;
  if (externalServices.indexOf(name) >= 0) return true;
  return builtin === true && (forwarded.indexOf(name) >= 0 || forwardedFunctions.indexOf(name) >= 0
    || builtinOnly.indexOf(name) >= 0);
}
