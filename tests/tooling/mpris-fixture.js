#!/usr/bin/env -S gjs -m
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const MPRIS = 'org.mpris.MediaPlayer2';
const PLAYER_IFACE = `${MPRIS}.Player`;
const ROOT_IFACE = MPRIS;
const CONTROL = 'org.pentad.MediaFixture';
const PATH = '/org/mpris/MediaPlayer2';
const CONTROL_PATH = '/org/pentad/MediaFixture';

const xml = `<node>
  <interface name="${PLAYER_IFACE}">
    <method name="Next"/><method name="Previous"/><method name="PlayPause"/><method name="Play"/><method name="Pause"/>
    <method name="Seek"><arg type="x" direction="in"/></method>
    <method name="SetPosition"><arg type="o" direction="in"/><arg type="x" direction="in"/></method>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="read"/><property name="Shuffle" type="b" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/><property name="Position" type="x" access="read"/>
    <property name="Volume" type="d" access="read"/><property name="CanControl" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/><property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/><property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
  </interface>
  <interface name="${ROOT_IFACE}">
    <method name="Raise"/><method name="Quit"/><method name="OpenUri"><arg type="s" direction="in"/></method>
    <property name="CanQuit" type="b" access="read"/><property name="CanRaise" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/><property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/><property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="${CONTROL}">
    <method name="DropPlayer"><arg type="s" direction="in"/></method>
    <method name="RestorePlayer"><arg type="s" direction="in"/></method>
    <method name="SetCanControl"><arg type="s" direction="in"/><arg type="b" direction="in"/></method>
    <method name="ChangeTrack"><arg type="s" direction="in"/><arg type="s" direction="in"/></method>
  </interface>
</node>`;
const info = Gio.DBusNodeInfo.new_for_xml(xml);
const loop = GLib.MainLoop.new(null, false);
const connection = Gio.bus_get_sync(Gio.BusType.SESSION, null);
const players = new Map();
const ownerIds = new Map();

function variant(type, value) { return new GLib.Variant(type, value); }
function metadata(key, title) {
  return {
    'mpris:trackid': variant('o', key),
    'mpris:length': variant('x', 120_000_000),
    'xesam:title': variant('s', title),
    'xesam:artist': variant('as', ['Pentad fixture']),
    'xesam:album': variant('s', 'Native integration'),
    'xesam:url': variant('s', 'https://fixture.invalid/track'),
  };
}
function emitChanged(player, changes) {
  player.connection.emit_signal(null, PATH, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
    variant('(sa{sv}as)', [PLAYER_IFACE, changes, []]));
}
function logEvent(event) {
  print(`PENTAD_MPRIS_EVENT ${JSON.stringify(event)}`);
}
function createPlayer(id) {
  const isA = id === 'A';
  const state = {
    id,
    service: `${MPRIS}.${id}`,
    status: isA ? 'Playing' : 'Paused',
    position: isA ? 7_250_000 : 12_500_000,
    canControl: true,
    metadata: metadata(`/track/${id}`, `Track ${id}`),
    connection: null,
    exported: false,
  };
  players.set(id, state);
  const playerInfo = info.lookup_interface(PLAYER_IFACE);
  const appInfo = info.lookup_interface(ROOT_IFACE);
  const vtable = {
    method_call(_conn, _sender, _path, _iface, method, params, invocation) {
      const args = params.deep_unpack();
      if (method === 'PlayPause' || method === 'Play' || method === 'Pause') {
        if (!state.canControl) return invocation.return_dbus_error(`${PLAYER_IFACE}.Error.NotAllowed`, 'CanControl is false');
        state.status = method === 'Play' ? 'Playing' : method === 'Pause' ? 'Paused' : state.status === 'Playing' ? 'Paused' : 'Playing';
        logEvent({ player: id, method });
        emitChanged(state, { PlaybackStatus: variant('s', state.status) });
      } else if (method === 'Next' || method === 'Previous') {
        if (!state.canControl) return invocation.return_dbus_error(`${PLAYER_IFACE}.Error.NotAllowed`, 'CanControl is false');
        logEvent({ player: id, method });
      } else if (method === 'SetPosition') {
        const [track, target] = args;
        if (!state.canControl) return invocation.return_dbus_error(`${PLAYER_IFACE}.Error.NotAllowed`, 'CanControl is false');
        if (track !== state.metadata['mpris:trackid'].deep_unpack())
          return invocation.return_dbus_error(`${PLAYER_IFACE}.Error.InvalidTrack`, 'stale track object path');
        state.position = Number(target);
        logEvent({ player: id, method, track, position: state.position });
        emitChanged(state, { Position: variant('x', state.position) });
      } else if (method === 'Seek') {
        const [offset] = args;
        state.position = Math.max(0, state.position + Number(offset));
        logEvent({ player: id, method, offset: Number(offset), position: state.position });
        emitChanged(state, { Position: variant('x', state.position) });
      }
      invocation.return_value(null);
    },
    get_property(_conn, _sender, _path, iface, name) {
      if (iface === ROOT_IFACE) {
        const rootValues = {
          CanQuit: variant('b', false), CanRaise: variant('b', false), Identity: variant('s', `Fixture ${id}`),
          DesktopEntry: variant('s', 'pentad-fixture'), SupportedUriSchemes: variant('as', []), SupportedMimeTypes: variant('as', []),
        };
        return rootValues[name] ?? null;
      }
      const values = {
        PlaybackStatus: variant('s', state.status), LoopStatus: variant('s', 'None'), Rate: variant('d', 1),
        Shuffle: variant('b', false), Metadata: variant('a{sv}', state.metadata), Position: variant('x', state.position),
        Volume: variant('d', 1), CanControl: variant('b', state.canControl), CanPlay: variant('b', true),
        CanPause: variant('b', true), CanSeek: variant('b', true), CanGoNext: variant('b', false),
        CanGoPrevious: variant('b', true),
      };
      return values[name] ?? null;
    },
    set_property() { return false; },
  };
  state.vtable = vtable;
  state.playerInfo = playerInfo;
  state.appInfo = appInfo;
  return state;
}

