#!/usr/bin/env node
import { cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile, stat, chmod, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { crc32, deflateSync } from 'node:zlib';
import { meetsFloor, parseVersion } from './check-quickshell.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const known = new Set(['shell-entrypoint', 'lock-entrypoint','runtime', 'output-lifecycle', 'design-system', 'control-templates', 'tool-context', 'bar-tools-ui', 'application-mixer', 'plugin-host', 'config-store', 'organizer', 'bar', 'tray-context-menu', 'menu-pointer-native', 'bar-visual', 'workspace-capsule', 'telemetry-live', 'telemetry-motion', 'media', 'artwork', 'popups', 'menu-motion', 'control-center', 'notification-popup', 'system-controls', 'sidebar', 'sidebar-tools', 'sidebar-file-tools', 'clock-timer', 'shelf', 'shelf-files', 'stash-window', 'drag-and-drop', 'window-navigation', 'navigation-adapter', 'window-navigation-visual', 'spotlight', 'spotlight-service', 'screenshot-editor', 'spotlight-emoji-grid', 'settings-primitives', 'settings-field', 'settings-window', 'level-overlay', 'wallpaper', 'lock-screen', 'showcase', 'spotlight-host', 'spotlight-lifecycle', 'menu-prebuild', 'cheatsheet', 'overnight', 'file-drop', 'spring-dropdown']);

// A minimal RGB PNG so fixtures need no image tools. pixel(x, y) -> [r, g, b].
export async function writeFixturePng(file, width, height, pixel) {
  const rows = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const offset = y * (width * 3 + 1) + 1 + x * 3;
    const [r, g, b] = pixel(x, y);
    rows[offset] = r; rows[offset + 1] = g; rows[offset + 2] = b;
  }
  const chunk = (type, data) => {
    const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const sum = Buffer.alloc(4); sum.writeUInt32BE(crc32(body));
    return Buffer.concat([length, body, sum]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 2;
  await writeFile(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header),
    chunk('IDAT', deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]));
}

export function parseTestOutput(output) {
  const events = output.split(/\r?\n/).filter((line) => line.includes('PENTAD_TEST ')).map((line) => {
    const record = line.slice(line.indexOf('PENTAD_TEST ') + 'PENTAD_TEST '.length);
    try { return JSON.parse(record); }
    catch { return { status: 'fail', detail: `Malformed test output: ${line}` }; }
  });
  const checks = events.flatMap((event) => Array.isArray(event.checks)
    ? event.checks.map((check) => ({ name: check.name, status: check.passed === true ? 'pass' : 'fail', detail: check.detail }))
    : [{ name: event.name || 'fixture', status: event.status === 'pass' ? 'pass' : 'fail', detail: event.detail }]);
  return { events, checks };
}

export function qmlRuntimeErrors(output) {
  return output.split(/\r?\n/).filter(line => /TypeError:|ReferenceError:|SyntaxError:|Binding loop detected|Failed to load configuration|Cannot load controller|Cannot assign to non-existent property|Detected function .* in Connections element[^\n]*no signal .* matches/i.test(line));
}

