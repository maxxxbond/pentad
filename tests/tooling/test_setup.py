import hashlib
import importlib.util
import io
import json
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
for name in ("pentad_doctor", "pentad_setup"):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"tools/{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module  # setup imports the doctor by name; dataclasses resolve annotations through the registry
    spec.loader.exec_module(module)
setup = sys.modules["pentad_setup"]

NOW = datetime(2026, 10, 24, 12, 0, 0, tzinfo=timezone.utc)
STAMP = "20261024T120000Z"
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
        self.state = self.home / ".local/state/pentad/setup"
        write(self.root / "shell.qml")
        write(self.root / "defaults/hyprland-quickshell.lua")
        self.fake("busctl", 'echo "b false"')
        self.fake("hyprctl", "echo '{}'")
        self.env = {"PATH": str(self.bin), "LANG": "en_US.UTF-8", "HYPRLAND_INSTANCE_SIGNATURE": "test",
                    "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config"),
                    "XDG_STATE_HOME": str(self.home / ".local/state")}
        self.hypr.mkdir(parents=True)

    def fake(self, name: str, body: str = "true") -> None:
        write(self.bin / name, f"#!/bin/sh\n{body}\n", 0o755)

    def proc(self, pid: int, comm: str, cmdline: list[str] | None = None, cgroup: str = "") -> None:
        write(self.system / f"proc/{pid}/comm", comm + "\n")
        write(self.system / f"proc/{pid}/cmdline", "\0".join(cmdline or [comm]) + "\0")
        if cgroup:
            write(self.system / f"proc/{pid}/cgroup", cgroup + "\n")

    def notification_owner(self, pid: int) -> None:
        self.fake("busctl", 'case "$*" in\n*NameHasOwner*) echo "b true";;\n'
                            f'*GetConnectionUnixProcessID*) echo "u {pid}";;\nesac')

    def layers(self, *surfaces: tuple[int, int, str]) -> None:
        levels = {str(level): [] for level in range(4)}
        for level, pid, namespace in surfaces:
            levels[str(level)].append({"namespace": namespace, "pid": pid})
        self.fake("hyprctl", f"echo '{json.dumps({'DP-1': {'levels': levels}})}'")

    def ii_shell(self) -> None:
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        self.notification_owner(2411)
        self.layers((0, 2411, "wallpaper"), (1, 2411, "bar"), (3, 2411, "osd"))
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA)
        write(self.hypr / "hyprland/execs.lua", EXECS_LUA)
        write(self.hypr / "hyprland/keybinds.lua", KEYBINDS_LUA)

    def run_setup(self, *flags: str, stdin: io.StringIO | None = None) -> tuple[str, int]:
        output = io.StringIO()
        with redirect_stdout(output):
            status = setup.main(["--root", str(self.root), "--qs", "qs", *flags], self.env, self.system,
                                io.StringIO("y\n") if stdin is None else stdin, NOW)
        return output.getvalue(), status

    def read(self, name: str) -> str:
        return (self.hypr / name).read_text(encoding="utf-8")

    def expected_execs(self) -> str:
        return EXECS_LUA.replace('    hl.exec_cmd("qs -c $qsConfig")', '    -- [pentad setup] hl.exec_cmd("qs -c $qsConfig")')

    def lua_include(self) -> str:
        return f'dofile("{self.hypr}/pentad.lua")'

    def expected_hyprland_lua(self) -> str:
        return HYPRLAND_LUA + f"\n-- [pentad setup] Pentad's Hyprland fragment\n{self.lua_include()}\n"

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
                self.assertIn(f"+{self.lua_include()}\n", output)
                self.assertIn("By hand\n  ~/.config/hypr/hyprland/execs.lua:6 calls qs -c ii but may do other work too: "
                              "change the line so it stops calling it rather than delete it.\n", output)
                reload = ("The changes take effect at the next login." if loaded else
                          "Hyprland reloads its config when these files change, so the added key bindings take effect at once; "
                          "the shell switch itself happens at the next login.")
                self.assertIn(f"Heads-up\n  {reload}\n"
                              "  These files may belong to another shell's own setup; its updates can bring the lines back. "
                              "Run pentad doctor after updating it.\n\nApply these changes? [y/N] "
                              f"Applied. Backups are in ~/.local/state/pentad/setup/{STAMP}; undo with `pentad setup --undo`. "
                              "Log out and back in to switch to Pentad.\n", output)
                self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())
                self.assertEqual(self.read("hyprland.lua"), self.expected_hyprland_lua())
                self.assertEqual(self.read("pentad.lua"), self.expected_fragment(bindings=loaded is None))
                self.assertEqual(self.read("hyprland/keybinds.lua"), KEYBINDS_LUA)
                manifest = json.loads((self.state / STAMP / "manifest.json").read_text(encoding="utf-8"))
                self.assertEqual(manifest["schemaVersion"], 1)
                self.assertEqual(manifest["created"], "2026-10-24T12:00:00+00:00")
                self.assertNotIn("undone", manifest)
                self.assertEqual([(entry["path"], entry["backup"]) for entry in manifest["files"]],
                                 [(str(self.hypr / "hyprland/execs.lua"), "1-execs.lua"), (str(self.hypr / "pentad.lua"), None),
                                  (str(self.hypr / "hyprland.lua"), "3-hyprland.lua")])
                self.assertEqual((self.state / STAMP / "1-execs.lua").read_text(encoding="utf-8"), EXECS_LUA)
                self.assertEqual((self.state / STAMP / "3-hyprland.lua").read_text(encoding="utf-8"), HYPRLAND_LUA)
                for entry in manifest["files"]:
                    self.assertEqual(entry["sha256After"], sha256(Path(entry["path"])))
                output, status = self.run_setup("--undo")
                self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland/execs.lua.\nRestored ~/.config/hypr/hyprland.lua.\n"
                                                    "Removed ~/.config/hypr/pentad.lua.\n", 0))
                self.assertEqual((self.hypr / "hyprland/execs.lua").read_bytes(), EXECS_LUA.encode())
                self.assertEqual((self.hypr / "hyprland.lua").read_bytes(), HYPRLAND_LUA.encode())
                self.assertFalse((self.hypr / "pentad.lua").exists())
                self.assertEqual(json.loads((self.state / STAMP / "manifest.json").read_text(encoding="utf-8"))["undone"],
                                 "2026-10-24T12:00:00+00:00")
                self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))
                shutil.rmtree(self.state)

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
        self.assertIn("Heads-up\n  The changes take effect at the next login.\n", output)
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
        self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland/execs.lua.\nRestored ~/.config/hypr/hyprland.lua.\n"
                                            "Removed ~/.config/hypr/pentad.lua.\n", 0))
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA)
        self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))

    def test_an_existing_fragment_is_regenerated_and_an_existing_include_is_not_repeated(self):
        self.ii_shell()
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA + f"{self.lua_include()} -- mine\n")
        write(self.hypr / "pentad.lua", "-- stale\n")
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn(f"--- ~/.config/hypr/pentad.lua\n+++ ~/.config/hypr/pentad.lua\n@@ -1 +1,3 @@\n--- stale\n+{LUA_HEADER}", output)
        self.assertNotIn("--- ~/.config/hypr/hyprland.lua", output)
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + f"{self.lua_include()} -- mine\n")
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())
        self.assertEqual((self.state / STAMP / "2-pentad.lua").read_text(encoding="utf-8"), "-- stale\n")
        output, status = self.run_setup("--undo")
        self.assertEqual((output, status), ("Restored ~/.config/hypr/hyprland/execs.lua.\nRestored ~/.config/hypr/pentad.lua.\n", 0))
        self.assertEqual(self.read("pentad.lua"), "-- stale\n")

    def test_an_entry_file_ending_in_return_gets_the_include_by_hand(self):
        self.ii_shell()
        ending = "return {\n  a = 1,\n}\n-- the end\n"
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA + ending)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn(f"  ~/.config/hypr/hyprland.lua has a return; add {self.lua_include()} before it by hand.\n", output)
        self.assertNotIn("--- ~/.config/hypr/hyprland.lua", output)
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA + ending)
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())
        self.assertEqual(self.read("hyprland/execs.lua"), self.expected_execs())

    def test_two_holders_sharing_a_start_line_comment_it_once(self):
        self.ii_shell()
        self.proc(2412, "qs", ["qs", "-c", "ii"])
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

    def test_other_start_lines_shell_lists_and_services_are_left_to_the_user(self):
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        self.proc(700, "waybar", cgroup="0::/user.slice/user-1000.slice/user@1000.service/app.slice/waybar.service")
        self.proc(42, "mako")
        self.notification_owner(42)
        self.layers((1, 2411, "bar"), (2, 700, "waybar"))
        write(self.hypr / "hyprland.lua", 'hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii")\nend)\n'
                                          'hl.exec_cmd("sleep 1 && qs -c ii")\n'
                                          'hl.on("hyprland.start", function () hl.exec_cmd("pentad start") end)\n')
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertIn("By hand\n"
                      "  mako (pid 42) holds: notifications. No start line for it was found in ~/.config/hypr. "
                      "If you already removed it, it is still running from this session: log out and back in. "
                      "Otherwise remove it from your session's autostart by hand.\n"
                      "  waybar (pid 700) holds: panels and overlays. Runs as the systemd user service waybar.service: "
                      "systemctl --user disable --now waybar.service\n"
                      "  ~/.config/hypr/hyprland.lua:1: not a single plain start command; comment the call out by hand: "
                      'hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii")\n'
                      "  ~/.config/hypr/hyprland.lua:3: not a single plain start command; comment the call out by hand: "
                      'hl.exec_cmd("sleep 1 && qs -c ii")\n', output)
        self.assertTrue(output.endswith("\npentad setup cannot make any of these changes itself; edit the items above by hand.\n"), output)
        self.assertNotIn("Apply these changes", output)
        self.assertFalse((self.hypr / "pentad.lua").exists())
        self.assertFalse(self.state.exists())

    def test_only_single_plain_start_commands_are_commentable(self):
        accepted = [
            ('    hl.exec_cmd("qs -c $qsConfig")', True, 'hl.on("hyprland.start", function ()'),
            ("hl.exec_cmd('qs -c ii')", True, ""),
            ('hl.exec_cmd("uwsm app -- qs -c ii") -- through uwsm', True, "end)"),
            ("exec-once = waybar", False, ""),
            ("exec = qs -c ii # shell", False, ""),
        ]
        refused = [
            ('hl.on("hyprland.start", function () hl.exec_cmd("qs -c ii") end)', True, ""),
            ('if x then hl.exec_cmd("qs -c ii") end', True, ""),
            ('hl.exec_cmd([[qs -c ii]])', True, ""),
            ('hl.exec_cmd("sleep 1 && qs -c ii")', True, ""),
            ('hl.exec_cmd("qs -c ii; waybar")', True, ""),
            ('hl.exec_cmd("qs -c ii &")', True, ""),
            ('hl.exec_cmd("qs -c \\"ii\\"")', True, ""),
            ('hl.exec_cmd("qs -c ii"); hl.exec_cmd("waybar")', True, ""),
            ('hl.exec_cmd("qs -c ii") --[[ old:', True, ""),
            ('hl.exec_cmd("qs") --[[x]] hl.exec_cmd("waybar")', True, ""),
            ('hl.exec_cmd("qs -c ii")', True, "local start ="),
            ('hl.exec_cmd("qs -c ii")', True, 'hl.exec_cmd("waybar"),'),
            ('-- [pentad setup] hl.exec_cmd("qs -c ii")', True, ""),
            ("exec-once = qs -c ii & waybar", False, ""),
            ("exec-once = cliphist wipe && qs -c ii", False, ""),
            ("bind = SUPER, B, exec, qs -c ii", False, ""),
        ]
        for line, lua, previous in accepted:
            with self.subTest(line=line, previous=previous):
                self.assertTrue(setup.commentable(line, lua, previous))
        for line, lua, previous in refused:
            with self.subTest(line=line, previous=previous):
                self.assertFalse(setup.commentable(line, lua, previous))

    def test_undo_leaves_a_file_edited_after_setup_alone(self):
        self.ii_shell()
        self.run_setup()
        edited = self.expected_execs() + "-- edited later\n"
        write(self.hypr / "hyprland/execs.lua", edited)
        write(self.hypr / "pentad.lua", self.expected_fragment() + "-- also edited\n")
        output, status = self.run_setup("--undo")
        self.assertEqual(status, 0, output)
        self.assertEqual(output, "Left ~/.config/hypr/hyprland/execs.lua alone: it changed after pentad setup; "
                                 f"the backup is ~/.local/state/pentad/setup/{STAMP}/1-execs.lua.\n"
                                 "Restored ~/.config/hypr/hyprland.lua.\n"
                                 "Left ~/.config/hypr/pentad.lua alone: it changed after pentad setup.\n")
        self.assertEqual(self.read("hyprland/execs.lua"), edited)
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment() + "-- also edited\n")
        self.assertEqual(self.read("hyprland.lua"), HYPRLAND_LUA)
        self.assertEqual(self.run_setup("--undo"), ("Nothing to undo.\n", 1))

    def test_undo_keeps_the_fragment_while_the_entry_file_still_loads_it(self):
        self.ii_shell()
        self.run_setup()
        edited = self.expected_hyprland_lua() + "-- edited later\n"
        write(self.hypr / "hyprland.lua", edited)
        output, status = self.run_setup("--undo")
        self.assertEqual(status, 0, output)
        self.assertEqual(output, "Restored ~/.config/hypr/hyprland/execs.lua.\n"
                                 "Left ~/.config/hypr/hyprland.lua alone: it changed after pentad setup; "
                                 f"the backup is ~/.local/state/pentad/setup/{STAMP}/3-hyprland.lua.\n"
                                 "Left ~/.config/hypr/pentad.lua alone: ~/.config/hypr/hyprland.lua was left alone and may still load it.\n")
        self.assertEqual(self.read("hyprland.lua"), edited)
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())

    def test_a_later_run_keeps_the_bindings_the_fragment_already_loads(self):
        self.ii_shell()
        (self.hypr / "hyprland/keybinds.lua").unlink()  # no foreign bindings this time
        write(self.hypr / "hyprland.lua", HYPRLAND_LUA + f"{self.lua_include()}\n")
        write(self.hypr / "pentad.lua", "-- old header\n" + self.expected_fragment()[len(LUA_HEADER):])
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("pentad.lua"), self.expected_fragment())
        self.assertIn("Heads-up\n  The changes take effect at the next login.\n", output)  # the dofile is not new

    def test_interpreter_hosted_and_indirect_start_lines_are_left_to_the_user(self):
        self.proc(2411, "python", ["python", str(self.home / ".config/Ax-Shell/main.py")])
        self.layers((1, 2411, "ax-bar"))
        content = "exec-once = python ~/.config/Ax-Shell/main.py\nexec-once = python ~/bin/battery.py\n"
        write(self.hypr / "hyprland.conf", content)
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertEqual(self.read("hyprland.conf"), content + f"\n# [pentad setup] Pentad's Hyprland fragment\nsource = {self.hypr}/pentad.conf\n")
        self.assertIn(f"  ~/.config/hypr/hyprland.conf:1: python {self.home}/.config/Ax-Shell/main.py runs under an interpreter, "
                      "so the line is not commented out automatically: exec-once = python ~/.config/Ax-Shell/main.py\n", output)
        self.assertIn("  ~/.config/hypr/hyprland.conf:2: python ", output)
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
        marker = self.temp / "hyprctl-was-called"
        self.fake("hyprctl", f': > "{marker}"')
        del self.env["HYPRLAND_INSTANCE_SIGNATURE"]
        write(self.hypr / "hyprland.conf", "exec-once = waybar\n")
        output, status = self.run_setup(stdin=NeverRead())
        self.assertEqual(status, 1, output)
        self.assertFalse(marker.exists())
        self.assertIn("+exec-once = pentad start\n", output)
        self.assertTrue(output.endswith(
            "Heads-up\n  This is not a Hyprland session right now, so it is unknown who draws the wallpaper and panels, "
            "and the changes above are only a preview. Run pentad setup inside a Hyprland session.\n"), output)
        self.assertNotIn("Apply these changes", output)
        self.assertEqual(self.read("hyprland.conf"), "exec-once = waybar\n")
        self.assertFalse((self.hypr / "pentad.conf").exists())
        self.assertFalse(self.state.exists())

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

    def test_ukrainian_output(self):
        self.env["LANG"] = "uk_UA.UTF-8"
        self.ii_shell()
        output, status = self.run_setup()
        self.assertEqual(status, 0, output)
        self.assertTrue(output.startswith("Налаштування Pentad\n\nЗнайдено\n  qs -c ii (pid 2411) займає: сповіщення, шпалери, панелі та накладки.\n"))
        self.assertIn("\nЗміни\n", output)
        self.assertIn("\nЗробити вручну\n  ~/.config/hypr/hyprland/execs.lua:6 викликає qs -c ii, але може робити й іншу роботу", output)
        self.assertIn("\nЗверніть увагу\n  Hyprland перечитує конфігурацію", output)
        self.assertIn("Застосувати ці зміни? [y/N] Застосовано. Резервні копії: ~/.local/state/pentad/setup/", output)
        self.assertIn("-- [pentad setup] Фрагмент Pentad для Hyprland\n", self.read("hyprland.lua"))
        self.assertTrue(self.read("pentad.lua").startswith("-- [pentad setup] Цей файл пише `pentad setup`; зміни тут можуть бути перезаписані.\n"))
        output, _ = self.run_setup("--undo")
        self.assertEqual(output, "Відновлено ~/.config/hypr/hyprland/execs.lua.\nВідновлено ~/.config/hypr/hyprland.lua.\n"
                                 "Вилучено ~/.config/hypr/pentad.lua.\n")
        self.assertEqual(self.run_setup("--undo"), ("Нема чого скасовувати.\n", 1))

if __name__ == "__main__":
    unittest.main()