function ownPlayer(id) {
  if (ownerIds.has(id)) return;
  const state = players.get(id) ?? createPlayer(id);
  if (!state.connection) {
    const address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, null);
    state.connection = Gio.DBusConnection.new_for_address_sync(address,
      Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, null, null);
  }
  if (!state.exported) {
    state.connection.register_object(PATH, state.playerInfo, state.vtable.method_call, state.vtable.get_property, state.vtable.set_property);
    state.connection.register_object(PATH, state.appInfo, state.vtable.method_call, state.vtable.get_property, state.vtable.set_property);
    state.exported = true;
  }
  ownerIds.set(id, Gio.bus_own_name_on_connection(state.connection, state.service, Gio.BusNameOwnerFlags.NONE,
    () => logEvent({ player: id, event: 'registered' }),
    () => logEvent({ player: id, event: 'ownership-lost' })));
}
function dropPlayer(id) {
  if (!ownerIds.has(id)) return;
  Gio.bus_unown_name(ownerIds.get(id));
  ownerIds.delete(id);
  logEvent({ player: id, event: 'dropped' });
}

const controlInfo = info.lookup_interface(CONTROL);
connection.register_object(CONTROL_PATH, controlInfo, {
  method_call(_conn, _sender, _path, _iface, method, params, invocation) {
    const [id, value] = params.deep_unpack();
    const state = players.get(id);
    if (method === 'DropPlayer') dropPlayer(id);
    else if (method === 'RestorePlayer') ownPlayer(id);
    else if (method === 'SetCanControl' && state) {
      state.canControl = value;
      emitChanged(state, { CanControl: variant('b', value) });
    } else if (method === 'ChangeTrack' && state) {
      state.metadata = metadata(value, `Changed ${id}`);
      state.position = 3_000_000;
      emitChanged(state, { Metadata: variant('a{sv}', state.metadata), Position: variant('x', state.position) });
      logEvent({ player: id, event: 'track-changed', track: value });
    }
    invocation.return_value(null);
  },
}.method_call, null, null);

createPlayer('A');
createPlayer('B');
ownPlayer('A');
ownPlayer('B');
Gio.bus_own_name_on_connection(connection, CONTROL, Gio.BusNameOwnerFlags.NONE,
  () => { print('PENTAD_MPRIS_READY'); },
  () => { printerr('Could not own private fixture bus name'); loop.quit(); });
loop.run();
