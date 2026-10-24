import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts/pentad"

# A stand-in for qs: `list` prints PENTAD_FAKE_LIST, `kill` is logged, and a launch logs its
# arguments and environment, confirms the lock when asked, may hang, then exits with a status.
FAKE_QS = """case "$1" in
  list) printf '%s\\n' "${PENTAD_FAKE_LIST:-[]}" ;;
  kill) echo "qs kill" >> "$LOG" ;;
  *)
    printf 'qs %s crash-handler-off=%s\\n' "$*" "${QS_DISABLE_CRASH_HANDLER:-}" >> "$LOG"
    [ -z "${PENTAD_FAKE_CONFIRM:-}" ] || printf locked > "$PENTAD_LOCK_STATE"
    [ -z "${PENTAD_FAKE_HANG:-}" ] || exec sleep 30
    exit "${PENTAD_FAKE_LOCK_STATUS:-0}" ;;
esac"""

class LockLauncherTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="pentad-lock-test-")
        self.addCleanup(temp.cleanup)
        self.temp = Path(temp.name)
        self.root = self.temp / "runtime"
        self.root.mkdir()
        (self.root / "lock.qml").write_text("", encoding="utf-8")
        self.run_dir = self.temp / "run"
        self.run_dir.mkdir()
        self.state = self.run_dir / "pentad-lock.state"
        # Only stand-ins and the few tools the launcher needs are on PATH: no real qs or hyprlock.
        self.bin = self.temp / "bin"
        self.bin.mkdir()
        for tool in ("dirname", "realpath", "cat", "rm", "sleep"):
            (self.bin / tool).symlink_to(shutil.which(tool))
        self.log = self.temp / "calls.log"
        self.fake("qs", FAKE_QS)
        self.env = {"PATH": str(self.bin), "HOME": str(self.temp), "LANG": "C", "LOG": str(self.log),
                    "XDG_RUNTIME_DIR": str(self.run_dir)}

    def fake(self, name, body):
        (self.bin / name).write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
        (self.bin / name).chmod(0o755)

    def with_hyprlock(self):
        self.fake("hyprlock", 'echo hyprlock >> "$LOG"')

    def lock(self, *args, **env):
        return subprocess.run(["/bin/sh", str(LAUNCHER), "lock", "--path", str(self.root), *args],
                              env={**self.env, **env}, capture_output=True, text=True, timeout=30)

    def calls(self):
        return self.log.read_text(encoding="utf-8").splitlines() if self.log.exists() else []

    def test_a_confirmed_lock_that_unlocks_needs_no_fallback(self):
        self.with_hyprlock()
        result = self.lock(PENTAD_FAKE_CONFIRM="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [f"qs --no-duplicate --path {self.root}/lock.qml crash-handler-off=1"])

    def test_a_failed_or_lost_lock_hands_over_to_hyprlock(self):
        self.with_hyprlock()
        for status in ("1", "3", "4", "134"):
            self.log.unlink(missing_ok=True)
            result = self.lock(PENTAD_FAKE_LOCK_STATUS=status)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.calls()[-1], "hyprlock")
            self.assertIn(f"status {status}", result.stderr)

    def test_an_instance_that_never_confirms_is_killed_and_replaced(self):
        self.with_hyprlock()
        result = self.lock(PENTAD_FAKE_HANG="1")
        self.assertIn("did not confirm a lock", result.stderr)
        self.assertEqual(self.calls()[-1], "hyprlock")

    def test_a_running_confirmed_lock_is_kept(self):
        self.state.write_text("locked", encoding="utf-8")
        result = self.lock(PENTAD_FAKE_LIST='[{"id":"a1"}]')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_a_running_instance_without_a_lock_is_replaced(self):
        self.with_hyprlock()
        self.state.write_text("", encoding="utf-8")
        result = self.lock(PENTAD_FAKE_LIST='[{"id":"a1"}]', PENTAD_FAKE_CONFIRM="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0], "qs kill")
        self.assertTrue(self.calls()[1].startswith("qs --no-duplicate"))

    def test_without_hyprlock_the_failure_is_reported(self):
        result = self.lock(PENTAD_FAKE_LOCK_STATUS="3")
        self.assertEqual(result.returncode, 3)
        self.assertIn("install hyprlock", result.stderr)

    def test_a_missing_lock_entry_falls_back(self):
        (self.root / "lock.qml").unlink()
        self.with_hyprlock()
        result = self.lock()
        self.assertEqual(self.calls(), ["hyprlock"])
        self.assertIn("missing", result.stderr)

    def test_a_typo_in_lock_cmd_still_locks_with_the_fallback(self):
        self.with_hyprlock()
        result = subprocess.run(["/bin/sh", str(LAUNCHER), "lock", "--developmnet"],
                                env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["hyprlock"])
        self.assertIn("Unknown argument", result.stderr)

if __name__ == "__main__":
    unittest.main()
