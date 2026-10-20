"""Opt-in Quickshell host/IPC probe; native actions are gated by preview."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

def probe(report_path):
    repo = Path(__file__).resolve().parents[2]
    checks = []
    report = {"scenario": "ipc-reload", "status": "blocked", "checks": checks}
    version = subprocess.run(["qs", "--version"], capture_output=True, text=True, timeout=5)
    report["environment"] = {"quickshell": version.stdout.strip()}
    if version.returncode or "Quickshell 0.3.2" not in version.stdout:
        raise RuntimeError("This acceptance probe requires the pinned Quickshell 0.3.2 build")
    with tempfile.TemporaryDirectory(prefix="pentad-ipc-probe-") as directory:
        scratch = Path(directory)
        config = scratch / "shell"
        shutil.copytree(repo / "quickshell", config)
        registry = [{"id": json.loads(source.read_text())["id"],
                     "path": source.relative_to(config).as_posix()}
                    for source in sorted((config / "widgets").rglob("manifest.json"))]
        (config / "builtin-registry.json").write_text(json.dumps(registry))
        env = {key: os.environ[key] for key in ("PATH", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR") if key in os.environ}
        env.update({"HOME": directory, "PENTAD_SAFE_MODE": "1", "PENTAD_PREVIEW": "1", "LANG": "C.UTF-8"})
        for name in ("CONFIG", "STATE", "DATA", "CACHE"):
            path = scratch / name.lower()
            path.mkdir(mode=0o700)
            env[f"XDG_{name}_HOME"] = str(path)
        with (scratch / "host.log").open("w+") as log:
            child = subprocess.Popen([str(repo / "scripts/pentad"), "start", "--path", str(config), "--safe-mode"], env=env, stdout=log, stderr=log)
            try:
                def request(command="ping", payload="{}"):
                    response = subprocess.run(["qs", "ipc", "--path", str(config), "call", "pentad", "request", command, payload], env=env, capture_output=True, text=True, timeout=5)
                    if response.returncode:
                        raise RuntimeError(response.stderr)
                    if not response.stdout.strip():
                        raise RuntimeError(f"Empty IPC reply for {command!r}/{payload!r}: {response.stderr}")
                    try:
                        return json.loads(response.stdout)
                    except json.JSONDecodeError as error:
                        raise RuntimeError(f"Invalid IPC reply for {command!r}/{payload!r}: {response.stdout!r} {response.stderr!r}") from error

                def ready():
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        if child.poll() is not None:
                            log.seek(0)
                            raise RuntimeError(log.read())
                        try:
                            return request()
                        except (RuntimeError, json.JSONDecodeError):
                            time.sleep(0.05)
                    raise RuntimeError("IPC did not become ready")

                ping = ready()
                assert ping["ok"] and ping["preview"] and ping["safeMode"]
                checks.append({"name": "exact-root-cli-ping-safe-mode", "passed": True})
                assert request("unknown")["reason"] == "unsupported"
                assert request(payload="not-json")["reason"] == "invalid-payload"
                checks.append({"name": "typed-request-validation", "passed": True})
                assert request("workspace-super", '{"key":"Super_L","action":"press"}')["workspaceHeld"]
                assert request("workspace-super", '{"key":"Super_L","action":"press"}')["workspaceHeld"]
                assert request("workspace-super", '{"key":"Super_R","action":"press"}')["workspaceHeld"]
                assert request("workspace-super", '{"key":"Super_L","action":"release"}')["workspaceHeld"]
                assert not request("workspace-super", '{"key":"Super_R","action":"release"}')["workspaceHeld"]
                assert not request("workspace-super", '{"key":"Alt_L","action":"press"}')["ok"]
                assert request("workspace-slot", '{"slot":1}')["reason"] == "denied"
                checks.append({"name": "workspace-held-ipc-idempotent-and-preview-denies-focus", "passed": True})
                with (config / "shell.qml").open("a") as source:
                    source.write("\n// native fixture reload\n")
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    log.seek(0)
                    if log.read().count("Configuration Loaded") >= 2:
                        break
                    time.sleep(0.05)
                else:
                    raise RuntimeError("No reload completion in host log")
                assert ready() == ping
                checks.append({"name": "file-reload-retains-ipc-and-container", "passed": True})
                report["status"] = "pass"
            except Exception as error:
                report["status"] = "fail"
                report["error"] = str(error)
            finally:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
                log.seek(0)
                report["log"] = log.read()
                checks.append({"name": "owned-host-disposed", "passed": child.poll() is not None})
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    return report

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = probe(args.report)
    print(f"{result['status']}: IPC, reload and disposal")
    raise SystemExit(0 if result["status"] == "pass" else 1)
