#!/usr/bin/env node
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const qsDefault = '/tmp/pentad-qs-bin/qs';
const marker = 'PENTAD_LYRICS_TEST ';

function parseArgs(argv) {
  const options = { qs: process.env.PENTAD_QS_BIN || qsDefault, report: undefined };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--qs' && argv[i + 1]) options.qs = argv[++i];
    else if (argv[i] === '--report' && argv[i + 1]) options.report = argv[++i];
    else throw new Error(`Unknown or incomplete argument: ${argv[i]}`);
  }
  return options;
}

function check(name, passed, detail = '') {
  return { name, passed: passed === true, detail };
}

const fakeCurl = String.raw`#!/usr/bin/python3
import json, os, sys, time
from urllib.parse import parse_qs, urlparse

argv = sys.argv[1:]
url = argv[argv.index('--url') + 1] if '--url' in argv else ''
parsed = urlparse(url)
query = parse_qs(parsed.query)
title = query.get('track_name', [''])[0]
endpoint = parsed.path.rsplit('/', 1)[-1]
log_path = os.environ['PENTAD_LYRICS_CURL_LOG']

def log(record):
    with open(log_path, 'a', encoding='utf-8') as stream:
        stream.write(json.dumps(record, ensure_ascii=False) + '\n')

log({'event': 'start', 'url': url, 'argv': argv, 'pid': os.getpid()})
status, code, body = 200, 0, ''
if parsed.scheme != 'https' or parsed.hostname != 'lrclib.net':
    status, code, body = 0, 7, 'blocked fakecurl target'
elif title in ('StaleSong', 'CancelSong'):
    time.sleep(8)
elif title == 'TimeoutSong':
    time.sleep(20)
elif title == 'SyncedSong':
    body = json.dumps({'syncedLyrics': '[00:01.00]Synced fixture line'})
elif title == 'SearchSong' and endpoint == 'get':
    status, body = 404, ''
elif title == 'SearchSong' and endpoint == 'search':
    body = json.dumps([{'trackName': 'SearchSong', 'artistName': 'Fixture Artist',
        'albumName': 'Fixture Album', 'duration': 180,
        'syncedLyrics': '[00:02.00]Search fixture line'}])
elif title == 'RateSong':
    status, body = 429, ''
elif title == 'InvalidSong':
    body = '{invalid json'
elif title == 'FailureSong':
    code, status, body = 22, 0, 'simulated curl failure'
elif title == 'OversizeSong':
    body = json.dumps({'plainLyrics': 'oversize fixture'}) + (' ' * 1048600)
elif title == 'StatusSong':
    status, body = 500, '{"error":"fixture"}'
elif title == 'InstrumentalSong':
    body = json.dumps({'instrumental': True})
elif title == 'PlainSong':
    body = json.dumps({'plainLyrics': 'Plain fixture lyrics'})
elif title == 'CurrentSong':
    body = json.dumps({'syncedLyrics': '[00:03.00]Current track line'})
else:
    status, body = 404, ''

if code:
    sys.stderr.write(body + '\n')
else:
    sys.stdout.write(body + '\n' + str(status))
log({'event': 'done', 'title': title, 'endpoint': endpoint, 'http': status, 'exit': code})
sys.exit(code)
`;

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const scratch = await mkdtemp(path.join(os.tmpdir(), 'pentad-lyrics-native-'));
  const bin = path.join(scratch, 'bin');
  const config = path.join(scratch, 'config');
  const data = path.join(scratch, 'data');
  const logPath = path.join(scratch, 'curl.jsonl');
  const report = { status: 'fail', scenario: 'lyrics-native', qs: options.qs, network: 'fakecurl only' };
  let child;
  let output = '';
  try {
    const version = spawnSync(options.qs, ['--version'], { encoding: 'utf8', timeout: 5000 });
    if (version.error || version.status !== 0 || !/Quickshell 0\.3\.2\b/.test(`${version.stdout}\n${version.stderr}`))
      throw new Error(`Need pinned Quickshell 0.3.2: ${version.error?.message || version.stderr || version.stdout}`);

    for (const folder of [bin, config, data, path.join(scratch, 'runtime'), path.join(scratch, 'cache'), path.join(scratch, 'state')])
      await mkdir(folder, { recursive: true, mode: 0o700 });
    const curlPath = path.join(bin, 'curl');
    await writeFile(curlPath, fakeCurl, { mode: 0o700 });
    await mkdir(path.join(config, 'services'));
    await mkdir(path.join(config, 'logic'));
    await cp(path.join(repo, 'quickshell/services/Lyrics.qml'), path.join(config, 'services/Lyrics.qml'));
    await cp(path.join(repo, 'quickshell/logic/lyrics.mjs'), path.join(config, 'logic/lyrics.mjs'));
    await cp(path.join(repo, 'quickshell/tests/lyrics-native.qml'), path.join(config, 'shell.qml'));

    const env = {
      PATH: `${bin}:/usr/local/bin:/usr/bin:/bin`,
      HOME: scratch,
      XDG_CONFIG_HOME: path.join(scratch, 'config-home'),
      XDG_DATA_HOME: data,
      XDG_CACHE_HOME: path.join(scratch, 'cache'),
      XDG_STATE_HOME: path.join(scratch, 'state'),
      XDG_RUNTIME_DIR: path.join(scratch, 'runtime'),
      LANG: 'C.UTF-8',
      QT_QPA_PLATFORM: 'offscreen',
      GIO_USE_VFS: 'local',
      PENTAD_LYRICS_CURL_LOG: logPath,
    };
    await mkdir(env.XDG_CONFIG_HOME, { recursive: true, mode: 0o700 });
    child = spawn('/usr/bin/dbus-run-session', ['--', options.qs, '--no-duplicate', '--path', config], {
      cwd: repo, env, stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
    child.stderr.setEncoding('utf8').on('data', (chunk) => { output += chunk; });
    const result = await new Promise((resolve, reject) => {
      const timeout = setTimeout(async () => {
        const curlLog = await readFile(logPath, 'utf8').catch(() => 'no fakecurl invocations');
        child.kill('SIGKILL');
        reject(new Error(`Native lyrics fixture timed out. Output:\n${output}\nFakecurl log:\n${curlLog}`));
      }, 25000);
      child.once('error', (error) => { clearTimeout(timeout); reject(error); });
      child.once('close', (code, signal) => { clearTimeout(timeout); resolve({ code, signal }); });
    });

    const markerLine = output.split(/\r?\n/).find((line) => line.includes(marker));
    const event = markerLine ? JSON.parse(markerLine.slice(markerLine.indexOf(marker) + marker.length)) : null;
    const checks = (event && Array.isArray(event.checks) ? event.checks : []).map((item) =>
      check(item.name, item.passed, item.detail || ''));

    const noCurlPath = path.join(scratch, 'no-curl-bin');
    await mkdir(noCurlPath, { mode: 0o700 });
    await symlink('/usr/bin/dbus-daemon', path.join(noCurlPath, 'dbus-daemon'));
    let startFailureOutput = '';
    const startFailureEnv = { ...env, PATH: noCurlPath, PENTAD_LYRICS_START_FAILURE: '1' };
    child = spawn('/usr/bin/dbus-run-session', ['--', options.qs, '--no-duplicate', '--path', config], {
      cwd: repo, env: startFailureEnv, stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.setEncoding('utf8').on('data', (chunk) => { startFailureOutput += chunk; });
    child.stderr.setEncoding('utf8').on('data', (chunk) => { startFailureOutput += chunk; });
    const startFailureResult = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        child.kill('SIGKILL');
        reject(new Error(`Missing-curl fixture timed out. Output:\n${startFailureOutput}`));
      }, 7000);
      child.once('error', (error) => { clearTimeout(timeout); reject(error); });
      child.once('close', (code, signal) => { clearTimeout(timeout); resolve({ code, signal }); });
    });
    const startFailureLine = startFailureOutput.split(/\r?\n/).find((line) => line.includes(marker));
    const startFailureEvent = startFailureLine
      ? JSON.parse(startFailureLine.slice(startFailureLine.indexOf(marker) + marker.length)) : null;
    for (const item of startFailureEvent?.checks || [])
      checks.push(check(item.name, item.passed, item.detail || ''));
    checks.push(check('empty private PATH contains no curl executable',
      startFailureResult.code === 0 && startFailureEvent?.status === 'pass'
      && startFailureOutput.includes('start-failed'), startFailureOutput.trim()));

    const records = (await readFile(logPath, 'utf8').catch(() => '')).split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
    const starts = records.filter((item) => item.event === 'start');
    const done = records.filter((item) => item.event === 'done');
    const byTitle = (title, eventName) => records.filter((item) => item.title === title && item.event === eventName);
    const searchGet = byTitle('SearchSong', 'done').find((item) => item.endpoint === 'get');
    const searchFallback = byTitle('SearchSong', 'done').find((item) => item.endpoint === 'search');
    const searchStart = starts.find((item) => item.url.includes('/api/search?'));
    const syncedStarts = starts.filter((item) => item.url.includes('track_name=SyncedSong'));
    const rateStarts = starts.filter((item) => item.url.includes('track_name=RateSong'));
    const rateDone = done.filter((item) => item.title === 'RateSong');
    const staleStarts = starts.filter((item) => item.url.includes('track_name=StaleSong'));
    const staleDone = done.filter((item) => item.title === 'StaleSong');
    const currentDone = done.filter((item) => item.title === 'CurrentSong');
    const cancelStarts = starts.filter((item) => item.url.includes('track_name=CancelSong'));
    const cancelDone = done.filter((item) => item.title === 'CancelSong');
    const failureDone = done.filter((item) => item.title === 'FailureSong');
    const invalidDone = done.filter((item) => item.title === 'InvalidSong');
    const oversizeDone = done.filter((item) => item.title === 'OversizeSong');
    const statusDone = done.filter((item) => item.title === 'StatusSong');
    const instrumentalDone = done.filter((item) => item.title === 'InstrumentalSong');
    const plainDone = done.filter((item) => item.title === 'PlainSong');
    const timeoutStarts = starts.filter((item) => item.url.includes('track_name=TimeoutSong'));
    const timeoutDone = done.filter((item) => item.title === 'TimeoutSong');
    const policyArgs = starts.length > 0 && starts.every((item) => item.argv.includes('--proto')
      && item.argv.includes('=https') && item.argv.includes('--max-time')
      && item.argv.includes('12') && item.argv.includes('--connect-timeout')
      && item.argv.includes('5') && item.argv.includes('--max-filesize')
      && item.argv.includes('1048576'));
    checks.push(check('all requests used fakecurl and HTTPS-only bounded argv', policyArgs,
      `fake requests=${starts.length}; no external curl is on PATH`));
    checks.push(check('exact lookup 404 triggers only the strict search query',
      searchGet?.http === 404 && searchFallback?.http === 200 && !!searchStart
      && !searchStart.url.includes('album_name=') && !searchStart.url.includes('duration='),
      JSON.stringify({ exact: searchGet, search: searchStart?.url })));
    checks.push(check('429 response is requested once across reacquire during backoff',
      rateStarts.length === 1 && rateDone.length === 1 && rateDone[0].http === 429,
      `starts=${rateStarts.length}`));
    checks.push(check('successful exact response is cached across release and reacquire',
      syncedStarts.length === 1, `starts=${syncedStarts.length}`));
    checks.push(check('invalid JSON and curl failure were delivered by the stub',
      invalidDone.length === 1 && invalidDone[0].http === 200
      && failureDone.length === 1 && failureDone[0].exit === 22,
      JSON.stringify({ invalidDone, failureDone })));
    checks.push(check('oversize, HTTP 500, instrumental and plain cases reached fakecurl',
      oversizeDone.length === 1 && statusDone.length === 1 && statusDone[0].http === 500
      && instrumentalDone.length === 1 && plainDone.length === 1
      && timeoutStarts.length === 1 && timeoutDone.length === 0,
      JSON.stringify({ oversizeDone, statusDone, instrumentalDone, plainDone,
        timeoutStarts: timeoutStarts.length, timeoutDone: timeoutDone.length })));
    checks.push(check('stale and released Processes do not complete',
      staleStarts.length === 1 && staleDone.length === 0 && cancelStarts.length === 1
      && cancelDone.length === 0 && currentDone.length === 1,
      JSON.stringify({ staleStarts: staleStarts.length, staleDone: staleDone.length,
        cancelStarts: cancelStarts.length, cancelDone: cancelDone.length, currentDone: currentDone.length })));

    report.checks = checks;
    report.artifacts = [];
    if (options.report) {
      const reportPath = path.resolve(options.report);
      const logCopy = `${reportPath}.curl.jsonl`;
      await mkdir(path.dirname(reportPath), { recursive: true });
      await writeFile(logCopy, records.map((item) => JSON.stringify(item)).join('\n') + (records.length ? '\n' : ''));
      report.artifacts.push(logCopy);
      report.output = `${output}\n${startFailureOutput}`;
      report.status = result.code === 0 && event?.status === 'pass' && checks.length > 0 && checks.every((item) => item.passed)
        ? 'pass' : 'fail';
      await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    } else {
      report.output = `${output}\n${startFailureOutput}`;
      report.status = result.code === 0 && event?.status === 'pass' && checks.length > 0 && checks.every((item) => item.passed)
        ? 'pass' : 'fail';
    }
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return report.status === 'pass' ? 0 : 1;
  } finally {
    if (child && child.exitCode === null) child.kill('SIGKILL');
    await rm(scratch, { recursive: true, force: true });
  }
}

main().then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(JSON.stringify({ status: 'fail', scenario: 'lyrics-native', error: error.stack || String(error) }, null, 2));
  process.exitCode = 1;
});