export async function main(args = process.argv.slice(2)) {
  if (args[0] === '--') args = args.slice(1);
  let scenario;
  let reportPath;
  const gallery = { appearance: 'dark', scale: '1', accent: '#869677', reducedMotion: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--scenario') scenario = args[++i];
    else if (args[i] === '--report') reportPath = args[++i];
    else if (args[i] === '--appearance') gallery.appearance = args[++i];
    else if (args[i] === '--scale') gallery.scale = args[++i];
    else if (args[i] === '--accent') gallery.accent = args[++i];
    else if (args[i] === '--reduced-motion') gallery.reducedMotion = true;
    else { console.error(`Unknown argument: ${args[i]}`); return 2; }
  }
  if (!['dark', 'light'].includes(gallery.appearance) || !['1', '1.25', '1.5', '2'].includes(gallery.scale)
      || !/^#[0-9a-f]{6}$/i.test(gallery.accent)) {
    console.error('Invalid gallery appearance, scale or accent.');
    return 2;
  }
  if (!scenario || !known.has(scenario) || !reportPath) {
    console.error('Usage: node scripts/test-quickshell.mjs --scenario <' + [...known].join('|') + '> --report <path>');
    return 2;
  }

  const sourceFixture = scenario === 'shell-entrypoint'
    ? path.join(repo, 'quickshell/shell.qml')
    : scenario === 'lock-entrypoint'
      ? path.join(repo, 'quickshell/lock.qml')
      : path.join(repo, 'quickshell/tests', `${scenario}.qml`);
  const scratch = await mkdtemp(path.join(tmpdir(), 'pentad-qs-test-'));
  const roots = Object.fromEntries(['config', 'data', 'state', 'cache', 'runtime'].map((name) => [name, path.join(scratch, name)]));
  await Promise.all(Object.values(roots).map((dir) => mkdir(dir, { recursive: true, mode: 0o700 })));
  const report = {
    status: 'blocked', scenario, environment: { runtime: Boolean(process.env.XDG_RUNTIME_DIR), wayland: Boolean(process.env.WAYLAND_DISPLAY) },
    checks: [], artifacts: [],
  };
  try {
    const qsVersion = spawnSync('qs', ['--version'], { encoding: 'utf8', timeout: 5000 });
    const version = qsVersion.error ? undefined : parseVersion(`${qsVersion.stdout}\n${qsVersion.stderr}`);
    if (qsVersion.error || qsVersion.status !== 0 || !meetsFloor(version)) {
      report.checks.push({ name: 'quickshell-version', status: 'blocked', detail: qsVersion.error?.message || `Quickshell ${version?.join('.') || 'version unavailable'}; required version is at least 0.3.2.` });
    }
    try { await readFile(sourceFixture); } catch {
      if (!report.checks.length) report.checks.push({ name: 'fixture', status: 'blocked', detail: `Fixture not present: ${path.relative(repo, sourceFixture)}` });
    }
    if (report.checks.length === 0 && (!process.env.XDG_RUNTIME_DIR || !process.env.WAYLAND_DISPLAY)) {
      report.checks.push({ name: 'display', status: 'blocked', detail: 'A Wayland session and XDG_RUNTIME_DIR are required.' });
    }
    if (report.checks.length === 0) {
      const stagedConfig = path.join(roots.config, 'quickshell-fixture');
      await cp(path.join(repo, 'quickshell'), stagedConfig, { recursive: true, dereference: false });
      const manifests = (await readdir(path.join(stagedConfig, 'widgets'), { recursive: true }))
        .filter(name => path.basename(name) === 'manifest.json').sort();
      const registry = await Promise.all(manifests.map(async name => ({
        id: JSON.parse(await readFile(path.join(stagedConfig, 'widgets', name), 'utf8')).id,
        path: 'widgets/' + name.replaceAll(path.sep, '/'),
      })));
      await writeFile(path.join(stagedConfig, 'builtin-registry.json'), JSON.stringify(registry));
      if (scenario === 'config-store' || scenario === 'artwork' || scenario === 'sidebar-tools' || scenario === 'sidebar-file-tools' || scenario === 'shelf-files' || scenario === 'shelf' || scenario === 'stash-window' || scenario === 'bar-tools-ui' || scenario === 'wallpaper' || scenario === 'spotlight-service' || scenario === 'spotlight') {
        const helpers = path.join(stagedConfig, 'helpers');
        await mkdir(helpers, { recursive: true, mode: 0o700 });
        await Promise.all((scenario === 'sidebar-tools' ? ['pentad_read_input.py'] : scenario === 'sidebar-file-tools' ? ['pentad_read_input.py', 'pentad_file_tool.py', 'pentad_tool_core.py', 'pentad_tool_pdf.py', 'pentad_tool_image.py', 'pentad_tool_media.py', 'pentad_tool_archive.py', 'pentad_shelf_preview.py'] : scenario === 'shelf-files' ? ['pentad_shelf_preview.py']
          : scenario === 'shelf' || scenario === 'stash-window' ? ['pentad_shelf_content.py', 'pentad_shelf_preview.py'] : scenario === 'bar-tools-ui' ? ['pentad_screenshot.py', 'pentad_screenshot_regions.py', 'pentad-files.py', 'pentad_files.py'] : scenario === 'wallpaper' ? ['pentad_recolor_wallpaper.py'] : scenario === 'spotlight-service' || scenario === 'spotlight' ? ['pentad_spotlight.py', 'pentad_files.py'] : ['pentad-files.py', 'pentad_files.py', 'pentad_lyrics_cache.py']).map((name) =>
          cp(path.join(repo, 'tools', name), path.join(helpers, name))));
        // The shelf service talks to the clipboard through this helper; the fixture gets a recording fake.
        if (scenario === 'shelf' || scenario === 'stash-window')
          await cp(path.join(repo, 'tests', 'quickshell', 'fake-stash-clipboard.py'), path.join(helpers, 'pentad_stash_clipboard.py'));
      }
      let fakeBin;
      if (scenario === 'artwork') {
        fakeBin = path.join(scratch, 'fake-bin');
        await mkdir(fakeBin, { recursive: true, mode: 0o700 });
        const fakeCurl = path.join(fakeBin, 'curl');
        await cp(path.join(repo, 'tests', 'quickshell', 'fake-curl.py'), fakeCurl);
        await chmod(fakeCurl, 0o700);
      }
      if (scenario === 'stash-window') {
        // Qt.openUrlExternally runs xdg-open from PATH: a recording stub, so no real app opens the fixture's entries.
        fakeBin = path.join(scratch, 'fake-bin');
        await mkdir(fakeBin, { recursive: true, mode: 0o700 });
        const fakeOpen = path.join(fakeBin, 'xdg-open');
        await writeFile(fakeOpen, '#!/bin/sh\nprintf \'%s\\n\' "$1" >> "${XDG_STATE_HOME:-/tmp}/opened-urls.log"\n', { mode: 0o700 });
      }
      if (scenario === 'overnight') {
        // Every program the overnight service runs is a recording stand-in, and PATH holds nothing
        // else (see env below): no real sleep inhibitor, display, lighting or notification command runs.
        fakeBin = path.join(scratch, 'fake-bin');
        await mkdir(fakeBin, { recursive: true, mode: 0o700 });
        const record = 'log="${XDG_STATE_HOME:?}/overnight-calls.log"; { printf %s "${0##*/}"; printf \'\\t%s\' "$@"; printf \'\\n\'; } >> "$log"\n';
        const fakes = {
          // Like the real one: refuses (mode "fail"), or runs its child after the options and ignores
          // SIGINT, ending the child on SIGTERM; mode "drop" loses the block soon after granting it.
          'systemd-inhibit': record + 'mode="$(cat "$XDG_STATE_HOME/inhibit-mode" 2>/dev/null)"\n'
            + '[ "$mode" = fail ] && { echo "Failed to inhibit: Access denied" >&2; exit 1; }\n'
            + 'while [ "${1#--}" != "$1" ]; do shift; done\n'
            // The child is `sh -c <script> overnight <seconds>`; a run that fails half way must not
            // leave a long sleep behind, so the length is capped at 25 s.
            + 'n="$5"; [ "$n" = infinity ] || [ "$n" -gt 25 ] && n=25\n'
            + 'trap \'\' INT\n"$1" "$2" "$3" "$4" "$n" &\nchild=$!\n'
            + '[ "$mode" = drop ] && { sleep 0.3; kill "$child"; exit 1; }\n'
            + 'trap \'kill "$child" 2>/dev/null; exit 0\' TERM\nwait "$child"\n',
          setpriv: record + '[ "$1" = --pdeathsig ] && shift 2\nexec "$@"\n',
          // The openrazer scripts span lines, so only the read or the brightness list is recorded.
          python3: 'log="${XDG_STATE_HOME:?}/overnight-calls.log"\n'
            + 'if [ "$#" -eq 2 ]; then printf \'python3\\tread\\n\' >> "$log"; printf \'%s\\n\' \'[{"serial": "PM1", "brightness": 42}]\'\n'
            + 'else printf \'python3\\tset\\t%s\\n\' "$3" >> "$log"; fi\n',
          // Mode "fail" stands for a session that refuses the lock.
          loginctl: record + '[ "$(cat "$XDG_STATE_HOME/lock-mode" 2>/dev/null)" = fail ] && exit 1\nexit 0\n',
          openrgb: record, hyprctl: record, 'notify-send': record, timeout: record,
        };
        for (const [name, body] of Object.entries(fakes))
          await writeFile(path.join(fakeBin, name), '#!/bin/sh\n' + body, { mode: 0o700 });
        // The fakes need cat and sleep, the service sh and mv; qs is linked so the runner can start it.
        for (const tool of ['cat', 'mv', 'sh', 'sleep', 'qs']) {
          const found = spawnSync('sh', ['-c', 'command -v "$1"', 'sh', tool], { encoding: 'utf8', timeout: 5000 });
          const real = (found.stdout || '').trim();
          if (found.status !== 0 || !real.startsWith('/')) throw new Error(`Overnight fixture needs ${tool}`);
          await symlink(real, path.join(fakeBin, tool));
        }
      }
      if (scenario === 'wallpaper') {
        // HOME is the scratch directory: a folder with a mostly blue, a gray and an orange image.
        const folder = path.join(scratch, 'Pictures', 'Wallpapers');
        await mkdir(folder, { recursive: true, mode: 0o700 });
        const dark = [30, 30, 30];
        await writeFixturePng(path.join(folder, 'blue.png'), 80, 50, (x, y) => y < 30 ? [40, 120, 200] : x < 30 ? [220, 120, 40] : dark);
        await writeFixturePng(path.join(folder, 'gray.png'), 80, 50, (x) => { const v = 20 + Math.round(x * 2.5); return [v, v, v]; });
        await writeFixturePng(path.join(folder, 'orange.png'), 80, 50, (x, y) => y < 35 ? [220, 120, 40] : dark);
      }
      if (scenario === 'stash-window') {
        // HOME is the scratch directory: photos for the strips and two small files for rows.
        const photos = path.join(scratch, 'Pictures', 'Stash');
        await mkdir(photos, { recursive: true, mode: 0o700 });
        for (let index = 1; index <= 11; index++)
          await writeFixturePng(path.join(photos, `photo-${index}.png`), 96, 72, (x, y) => [40 + index * 16, 90 + Math.round(y * 1.5), 160 - index * 8 + Math.round(x / 4)]);
        await mkdir(path.join(scratch, 'Documents'), { recursive: true, mode: 0o700 });
        await writeFile(path.join(scratch, 'Documents', 'report.pdf'), '%PDF-1.4\n'.padEnd(184320, ' '));
        await mkdir(path.join(scratch, 'Downloads'), { recursive: true, mode: 0o700 });
        await writeFile(path.join(scratch, 'Downloads', 'archive.zip'), 'PK'.padEnd(4096, '\0'));
      }
      if (scenario === 'spotlight-host' || scenario === 'spotlight-service') {
        // HOME is the scratch directory: one picture for the file preview pane.
        const folder = path.join(scratch, 'Pictures');
        await mkdir(folder, { recursive: true, mode: 0o700 });
        await writeFixturePng(path.join(folder, 'Sea Sunset.png'), 320, 200, (x, y) => y < 120
          ? [240 - y, 120 + Math.round(x / 8) - y / 2, 90 + y / 2]
          : [20, 40 + Math.round((y - 120) / 4), 70 + Math.round(x / 10)]);
      }
      if (scenario === 'plugin-host') {
        await cp(path.join(repo, 'quickshell', 'tests', 'fixtures', 'external-widget'),
          path.join(stagedConfig, 'tests', 'external-example'), { recursive: true });
      }
      let fixtureSource = await readFile(sourceFixture, 'utf8');
      let dragDriver = '';
      if (scenario === 'menu-pointer-native')
        await cp(path.join(repo, 'tests/tools/fake-tray-menu.py'), path.join(stagedConfig, 'tests/fake-tray-menu.py'));
      if (['shelf-files', 'menu-pointer-native'].includes(scenario) && process.env.PENTAD_HEADLESS === '1') {
        const hyprlandInput = scenario === 'menu-pointer-native' && process.env.PENTAD_HYPRLAND_TEST_RUNTIME;
        const driverName = hyprlandInput ? 'hyprland-menu-input'
          : scenario === 'menu-pointer-native' ? 'kwin-menu-input' : 'kwin-drag-input';
        dragDriver = path.join(scratch, driverName);
        const pkg = spawnSync('pkg-config', ['--cflags', '--libs', ...(hyprlandInput ? ['wayland-client'] : ['gio-2.0', 'libei-1.0'])], { encoding: 'utf8', timeout: 5000 });
        if (pkg.error || pkg.status !== 0) throw new Error(`Native drag input dependencies unavailable: ${pkg.error?.message || pkg.stderr}`);
        const compiled = spawnSync('cc', [path.join(repo, 'tests/tools', driverName + '.c'), ...pkg.stdout.trim().split(/\s+/), '-o', dragDriver], { encoding: 'utf8', timeout: 10000 });
        if (compiled.error || compiled.status !== 0) throw new Error(`Native drag input build failed: ${compiled.error?.message || compiled.stderr}`);
      }
      if (scenario === 'shell-entrypoint') {
        fixtureSource = fixtureSource.replace(/}\s*$/, `
    Timer {
        interval: 1000; running: true; repeat: false
        onTriggered: {
            console.log('PENTAD_TEST ' + JSON.stringify({ status: 'pass', checks: [
                { name: 'production-shell-entrypoint-loads', passed: true }
            ] }));
            Qt.quit();
        }
    }
}
`);
      }
      if (scenario === 'lock-entrypoint') {
        // The real lock entry inside the private compositor. The virtual KWin offers no
        // ext-session-lock-v1, so this proves the entry loads and that, without the protocol,
        // nothing claims a lock; the entry's own timer would then exit non-zero for the fallback.
        fixtureSource = fixtureSource.replace(/}\s*$/, `
    Timer {
        interval: 1500; running: true; repeat: false
        onTriggered: {
            const checks = [
                { name: 'lock-entrypoint-loads', passed: true },
                { name: 'no-protocol-claims-no-lock', passed: !sessionLock.locked && !sessionLock.secure && !root.held },
                { name: 'still-waiting-for-a-password', passed: !root.unlocking && !lockAuth.unlockedState }
            ];
            console.log('PENTAD_TEST ' + JSON.stringify({ status: checks.every(c => c.passed) ? 'pass' : 'fail', checks: checks }));
            Qt.quit();
        }
    }
}
`);
      }
      const stagedFixture = fixtureSource
        .replaceAll('import "../services"', 'import "services"')
        .replaceAll('import "../shell"', 'import "shell"')
        .replaceAll('import "../features/sidebar"', 'import "features/sidebar"')
        .replaceAll('import "../features/settings"', 'import "features/settings"')
        .replaceAll('import "../features/bar"', 'import "features/bar"')
        .replaceAll('import "../features/overview"', 'import "features/overview"')
        .replaceAll('import "../features/windowswitcher"', 'import "features/windowswitcher"')
        .replaceAll('import "../widgets/clock"', 'import "widgets/clock"')
        .replaceAll("import '../logic/", "import 'logic/")
        .replaceAll('import "../logic/', 'import "logic/');
      await writeFile(path.join(stagedConfig, 'shell.qml'), stagedFixture);
      const waylandDisplay = path.isAbsolute(process.env.WAYLAND_DISPLAY)
        ? process.env.WAYLAND_DISPLAY
        : path.join(process.env.XDG_RUNTIME_DIR, process.env.WAYLAND_DISPLAY);
      const env = {
        PATH: scenario === 'overnight' ? fakeBin : fakeBin
          ? `${fakeBin}:${process.env.PATH || '/usr/bin:/bin'}`
          : process.env.PATH || '/usr/bin:/bin', HOME: scratch,
        XDG_CONFIG_HOME: roots.config, XDG_DATA_HOME: roots.data,
        XDG_STATE_HOME: roots.state, XDG_CACHE_HOME: roots.cache,
        XDG_RUNTIME_DIR: roots.runtime, WAYLAND_DISPLAY: waylandDisplay,
        PENTAD_PREVIEW: '1', PENTAD_SAFE_MODE: '1',
        ...(scenario === 'stash-window' ? { PENTAD_FAKE_OPEN: '1' } : {}),
        LANG: 'C.UTF-8',
      };
      if (process.env.PENTAD_HEADLESS === '1') {
        env.PENTAD_HEADLESS = '1';
        if (scenario === 'menu-pointer-native') env.PENTAD_MENU_CAPTURE_PATH = path.resolve(`${reportPath}.png`);
        if (dragDriver) {
          if (!process.env.DBUS_SESSION_BUS_ADDRESS || process.env.DBUS_SESSION_BUS_ADDRESS === process.env.PENTAD_PARENT_DBUS)
            throw new Error('The drag driver requires the private compositor D-Bus session.');
          env.PENTAD_DND_DRIVER = dragDriver;
          if (scenario === 'menu-pointer-native') env.PENTAD_MENU_INPUT_DRIVER = dragDriver;
          if (scenario === 'menu-pointer-native' && process.env.PENTAD_HYPRLAND_TEST_RUNTIME) {
            env.PENTAD_HYPRLAND_TEST_RUNTIME = process.env.PENTAD_HYPRLAND_TEST_RUNTIME;
            env.PENTAD_HYPRLAND_TEST_INSTANCE = process.env.PENTAD_HYPRLAND_TEST_INSTANCE;
          }
          env.DBUS_SESSION_BUS_ADDRESS = process.env.DBUS_SESSION_BUS_ADDRESS;
          env.PENTAD_PRIVATE_DBUS_SOCKET = process.env.PENTAD_PRIVATE_DBUS_SOCKET;
        }
        env.QT_SCALE_FACTOR = gallery.scale;
        report.environment.displayKind = 'private-virtual';
      }
      if (process.env.DISPLAY) env.DISPLAY = process.env.DISPLAY;
      if (scenario === 'media') {
        env.PENTAD_MEDIA_FIXTURE = ['playing', 'paused', 'no-art', 'no-player', 'missing-lyrics', 'long-title']
          .includes(process.env.PENTAD_MEDIA_FIXTURE) ? process.env.PENTAD_MEDIA_FIXTURE : 'playing';
        report.environment.mediaFixture = env.PENTAD_MEDIA_FIXTURE;
      }
      if (['design-system', 'control-templates', 'tool-context', 'bar-tools-ui', 'application-mixer', 'bar', 'bar-visual', 'workspace-capsule', 'media', 'popups', 'control-center', 'window-navigation-visual', 'shelf-files', 'shelf', 'stash-window', 'sidebar-tools', 'sidebar-file-tools', 'screenshot-editor', 'settings-window', 'level-overlay', 'wallpaper', 'lock-screen', 'showcase', 'spotlight-host', 'notification-popup', 'cheatsheet', 'file-drop', 'spring-dropdown'].includes(scenario)) {
        const font = spawnSync('fc-match', ['-f', '%{family}\n%{file}', 'Geist'], { encoding: 'utf8', timeout: 5000 });
        const [family, fontPath] = (font.stdout || '').trim().split('\n');
        report.environment.font = { requested: 'Geist', resolved: family || 'unavailable' };
        if (font.status === 0 && fontPath && /\.(?:ttf|otf)$/i.test(fontPath)) {
          const fonts = path.join(roots.data, 'fonts');
          await mkdir(fonts, { recursive: true, mode: 0o700 });
          await cp(fontPath, path.join(fonts, path.basename(fontPath)));
        }
        if (scenario === 'workspace-capsule') {
          const identityFont = spawnSync('fc-match', ['-f', '%{file}', 'Google Sans Flex'], { encoding: 'utf8', timeout: 5000 });
          const identityPath = (identityFont.stdout || '').trim();
          if (identityFont.status === 0 && /\.(?:ttf|otf)$/i.test(identityPath)) {
            const fonts = path.join(roots.data, 'fonts');
            await mkdir(fonts, { recursive: true, mode: 0o700 });
            await cp(identityPath, path.join(fonts, path.basename(identityPath)));
          }
        }
        if (scenario === 'bar' || scenario === 'bar-visual' || scenario === 'media' || scenario === 'tool-context' || scenario === 'bar-tools-ui' || scenario === 'application-mixer'
            || scenario === 'control-center' || scenario === 'notification-popup' || scenario === 'sidebar-tools' || scenario === 'sidebar-file-tools'
            || scenario === 'showcase') {
          const symbols = spawnSync('fc-match', ['-f', '%{file}', 'Material Symbols Rounded'], { encoding: 'utf8', timeout: 5000 });
          const symbolsPath = (symbols.stdout || '').trim();
          if (symbols.status === 0 && /\.(?:ttf|otf)$/i.test(symbolsPath)) {
            const fonts = path.join(roots.data, 'fonts');
            await mkdir(fonts, { recursive: true, mode: 0o700 });
            await cp(symbolsPath, path.join(fonts, path.basename(symbolsPath)));
          }
        }
        const capture = path.resolve(`${reportPath}.png`);
        await mkdir(path.dirname(capture), { recursive: true });
        await rm(capture, { force: true });
        env.PENTAD_ARTIFACT_PATH = capture;
        if (scenario === 'bar-visual') {
          env.PENTAD_TOOLTIP_CAPTURE_PATH = `${capture}.tooltip.png`;
          env.PENTAD_TOOLTIP_LONG_CAPTURE_PATH = `${capture}.tooltip-long.png`;
          env.PENTAD_TOOLTIP_EDGE_CAPTURE_PATH = `${capture}.tooltip-edge.png`;
          await Promise.all([env.PENTAD_TOOLTIP_CAPTURE_PATH, env.PENTAD_TOOLTIP_LONG_CAPTURE_PATH,
            env.PENTAD_TOOLTIP_EDGE_CAPTURE_PATH]
            .map((artifact) => rm(artifact, { force: true })));
        }
        env.PENTAD_GALLERY_APPEARANCE = gallery.appearance;
        env.PENTAD_GALLERY_SCALE = gallery.scale;
        env.PENTAD_GALLERY_ACCENT = gallery.accent;
        env.PENTAD_GALLERY_REDUCED_MOTION = gallery.reducedMotion ? '1' : '0';
        report.environment.gallery = gallery;
      }
      const child = spawn('qs', ['--no-duplicate', '--path', stagedConfig], { cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'] });
      let output = '';
      child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
      child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        child.kill('SIGTERM');
        setTimeout(() => child.kill('SIGKILL'), 1000).unref();
      }, 30000);
      const closed = await new Promise((resolve) => {
        child.once('error', (error) => resolve({ error }));
        child.once('close', (code, signal) => resolve({ code, signal }));
      });
      clearTimeout(timer);
      const { events, checks } = parseTestOutput(output);
      report.checks = checks;
      const errors = output.split(/\r?\n/).filter((line) => /module .* not installed|could not connect to display|failed to create.*display/i.test(line));
      const runtimeErrors = qmlRuntimeErrors(output);
      if (closed.error) {
        report.status = 'blocked';
        report.checks.push({ status: 'blocked', detail: `Could not launch qs: ${closed.error.message}` });
      } else if (timedOut) {
        report.status = 'blocked';
        report.checks.push({ status: 'blocked', detail: 'Fixture exceeded the 30 second timeout.' });
      } else if (errors.length) {
        report.status = 'blocked';
        report.checks.push({ status: 'blocked', detail: errors.join('\n') });
      } else if (runtimeErrors.length) {
        report.status = 'fail';
        report.checks.push({ name: 'qml-runtime-errors', status: 'fail', detail: runtimeErrors.join('\n') });
      } else if (closed.code === 0 && events.length > 0 && checks.length > 0 && checks.every((check) => check.status === 'pass') && events.every((event) => event.status === 'pass')) report.status = 'pass';
      else report.status = events.length ? 'fail' : 'blocked';
      if (['design-system', 'control-templates', 'tool-context', 'bar-tools-ui', 'application-mixer', 'bar', 'bar-visual', 'workspace-capsule', 'media', 'popups', 'control-center', 'window-navigation-visual', 'shelf-files', 'shelf', 'stash-window', 'sidebar-tools', 'sidebar-file-tools', 'screenshot-editor', 'settings-window', 'level-overlay', 'wallpaper', 'lock-screen', 'showcase', 'spotlight-host', 'cheatsheet', 'file-drop', 'spring-dropdown'].includes(scenario)
          && (report.status === 'pass' || scenario === 'bar-visual')) {
        try {
          const capture = path.resolve(`${reportPath}.png`);
          if (scenario === 'popups') {
            for (const side of ['left', 'right']) {
              const drawerCapture = capture + '.' + side + '.png';
              if ((await stat(drawerCapture)).size < 8) throw new Error('Empty drawer capture');
              await chmod(drawerCapture, 0o600);
              report.artifacts.push(drawerCapture);
            }
          } else if (scenario === 'control-center') {
            for (const suffix of ['.right.png', '.tasks.png', '.short.png', '.collapsed.png', '.empty.png']) {
              const panelCapture = capture + suffix;
              if ((await stat(panelCapture)).size < 8) throw new Error('Empty control-center capture');
              await chmod(panelCapture, 0o600);
              report.artifacts.push(panelCapture);
            }
          } else {
            if ((await stat(capture)).size < 8) throw new Error('Empty capture');
            await chmod(capture, 0o600);
            report.artifacts.push(capture);
            if (scenario === 'sidebar-tools') {
              for (const suffix of ['.empty.png', '.large.png', '.choices.png']) {
                const catalogCapture = capture + suffix;
                if ((await stat(catalogCapture)).size < 8) throw new Error('Empty catalog capture');
                await chmod(catalogCapture, 0o600);
                report.artifacts.push(catalogCapture);
              }
            }
            if (scenario === 'sidebar-file-tools') {
              for (const suffix of ['.images.png', '.image-text.png', '.checksum.png', '.text-tools.png', '.dragmode.png', '.catalog.png']) {
                const toolCapture = capture + suffix;
                if ((await stat(toolCapture)).size < 8) throw new Error('Empty file tool capture');
                await chmod(toolCapture, 0o600);
                report.artifacts.push(toolCapture);
              }
            }
            if (scenario === 'showcase') {
              const mediaCapture = capture + '.media.png';
              if ((await stat(mediaCapture)).size < 8) throw new Error('Empty showcase media capture');
              await chmod(mediaCapture, 0o600);
              report.artifacts.push(mediaCapture);
            }
            if (scenario === 'cheatsheet') {
              for (const suffix of ['.uk.png', '.unavailable.png']) {
                const sheetCapture = capture + suffix;
                if ((await stat(sheetCapture)).size < 8) throw new Error('Empty cheatsheet capture');
                await chmod(sheetCapture, 0o600);
                report.artifacts.push(sheetCapture);
              }
            }
            if (scenario === 'wallpaper') {
              const windowCapture = capture + '.window.png';
              if ((await stat(windowCapture)).size < 8) throw new Error('Empty wallpaper window capture');
              await chmod(windowCapture, 0o600);
              report.artifacts.push(windowCapture);
              // Mid-transition frames; a reduced-motion run has no transition to capture.
              for (const suffix of ['.transition.png', '.transition-disc.png', '.transition-pixelate.png', '.transition-iris.png']) {
                const transitionCapture = capture + suffix;
                const transitionSize = await stat(transitionCapture).then(({ size }) => size, () => 0);
                if (transitionSize < 8) continue;
                await chmod(transitionCapture, 0o600);
                report.artifacts.push(transitionCapture);
              }
            }
            if (scenario === 'level-overlay') {
              for (const suffix of ['.settled.png', '.falling.png', '.layout.png']) {
                const levelCapture = capture + suffix;
                if ((await stat(levelCapture)).size < 8) throw new Error('Empty level overlay capture');
                await chmod(levelCapture, 0o600);
                report.artifacts.push(levelCapture);
              }
            }
            if (scenario === 'screenshot-editor') {
              for (const suffix of ['.crosshair.png', '.region.png', '.selected.png', '.right.png', '.left.png', '.palette.png']) {
                const editorCapture = capture + suffix;
                if ((await stat(editorCapture)).size < 8) throw new Error('Empty screenshot editor capture');
                await chmod(editorCapture, 0o600);
                report.artifacts.push(editorCapture);
              }
            }
            if (scenario === 'window-navigation-visual') {
              for (const suffix of ['.all.png', '.application.png']) {
                const navigationCapture = capture + suffix;
                if ((await stat(navigationCapture)).size < 8) throw new Error('Empty navigation capture');
                await chmod(navigationCapture, 0o600);
                report.artifacts.push(navigationCapture);
              }
            }
            if (scenario === 'bar-visual') {
              for (const suffix of ['.tooltip.png', '.tooltip-long.png', '.tooltip-edge.png',
                '.audio-09.png', '.audio-10.png', '.audio-99.png', '.audio-100.png',
                '.audio-long-device.png', '.audio-muted.png', '.audio-unavailable.png',
                '.audio-error.png', '.audio-reopen.png']) {
                const tooltipCapture = `${capture}${suffix}`;
                if ((await stat(tooltipCapture)).size < 8) throw new Error(`Empty tooltip capture: ${suffix}`);
                await chmod(tooltipCapture, 0o600);
                report.artifacts.push(tooltipCapture);
              }
            }
            if (scenario === 'application-mixer') {
              const popupCapture = `${capture}.mixer-popover.png`;
              if ((await stat(popupCapture)).size < 8) throw new Error('Empty mixer popup capture');
              await chmod(popupCapture, 0o600);
              report.artifacts.push(popupCapture);
            }
            if (scenario === 'tool-context') {
              const popoverCapture = `${capture}.popover.png`;
              try {
                if ((await stat(popoverCapture)).size >= 8) {
                  await chmod(popoverCapture, 0o600);
                  report.artifacts.push(popoverCapture);
                }
              } catch {}
            }
          }
          if (scenario === 'bar') {
            for (const suffix of ['.telemetry-popup.png', '.active-title.png']) {
              const barCapture = capture + suffix;
              if ((await stat(barCapture)).size < 8) throw new Error('Empty bar detail capture');
              await chmod(barCapture, 0o600);
              report.artifacts.push(barCapture);
            }
          } else if (scenario === 'media') {
            const focusCapture = capture + '.focus.png';
            if ((await stat(focusCapture)).size < 8) throw new Error('Empty karaoke focus capture');
            await chmod(focusCapture, 0o600);
            report.artifacts.push(focusCapture);
          }
        } catch (error) {
          report.status = 'fail';
          report.checks.push({ name: 'gallery-capture', status: 'fail', detail: error.message });
        }
      }
      if (output) {
        const logPath = `${reportPath}.log`;
        await mkdir(path.dirname(path.resolve(logPath)), { recursive: true });
        await writeFile(logPath, output, { mode: 0o600 });
        report.artifacts.push(logPath);
      }
      if (scenario === 'menu-pointer-native') {
        const capture = path.resolve(`${reportPath}.png`);
        try { if ((await stat(capture)).size > 8) report.artifacts.push(capture); } catch {}
      }
    }
  } finally {
    await mkdir(path.dirname(path.resolve(reportPath)), { recursive: true });
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
    await rm(scratch, { recursive: true, force: true });
  }
  console.log(`${report.status}: ${scenario} (${report.checks.length} checks); report ${reportPath}`);
  return report.status === 'pass' ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = await main();
