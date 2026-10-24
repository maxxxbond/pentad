import hashlib
import importlib.util
import io
import json
import re
import shutil
import socket
import sys
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
for name in ("pentad_lua", "pentad_doctor", "pentad_setup"):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"tools/{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module  # setup imports the doctor by name; dataclasses resolve annotations through the registry
    spec.loader.exec_module(module)
setup = sys.modules["pentad_setup"]
doctor = sys.modules["pentad_doctor"]

NOW = datetime(2026, 10, 24, 12, 0, 0, tzinfo=timezone.utc)
STAMP = "20261024T120000Z"
HYPRLAND_PID = 1371
# Shaped like illogical-impulse's Lua config: an entry file that requires modules, the shell started inside a handler.
HYPRLAND_LUA = 'require("hyprland.execs")\nrequire("hyprland.keybinds")\nrequire("custom.general")\n'
EXECS_LUA = ('local qsConfig = "ii"\n'
             "\n"
             'hl.on("hyprland.start", function ()\n'
             '    hl.exec_cmd("qs -c $qsConfig")\n'
             '    hl.exec_cmd("hypridle")\n'
             "    hl.exec_cmd(\"wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'\")\n"
             "end)\n")
KEYBINDS_LUA = "".join(f'hl.bind("SUPER + {key}", hl.dsp.global("quickshell:{action}"))\n'
                       for key, action in [("SUPER_L", "searchToggleRelease"), ("Tab", "overviewToggle")] * 15)
LUA_START = 'hl.on("hyprland.start", function () hl.exec_cmd("pentad start") end)'
LUA_HEADER = "-- [pentad setup] This file is written by `pentad setup`; changes here may be overwritten.\n"
CONF_HEADER = "# [pentad setup] This file is written by `pentad setup`; changes here may be overwritten.\n"
LUA_INCLUDE = 'if package.searchpath("pentad", package.path) then package.loaded.pentad = nil require("pentad") end'
APPLIED = ("Hyprland reloaded the config without new errors.\n"
           f"Applied. Backups are in ~/.local/state/pentad/setup/{STAMP}; undo with `pentad setup --undo`.\n")
SWITCH_PROMPT = "\nSwitch to Pentad now instead of at the next login? [y/N] "
NOT_NOW = "All right, the switch happens at the next login.\n"
HYPRCTL = r'''#!/bin/sh
PATH=/usr/bin:/bin:$PATH
d="%(ctl)s"
printf '%%s\n' "$*" >> "$d/log"
case "$*" in
  "-j layers") cat "$d/layers.json" 2>/dev/null || echo '{}' ;;
  "-j instances") cat "$d/instances.json" 2>/dev/null || echo '[]' ;;
  "-j configerrors")
    if [ -f "$d/error-rule" ]; then
      p=$(sed -n 1p "$d/error-rule"); t=$(sed -n 2p "$d/error-rule"); m=$(sed -n 3p "$d/error-rule")
      if grep -qF -- "$t" "$p" 2>/dev/null; then printf '[\n\t"%%s"\n]\n' "$m"; exit 0; fi
    fi
    cat "$d/errors.json" 2>/dev/null || cat "$d/errors-base.json" 2>/dev/null || printf '[\n\t""\n]\n' ;;
  "-j getoption misc:disable_autoreload")
    cat "$d/autoreload.json" 2>/dev/null || echo '{"option": "misc:disable_autoreload", "bool": false, "set": false }' ;;
  reload) : > "$d/reload-trigger"; echo ok ;;
  dispatch*)
    if [ -f "$d/dispatch-reply" ]; then cat "$d/dispatch-reply"; exit 0; fi
    [ -f "$d/layers-after.json" ] && cp "$d/layers-after.json" "$d/layers.json"
    [ -f "$d/owner-after" ] && cp "$d/owner-after" "$d/owner"
    echo ok ;;
  *) echo '{}' ;;
esac
'''
BUSCTL = r'''#!/bin/sh
PATH=/usr/bin:/bin:$PATH
d="%(ctl)s"
pid=$(cat "$d/owner" 2>/dev/null)
case "$*" in
  *NameHasOwner*) [ -n "$pid" ] && echo "b true" || echo "b false" ;;
  *GetConnectionUnixProcessID*) echo "u $pid" ;;
esac
'''
SYSTEMCTL = r'''#!/bin/sh
PATH=/usr/bin:/bin:$PATH
d="%(ctl)s"
printf '%%s\n' "$*" >> "$d/systemctl.log"
case "$*" in
  "--user mask "*) mkdir -p "$HOME/.config/systemd/user" && ln -s /dev/null "$HOME/.config/systemd/user/$3" ;;
  "--user unmask "*) rm -f "$HOME/.config/systemd/user/$3" ;;
  "--user stop "*) [ -f "$d/unit-pid-$3" ] && rm -rf "%(system)s/proc/$(cat "$d/unit-pid-$3")" ;;
esac
'''

