import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "pentad_system.py"
SPEC = importlib.util.spec_from_file_location("pentad_system", MODULE_PATH)
system = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(system)


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def desktop(name, mimes="", extra=""):
    return f"[Desktop Entry]\nType=Application\nName={name}\nExec={name.lower()}\nMimeType={mimes}\n{extra}"


class FakeRun:
    """Answers known argv lists and records every call."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def __call__(self, argv, timeout=5):
        self.calls.append(list(argv))
        answer = self.answers.get(tuple(argv[:3]))
        if isinstance(answer, Exception):
            raise answer
        if answer is None:
            raise FileNotFoundError(argv[0])
        return answer


class SystemHelperTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.share = self.root / "share"
        write(self.share / "applications/firefox.desktop", desktop("Firefox", "text/html;x-scheme-handler/https;x-scheme-handler/http;"))
        write(self.share / "applications/org.gnome.Loupe.desktop", desktop("Loupe", "image/png;image/jpeg;"))
        write(self.share / "applications/hidden.desktop", desktop("Hidden", "image/png;", "NoDisplay=true"))
        write(self.share / "applications/kde/okular.desktop", desktop("Okular", "application/pdf;image/png;"))

    def tearDown(self):
        self.temp.cleanup()

    def test_about_reads_os_release_cpu_memory_and_uptime(self):
        write(self.root / "etc/os-release", 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\n')
        write(self.root / "proc/cpuinfo", "processor\t: 0\nmodel name\t: AMD  Ryzen 7 7840U\n")
        write(self.root / "proc/meminfo", "MemTotal:       32768000 kB\n")
        write(self.root / "proc/uptime", "3725.42 1000.00\n")
        result = system.about(str(self.root))
        self.assertEqual((result["os"], result["cpu"], result["memory"], result["uptime"]),
                         ("Arch Linux", "AMD Ryzen 7 7840U", 32768000 * 1024, 3725))

    def test_about_survives_missing_files(self):
        result = system.about(str(self.root / "missing"))
        self.assertEqual((result["ok"], result["os"], result["cpu"], result["memory"], result["uptime"]), (True, "", "", None, None))

    def test_time_reads_timedatectl_and_falls_back_to_localtime(self):
        fake = FakeRun({("timedatectl", "show", "-p"): "Timezone=Europe/Kyiv\nNTP=yes\nNTPSynchronized=no\nCanNTP=yes\n"})
        with patch.object(system, "run", fake):
            self.assertEqual(system.time_state(str(self.root)), dict(
                ok=True, timezone="Europe/Kyiv", ntp=True, synchronized=False, canNtp=True, canSet=True))
        (self.root / "etc").mkdir(parents=True, exist_ok=True)
        os.symlink("/usr/share/zoneinfo/America/New_York", self.root / "etc/localtime")
        with patch.object(system, "run", FakeRun({})):
            result = system.time_state(str(self.root))
        self.assertEqual((result["timezone"], result["canSet"], result["ntp"]), ("America/New_York", False, None))

    def test_set_timezone_accepts_only_listed_zones(self):
        fake = FakeRun({("timedatectl", "list-timezones"): "Europe/Kyiv\nUTC\n", ("timedatectl", "set-timezone", "Europe/Kyiv"): ""})
        with patch.object(system, "run", fake):
            self.assertEqual(system.handle({"operation": "set-timezone", "timezone": "Europe/Kyiv"}, "/", []), {"ok": True})
            self.assertEqual(system.handle({"operation": "set-timezone", "timezone": "Mars/Base"}, "/", []),
                             {"ok": False, "reason": "invalid-timezone"})
            self.assertEqual(system.handle({"operation": "set-timezone", "timezone": "; rm -rf /"}, "/", [])["ok"], False)
        self.assertIn(["timedatectl", "set-timezone", "Europe/Kyiv"], fake.calls)
        self.assertEqual(sum(call[1] == "set-timezone" for call in fake.calls), 1)

    def test_set_ntp_needs_a_boolean(self):
        fake = FakeRun({("timedatectl", "set-ntp", "false"): ""})
        with patch.object(system, "run", fake):
            self.assertEqual(system.handle({"operation": "set-ntp", "enabled": False}, "/", []), {"ok": True})
            self.assertEqual(system.handle({"operation": "set-ntp", "enabled": "no"}, "/", [])["reason"], "invalid-request")
        self.assertEqual(fake.calls, [["timedatectl", "set-ntp", "false"]])

    def test_default_apps_list_visible_candidates_and_the_current_choice(self):
        answers = {("xdg-mime", "query", "default"): "firefox.desktop\n"}
        with patch.object(system, "run", FakeRun(answers)):
            result = system.default_apps([str(self.share)])
        categories = {item["category"]: item for item in result["categories"]}
        self.assertEqual(categories["web"]["current"], "firefox.desktop")
        # Sorted by name; the hidden entry is left out and a subdirectory joins the id with "-".
        self.assertEqual([item["id"] for item in categories["image"]["candidates"]], ["org.gnome.Loupe.desktop", "kde-okular.desktop"])
        self.assertEqual([item["name"] for item in categories["pdf"]["candidates"]], ["Okular"])

    def test_default_apps_report_a_missing_xdg_mime(self):
        with patch.object(system, "run", FakeRun({})):
            self.assertEqual(system.default_apps([str(self.share)]), {"ok": False, "reason": "xdg-mime-missing"})

    def test_set_default_app_sets_every_mime_of_the_category_for_a_known_app(self):
        fake = FakeRun({("xdg-mime", "default", "org.gnome.Loupe.desktop"): ""})
        with patch.object(system, "run", fake):
            ok = system.handle({"operation": "set-default-app", "category": "image", "desktopId": "org.gnome.Loupe.desktop"}, "/", [str(self.share)])
            unknown = system.handle({"operation": "set-default-app", "category": "image", "desktopId": "firefox.desktop"}, "/", [str(self.share)])
            hidden = system.handle({"operation": "set-default-app", "category": "image", "desktopId": "hidden.desktop"}, "/", [str(self.share)])
            bad = system.handle({"operation": "set-default-app", "category": "image", "desktopId": "../x.desktop"}, "/", [str(self.share)])
        self.assertEqual(ok, {"ok": True})
        self.assertEqual((unknown["reason"], hidden["reason"], bad["reason"]), ("unknown-application", "unknown-application", "invalid-request"))
        self.assertEqual(fake.calls, [["xdg-mime", "default", "org.gnome.Loupe.desktop", "image/png", "image/jpeg", "image/webp", "image/gif"]])

    def test_unknown_operation_is_rejected(self):
        with self.assertRaises(ValueError):
            system.handle({"operation": "reboot"}, "/", [])

    def test_idle_operations_use_the_config_adapter_without_executing_commands(self):
        request = dict(operation='set-idle-timeout', action='display', seconds=360, revision='fixture')
        with patch.object(system, 'idle_state', return_value={'ok': True, 'display': 600}) as read_idle, \
                patch.object(system, 'set_idle_timeout', return_value={'ok': True, 'restartRequired': True}) as save_idle, \
                patch.object(system, 'run') as run:
            self.assertEqual(system.handle({'operation': 'idle'}, '/', [])['display'], 600)
            self.assertTrue(system.handle(request, '/', [])['restartRequired'])
            read_idle.assert_called_once_with()
            save_idle.assert_called_once_with(request)
            run.assert_not_called()

    def test_failed_program_maps_to_a_reason(self):
        error = subprocess.CalledProcessError(1, ["timedatectl"], stderr="Access denied")
        with patch.object(system, "handle", side_effect=error), patch("sys.stdin") as stdin, patch("builtins.print") as printed:
            stdin.buffer.read.return_value = b'{"operation":"set-ntp","enabled":true}'
            with patch("sys.argv", ["pentad_system.py"]):
                system.main()
        self.assertIn('"reason": "denied"', printed.call_args[0][0])


if __name__ == "__main__":
    unittest.main()
