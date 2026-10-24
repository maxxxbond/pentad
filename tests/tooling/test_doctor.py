import importlib.util
import io
import json
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("pentad_doctor", ROOT / "tools/pentad_doctor.py")
doctor = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = doctor  # dataclasses resolve annotations through the module registry
SPEC.loader.exec_module(doctor)

def write(path: Path, text: str = "", mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)

class DoctorTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pentad-doctor-test-")
        self.addCleanup(temp.cleanup)
        self.temp = Path(temp.name)
        self.system = self.temp / "system"
        self.bin = self.temp / "bin"
        self.root = self.temp / "runtime"
        write(self.root / "shell.qml")
        write(self.root / "builtin-registry.json", "[]\n")
        write(self.system / "etc/os-release", 'NAME="Arch Linux"\nID=arch\n')
        qml = self.system / "usr/lib/qt6/qml"
        write(qml / "QtQuick/qmldir")
        write(qml / "Qt5Compat/GraphicalEffects/qmldir")
        write(self.system / "usr/lib/qt6/plugins/imageformats/libqsvg.so")
        self.fake("qs", 'echo "quickshell 0.3.2, revision 0123456"')
        self.fake("fc-list", 'printf "%s\\n" "Geist" "Noto Color Emoji,Noto Color Emoji"')
        self.fake("Hyprland")
        for feature in doctor.FEATURES:
            for need in feature.needs:
                if need.kind == "program":
                    self.fake(need.name)
        self.fake("busctl", 'echo "b false"')
        self.fake("hyprctl", "echo '{}'")
        self.env = {"PATH": str(self.bin), "LANG": "en_US.UTF-8", "HYPRLAND_INSTANCE_SIGNATURE": "test"}
        modules = patch.object(doctor.importlib.util, "find_spec", return_value=object())
        modules.start()
        self.addCleanup(modules.stop)

    def fake(self, name: str, body: str = "true") -> None:
        write(self.bin / name, f"#!/bin/sh\n{body}\n", 0o755)

    def run_doctor(self) -> tuple[str, int]:
        output = io.StringIO()
        with redirect_stdout(output):
            status = doctor.main(["--root", str(self.root), "--qs", "qs"], self.env, self.system)
        return output.getvalue(), status

    def proc(self, pid: int, comm: str, cmdline: list[str] | None = None, cgroup: str = "") -> None:
        write(self.system / f"proc/{pid}/comm", comm + "\n")
        write(self.system / f"proc/{pid}/cmdline", "\0".join(cmdline or [comm]) + "\0")
        if cgroup:
            write(self.system / f"proc/{pid}/cgroup", cgroup + "\n")

    def notification_owner(self, pid: int) -> None:
        self.fake("busctl", 'case "$*" in\n*NameHasOwner*) echo "b true";;\n'
                            f'*GetConnectionUnixProcessID*) echo "u {pid}";;\nesac')

    def layers(self, *surfaces: tuple[int, int, str]) -> None:
        """Make hyprctl print one monitor with (level, pid, namespace) surfaces."""
        levels = {str(level): [] for level in range(4)}
        for level, pid, namespace in surfaces:
            levels[str(level)].append({"namespace": namespace, "pid": pid})
        reply = json.dumps({"DP-1": {"levels": levels}})
        self.fake("hyprctl", f"echo '{reply}'")

    def hypr_config(self) -> Path:
        """Point HOME and XDG_CONFIG_HOME at temporary directories and return the hypr directory."""
        home = self.temp / "home"
        self.env["HOME"] = str(home)
        self.env["XDG_CONFIG_HOME"] = str(home / ".config")
        return home / ".config/hypr"

    def pentad_process(self, pid: int, flags: list[str]) -> None:
        self.proc(pid, "qs", ["qs", "--no-duplicate", *flags])

    def test_complete_system_passes_and_names_a_notification_daemon_from_dbus(self):
        self.proc(42, "mako", ["/usr/bin/mako"])
        self.notification_owner(42)
        output, status = self.run_doctor()
        self.assertEqual(status, 0, output)
        self.assertNotIn("missing", output)
        self.assertIn("ok       Quickshell 0.3.2", output)
        self.assertIn("/usr/bin/mako (pid 42) holds: notifications.", output)
        self.assertIn("Remove it from autostart and start Pentad with `pentad start`", output)
        self.assertNotIn("pacman", output)

    def test_a_clean_system_has_no_heads_up(self):
        output, status = self.run_doctor()
        self.assertEqual(status, 0, output)
        self.assertNotIn("Heads-up", output)
        self.assertNotIn("Could not check", output)

    def test_a_whole_shell_is_listed_with_its_start_lines_and_key_bindings(self):
        hypr = self.hypr_config()
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        self.pentad_process(100, ["--path", str(self.root)])
        self.notification_owner(2411)
        self.layers((0, 2411, "wallpaper"), (1, 2411, "bar"), (3, 2411, "osd"), (2, 100, "pentad-bar"))
        write(hypr / "extra.conf", '# exec-once = qs -c ii\nexec-once = qs -c ii # shell\nexec-once = qsx\n')
        write(hypr / "hyprland/execs.lua",
              'hl.exec_cmd("qs -c ii")\n-- hl.exec_cmd("qs -c old")\nhl.exec_cmd("waybar")\n'
              'hl.exec_cmd("uwsm app -- qs -c ii") -- through uwsm\n')
        write(hypr / "hyprland/keybinds.lua",
              'hl.bind("SUPER+R", hl.dsp.exec_cmd("qs -c ii ipc call overview toggle"))\n'
              'hl.bind("SUPER+T", hl.dsp.exec_cmd("qs -c ii ipc call tools toggle"))\n')
        write(hypr / ".git/hidden.lua", 'hl.exec_cmd("qs -c ii")\n')
        write(hypr / "big.lua", 'hl.exec_cmd("qs -c ii")\n' + "-- padding\n" * 30000)
        output, status = self.run_doctor()
        self.assertEqual(status, 0, output)
        self.assertIn(
            "Heads-up\n"
            "  qs -c ii (pid 2411) holds: notifications, wallpaper, panels and overlays.\n"
            "    Started from ~/.config/hypr/extra.conf:2\n"
            "                 ~/.config/hypr/hyprland/execs.lua:1\n"
            "                 ~/.config/hypr/hyprland/execs.lua:4\n"
            "    Also called by 2 key bindings in ~/.config/hypr.\n"
            "    Remove it from autostart and start Pentad with `pentad start`, then run pentad doctor again.\n",
            output)
        self.assertNotIn("pid 100", output)

    def test_only_five_start_lines_are_listed(self):
        hypr = self.hypr_config()
        self.proc(2411, "waybar")
        self.layers((1, 2411, "waybar"))
        write(hypr / "autostart.conf", "".join(f"exec-once = waybar -c {n}\n" for n in range(7)))
        output, _ = self.run_doctor()
        self.assertIn("Started from ~/.config/hypr/autostart.conf:1\n", output)
        self.assertIn("~/.config/hypr/autostart.conf:5\n", output)
        self.assertNotIn("autostart.conf:6", output)
        self.assertIn("                 and 2 more\n", output)

    def test_a_single_key_binding_is_not_pluralised(self):
        hypr = self.hypr_config()
        self.proc(2411, "waybar")
        self.layers((1, 2411, "waybar"))
        write(hypr / "keys.conf", "bind = SUPER, B, exec, waybar\n")
        output, _ = self.run_doctor()
        self.assertIn("Also called by 1 key binding in ~/.config/hypr.\n", output)
        self.assertIn("Pentad found no start line for it in ~/.config/hypr;", output)

    def test_a_nix_wrapped_quickshell_is_still_found(self):
        hypr = self.hypr_config()
        self.proc(900, ".quickshell-wra", ["/nix/store/abc-quickshell/bin/.quickshell-wrapped", "-c", "ii"])
        self.layers((1, 900, "bar"))
        write(hypr / "autostart.conf", "exec-once = qs -c ii\n")
        output, _ = self.run_doctor()
        self.assertIn("Started from ~/.config/hypr/autostart.conf:1\n", output)

    def test_pentad_itself_is_ignored_however_it_names_its_path(self):
        self.notification_owner(100)
        self.layers((0, 100, "wallpaper"), (1, 100, "bar"))
        for flags in (["--path", str(self.root)], ["-p", str(self.root / "../runtime")], [f"--path={self.root}"]):
            with self.subTest(flags=flags):
                self.pentad_process(100, flags)
                output, status = self.run_doctor()
                self.assertEqual(status, 0, output)
                self.assertNotIn("Heads-up", output)

    def test_another_quickshell_config_is_not_taken_for_pentad(self):
        self.notification_owner(100)
        self.pentad_process(100, ["--path", str(self.temp / "other-shell")])
        output, _ = self.run_doctor()
        self.assertIn("(pid 100) holds: notifications.", output)

    def test_a_systemd_user_service_gets_its_disable_command(self):
        self.hypr_config()
        self.proc(700, "waybar", ["waybar"], "0::/user.slice/user-1000.slice/user@1000.service/app.slice/waybar.service")
        self.proc(701, "foot", ["foot"], "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-foot-701.service")
        self.proc(702, "swaync", ["swaync"], "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app@1.service")
        # Started by hand from a footclient terminal: it inherits the terminal server's cgroup.
        self.proc(703, "qs", ["qs", "-c", "ii"], "0::/user.slice/user-1000.slice/user@1000.service/app.slice/foot-server.service")
        self.layers((1, 700, "waybar"), (2, 701, "foot"), (2, 702, "swaync"), (2, 703, "bar"))
        output, _ = self.run_doctor()
        self.assertIn("waybar (pid 700) holds: panels and overlays.\n"
                      "    Runs as the systemd user service waybar.service: systemctl --user disable --now waybar.service\n",
                      output)
        self.assertEqual(output.count("Runs as the systemd user service"), 1)
        self.assertNotIn("foot-server.service", output)
        self.assertIn("foot (pid 701) holds: panels and overlays.\n    Pentad found no start line for it in ~/.config/hypr;", output)

    def test_a_holder_without_a_start_line_says_where_it_looked(self):
        self.hypr_config()
        self.proc(42, "mako")
        self.notification_owner(42)
        output, _ = self.run_doctor()
        self.assertIn("Pentad found no start line for it in ~/.config/hypr; check that folder and your session's autostart.",
                      output)

    def test_without_a_config_location_the_scan_is_skipped_and_said_so(self):
        self.proc(42, "mako")
        self.notification_owner(42)
        output, _ = self.run_doctor()
        self.assertIn("Its start line was not searched for", output)

    def test_missing_or_broken_busctl_is_reported_not_ignored(self):
        (self.bin / "busctl").unlink()
        output, status = self.run_doctor()
        self.assertEqual(status, 0, output)
        self.assertIn("Could not check who shows notifications", output)
        for body in ("exit 1", "echo 'what'", 'case "$*" in\n*NameHasOwner*) echo "b true";;\nesac'):
            with self.subTest(body=body):
                self.fake("busctl", body)
                output, _ = self.run_doctor()
                self.assertIn("Could not check who shows notifications", output)

    def test_layers_are_not_probed_outside_a_hyprland_session(self):
        marker = self.temp / "hyprctl-was-called"
        self.fake("hyprctl", f': > "{marker}"')  # a builtin: PATH holds only the fake bin
        del self.env["HYPRLAND_INSTANCE_SIGNATURE"]
        output, _ = self.run_doctor()
        self.assertFalse(marker.exists())
        self.assertIn("This is not a Hyprland session right now", output)
        self.assertNotIn("Could not check wallpaper", output)

    def test_failing_or_unreadable_hyprctl_is_reported_inside_a_session(self):
        for body in ("exit 1", "echo 'not json'", "echo '[1]'", "echo '{\"DP-1\": {}}'"):
            with self.subTest(body=body):
                self.fake("hyprctl", body)
                output, status = self.run_doctor()
                self.assertEqual(status, 0, output)
                self.assertIn("Could not check wallpaper and panels", output)
        (self.bin / "hyprctl").unlink()
        output, _ = self.run_doctor()
        self.assertIn("Could not check wallpaper and panels", output)

    def test_old_quickshell_fails_with_the_arch_package(self):
        self.fake("qs", 'echo "quickshell 0.2.1"')
        output, status = self.run_doctor()
        self.assertEqual(status, 1)
        self.assertIn("missing  Quickshell 0.2.1: version 0.3.2 or newer is needed", output)
        self.assertIn("sudo pacman -S --needed quickshell", output)

    def test_required_packages_lists_only_what_pentad_cannot_start_without(self):
        self.fake("qs", 'echo "quickshell 0.2.1"')
        (self.bin / "wf-recorder").unlink()
        output = io.StringIO()
        with redirect_stdout(output):
            doctor.main(["--root", str(self.root), "--required-packages"], self.env, self.system)
        self.assertEqual(output.getvalue(), "quickshell\n")
        write(self.system / "etc/os-release", "ID=fedora\n")
        output = io.StringIO()
        with redirect_stdout(output):
            doctor.main(["--root", str(self.root), "--required-packages"], self.env, self.system)
        self.assertEqual(output.getvalue(), "\n")

    def test_missing_runtime_files_fail(self):
        (self.root / "builtin-registry.json").unlink()
        output, status = self.run_doctor()
        self.assertEqual(status, 1)
        self.assertIn("missing  Pentad files", output)

    def test_missing_optional_program_only_disables_its_feature(self):
        (self.bin / "wf-recorder").unlink()
        (self.bin / "wl-copy").unlink()
        output, status = self.run_doctor()
        self.assertEqual(status, 0)
        self.assertIn("missing  Screen recording: needs wf-recorder", output)
        self.assertIn("missing  Screenshots: needs wl-copy (wl-clipboard)", output)
        self.assertRegex(output, r"For every feature: sudo pacman -S --needed wl-clipboard wf-recorder\n")

    def test_one_alternative_is_enough(self):
        (self.bin / "brightnessctl").unlink()
        output, _ = self.run_doctor()
        self.assertIn("ok       Brightness", output)

    def test_other_distributions_get_program_names_without_pacman(self):
        write(self.system / "etc/os-release", "ID=fedora\n")
        (self.bin / "wl-copy").unlink()
        (self.bin / "qs").unlink()
        output, status = self.run_doctor()
        self.assertEqual(status, 1)
        self.assertIn("Screenshots: needs wl-copy\n", output)
        self.assertNotIn("pacman", output)
        self.assertIn("distribution's package manager", output)

    def test_unknown_qt_layout_is_not_a_failure(self):
        for path in sorted((self.system / "usr/lib/qt6").rglob("*"), reverse=True):
            path.unlink() if path.is_file() else path.rmdir()
        output, status = self.run_doctor()
        self.assertEqual(status, 0, output)
        self.assertIn("unknown  Qt SVG", output)

    def test_ukrainian_locale(self):
        self.env["LANG"] = "uk_UA.UTF-8"
        del self.env["HYPRLAND_INSTANCE_SIGNATURE"]
        output, _ = self.run_doctor()
        self.assertTrue(output.startswith("Перевірка Pentad\n"))
        self.assertIn("є        Знімки екрана", output)
        self.assertIn("Зараз це не сеанс Hyprland", output)

    def test_ukrainian_conflict_report(self):
        self.env["LANG"] = "uk_UA.UTF-8"
        hypr = self.hypr_config()
        self.proc(2411, "qs", ["qs", "-c", "ii"])
        self.proc(700, "waybar", cgroup="0::/user.slice/user-1000.slice/user@1000.service/app.slice/waybar.service")
        self.notification_owner(2411)
        self.layers((0, 2411, "wallpaper"), (1, 700, "waybar"))
        write(hypr / "execs.conf", "exec-once = qs -c ii\nbind = SUPER, R, exec, qs -c ii ipc call overview toggle\n")
        output, _ = self.run_doctor()
        self.assertIn(
            "Зверніть увагу\n"
            "  waybar (pid 700) займає: панелі та накладки.\n"
            "    Працює як користувацька служба systemd waybar.service: systemctl --user disable --now waybar.service\n",
            output)
        self.assertIn("qs -c ii (pid 2411) займає: сповіщення, шпалери.\n"
                      "    Запускається з ~/.config/hypr/execs.conf:1\n"
                      "    Його також викликають прив'язки клавіш: 1 (у ~/.config/hypr).\n"
                      "    Приберіть його з автозапуску й запустіть Pentad командою `pentad start`", output)
        (self.bin / "busctl").unlink()
        output, _ = self.run_doctor()
        self.assertIn("Не вдалося перевірити, хто показує сповіщення", output)

    def test_arch_package_lists_every_package_the_doctor_suggests(self):
        pkgbuild = (ROOT / "packaging/arch/PKGBUILD").read_text(encoding="utf-8")
        listed = set(re.findall(r"^  '([^':]+):", pkgbuild, re.MULTILINE))
        listed.update(name.split(">=")[0] for name in re.findall(r"'([^']+)'", pkgbuild.split("depends=(", 1)[1].split(")", 1)[0]))
        suggested = {need.arch for feature in doctor.FEATURES for need in feature.needs if need.arch}
        suggested.discard("systemd")
        self.assertEqual(suggested - listed, set())
        self.assertLessEqual({"quickshell", "hyprland", "qt6-5compat", "qt6-svg"}, listed)

if __name__ == "__main__":
    unittest.main()
