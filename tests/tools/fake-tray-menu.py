#!/usr/bin/python3
"""Handy-sized DBusMenu fixture, restricted to the runner's private bus."""
import os
import sys
from gi.repository import Gio, GLib

address = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
if os.environ.get("PENTAD_HEADLESS") != "1" or not address.startswith("unix:path=/tmp/pentad-headless-"):
    sys.exit("Only the disposable private test bus is allowed")

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
item_xml = """<node><interface name="org.kde.StatusNotifierItem">
<property name="Category" type="s" access="read"/><property name="Id" type="s" access="read"/>
<property name="Title" type="s" access="read"/><property name="Status" type="s" access="read"/>
<property name="WindowId" type="u" access="read"/><property name="IconName" type="s" access="read"/>
<property name="ItemIsMenu" type="b" access="read"/><property name="Menu" type="o" access="read"/>
</interface></node>"""
menu_xml = """<node><interface name="com.canonical.dbusmenu">
<property name="Version" type="u" access="read"/><property name="TextDirection" type="s" access="read"/>
<property name="Status" type="s" access="read"/><property name="IconThemePath" type="as" access="read"/>
<method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/>
<arg type="as" direction="in"/><arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
<method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
<method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/>
<arg type="v" direction="in"/><arg type="u" direction="in"/></method>
<signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
</interface></node>"""
labels = ["Handy v0.9.8", None, "Copy Last Transcript", None, "Parakeet TDT 0.6B v3",
          "Unload Model", None, "Settings...", "Check for Updates...", None, "Quit"]

def layout():
    children = []
    for index, text in enumerate(labels, 1):
        props = {"label": GLib.Variant("s", text)} if text else {"type": GLib.Variant("s", "separator")}
        children.append(GLib.Variant("(ia{sv}av)", (index, props, [])))
    return (0, {"children-display": GLib.Variant("s", "submenu")}, children)

def method(connection, sender, path, interface, name, parameters, invocation):
    if name == "GetLayout":
        invocation.return_value(GLib.Variant("(u(ia{sv}av))", (1, layout())))
    elif name == "AboutToShow":
        def reply():
            invocation.return_value(GLib.Variant("(b)", (False,)))
            return False
        GLib.timeout_add(1, reply)
    elif name == "Event":
        invocation.return_value(None)
    else:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", name)

def prop(connection, sender, path, interface, name):
    values = {"Category": ("s", "ApplicationStatus"), "Id": ("s", "pentad-handy-fixture"),
        "Title": ("s", "Handy fixture"), "Status": ("s", "Active"), "WindowId": ("u", 0),
        "IconName": ("s", "dialog-information"), "ItemIsMenu": ("b", True), "Menu": ("o", "/Menu"),
        "Version": ("u", 3), "TextDirection": ("s", "ltr"), "IconThemePath": ("as", [])}
    signature, value = values[name]
    return GLib.Variant(signature, value)

bus.register_object("/StatusNotifierItem", Gio.DBusNodeInfo.new_for_xml(item_xml).interfaces[0], method, prop, None)
bus.register_object("/Menu", Gio.DBusNodeInfo.new_for_xml(menu_xml).interfaces[0], method, prop, None)

def register():
    try:
        bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
            "RegisterStatusNotifierItem", GLib.Variant("(s)", ("/StatusNotifierItem",)), None,
            Gio.DBusCallFlags.NONE, 500, None)
        return False
    except GLib.Error:
        return True

GLib.timeout_add(100, register)
loop = GLib.MainLoop()
GLib.timeout_add_seconds(25, lambda: (loop.quit(), False)[1])
loop.run()
