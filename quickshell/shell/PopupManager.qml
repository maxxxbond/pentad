import QtQml
import Quickshell
import Quickshell.Hyprland

QtObject {
    id: manager
    property var surfaces: []
    readonly property string surface: surfaces.length ? surfaces[surfaces.length - 1].name : ''
    readonly property string outputId: surfaces.length ? surfaces[surfaces.length - 1].output : ''
    readonly property string instanceId: surfaces.length ? surfaces[surfaces.length - 1].instance : ''
    property var children: []
    readonly property var childSurface: children.length ? children[children.length - 1].child : null
    property var hosts: []
    property var visibleHosts: ({})
    property bool capturePending: false
    readonly property var focusWindows: focusWindowList()
    readonly property bool focusActive: needsFocusGrab()

    function focusWindowList() {
        let windows = [];
        for (const host of hosts) {
            windows.push(host.barWindow);
            if (host.visible) windows.push(host);
        }
        for (const entry of children) {
            const child = entry.child;
            if (child.grabFocus === false) continue;
            if (child.focusWindows) windows = windows.concat(child.focusWindows);
            else if (child.window) windows.push(child.window);
        }
        return windows.filter((window, index) => window && windows.indexOf(window) === index);
    }
    function needsFocusGrab() {
        return hosts.length > 0
            && (Object.keys(visibleHosts).length > 0 || children.some(entry => entry.child.grabFocus !== false))
            && !hosts.some(host => host.dragOutActive);
    }
    property HyprlandFocusGrab focusGrab: HyprlandFocusGrab {
        active: manager.focusActive
        windows: manager.focusWindows
        onCleared: if (manager.focusActive) {
            if (Quickshell.env("PENTAD_MENU_POINTER_DEBUG") === "1")
                console.info("PENTAD_MENU_POINTER", JSON.stringify({ event: "focus-grab-cleared",
                    windows: manager.focusWindows.length, children: manager.children.length }));
            manager.close()
        }
    }
    signal changed()
    signal capturePreparing()
    signal captureReady()
    function registerHost(host) {
        if (!hosts.includes(host)) hosts = hosts.concat([host]);
    }
    function unregisterHost(host) {
        hosts = hosts.filter(item => item !== host);
    }
    function isOpen(name, output) {
        return surfaces.some(item => item.name === name && item.output === output);
    }
    function instanceFor(name, output) {
        const entry = surfaces.find(item => item.name === name && item.output === output);
        return entry ? entry.instance : '';
    }
    function hostVisibility(key, visible) {
        const next = Object.assign({}, visibleHosts);
        if (visible) next[key] = true;
        else delete next[key];
        visibleHosts = next;
        finishCapturePreparation();
    }
    function prepareCapture() {
        capturePending = true;
        close();
        capturePreparing();
        finishCapturePreparation();
    }
    // Hosts that must be gone before a screenshot is taken: transient menus and overlays.
    // Windows the user opened on purpose (the settings dialogs) are part of the picture.
    function captureBlockingHosts() {
        const captured = ['settings', 'screenshot-settings'];
        return Object.keys(visibleHosts).filter(key => !captured.includes(key));
    }
    function finishCapturePreparation() {
        if (!capturePending || captureBlockingHosts().length) return;
        Qt.callLater(function() {
            if (!capturePending || captureBlockingHosts().length) return;
            capturePending = false;
            captureReady();
        });
    }
    function open(name, output, instance) {
        if (!['left', 'right', 'activity'].includes(name)) return false;
        capturePending = false;
        const previous = surfaces.find(item => item.name === name && item.output === output);
        if (previous && previous.instance !== (instance || '')) closeOwnedChildren(name, output);
        surfaces = surfaces.filter(item => item.name !== name || item.output !== output)
            .concat([{ name: name, output: output, instance: instance || '' }]);
        changed();
        return true;
    }
    function toggle(name, output, instance) {
        if (isOpen(name, output) && instanceFor(name, output) === (instance || '')) closeSurface(name, output);
        else open(name, output, instance);
    }
    function closeSurface(name, output) {
        closeOwnedChildren(name, output);
        const next = surfaces.filter(item => item.name !== name || item.output !== output);
        if (next.length === surfaces.length) return;
        surfaces = next;
        changed();
    }
    function close() {
        const pending = children;
        children = [];
        for (const entry of pending) entry.child.close();
        if (!surfaces.length) return;
        surfaces = [];
        changed();
    }
    function registerChild(child) {
        if (children.some(entry => entry.child === child)) return;
        const host = hosts.find(item => item === child.ownerWindow);
        const parent = children.find(entry => entry.child.window === child.ownerWindow
            || (entry.child.focusWindows && entry.child.focusWindows.includes(child.ownerWindow)));
        // One interactive menu at a time: a new one closes the others, except the menus it opened from.
        const ancestors = [];
        for (let entry = parent; entry; entry = children.find(item => item.child === entry.parent))
            ancestors.push(entry.child);
        const rivals = child.grabFocus === false ? [] : children
            .filter(entry => entry.child.grabFocus !== false && !ancestors.includes(entry.child))
            .map(entry => entry.child);
        children = children.concat([{ child: child, parent: parent ? parent.child : null,
            name: host ? host.surfaceName : parent ? parent.name : '',
            output: host ? host.outputId : parent ? parent.output :
                child.ownerWindow && child.ownerWindow.screen ? child.ownerWindow.screen.name : '' }]);
        for (const rival of rivals) {
            if (!children.some(entry => entry.child === rival)) continue;
            unregisterChild(rival);
            rival.close();
        }
    }
    function unregisterChild(child) {
        const descendants = children.filter(entry => entry.parent === child);
        children = children.filter(entry => entry.child !== child);
        for (const entry of descendants) {
            unregisterChild(entry.child);
            entry.child.close();
        }
    }
    function closeChild() {
        const child = childSurface;
        if (!child) return false;
        unregisterChild(child);
        child.close();
        return true;
    }
    function closeOwnedChildren(name, output) {
        const pending = children.filter(entry => entry.name === name && entry.output === output);
        children = children.filter(entry => !pending.includes(entry));
        for (const entry of pending) entry.child.close();
    }
    function dismissTop() {
        if (childSurface && typeof childSurface.dismissTop === 'function') childSurface.dismissTop();
        else if (!closeChild() && surfaces.length) closeSurface(surface, outputId);
    }
    function disposeOutput(output) {
        const pending = children.filter(entry => entry.output === output);
        children = children.filter(entry => entry.output !== output);
        for (const entry of pending) entry.child.close();
        const next = surfaces.filter(item => item.output !== output);
        if (next.length === surfaces.length) return;
        surfaces = next;
        changed();
    }
}
