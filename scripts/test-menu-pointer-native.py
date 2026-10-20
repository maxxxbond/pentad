#!/usr/bin/env python3
"""Opt-in native menu test. Launches only disposable private compositor sessions."""
import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]

def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)

def interrupted(signum, frame):
    raise KeyboardInterrupt

def await_socket(process, lookup, seconds=12):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = lookup()
        if result:
            return result
        if process.poll() is not None:
            raise RuntimeError('Private compositor exited; inspect its report log')
        time.sleep(.05)
    raise RuntimeError('Private compositor startup timeout')

def inside(args):
    root, nested_runtime = Path(args.scratch), Path(args.nested_runtime)
    kwin = nested = test = None
    with open(str(args.report) + '.kwin.log', 'w') as kwin_log, open(str(args.report) + '.hyprland.log', 'w') as hypr_log:
        try:
            kwin = subprocess.Popen(['/usr/bin/kwin_wayland', '--virtual', '--no-global-shortcuts',
                '--no-kactivities', '--no-lockscreen', '--width', '800', '--height', '600',
                '--socket', 'pentad-test-virtual'], stdout=kwin_log, stderr=kwin_log)
            socket = root / 'runtime/pentad-test-virtual'
            await_socket(kwin, lambda: socket if socket.is_socket() else None)
            env = dict(os.environ, WAYLAND_DISPLAY=str(socket), QT_QPA_PLATFORM='wayland',
                PENTAD_HEADLESS='1', PENTAD_PRIVATE_DBUS_SOCKET=str(root / 'dbus.sock'),
                PATH=str(REPO / 'artifacts/quickshell-runtime/bin') + ':/usr/bin:/bin')
            if args.compositor == 'hyprland':
                config = root / 'hyprland.lua'
                config.write_text('hl.monitor({output="",mode="800x600@60",position="0x0",scale=1})\n'
                    'hl.config({animations={enabled=false},'
                    'misc={disable_hyprland_logo=true,disable_splash_rendering=true},'
                    'debug={suppress_errors=true},input={follow_mouse=1}})\n')
                nested_env = dict(env, XDG_RUNTIME_DIR=str(nested_runtime), AQ_BACKEND='wayland',
                    HYPRLAND_NO_SD_NOTIFY='1', HYPRLAND_NO_RT='1')
                nested = subprocess.Popen(['/usr/bin/Hyprland', '--config', str(config)],
                    env=nested_env, stdout=hypr_log, stderr=hypr_log)
                socket = await_socket(nested, lambda: next((p for p in nested_runtime.glob('wayland-*') if p.is_socket()), None))
                ipc = await_socket(nested, lambda: next((nested_runtime / 'hypr').glob('*/.socket.sock'), None))
                env.update(WAYLAND_DISPLAY=str(socket), PENTAD_HYPRLAND_TEST_RUNTIME=str(nested_runtime),
                    PENTAD_HYPRLAND_TEST_INSTANCE=ipc.parent.name)
            command = ['/usr/bin/node', str(REPO / 'scripts/test-quickshell.mjs'), '--scenario', args.scenario,
                       '--scale', args.scale, '--report', str(args.report)]
            test = subprocess.Popen(command, env=env, cwd=REPO)
            return test.wait(timeout=40)
        finally:
            stop(test)
            stop(nested)
            for log in nested_runtime.glob('hypr/*/hyprland.log'):
                shutil.copy(log, str(args.report) + '.hyprland-runtime.log')
            stop(kwin)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compositor', choices=['kwin', 'hyprland'], default='hyprland')
    parser.add_argument('--scenario', default='menu-pointer-native')
    parser.add_argument('--scale', choices=['1', '1.25', '1.5', '2'], default='1')
    parser.add_argument('--report', type=Path, default=Path('/tmp/pentad-menu-native.json'))
    parser.add_argument('--scratch', help=argparse.SUPPRESS)
    parser.add_argument('--nested-runtime', help=argparse.SUPPRESS)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, interrupted)
    args.report = args.report.resolve()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    if args.scratch:
        return inside(args)
    root = Path(tempfile.mkdtemp(prefix='pentad-headless-'))
    nested_runtime = Path(tempfile.mkdtemp(prefix='ph-'))
    process = None
    try:
        env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'QT_QPA_PLATFORM': 'offscreen',
               'LIBGL_ALWAYS_SOFTWARE': '1', 'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(root / 'no-system-bus')}
        for key, name in {'HOME': 'home', 'XDG_RUNTIME_DIR': 'runtime', 'XDG_CONFIG_HOME': 'config',
                'XDG_DATA_HOME': 'data', 'XDG_CACHE_HOME': 'cache', 'XDG_STATE_HOME': 'state'}.items():
            (root / name).mkdir(mode=0o700)
            env[key] = str(root / name)
        config = root / 'dbus.conf'
        config.write_text('<busconfig><type>session</type><listen>unix:path=' + str(root / 'dbus.sock')
            + '</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*"/>'
            + '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
        command = ['/usr/bin/dbus-run-session', '--config-file', str(config), '--', sys.executable,
            str(Path(__file__).resolve()), '--scratch', str(root), '--nested-runtime', str(nested_runtime),
            '--compositor', args.compositor, '--scenario', args.scenario, '--scale', args.scale,
            '--report', str(args.report)]
        process = subprocess.Popen(command, env=env, start_new_session=True)
        return process.wait(timeout=65)
    finally:
        if process:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=3)
        shutil.rmtree(root)
        shutil.rmtree(nested_runtime)

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (KeyboardInterrupt, subprocess.TimeoutExpired, RuntimeError) as error:
        print('Native menu test stopped:', error, file=sys.stderr)
        sys.exit(1)