def write(path: Path, text: str = "", mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

class Tampering(io.StringIO):
    """Stdin that edits a file while the user is 'typing' the answer."""
    def __init__(self, path: Path, extra: str):
        super().__init__("y\n")
        self.path, self.extra = path, extra

    def readline(self, *args):
        self.path.write_text(self.path.read_text(encoding="utf-8") + self.extra, encoding="utf-8")
        return super().readline(*args)

class NeverRead(io.StringIO):
    """Stdin that fails the test when setup prompts."""
    def readline(self, *args):
        raise AssertionError("setup prompted when it must not")

class FakeSocket2(threading.Thread):
    """Hyprland's event socket, as far as setup can tell.

    Hyprland reloads at once for every loaded file that is replaced (the inotify watch fires IN_IGNORED on the
    old inode), posts one configreloaded per reload, and reloads once more on `hyprctl reload`. A file that is
    not loaded yet (a new fragment) triggers nothing. Loaded means: the entry file and what it reaches through
    require/source, as of the last reload. Each reload also recomputes the config errors the way hyprlang does
    for a missing `source =` target, into errors.json for the fake hyprctl.
    """

    def __init__(self, path: Path, hypr: Path, ctl: Path, policy: str):
        super().__init__(daemon=True)
        self.path, self.hypr, self.ctl, self.policy = path, hypr, ctl, policy
        self.trigger = ctl / "reload-trigger"
        self.stopping = threading.Event()
        self.sent = 0
        self.reloaded_with: list[list[str]] = []  # the loaded files at each reload, for assertions
        self.error_history: list[list[str]] = []  # the config errors of each reload

    def entry(self) -> Path | None:
        for name in ("hyprland.lua", "hyprland.conf"):
            if (self.hypr / name).is_file():
                return self.hypr / name
        return None

    def loaded(self) -> dict[Path, tuple]:
        """The files Hyprland would watch now, with their identity (inode, mtime, size)."""
        files: dict[Path, tuple] = {}
        pending = [self.entry()] if self.entry() else []
        while pending:
            path = pending.pop()
            if path is None or path in files or not path.is_file():
                continue
            info = path.stat()
            files[path] = (info.st_ino, info.st_mtime_ns, info.st_size)
            text = path.read_text(encoding="utf-8", errors="replace")
            for line in text.split("\n"):
                code = line.split("--", 1)[0] if path.suffix == ".lua" else line.split("#", 1)[0]
                if path.suffix == ".lua":
                    for match in re.finditer(r"""require\s*\(?\s*["']([^"']+)["']""", code):
                        module = match.group(1).replace(".", "/")
                        pending.extend([self.hypr / f"{module}.lua", self.hypr / module / "init.lua"])
                elif code.strip().startswith("source"):
                    target = code.split("=", 1)[1].strip().replace("~", str(self.hypr.parent.parent))
                    pending.append(Path(target))
        return files

    def errors(self) -> list[str]:
        base = []
        try:
            base = json.loads((self.ctl / "errors-base.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
        entry = self.entry()
        found = []
        if entry and entry.suffix == ".conf":
            for line in entry.read_text(encoding="utf-8", errors="replace").split("\n"):
                code = line.split("#", 1)[0].strip()
                if code.startswith("source"):
                    target = Path(code.split("=", 1)[1].strip().replace("~", str(self.hypr.parent.parent)))
                    if not target.exists():
                        found.append("source= globbing error")
        return base + found

    def reload(self, client) -> None:
        self.reloaded_with.append(sorted(str(path) for path in self.loaded()))
        self.error_history.append(self.errors())
        (self.ctl / "errors.json").write_text(json.dumps(self.errors() or [""]), encoding="utf-8")
        client.sendall(b"configreloaded>>\n")
        self.sent += 1

    def run(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(self.path))
        server.listen(1)
        server.settimeout(0.05)
        while not self.stopping.is_set():
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            with client:
                client.settimeout(0)
                watched = self.loaded()
                while not self.stopping.is_set():
                    try:
                        if client.recv(1) == b"":
                            break
                    except BlockingIOError:
                        pass
                    except OSError:
                        break
                    try:
                        if self.policy == "auto":
                            for path, identity in list(watched.items()):
                                if not path.exists() or (path.stat().st_ino, path.stat().st_mtime_ns, path.stat().st_size) != identity:
                                    self.reload(client)
                                    watched = self.loaded()  # the watch list follows the reload
                                    break
                        if self.trigger.exists():
                            self.trigger.unlink()
                            if self.policy != "silent":
                                self.reload(client)
                                watched = self.loaded()
                    except OSError:
                        break
                    time.sleep(0.02)
        server.close()

class SetupTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pentad-setup-test-")
        self.addCleanup(temp.cleanup)
        self.temp = Path(temp.name)
        self.system = self.temp / "system"
        self.bin = self.temp / "bin"
        self.root = self.temp / "runtime"
        self.home = self.temp / "home"
        self.hypr = self.home / ".config/hypr"
        self.autostart = self.home / ".config/autostart"
        self.state = self.home / ".local/state/pentad/setup"
        self.ctl = self.temp / "ctl"
        self.ctl.mkdir()
        self.runtime_dir = self.temp / "run"
        write(self.root / "shell.qml")
        write(self.root / "defaults/hyprland-quickshell.lua")
        self.fake("hyprctl", HYPRCTL % {"ctl": self.ctl})
        self.fake("busctl", BUSCTL % {"ctl": self.ctl})
        self.fake("systemctl", SYSTEMCTL % {"ctl": self.ctl, "system": self.system})
        self.fake("pentad", "exit 0")
        self.env = {"PATH": str(self.bin), "LANG": "en_US.UTF-8", "HYPRLAND_INSTANCE_SIGNATURE": "test",
                    "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config"),
                    "XDG_STATE_HOME": str(self.home / ".local/state"), "XDG_RUNTIME_DIR": str(self.runtime_dir)}
        self.hypr.mkdir(parents=True)
        self.proc(HYPRLAND_PID, "Hyprland", ["Hyprland", "--watchdog-fd", "4"], ppid=1)
        write(self.ctl / "instances.json", json.dumps([{"instance": "test", "time": 1, "pid": HYPRLAND_PID, "wl_socket": "wayland-1"}]))
        for name, value in (("RELOAD_TIMEOUT", 0.8), ("EVENT_GRACE", 0.05), ("STOP_TIMEOUT", 0.5), ("SWITCH_TIMEOUT", 0.5),
                            ("POLL_INTERVAL", 0.01)):
            patcher = patch.object(setup, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.socket2 = None
        self.killed = []
        self.hyprland("auto")

    def hyprland(self, policy: str) -> None:
        """Run the fake event socket with the given policy: auto, manual (only after hyprctl reload), silent, or none."""
        if self.socket2 is not None:
            self.socket2.stopping.set()
            self.socket2.join(timeout=2)
            self.socket2 = None
            (self.runtime_dir / "hypr/test/.socket2.sock").unlink(missing_ok=True)
        if policy == "none":
            return
        self.socket2 = FakeSocket2(self.runtime_dir / "hypr/test/.socket2.sock", self.hypr, self.ctl, policy)
        self.socket2.start()
        self.addCleanup(self.hyprland, "none")

    def fake(self, name: str, body: str = "true") -> None:
        write(self.bin / name, body if body.startswith("#!") else f"#!/bin/sh\n{body}\n", 0o755)

    def proc(self, pid: int, comm: str, cmdline: list[str] | None = None, cgroup: str = "", ppid: int = HYPRLAND_PID,
             tty: int = 0, started: int = 1000, environment: dict[str, str] | None = None) -> None:
        write(self.system / f"proc/{pid}/comm", comm + "\n")
        write(self.system / f"proc/{pid}/environ", "".join(f"{key}={value}\0" for key, value in (environment or {}).items()))
        write(self.system / f"proc/{pid}/cmdline", "\0".join(cmdline or [comm]) + "\0")
        fields = ["S", str(ppid), "1", "1", str(tty), "-1", "4194560"] + ["0"] * 12 + [str(started), "0", "0"]
        write(self.system / f"proc/{pid}/stat", f"{pid} ({comm}) " + " ".join(fields) + "\n")
        if cgroup:
            write(self.system / f"proc/{pid}/cgroup", cgroup + "\n")

    def notification_owner(self, pid: int | None) -> None:
        write(self.ctl / "owner", str(pid) if pid else "")

    def layers_json(self, *surfaces: tuple[int, int, str]) -> str:
        levels = {str(level): [] for level in range(4)}
        for level, pid, namespace in surfaces:
            levels[str(level)].append({"namespace": namespace, "pid": pid})
        return json.dumps({"DP-1": {"levels": levels}})

    def layers(self, *surfaces: tuple[int, int, str]) -> None:
        write(self.ctl / "layers.json", self.layers_json(*surfaces))

    def hyprctl_log(self) -> list[str]:
        try:
            return (self.ctl / "log").read_text(encoding="utf-8").splitlines()
        except OSError:
            return []

    def systemctl_log(self) -> list[str]:
        try:
            return (self.ctl / "systemctl.log").read_text(encoding="utf-8").splitlines()
        except OSError:
            return []

    def ii_shell(self) -> None:
        self.proc(2411, "qs", ["qs", "-c", "ii"], environment={"qsConfig": "ii"})  # the shell that ran `qs -c $qsConfig`
        self.notification_owner(2411)
        self.layers((0, 2411, "wallpaper"), (1, 2411, "bar"), (3, 2411, "osd"))
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA)
        write(self.hypr / "hyprland/execs.lua", EXECS_LUA)
        write(self.hypr / "hyprland/keybinds.lua", KEYBINDS_LUA)

    def hooks(self) -> "setup.Hooks":
        def kill(pid, signum):
            self.killed.append((pid, signum))
            shutil.rmtree(self.system / f"proc/{pid}", ignore_errors=True)
        return setup.Hooks(kill=kill, sleep=time.sleep, clock=time.monotonic)

    def run_setup(self, *flags: str, stdin: io.StringIO | None = None) -> tuple[str, int]:
        output = io.StringIO()
        with redirect_stdout(output):
            status = setup.main(["--root", str(self.root), "--qs", "qs", *flags], self.env, self.system,
                                io.StringIO("y\n") if stdin is None else stdin, NOW, self.hooks())
        return output.getvalue(), status

    def read(self, name: str) -> str:
        return (self.hypr / name).read_text(encoding="utf-8")

    def manifest(self, stamp: str = STAMP) -> dict:
        return json.loads((self.state / stamp / "manifest.json").read_text(encoding="utf-8"))

    def expected_execs(self) -> str:
        return EXECS_LUA.replace('    hl.exec_cmd("qs -c $qsConfig")', '    -- [pentad setup] hl.exec_cmd("qs -c $qsConfig")')

    def expected_hyprland_lua(self) -> str:
        return HYPRLAND_LUA + f"\n-- [pentad setup] Pentad's Hyprland fragment\n{LUA_INCLUDE}\n"

    def expected_fragment(self, bindings: bool = True) -> str:
        dofile = f'dofile("{self.root}/defaults/hyprland-quickshell.lua")\n' if bindings else ""
        return f"{LUA_HEADER}{LUA_START}\n{dofile}"

    def test_an_ii_shaped_lua_config_is_switched_after_a_yes(self):
        self.ii_shell()
        for loaded in (None, 'hl.bind("SUPER + Tab", hl.dsp.global("pentad:overview"))\n'):
            with self.subTest(pentad_bindings_loaded=loaded is not None):
                if loaded:
                    write(self.hypr / "custom/pentad.lua", loaded)
                output, status = self.run_setup()
                self.assertEqual(status, 0, output)
                self.assertIn("Pentad setup\n\nFound\n  qs -c ii (pid 2411) holds: notifications, wallpaper, panels and overlays.\n", output)
                self.assertIn("--- ~/.config/hypr/hyprland/execs.lua\n+++ ~/.config/hypr/hyprland/execs.lua\n", output)
                self.assertIn('-    hl.exec_cmd("qs -c $qsConfig")\n+    -- [pentad setup] hl.exec_cmd("qs -c $qsConfig")\n', output)
                self.assertIn(f"--- ~/.config/hypr/pentad.lua\n+++ ~/.config/hypr/pentad.lua\n@@ -0,0 +1,{2 if loaded else 3} @@\n"
                              f"+{LUA_HEADER}+{LUA_START}\n", output)
                self.assertIn(f"+-- [pentad setup] Pentad's Hyprland fragment\n+{LUA_INCLUDE}\n", output)
                self.assertIn("By hand\n  ~/.config/hypr/hyprland/execs.lua:6 calls qs -c ii but may do other work too: "
                              "change the line so it stops calling it rather than delete it.\n", output)
                reload = ("The changes take effect at the next login, or now if you agree to it after applying." if loaded else
                          "Hyprland reloads its config when these files change, so the added key bindings take effect at once; "
                          "the shell switch itself happens at the next login, or now if you agree to it after applying.")
                self.assertIn(f"Heads-up\n  {reload}\n"
                              "  These files may belong to another shell's own setup; its updates can bring the lines back. "
                              "Run pentad doctor after updating it.\n\nApply these changes? [y/N] " + APPLIED + SWITCH_PROMPT + "\n" + NOT_NOW, output)
                self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())
                self.assertEqual(self.read("hyprland.lua"), self.expected_hyprland_lua())
                self.assertEqual(self.read("pentad.lua"), self.expected_fragment(bindings=loaded is None))
                self.assertEqual(self.read("hyprland/keybinds.lua"), KEYBINDS_LUA)
                manifest = self.manifest()
                self.assertEqual(manifest["schemaVersion"], 2)
                self.assertEqual(manifest["created"], "2026-10-24T12:00:00+00:00")
                self.assertTrue(manifest["verified"])
                self.assertNotIn("undone", manifest)
                self.assertEqual([(entry["path"], entry["backup"], entry["role"]) for entry in manifest["files"]],
                                 [(str(self.hypr / "hyprland/execs.lua"), "1-execs.lua", "config"), (str(self.hypr / "pentad.lua"), None, "fragment"),
                                  (str(self.hypr / "hyprland.lua"), "3-hyprland.lua", "config")])
                self.assertEqual(manifest["files"][0]["commented"], ['    hl.exec_cmd("qs -c $qsConfig")'])
                self.assertEqual(manifest["files"][2]["include"], ["-- [pentad setup] Pentad's Hyprland fragment", LUA_INCLUDE])
                self.assertEqual(manifest["units"], [])
                self.assertEqual((self.state / STAMP / "1-execs.lua").read_text(encoding="utf-8"), EXECS_LUA)
                self.assertEqual((self.state / STAMP / "3-hyprland.lua").read_text(encoding="utf-8"), HYPRLAND_LUA)
                for entry in manifest["files"]:
                    self.assertEqual(entry["sha256After"], sha256(Path(entry["path"])))
                self.assertIn("-j configerrors", self.hyprctl_log())
                self.assertNotIn("reload", self.hyprctl_log())  # the automatic reload was enough
                output, status = self.run_setup("--undo", stdin=NeverRead())
                self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland.lua.\nRestored ~/.config/hypr/hyprland/execs.lua.\n"
                                                    "Removed ~/.config/hypr/pentad.lua.\n", 0))
                self.assertEqual((self.hypr / "hyprland/execs.lua").read_bytes(), EXECS_LUA.encode())
                self.assertEqual((self.hypr / "hyprland.lua").read_bytes(), HYPRLAND_LUA.encode())
                self.assertFalse((self.hypr / "pentad.lua").exists())
                self.assertEqual(self.manifest()["undone"], "2026-10-24T12:00:00+00:00")
                self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))
                shutil.rmtree(self.state)
                (self.ctl / "log").unlink()

    def test_a_conf_config_gets_a_pentad_conf_and_a_source_line(self):
        self.proc(2411, "waybar")
        self.layers((1, 2411, "waybar"))
        write(self.hypr / "hyprland.conf", "exec-once = waybar # bar\nbind = SUPER, B, exec, waybar\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("hyprland.conf"),
                         "# [pentad setup] exec-once = waybar # bar\nbind = SUPER, B, exec, waybar\n"
                         f"\n# [pentad setup] Pentad's Hyprland fragment\nsource = {self.hypr}/pentad.conf\n")
        self.assertEqual(self.read("pentad.conf"), f"{CONF_HEADER}exec-once = pentad start\n")
        self.assertIn(f"By hand\n  Pentad's key bindings are in {self.root}/defaults/hyprland-quickshell.lua; copy the ones you want.\n",
                      output)
        self.assertNotIn("dofile", output)
        self.assertNotIn("another shell's own setup", output)
        self.assertIn("Heads-up\n  The changes take effect at the next login, or now if you agree to it after applying.\n", output)
        self.assertNotIn("key bindings take effect", output)

    def test_every_untouched_byte_and_the_mode_survive_apply_and_undo(self):
        self.proc(2411, "waybar")
        self.layers((1, 2411, "waybar"))
        original = b"exec-once = waybar\r\n# caf\xc3\xa9 \xff\r\nbind = SUPER, B, exec, waybar"
        path = self.hypr / "hyprland.conf"
        path.write_bytes(original)
        path.chmod(0o640)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(path.read_bytes(),
                         b"# [pentad setup] exec-once = waybar\r\n# caf\xc3\xa9 \xff\r\nbind = SUPER, B, exec, waybar\r\n"
                         b"\r\n# [pentad setup] Pentad's Hyprland fragment\r\nsource = " + str(self.hypr / "pentad.conf").encode() + b"\r\n")
        self.assertEqual(path.stat().st_mode & 0o777, 0o640)
        self.assertEqual((self.hypr / "pentad.conf").stat().st_mode & 0o777, 0o644)
        output, status = self.run_setup("--undo")
        self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland.conf.\nRemoved ~/.config/hypr/pentad.conf.\n", 0))
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(path.stat().st_mode & 0o777, 0o640)
        self.assertFalse((self.hypr / "pentad.conf").exists())

    def test_undo_takes_the_newest_run_first_even_with_the_same_timestamp(self):
        self.ii_shell()
        self.run_setup()
        write(self.hypr / "extra.conf", "exec-once = qs -c ii\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn(f"~/.local/state/pentad/setup/{STAMP}-2;", output)
        self.assertNotIn("pentad.lua", output.split("Changes", 1)[1].split("By hand", 1)[0])  # the fragment is already right
        self.assertEqual(self.read("extra.conf"), "# [pentad setup] exec-once = qs -c ii\n")
        output, status = self.run_setup("--undo")
        self.assertEqual((output, status), ("Restored ~/.config/hypr/extra.conf.\n", 0))
        self.assertEqual(self.read("hyprland.lua"), self.expected_hyprland_lua())
        output, status = self.run_setup("--undo")
        self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland.lua.\nRestored ~/.config/hypr/hyprland/execs.lua.\n"
                                            "Removed ~/.config/hypr/pentad.lua.\n", 0))
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA)
        self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))

    def test_a_fragment_with_setups_header_is_regenerated_and_a_v1_include_is_kept(self):
        self.ii_shell()
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA + f'dofile("{self.hypr}/pentad.lua") -- mine\n')
        write(self.hypr / "pentad.lua", "-- [pentad setup] Цей файл пише `pentad setup`; зміни тут можуть бути перезаписані.\n-- stale\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("--- ~/.config/hypr/pentad.lua\n+++ ~/.config/hypr/pentad.lua\n@@ -1,2 +1,3 @@\n", output)
        self.assertNotIn("--- ~/.config/hypr/hyprland.lua", output)
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + f'dofile("{self.hypr}/pentad.lua") -- mine\n')
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())
        self.assertTrue((self.state / STAMP / "2-pentad.lua").read_text(encoding="utf-8").endswith("-- stale\n"))
        output, status = self.run_setup("--undo")
        self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland/execs.lua.\nRestored ~/.config/hypr/pentad.lua.\n", 0))
        self.assertTrue(self.read("pentad.lua").endswith("-- stale\n"))

    def test_a_fragment_the_user_wrote_is_left_alone(self):
        self.ii_shell()
        write(self.hypr / "pentad.lua", "-- mine\nhl.exec_cmd('x')\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("  ~/.config/hypr/pentad.lua was not written by pentad setup (its first line is not setup's header), so it is yours; "
                      f"add to it yourself: {LUA_START} dofile(\"{self.root}/defaults/hyprland-quickshell.lua\")\n", output)
        self.assertEqual(self.read("pentad.lua"), "-- mine\nhl.exec_cmd('x')\n")
        self.assertEqual(self.read("hyprland.lua"), self.expected_hyprland_lua())  # the include still makes sense: the file exists

    def test_an_existing_require_of_the_fragment_is_not_repeated(self):
        self.ii_shell()
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA + 'require "pentad"\n')
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertNotIn("--- ~/.config/hypr/hyprland.lua", output)
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + 'require "pentad"\n')

    def test_an_entry_file_ending_in_return_gets_the_include_by_hand(self):
        self.ii_shell()
        for ending in ("return {\n  a = 1,\n}\n-- the end\n", "  return\n"):
            with self.subTest(ending=ending):
                write(self.hypr / "hyprland.lua", HYPRLAND_LUA + ending)
                (self.hypr / "pentad.lua").unlink(missing_ok=True)
                write(self.hypr / "hyprland/execs.lua", EXECS_LUA)
                output, status = self.run_setup()
                self.assertEqual(status, 0, output)
                self.assertIn(f"  ~/.config/hypr/hyprland.lua has a return; add {LUA_INCLUDE} before it by hand.\n", output)
                self.assertNotIn("--- ~/.config/hypr/hyprland.lua", output)
                self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + ending)
                self.assertEqual(self.read("pentad.lua"), self.expected_fragment())
                self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())
                shutil.rmtree(self.state)

    def test_a_file_that_does_not_parse_as_lua_is_not_touched(self):
        self.ii_shell()
        write(self.hypr / "hyprland/execs.lua", EXECS_LUA.replace("end)\n", ""))  # the hook never closes
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA + 'x = "open\n')
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("  ~/.config/hypr/hyprland/execs.lua:4: the file does not parse as Lua (unclosed bracket, function); "
                      'comment the line out by hand: hl.exec_cmd("qs -c $qsConfig")\n', output)
        self.assertIn(f"  ~/.config/hypr/hyprland.lua does not parse as Lua (line 4: unfinished string); add {LUA_INCLUDE} by hand.\n", output)
        self.assertNotIn("--- ~/.config/hypr/hyprland", output)

    def test_two_holders_sharing_a_start_line_comment_it_once(self):
        self.ii_shell()
        self.proc(2412, "qs", ["qs", "-c", "ii"], environment={"qsConfig": "ii"})
        self.layers((0, 2411, "wallpaper"), (1, 2412, "bar"))
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertNotIn("By hand\n  ~/.config/hypr/hyprland/execs.lua:4", output)
        self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())

    def test_a_root_without_pentad_files_is_refused(self):
        self.ii_shell()
        (self.root / "shell.qml").unlink()
        output, status = self.run_setup(stdin=NeverRead())
        self.assertEqual(status, 1, output)
        self.assertEqual(output, f"Pentad files not found in {self.root}; check --path or install Pentad again.\n")
        self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA)

    def test_a_hard_linked_file_is_listed_for_hand_editing_not_written(self):
        self.ii_shell()
        (self.temp / "execs-link.lua").hardlink_to(self.hypr / "hyprland/execs.lua")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("  ~/.config/hypr/hyprland/execs.lua:4: the file has other hard links; comment the line out by hand.\n", output)
        self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA)

    def test_declining_or_eof_changes_nothing(self):
        self.ii_shell()
        for answer in ("n\n", "", "Y es\n"):
            with self.subTest(answer=answer):
                output, status = self.run_setup(stdin=io.StringIO(answer))
                self.assertEqual(status, 1, output)
                self.assertTrue(output.endswith("Apply these changes? [y/N] \nNothing changed.\n" if not answer.endswith("\n")
                                                else "Apply these changes? [y/N] Nothing changed.\n"), output)
                self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA)
                self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA)
                self.assertFalse((self.hypr / "pentad.lua").exists())
                self.assertFalse(self.state.exists())

    def test_a_file_changed_after_the_plan_is_not_written_and_the_rest_is_restored(self):
        self.ii_shell()
        output, status = self.run_setup(stdin=Tampering(self.hypr / "hyprland.lua", "-- mine\n"))
        self.assertEqual(status, 1, output)
        self.assertIn("~/.config/hypr/hyprland.lua changed after the plan was shown; it was not written.\n"
                      "The files written before it were restored.\nNothing changed.\n", output)
        self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA)
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + "-- mine\n")
        self.assertFalse((self.hypr / "pentad.lua").exists())
        self.assertEqual(list(self.state.iterdir()), [])  # the run's backups go with the aborted run
        self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))

    def test_a_failed_write_restores_what_was_written(self):
        self.ii_shell()
        real_replace = setup.os.replace

        def replace(source, target):
            if Path(target).name == "hyprland.lua":
                raise OSError(28, "No space left on device")
            real_replace(source, target)

        with patch.object(setup.os, "replace", replace):
            output, status = self.run_setup()
        self.assertEqual(status, 1, output)
        self.assertIn("Could not write ~/.config/hypr/hyprland.lua: No space left on device.\n"
                      "The files written before it were restored.\nNothing changed.\n", output)
        self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA)
        self.assertEqual(sorted(path.name for path in self.hypr.rglob("*")),
                         ["execs.lua", "hyprland", "hyprland.lua", "keybinds.lua"])

    def test_a_symlinked_file_is_listed_for_hand_editing_not_written(self):
        self.ii_shell()
        target = self.temp / "dotfiles/execs.lua"
        write(target, EXECS_LUA)
        (self.hypr / "hyprland/execs.lua").unlink()
        (self.hypr / "hyprland/execs.lua").symlink_to(target)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("  ~/.config/hypr/hyprland/execs.lua:4: the file is a symlink; comment the line out by hand.\n", output)
        self.assertNotIn("--- ~/.config/hypr/hyprland/execs.lua", output)
        self.assertNotIn("another shell's own setup", output)
        self.assertEqual(target.read_text(encoding="utf-8"), EXECS_LUA)
        self.assertEqual(self.read("hyprland.lua"), self.expected_hyprland_lua())
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())

    def test_other_start_lines_and_shell_lists_are_left_to_the_user(self):
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        self.proc(42, "mako")
        self.notification_owner(42)
        self.layers((1, 2411, "bar"))
        write(self.hypr / "hyprland.lua", 'hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii")\nend)\n'
                                          'hl.exec_cmd("sleep 1 && qs -c ii")\n'
                                          'hl.on("hyprland.start", function () hl.exec_cmd("pentad start") end)\n')
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("By hand\n"
                      "  mako (pid 42) holds: notifications. No start line for it was found in ~/.config/hypr. "
                      "If you already removed it, it is still running from this session: log out and back in. "
                      "Otherwise remove it from your session's autostart by hand.\n"
                      "  ~/.config/hypr/hyprland.lua:1: not a single plain start command; comment the call out by hand: "
                      'hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii")\n'
                      "  ~/.config/hypr/hyprland.lua:3: not a single plain start command; comment the call out by hand: "
                      'hl.exec_cmd("sleep 1 && qs -c ii")\n', output)
        self.assertTrue(output.endswith("\npentad setup cannot make any of these changes itself; edit the items above by hand.\n"), output)
        self.assertNotIn("Apply these changes", output)
        self.assertFalse((self.hypr / "pentad.lua").exists())
        self.assertFalse(self.state.exists())

    def test_only_single_plain_start_statements_are_commentable(self):
        call = 'hl.exec_cmd("qs -c $qsConfig")'
        accepted = [
            ('hl.on("hyprland.start", function ()\n    ' + call + "\nend)\n", 2, True),
            ("hl.exec_cmd('qs -c ii')\n", 1, True),
            ('hl.on("x", function ()\nend)\nhl.exec_cmd("uwsm app -- qs -c ii") -- through uwsm\n', 3, True),
            ('hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii") end)\n', 1, True),
            ("hl.on('hyprland.start',function()hl.exec_cmd('noctalia')end) -- Noctalia\n", 1, True),
            ('hl.on("hyprland.start", function () hl.exec_cmd("dms run") end);\n', 1, True),
            ('hl.exec_cmd("qs -c ii &")\n', 1, True),
            ("exec-once = waybar\n", 1, False),
            ("exec = qs -c ii # shell\n", 1, False),
            ("exec-once = [workspace 1 silent] waybar &\n", 1, False),
        ]
        refused = [
            ('hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii")\nend)\n', 1, True),
            ('hl.on("other.event", function () hl.exec_cmd("qs -c ii") end)\n', 1, True),
            ('hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii") hl.exec_cmd("waybar") end)\n', 1, True),
            ('if x then hl.exec_cmd("qs -c ii") end\n', 1, True),
            ("hl.exec_cmd([[qs -c ii]])\n", 1, True),
            ('hl.exec_cmd("sleep 1 && qs -c ii")\n', 1, True),
            ('hl.exec_cmd("qs -c ii; waybar")\n', 1, True),
            ('hl.exec_cmd("qs -c ii & waybar")\n', 1, True),
            ('hl.exec_cmd("qs -c \\"ii\\"")\n', 1, True),
            ('hl.exec_cmd("qs -c ii"); hl.exec_cmd("waybar")\n', 1, True),
            ('hl.exec_cmd("qs -c ii") --[[ old:\n', 1, True),
            ('hl.exec_cmd("qs") --[[x]] hl.exec_cmd("waybar")\n', 1, True),
            ("local start =\n" + call + "\n", 2, True),
            ('hl.exec_cmd("waybar"),\n' + call + "\n", 2, True),
            ("--[[\n" + call + "\n]]\n", 2, True),
            ("x = [==[\n" + call + "\n]==]\n", 2, True),
            ("t = {\n" + call + "\n}\n", 2, True),
            ('hl.bind("SUPER + R", hl.dsp.exec_cmd("qs -c ii"))\n', 1, True),
            ('hl.exec_cmd("qs -c ii ipc call x")\n', 1, True) if False else ("-- [pentad setup] " + call + "\n", 1, True),
            ("exec-once = qs -c ii & waybar\n", 1, False),
            ("exec-once = cliphist wipe && qs -c ii\n", 1, False),
            ("exec-once = qs -c ii | tee log\n", 1, False),
            ("bind = SUPER, B, exec, qs -c ii\n", 1, False),
        ]
        for content, number, is_lua in accepted:
            with self.subTest(content=content):
                self.assertTrue(setup.commentable(content, number, is_lua))
        for content, number, is_lua in refused:
            with self.subTest(content=content):
                self.assertFalse(setup.commentable(content, number, is_lua))
        self.assertEqual(setup.plain_command("exec-once = [workspace 1 silent] waybar &\n", 1, False), "[workspace 1 silent] waybar")
        self.assertEqual(setup.first_program("[workspace 1 silent] uwsm app -- env FOO=1 waybar -c x"), "waybar")

    def test_undo_after_a_user_edit_falls_back_to_the_markers_after_a_yes(self):
        self.ii_shell()
        self.run_setup()
        edited_execs = self.expected_execs() + "-- edited later\n"
        write(self.hypr / "hyprland/execs.lua", edited_execs)
        edited_entry = self.expected_hyprland_lua() + "-- also edited\n"
        write(self.hypr / "hyprland.lua", edited_entry)
        output, status = self.run_setup("--undo", stdin=io.StringIO("n\n"))
        self.assertEqual(status, 1, output)
        self.assertIn("These files changed after pentad setup; its marked lines can be undone like this:\n"
                      "--- ~/.config/hypr/hyprland.lua\n+++ ~/.config/hypr/hyprland.lua\n", output)
        self.assertIn("--- ~/.config/hypr/hyprland/execs.lua\n+++ ~/.config/hypr/hyprland/execs.lua\n", output)
        self.assertIn('-    -- [pentad setup] hl.exec_cmd("qs -c $qsConfig")\n+    hl.exec_cmd("qs -c $qsConfig")\n', output)
        self.assertIn(f"--- [pentad setup] Pentad's Hyprland fragment\n-{LUA_INCLUDE}\n -- also edited\n", output)
        self.assertTrue(output.endswith("Undo these lines? [y/N] The marked lines are left as they are.\n"
                                        "Left ~/.config/hypr/pentad.lua alone: ~/.config/hypr/hyprland.lua, ~/.config/hypr/hyprland/execs.lua "
                                        "was left alone and may still load it.\n"), output)
        self.assertEqual(self.read("hyprland/execs.lua"), edited_execs)
        self.assertEqual(self.read("hyprland.lua"), edited_entry)
        self.assertTrue((self.hypr / "pentad.lua").exists())
        self.assertNotIn("undone", self.manifest())
        output, status = self.run_setup("--undo", stdin=io.StringIO("y\n"))
        self.assertEqual(status, 0, output)
        self.assertTrue(output.endswith("Undo these lines? [y/N] Unmarked the lines in ~/.config/hypr/hyprland.lua.\n"
                                        "Unmarked the lines in ~/.config/hypr/hyprland/execs.lua.\nRemoved ~/.config/hypr/pentad.lua.\n"), output)
        self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA + "-- edited later\n")
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + "\n-- also edited\n")
        self.assertFalse((self.hypr / "pentad.lua").exists())  # nothing loads it any more
        self.assertEqual(self.manifest()["undone"], "2026-10-24T12:00:00+00:00")

    def test_undo_reports_a_marked_line_the_user_changed(self):
        self.ii_shell()
        self.run_setup()
        edited = self.expected_execs().replace('-- [pentad setup] hl.exec_cmd("qs -c $qsConfig")',
                                               '-- [pentad setup] hl.exec_cmd("qs -c ii")') + "-- edited\n"
        write(self.hypr / "hyprland/execs.lua", edited)
        output, status = self.run_setup("--undo", stdin=io.StringIO("y\n"))
        self.assertEqual(status, 0, output)
        self.assertIn("Left ~/.config/hypr/hyprland/execs.lua alone: it changed after pentad setup; "
                      f"the backup is ~/.local/state/pentad/setup/{STAMP}/1-execs.lua.\n", output)
        self.assertIn("Restored ~/.config/hypr/hyprland.lua.\n", output)
        self.assertNotIn("Undo these lines", output)
        self.assertEqual(self.read("hyprland/execs.lua"), edited)
        edited = self.expected_execs().replace('"qs -c $qsConfig")', '"qs -c $qsConfig") -- old') + "\n-- edited\n"
        write(self.hypr / "hyprland/execs.lua", edited)
        write(self.hypr / "hyprland.lua", self.expected_hyprland_lua())
        write(self.hypr / "pentad.lua", self.expected_fragment())
        shutil.rmtree(self.state)
        self.ii_shell()
        self.run_setup()  # a run that comments nothing new but records the entry include again
        self.assertEqual(self.run_setup("--undo", stdin=io.StringIO("y\n"))[1], 0)

    def test_undo_keeps_the_fragment_while_the_entry_file_still_loads_it(self):
        self.ii_shell()
        self.run_setup()
        edited = HYPRLAND_LUA + f"\n-- my own note\n{LUA_INCLUDE}\n"  # the user removed the marker line
        write(self.hypr / "hyprland.lua", edited)
        output, status = self.run_setup("--undo", stdin=NeverRead())
        self.assertEqual(status, 0, output)
        self.assertEqual(output, "Left ~/.config/hypr/hyprland.lua alone: it changed after pentad setup; "
                                 f"the backup is ~/.local/state/pentad/setup/{STAMP}/3-hyprland.lua.\n"
                                 "Restored ~/.config/hypr/hyprland/execs.lua.\n"
                                 "Left ~/.config/hypr/pentad.lua alone: ~/.config/hypr/hyprland.lua was left alone and may still load it.\n")
        self.assertEqual(self.read("hyprland.lua"), edited)
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())

    def test_a_v1_manifest_is_still_undone(self):
        write(self.hypr / "hyprland.conf", "# [pentad setup] exec-once = waybar\n")
        write(self.hypr / "pentad.conf", "x\n")
        write(self.state / STAMP / "1-hyprland.conf", "exec-once = waybar\n")
        manifest = {"schemaVersion": 1, "created": "2026-10-24T11:00:00+00:00",
                    "files": [{"path": str(self.hypr / "hyprland.conf"), "backup": "1-hyprland.conf", "sha256After": sha256(self.hypr / "hyprland.conf")},
                              {"path": str(self.hypr / "pentad.conf"), "backup": None, "sha256After": sha256(self.hypr / "pentad.conf")}]}
        write(self.state / STAMP / "manifest.json", json.dumps(manifest))
        output, status = self.run_setup("--undo", stdin=NeverRead())
        self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland.conf.\nRemoved ~/.config/hypr/pentad.conf.\n", 0))
        self.assertEqual(self.read("hyprland.conf"), "exec-once = waybar\n")

    def test_a_later_run_keeps_the_bindings_the_fragment_already_loads(self):
        self.ii_shell()
        (self.hypr / "hyprland/keybinds.lua").unlink()  # no foreign bindings this time
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA + f"{LUA_INCLUDE}\n")
        write(self.hypr / "pentad.lua", "-- [pentad setup] old header\n" + self.expected_fragment()[len(LUA_HEADER):])
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())
        self.assertIn("Heads-up\n  The changes take effect at the next login, or now if you agree to it after applying.\n", output)  # the dofile is not new

    def test_interpreter_hosted_and_indirect_start_lines_are_left_to_the_user(self):
        self.proc(2411, "python", ["python", str(self.home / ".config/Ax-Shell/main.py")])
        self.layers((1, 2411, "ax-bar"))
        content = "exec-once = python ~/.config/Ax-Shell/main.py\nexec-once = python ~/bin/battery.py\n"
        write(self.hypr / "hyprland.conf", content)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("hyprland.conf"), content + f"\n# [pentad setup] Pentad's Hyprland fragment\nsource = {self.hypr}/pentad.conf\n")
        self.assertIn("  ~/.config/hypr/hyprland.conf:1: the line runs the interpreter python, so it is not commented out automatically: "
                      "exec-once = python ~/.config/Ax-Shell/main.py\n", output)
        self.assertNotIn("hyprland.conf:2", output)  # another script under the same interpreter is not this shell
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        write(self.hypr / "hyprland.conf", "exec-once = wl-paste --watch qs -c ii\nexec-once = uwsm app -- qs -c ii\n"
                                           "exec-once = env QT_QPA_PLATFORM=wayland qs -c ii\nexec-once = pentad start\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("hyprland.conf"),
                         "exec-once = wl-paste --watch qs -c ii\n# [pentad setup] exec-once = uwsm app -- qs -c ii\n"
                         "# [pentad setup] exec-once = env QT_QPA_PLATFORM=wayland qs -c ii\nexec-once = pentad start\n")
        self.assertIn("  ~/.config/hypr/hyprland.conf:1: the line does not start qs -c ii directly; change it by hand: "
                      "exec-once = wl-paste --watch qs -c ii\n", output)

    def test_a_continuation_before_blank_and_comment_lines_is_left_to_the_user(self):
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        self.layers((1, 2411, "bar"))
        content = f'local x =\n\n-- note\n    hl.exec_cmd("qs -c ii")\n{LUA_START}\n'
        write(self.hypr / "hyprland.lua", content)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn('  ~/.config/hypr/hyprland.lua:4: not a single plain start command; comment the call out by hand: hl.exec_cmd("qs -c ii")\n',
                      output)
        self.assertEqual(self.read("hyprland.lua"), content)

    def test_undo_without_any_run_says_so(self):
        self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))

    def test_nothing_to_do_when_the_config_already_starts_pentad(self):
        write(self.hypr / "hyprland.conf", "exec-once = pentad start\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(output, "Pentad setup\n\nNothing to change: the Hyprland config already starts Pentad.\n")
        self.assertFalse((self.hypr / "pentad.conf").exists())

    def test_outside_a_hyprland_session_setup_only_previews(self):
        del self.env["HYPRLAND_INSTANCE_SIGNATURE"]
        write(self.hypr / "hyprland.conf", "exec-once = waybar\n")
        output, status = self.run_setup(stdin=NeverRead())
        self.assertEqual(status, 1, output)
        self.assertEqual(self.hyprctl_log(), [])
        self.assertIn("+exec-once = pentad start\n", output)
        self.assertTrue(output.endswith(
            "Heads-up\n  This is not a Hyprland session right now, so it is unknown who draws the wallpaper and panels, "
            "and the changes above are only a preview. Run pentad setup inside a Hyprland session.\n"), output)
        self.assertNotIn("Apply these changes", output)
        self.assertEqual(self.read("hyprland.conf"), "exec-once = waybar\n")
        self.assertFalse((self.hypr / "pentad.conf").exists())
        self.assertFalse(self.state.exists())

    def test_a_hyprland_started_with_another_config_gets_a_preview_only(self):
        self.proc(2411, "waybar")
        self.layers((1, 2411, "waybar"))
        write(self.hypr / "hyprland.conf", "exec-once = waybar\n")
        other = self.home / "dotfiles/hypr.conf"
        write(other, "exec-once = waybar\n")
        self.proc(HYPRLAND_PID, "Hyprland", ["Hyprland", "-c", str(other)], ppid=1)
        output, status = self.run_setup(stdin=NeverRead())
        self.assertEqual(status, 1, output)
        self.assertIn("Heads-up\n  Hyprland was started with the config ~/dotfiles/hypr.conf, so the files in ~/.config/hypr are not the ones in use; "
                      "pentad setup will not edit them and only shows its plan.\n  The changes above are only a preview.\n", output)
        self.assertEqual(self.read("hyprland.conf"), "exec-once = waybar\n")
        self.assertFalse(self.state.exists())
        self.proc(HYPRLAND_PID, "Hyprland", ["Hyprland", "-c", str(self.hypr / "hyprland.conf")], ppid=1)  # -c with the default file
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertNotIn("Hyprland was started with", output)

    def test_a_missing_entry_file_is_asked_for_by_hand(self):
        self.proc(42, "mako")
        self.notification_owner(42)
        write(self.hypr / "autostart.conf", "exec-once = mako\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("autostart.conf"), "# [pentad setup] exec-once = mako\n")
        self.assertEqual(self.read("pentad.conf"), f"{CONF_HEADER}exec-once = pentad start\n")
        self.assertIn(f"  Create ~/.config/hypr/hyprland.conf with source = {self.hypr}/pentad.conf, "
                      "unless your session starts Pentad another way.\n", output)
        self.assertFalse((self.hypr / "hyprland.conf").exists())

    # The shells, bars and daemons setup must recognise, each with the process tree it really has.

    def shells(self) -> list[dict]:
        home = self.home
        return [
            {"name": "illogical-impulse", "file": "hyprland/execs.lua", "content": EXECS_LUA, "line": 4,
             "procs": [(2411, "qs", ["qs", "-c", "ii"], {"environment": {"qsConfig": "ii"}})], "roles": [(0, 2411, "wallpaper"), (1, 2411, "bar")]},
            {"name": "Noctalia v5", "file": "hyprland.lua", "content": 'hl.on("hyprland.start", function () hl.exec_cmd("noctalia") end)\n', "line": 1,
             "procs": [(300, "noctalia", ["/bin/sh", "/usr/bin/noctalia"], {}), (301, "qs", ["qs", "-c", "noctalia-shell"], {"ppid": 300})],
             "roles": [(1, 301, "noctalia-bar")]},
            {"name": "Noctalia v5 exec wrapper", "file": "hyprland.lua", "content": 'hl.on("hyprland.start", function () hl.exec_cmd("noctalia") end)\n',
             "line": 1, "procs": [(301, "qs", ["qs", "-c", "noctalia-shell"], {})], "roles": [(1, 301, "noctalia-bar")]},
            {"name": "Noctalia v4", "file": "hyprland.conf", "content": "exec-once = qs -c noctalia-shell\n", "line": 1,
             "procs": [(301, "qs", ["qs", "-c", "noctalia-shell"], {})], "roles": [(1, 301, "noctalia-bar")]},
            {"name": "DankMaterialShell", "file": "hyprland.lua", "content": 'hl.on("hyprland.start", function () hl.exec_cmd("dms run") end)\n', "line": 1,
             "procs": [(310, "dms", ["dms", "run"], {}), (311, "qs", ["qs", "-p", f"{home}/.config/quickshell/dms"], {"ppid": 310})],
             "roles": [(1, 311, "dank-bar"), (0, 311, "dank-wallpaper")]},
            {"name": "DankMaterialShell shell.qml", "file": "hyprland.conf", "content": "exec-once = dms run\n", "line": 1,
             "procs": [(310, "dms", ["dms", "run"], {}), (311, "qs", ["qs", "-p", f"{home}/.config/quickshell/dms/shell.qml"], {"ppid": 310})],
             "roles": [(1, 311, "dank-bar")]},
            {"name": "Caelestia", "file": "hyprland.lua", "content": 'hl.on("hyprland.start", function () hl.exec_cmd("caelestia shell -d") end)\n',
             "line": 1, "procs": [(2, "systemd", ["/usr/lib/systemd/systemd", "--user"], {"ppid": 1}),
                                  (320, "qs", ["qs", "-c", "caelestia", "-n", "-d"], {"ppid": 2})],
             "roles": [(1, 320, "caelestia-bar")], "notifications": 320},
            {"name": "HyprPanel", "file": "hyprland.conf", "content": "exec-once = hyprpanel\n", "line": 1,
             "procs": [(330, "hyprpanel", ["/bin/sh", "/usr/bin/hyprpanel"], {}), (331, "gjs", ["gjs", "-m", "/usr/lib/hyprpanel/main.js"], {"ppid": 330})],
             "roles": [(1, 331, "bar-0")], "notifications": 331},
            {"name": "AGS v2", "file": "hyprland.conf", "content": "exec-once = ags run\n", "line": 1,
             "procs": [(340, "ags", ["ags", "run"], {}), (341, "gjs", ["gjs", "-m", "/tmp/ags-bundle.js"], {"ppid": 340})],
             "roles": [(1, 341, "ags-bar")]},
            {"name": "waybar", "file": "hyprland.conf", "content": "exec-once = waybar\n", "line": 1,
             "procs": [(350, "waybar", ["waybar"], {})], "roles": [(1, 350, "waybar")]},
            {"name": "waybar via uwsm app", "file": "hyprland.conf", "content": "exec-once = uwsm app -- waybar\n", "line": 1,
             "procs": [(2, "systemd", ["/usr/lib/systemd/systemd", "--user"], {"ppid": 1}),
                       (350, "waybar", ["waybar"], {"ppid": 2, "cgroup": "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-waybar@5.service"})],
             "roles": [(1, 350, "waybar")]},
            {"name": "mako", "file": "hyprland.conf", "content": "exec-once = mako\n", "line": 1, "procs": [(360, "mako", ["mako"], {})],
             "roles": [], "notifications": 360},
            {"name": "dunst", "file": "hyprland.lua", "content": 'hl.on("hyprland.start", function () hl.exec_cmd("dunst") end)\n', "line": 1,
             "procs": [(361, "dunst", ["/usr/bin/dunst"], {})], "roles": [], "notifications": 361},
            {"name": "swaync", "file": "hyprland.conf", "content": "exec-once = swaync\n", "line": 1, "procs": [(362, "swaync", ["swaync"], {})],
             "roles": [(2, 362, "swaync-control-center")], "notifications": 362},
            {"name": "hyprpaper", "file": "hyprland.lua", "content": 'hl.on("hyprland.start", function () hl.exec_cmd("hyprpaper") end)\n', "line": 1,
             "procs": [(370, "hyprpaper", ["hyprpaper"], {})], "roles": [(0, 370, "hyprpaper")]},
            {"name": "swww", "file": "hyprland.conf", "content": "exec-once = swww-daemon\n", "line": 1,
             "procs": [(371, "swww-daemon", ["swww-daemon"], {})], "roles": [(0, 371, "swww-daemon")]},
            {"name": "swaybg", "file": "hyprland.conf", "content": "exec-once = swaybg -i ~/w.png\n", "line": 1,
             "procs": [(372, "swaybg", ["swaybg", "-i", f"{home}/w.png"], {})], "roles": [(0, 372, "swaybg")]},
        ]

    def test_every_popular_shell_bar_and_daemon_is_recognised_and_its_start_line_commented(self):
        for case in self.shells():
            with self.subTest(case["name"]):
                shutil.rmtree(self.hypr, ignore_errors=True)
                shutil.rmtree(self.system / "proc", ignore_errors=True)
                shutil.rmtree(self.state, ignore_errors=True)
                self.proc(HYPRLAND_PID, "Hyprland", ["Hyprland"], ppid=1)
                for pid, comm, cmdline, extra in case["procs"]:
                    self.proc(pid, comm, cmdline, **extra)
                self.notification_owner(case.get("notifications"))
                self.layers(*case["roles"])
                write(self.hypr / case["file"], case["content"])
                if case["file"] != "hyprland.lua" and not case["file"].endswith(".conf"):
                    write(self.hypr / "hyprland.lua", 'require("hyprland.execs")\n')
                output, status = self.run_setup()
                self.assertEqual(status, 0, output)
                lines = case["content"].splitlines()
                is_lua = case["file"].endswith(".lua")
                expected = list(lines)
                expected[case["line"] - 1] = setup.commented(lines[case["line"] - 1], is_lua)
                self.assertEqual(self.read(case["file"]).splitlines()[:len(lines)], expected, output)
                self.assertNotIn("By hand\n  " + case["file"], output)
                self.assertNotIn("not a single plain start command", output)
                self.assertNotIn("does not start", output)

    def test_lines_that_only_look_like_start_lines_are_never_touched(self):
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        self.layers((1, 2411, "bar"))
        content = ('--[[\nhl.exec_cmd("qs -c ii")\n]]\n'
                   '--[==[ hl.exec_cmd("qs -c ii") ]==]\n'
                   'local doc = [[\nhl.exec_cmd("qs -c ii")\n]]\n'
                   'hl.exec_cmd("cliphist wipe && qs -c ii")\n'
                   'hl.bind("SUPER + R", hl.dsp.exec_cmd("qs -c ii"))\n'
                   'hl.exec_cmd("qs -c ii ipc call overview toggle")\n'
                   f"{LUA_START}\n")
        write(self.hypr / "hyprland.lua", content)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertTrue(self.read("hyprland.lua").startswith(content))  # only the include was appended, for the bindings fragment
        self.assertEqual(self.read("pentad.lua"), f"{LUA_HEADER}dofile(\"{self.root}/defaults/hyprland-quickshell.lua\")\n")
        self.assertIn("  ~/.config/hypr/hyprland.lua:8: not a single plain start command", output)
        self.assertIn("  ~/.config/hypr/hyprland.lua:10 calls qs -c ii but may do other work too", output)
        for number in (2, 4, 6, 9):
            self.assertNotIn(f"hyprland.lua:{number}", output)

    # Systemd units, XDG autostart entries and D-Bus activation.

    def test_a_systemd_user_service_is_masked_and_unmasked(self):
        self.proc(2, "systemd", ["/usr/lib/systemd/systemd", "--user"], ppid=1)
        self.proc(311, "qs", ["qs", "-p", f"{self.home}/.config/quickshell/dms"], ppid=2,
                  cgroup="0::/user.slice/user-1000.slice/user@1000.service/app.slice/dms.service")
        self.layers((1, 311, "dank-bar"))
        write(self.hypr / "hyprland.conf", "")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("--- ~/.config/hypr/hyprland.conf\n", output)
        self.assertIn("\n  systemctl --user mask dms.service\n", output)
        self.assertIn("  A masked service is not stopped by this; it just does not start next time.\n", output)
        self.assertIn("Apply these changes? [y/N] " + APPLIED, output)
        self.assertEqual(self.systemctl_log(), ["--user mask dms.service"])
        link = self.home / ".config/systemd/user/dms.service"
        self.assertTrue(link.is_symlink())
        self.assertEqual(self.manifest()["units"], [{"unit": "dms.service", "mask": str(link)}])
        link.unlink()
        write(link, "[Unit]\n")  # the user replaced the mask with a real unit file
        output, status = self.run_setup("--undo")
        self.assertEqual(status, 0, output)
        self.assertIn("Left dms.service masked: ~/.config/systemd/user/dms.service is no longer the /dev/null link.\n", output)
        self.assertEqual(self.systemctl_log(), ["--user mask dms.service"])
        shutil.rmtree(self.state)
        link.unlink()
        self.run_setup()
        output, status = self.run_setup("--undo")
        self.assertEqual(status, 0, output)
        self.assertIn("Unmasked dms.service.\n", output)
        self.assertFalse(link.exists())
        self.assertEqual(self.systemctl_log()[-1], "--user unmask dms.service")

    def test_a_unit_file_in_the_way_of_the_mask_is_refused(self):
        self.proc(350, "waybar", ["waybar"], cgroup="0::/user.slice/user-1000.slice/user@1000.service/app.slice/waybar.service")
        self.layers((1, 350, "waybar"))
        write(self.home / ".config/systemd/user/waybar.service", "[Unit]\n")
        write(self.hypr / "hyprland.conf", "exec-once = pentad start\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("By hand\n  waybar (pid 350) holds: panels and overlays. Runs as the systemd service waybar.service, and "
                      "~/.config/systemd/user/waybar.service already holds a unit file, so it cannot be masked; disable it yourself: "
                      "systemctl --user disable --now waybar.service\n", output)
        self.assertEqual(self.systemctl_log(), [])

    def test_xdg_autostart_entries_are_hidden_and_undone(self):
        self.proc(350, "waybar", ["waybar"])
        self.proc(360, "mako", ["mako"])
        self.notification_owner(360)
        self.layers((1, 350, "waybar"))
        write(self.system / "etc/xdg/autostart/waybar.desktop", "[Desktop Entry]\nType=Application\nName=Waybar\nExec=waybar -c x\n")
        write(self.autostart / "mako.desktop", "[Desktop Entry]\nName=Mako\nExec=/usr/bin/mako %U\nType=Application\n\n[Desktop Action x]\nExec=mako\n")
        write(self.system / "etc/xdg/autostart/other.desktop", "[Desktop Entry]\nExec=waybar\nOnlyShowIn=GNOME;\n")
        write(self.hypr / "hyprland.conf", "exec-once = pentad start\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("--- ~/.config/autostart/mako.desktop\n+++ ~/.config/autostart/mako.desktop\n@@ -1,4 +1,6 @@\n [Desktop Entry]\n"
                      "+# [pentad setup] Pentad does this itself; entry hidden\n+Hidden=true\n Name=Mako\n", output)
        self.assertIn("--- ~/.config/autostart/waybar.desktop\n+++ ~/.config/autostart/waybar.desktop\n@@ -0,0 +1,3 @@\n"
                      f"+# [pentad setup] Hides {self.system}/etc/xdg/autostart/waybar.desktop: Pentad does this itself.\n+[Desktop Entry]\n+Hidden=true\n", output)
        self.assertNotIn("other.desktop", output)
        self.assertEqual((self.autostart / "waybar.desktop").read_text(encoding="utf-8"),
                         f"# [pentad setup] Hides {self.system}/etc/xdg/autostart/waybar.desktop: Pentad does this itself.\n[Desktop Entry]\nHidden=true\n")
        self.assertEqual((self.autostart / "mako.desktop").read_text(encoding="utf-8"),
                         "[Desktop Entry]\n# [pentad setup] Pentad does this itself; entry hidden\nHidden=true\nName=Mako\nExec=/usr/bin/mako %U\n"
                         "Type=Application\n\n[Desktop Action x]\nExec=mako\n")
        roles = [entry["role"] for entry in self.manifest()["files"]]
        self.assertEqual(roles, ["autostart", "autostart"])
        write(self.autostart / "mako.desktop", (self.autostart / "mako.desktop").read_text(encoding="utf-8") + "Comment=edited\n")
        output, status = self.run_setup("--undo", stdin=io.StringIO("y\n"))
        self.assertEqual(status, 0, output)
        self.assertIn("Undo these lines? [y/N] Unmarked the lines in ~/.config/autostart/mako.desktop.\n", output)
        self.assertIn("Removed ~/.config/autostart/waybar.desktop.\n", output)
        self.assertEqual((self.autostart / "mako.desktop").read_text(encoding="utf-8"),
                         "[Desktop Entry]\nName=Mako\nExec=/usr/bin/mako %U\nType=Application\n\n[Desktop Action x]\nExec=mako\nComment=edited\n")
        self.assertFalse((self.autostart / "waybar.desktop").exists())

    def test_an_autostart_entry_with_a_hidden_key_or_already_hidden_is_left_alone(self):
        self.proc(350, "waybar", ["waybar"])
        self.layers((1, 350, "waybar"))
        write(self.autostart / "waybar.desktop", "[Desktop Entry]\nExec=waybar\nHidden=false\n")
        write(self.system / "etc/xdg/autostart/waybar.desktop", "[Desktop Entry]\nExec=waybar\n")
        write(self.hypr / "hyprland.conf", "exec-once = pentad start\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("  ~/.config/autostart/waybar.desktop: the entry already has a Hidden key; set Hidden=true in it yourself.\n", output)
        self.assertNotIn("Changes", output)
        write(self.autostart / "waybar.desktop", "[Desktop Entry]\nExec=waybar\nHidden=true\n")
        output, status = self.run_setup()
        self.assertIn("No start line for it was found", output)  # hidden already, so nothing starts it

    def test_a_dbus_activation_file_for_notifications_is_a_heads_up_only(self):
        self.proc(360, "mako", ["mako"])
        self.notification_owner(360)
        write(self.hypr / "hyprland.conf", "exec-once = mako\n")
        write(self.system / "usr/share/dbus-1/services/fr.emersion.mako.service",
              "[D-BUS Service]\nName=org.freedesktop.Notifications\nExec=/usr/bin/mako\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn(f"  The D-Bus activation file {self.system}/usr/share/dbus-1/services/fr.emersion.mako.service starts mako as soon as "
                      "something asks for notifications while no notification server runs. Pentad shows notifications itself, so start it "
                      "before such programs; if mako keeps coming back, that file (from its package) is why.\n", output)
        self.assertTrue((self.system / "usr/share/dbus-1/services/fr.emersion.mako.service").exists())
        self.proc(362, "swaync", ["swaync"], cgroup="0::/user.slice/user-1000.slice/user@1000.service/app.slice/swaync.service")
        self.notification_owner(362)
        write(self.system / "usr/share/dbus-1/services/fr.emersion.mako.service",
              "[D-BUS Service]\nName=org.freedesktop.Notifications\nExec=/usr/bin/swaync\nSystemdService=swaync.service\n")
        shutil.rmtree(self.state)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("  systemctl --user mask swaync.service\n", output)
        self.assertIn("starts the service swaync.service as soon as something asks for notifications while no notification server runs; "
                      "a masked service does not start.\n", output)

    # Hyprland verifies: the event socket, configerrors, the single reload, and the rollback.

    def test_new_config_errors_roll_everything_back(self):
        self.ii_shell()
        self.proc(350, "waybar", ["waybar"], cgroup="0::/user.slice/user-1000.slice/user@1000.service/app.slice/waybar.service")
        self.layers((0, 2411, "wallpaper"), (1, 350, "waybar"))
        write(self.ctl / "error-rule", f"{self.hypr}/hyprland.lua\n{LUA_INCLUDE}\nconfig reload: [string]:5: attempt to call a nil value\n")
        output, status = self.run_setup()
        self.assertEqual(status, 1, output)
        self.assertTrue(output.endswith("Apply these changes? [y/N] Hyprland reports new config errors:\n"
                                        "  config reload: [string]:5: attempt to call a nil value\n"
                                        "The files written before it were restored.\nNothing changed.\n"), output)
        self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA)
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA)
        self.assertFalse((self.hypr / "pentad.lua").exists())
        self.assertEqual(self.systemctl_log(), ["--user mask waybar.service", "--user unmask waybar.service"])
        self.assertFalse((self.home / ".config/systemd/user/waybar.service").is_symlink())
        self.assertEqual(list(self.state.iterdir()), [])
        self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))
        self.assertGreaterEqual(self.socket2.sent, 2)  # one reload for the change, one for the restore

    def test_errors_already_present_before_the_change_do_not_count_but_block_the_confirmation(self):
        self.ii_shell()
        write(self.ctl / "errors-base.json", json.dumps(["old: something", ""]))
        output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 0, output)
        self.assertIn("  Hyprland already reports errors in this config (1), so pentad setup cannot confirm that Pentad's lines load; "
                      "fix those first (hyprctl configerrors).\n", output)
        self.assertTrue(output.endswith("Apply these changes? [y/N] No new errors, but Hyprland still reports the old ones, so whether Pentad's "
                                        "lines load is unknown; fix them and run pentad doctor.\n"
                                        f"Applied. Backups are in ~/.local/state/pentad/setup/{STAMP}; undo with `pentad setup --undo`.\n"), output)
        self.assertFalse(self.manifest()["verified"])
        self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())

    def test_without_an_automatic_reload_setup_reloads_exactly_once(self):
        self.ii_shell()
        for label, policy, autoreload in (("autoreload disabled", "manual", True), ("no event came", "manual", False)):
            with self.subTest(label):
                self.hyprland(policy)
                write(self.ctl / "autoreload.json", json.dumps({"option": "misc:disable_autoreload", "bool": autoreload, "set": autoreload}))
                output, status = self.run_setup()
                self.assertEqual(status, 0, output)
                self.assertIn(APPLIED, output)
                self.assertEqual(self.hyprctl_log().count("reload"), 1)
                self.run_setup("--undo")
                (self.ctl / "log").unlink()
                shutil.rmtree(self.state)

    def test_when_hyprland_cannot_confirm_the_changes_stay_with_a_warning(self):
        self.ii_shell()
        cases = {
            "no event socket": ("none", "the event socket could not be opened"),
            "silence even after reload": ("silent", "no configreloaded event arrived after hyprctl reload"),
        }
        for label, (policy, reason) in cases.items():
            with self.subTest(label):
                self.hyprland(policy)
                output, status = self.run_setup()
                self.assertEqual(status, 0, output)
                self.assertIn(f"Hyprland did not confirm the changes ({reason}", output)
                self.assertIn("Check `hyprctl configerrors`; undo with `pentad setup --undo`.\n"
                              f"Applied. Backups are in ~/.local/state/pentad/setup/{STAMP}; undo with `pentad setup --undo`.\n", output)
                self.assertNotIn("Switch to Pentad now", output)
                self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())
                self.assertFalse(self.manifest()["verified"])
                self.run_setup("--undo")
                shutil.rmtree(self.state)
        self.hyprland("auto")
        (self.bin / "hyprctl").unlink()
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("Hyprland did not confirm the changes (hyprctl configerrors did not answer before the change)", output)

    # Switching now.

    def pentad_running(self) -> None:
        self.proc(100, "qs", ["qs", "--no-duplicate", "--path", str(self.root)])
        write(self.ctl / "layers-after.json", self.layers_json((1, 100, "pentad-bar"), (0, 100, "pentad-wallpaper")))
        write(self.ctl / "owner-after", "100")

    def test_switching_now_stops_the_old_shell_and_starts_pentad_through_hyprland(self):
        self.ii_shell()
        self.pentad_running()
        output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 0, output)
        self.assertTrue(output.endswith(SWITCH_PROMPT + "Pentad now holds: notifications, wallpaper, panels and overlays.\n"), output)
        self.assertEqual(self.killed, [(2411, 15)])
        self.assertIn(f"dispatch hl.dsp.exec_cmd('pentad start --path {self.root}')", self.hyprctl_log())
        self.assertFalse((self.system / "proc/2411").exists())

    def test_switching_now_uses_the_conf_dispatch_and_stops_a_unit(self):
        self.proc(350, "waybar", ["waybar"], cgroup="0::/user.slice/user-1000.slice/user@1000.service/app.slice/waybar.service")
        self.layers((1, 350, "waybar"))
        write(self.ctl / "unit-pid-waybar.service", "350")
        write(self.hypr / "hyprland.conf", "")
        self.pentad_running()
        output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 0, output)
        self.assertTrue(output.endswith("Pentad now holds: notifications, wallpaper, panels and overlays.\n"), output)
        self.assertEqual(self.killed, [])
        self.assertEqual(self.systemctl_log(), ["--user mask waybar.service", "--user stop waybar.service"])
        self.assertIn("dispatch exec pentad start --path " + str(self.root), self.hyprctl_log())

    def test_a_reused_pid_is_not_signalled(self):
        self.ii_shell()
        self.pentad_running()
        real_survey = doctor.survey

        def survey(root, env, system_root):
            found = real_survey(root, env, system_root)
            self.proc(2411, "qs", ["qs", "-c", "ii"], started=2000, environment={"qsConfig": "ii"})  # another process got the pid
            return found

        with patch.object(doctor, "survey", survey):
            output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(self.killed, [])
        self.assertIn("qs -c ii (pid 2411) is no longer the same process or has exited; no signal sent.\n", output)

    def test_a_switch_that_fails_names_the_old_start_command_and_the_undo(self):
        self.ii_shell()
        self.proc(100, "qs", ["qs", "--no-duplicate", "--path", str(self.root)])
        (self.bin / "pentad").unlink()
        output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 1, output)
        self.assertTrue(output.endswith("Could not build the command that starts Pentad through Hyprland; start it yourself: pentad start\n"
                                        "To bring the previous shell back for this session, start it the way autostart did:\n"
                                        '  hl.exec_cmd("qs -c $qsConfig")\n'
                                        "To restore the config, run `pentad setup --undo`.\n"), output)
        self.assertEqual(self.killed, [(2411, 15)])
        self.fake("pentad", "exit 0")
        self.ii_shell()
        shutil.rmtree(self.state)
        write(self.hypr / "hyprland/execs.lua", EXECS_LUA)
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA)
        (self.hypr / "pentad.lua").unlink()
        real_rmtree = shutil.rmtree
        with patch.object(self, "hooks", lambda: setup.Hooks(kill=lambda pid, sig: self.killed.append((pid, sig)), sleep=time.sleep, clock=time.monotonic)):
            output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 1, output)
        self.assertIn("Still running: qs -c ii (pid 2411). Pentad does not kill it; end it yourself or log out.\n", output)
        self.assertIn("Within 0.5 s Pentad took over only: nothing. Check `pentad doctor` and `pentad logs`.\n", output)
        self.assertIsNotNone(real_rmtree)

    def test_a_running_pentad_is_not_started_again(self):
        self.ii_shell()
        self.proc(100, "qs", ["qs", "--no-duplicate", "--path", str(self.root)])
        self.layers((0, 2411, "wallpaper"), (1, 100, "pentad-bar"))
        self.notification_owner(100)
        output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 0, output)
        self.assertIn("Pentad is already running; it was not started again.\n", output)
        self.assertNotIn("dispatch", "\n".join(self.hyprctl_log()))
        self.assertEqual(self.killed, [(2411, 15)])


    # Review fixes: write order, line splitting, Quickshell config names, partial rollback, launchers, dispatch replies.

    def test_the_entry_file_is_written_last_so_the_reload_finds_the_fragment(self):
        self.proc(2411, "waybar")
        self.layers((1, 2411, "waybar"))
        write(self.hypr / "hyprland.conf", "exec-once = waybar\n")
        # Hyprland reloads the moment the entry file is replaced; written first, it points at a fragment that
        # does not exist yet, so Hyprland runs a broken config (hyprlang: a source error) until setup's fallback
        # reload, and every extra reload re-runs the user's top-level Lua.
        real_write = setup.write_atomically

        def write_and_let_hyprland_react(path, data):  # the compositor handles the inotify event before the next write
            real_write(path, data)
            time.sleep(0.08)

        with patch.object(setup, "write_atomically", write_and_let_hyprland_react):
            with patch.object(setup, "write_order", lambda plan: sorted(plan.drafts, key=lambda draft: draft.before is None)):
                output, status = self.run_setup()
            self.assertEqual(status, 0, output)
            self.assertIn(["source= globbing error"], self.socket2.error_history)
            self.assertIn("reload", self.hyprctl_log())
            self.assertEqual(self.run_setup("--undo")[1], 0)
            (self.ctl / "log").unlink()
            self.socket2.error_history.clear()
            shutil.rmtree(self.state)
            output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn(APPLIED, output)
        self.assertEqual(self.socket2.error_history, [[]])  # one reload, with the fragment already in place
        self.assertIn(str(self.hypr / "pentad.conf"), self.socket2.reloaded_with[-1])
        self.assertNotIn("reload", self.hyprctl_log())

    def test_a_form_feed_in_a_comment_does_not_shift_the_line_that_is_commented(self):
        self.proc(2411, "waybar")
        self.layers((1, 2411, "waybar"))
        content = '-- section\x0c notes\nhl.exec_cmd("nm-applet")\nhl.exec_cmd("waybar")\n' + LUA_START + "\n"
        write(self.hypr / "hyprland.lua", content)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("hyprland.lua"), content.replace('hl.exec_cmd("waybar")', '-- [pentad setup] hl.exec_cmd("waybar")'))
        self.assertEqual(self.run_setup("--undo")[1], 0)
        self.assertEqual(self.read("hyprland.lua"), content)

    def test_a_qs_line_counts_only_when_it_selects_the_holders_config(self):
        self.ii_shell()
        write(self.hypr / "hyprland/execs.lua", EXECS_LUA.replace('    hl.exec_cmd("hypridle")\n',
                                                                  '    hl.exec_cmd("qs -c clock")\n    hl.exec_cmd("qs -p ~/src/pentad/quickshell")\n'
                                                                  '    hl.exec_cmd("qs -c $other")\n    hl.exec_cmd("qs")\n'))
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        execs = self.read("hyprland/execs.lua")
        self.assertIn('    -- [pentad setup] hl.exec_cmd("qs -c $qsConfig")\n', execs)  # $qsConfig=ii in the shell\'s environment
        self.assertIn('\n    hl.exec_cmd("qs -c clock")\n', execs)
        self.assertIn('\n    hl.exec_cmd("qs -p ~/src/pentad/quickshell")\n', execs)
        self.assertIn('\n    hl.exec_cmd("qs -c $other")\n', execs)
        self.assertIn('\n    hl.exec_cmd("qs")\n', execs)
        self.assertIn("  ~/.config/hypr/hyprland/execs.lua:7: the line uses a variable that the process environment does not hold, "
                      'so it is unknown whether it starts qs -c ii; comment it out by hand if it does: hl.exec_cmd("qs -c $other")\n', output)
        self.assertNotIn("execs.lua:5", output)  # qs -c clock is simply another shell, not even listed
        self.assertNotIn("execs.lua:6", output)
        self.assertNotIn("execs.lua:8", output)

    def test_a_partial_rollback_leaves_the_run_open_for_undo(self):
        self.ii_shell()
        write(self.ctl / "error-rule", f"{self.hypr}/hyprland.lua\n{LUA_INCLUDE}\nconfig reload: boom\n")
        real_put_back = setup.put_back
        calls = []

        def put_back(path, before):
            calls.append(path.name)
            if path.name == "execs.lua":
                raise OSError(5, "Input/output error")
            real_put_back(path, before)

        with patch.object(setup, "put_back", put_back):
            output, status = self.run_setup()
        self.assertEqual(status, 1, output)
        self.assertEqual(calls, ["hyprland.lua", "execs.lua"])  # the entry file goes back first
        self.assertIn("Could not restore ~/.config/hypr/hyprland/execs.lua; the backups are in "
                      f"~/.local/state/pentad/setup/{STAMP}, and `pentad setup --undo` finishes the restore.\n", output)
        self.assertNotIn("Nothing changed", output)
        manifest = self.manifest()
        self.assertEqual(manifest["rolledBack"], "partial")
        self.assertNotIn("undone", manifest)
        self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())
        output, status = self.run_setup("--undo")
        self.assertEqual(status, 0, output)
        self.assertIn("Restored ~/.config/hypr/hyprland/execs.lua.\n", output)
        self.assertEqual(self.read("hyprland/execs.lua"), EXECS_LUA)
        self.assertEqual(self.manifest()["undone"], "2026-10-24T12:00:00+00:00")

    def test_a_return_inside_a_top_level_block_also_sends_the_include_by_hand(self):
        self.ii_shell()
        for ending in ("do return end\n", "if os.getenv('X') then return end\n"):
            with self.subTest(ending=ending):
                write(self.hypr / "hyprland.lua", HYPRLAND_LUA + ending)
                output, status = self.run_setup()
                self.assertEqual(status, 0, output)
                self.assertIn(f"  ~/.config/hypr/hyprland.lua has a return; add {LUA_INCLUDE} before it by hand.\n", output)
                self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + ending)
                self.run_setup("--undo")
                shutil.rmtree(self.state)

    def test_the_reason_hyprland_could_not_confirm_is_in_the_users_language(self):
        self.env["LANG"] = "uk_UA.UTF-8"
        self.hyprland("none")
        self.ii_shell()
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("Hyprland не підтвердив зміни (не вдалося відкрити сокет подій (", output)
        self.assertNotIn("could not be opened", output)

    def test_a_dispatch_that_answers_anything_but_ok_is_a_failure(self):
        self.ii_shell()
        self.pentad_running()
        write(self.ctl / "dispatch-reply", "Invalid dispatcher\n")
        output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 1, output)
        self.assertIn(f"hyprctl dispatch hl.dsp.exec_cmd('pentad start --path {self.root}') failed (Invalid dispatcher); "
                      f"start Pentad yourself: pentad start --path {self.root}\n", output)
        self.assertIn("To restore the config, run `pentad setup --undo`.\n", output)

    def test_switching_now_stops_the_launcher_before_the_shell_it_would_restart(self):
        self.proc(310, "dms", ["dms", "run"])
        self.proc(311, "qs", ["qs", "-p", f"{self.home}/.config/quickshell/dms"], ppid=310)
        self.layers((1, 311, "dank-bar"))
        self.notification_owner(311)
        write(self.hypr / "hyprland.lua", 'hl.on("hyprland.start", function () hl.exec_cmd("dms run") end)\n')
        self.pentad_running()
        output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertEqual(status, 0, output)
        self.assertEqual(self.killed, [(310, 15), (311, 15)])
        self.assertTrue(output.endswith("Pentad now holds: notifications, wallpaper, panels and overlays.\n"), output)
        # A reused launcher pid is not signalled, and the holder is still stopped.
        self.killed.clear()
        self.proc(310, "dms", ["dms", "run"], started=4242)
        self.proc(311, "qs", ["qs", "-p", f"{self.home}/.config/quickshell/dms"], ppid=310)
        write(self.hypr / "hyprland.lua", 'hl.on("hyprland.start", function () hl.exec_cmd("dms run") end)\n')
        self.layers((1, 311, "dank-bar"))
        self.notification_owner(311)
        shutil.rmtree(self.state)
        (self.hypr / "pentad.lua").unlink()
        real_survey = doctor.survey

        def survey(root, env, system_root):
            found = real_survey(root, env, system_root)
            self.proc(310, "dms", ["dms", "run"], started=5000)
            return found

        with patch.object(doctor, "survey", survey):
            output, status = self.run_setup(stdin=io.StringIO("y\ny\n"))
        self.assertIn("dms run (pid 310) is no longer the same process or has exited; no signal sent.\n", output)
        self.assertEqual(self.killed, [(311, 15)])

    def test_ukrainian_output(self):
        self.env["LANG"] = "uk_UA.UTF-8"
        self.ii_shell()
        output, status = self.run_setup(stdin=io.StringIO("y\nn\n"))
        self.assertEqual(status, 0, output)
        self.assertTrue(output.startswith("Налаштування Pentad\n\nЗнайдено\n  qs -c ii (pid 2411) займає: сповіщення, шпалери, панелі та накладки.\n"))
        self.assertIn("\nЗміни\n", output)
        self.assertIn("\nЗробити вручну\n  ~/.config/hypr/hyprland/execs.lua:6 викликає qs -c ii, але може робити й іншу роботу", output)
        self.assertIn("\nЗверніть увагу\n  Hyprland перечитує конфігурацію", output)
        self.assertIn("Застосувати ці зміни? [y/N] Hyprland перечитав конфігурацію без нових помилок.\n"
                      "Застосовано. Резервні копії: ~/.local/state/pentad/setup/", output)
        self.assertTrue(output.endswith("Перейти на Pentad зараз, не чекаючи наступного входу? [y/N] "
                                        "Гаразд, заміна відбудеться під час наступного входу в сеанс.\n"), output)
        self.assertIn("-- [pentad setup] Фрагмент Pentad для Hyprland\n", self.read("hyprland.lua"))
        self.assertTrue(self.read("pentad.lua").startswith("-- [pentad setup] Цей файл пише `pentad setup`; зміни тут можуть бути перезаписані.\n"))
        output, _ = self.run_setup("--undo")
        self.assertEqual(output, "Відновлено ~/.config/hypr/hyprland.lua.\nВідновлено ~/.config/hypr/hyprland/execs.lua.\n"
                                 "Вилучено ~/.config/hypr/pentad.lua.\n")
        self.assertEqual(self.run_setup("--undo"), ("Нема чого скасовувати.\n", 1))

if __name__ == "__main__":
    unittest.main()
