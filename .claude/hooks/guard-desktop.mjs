#!/usr/bin/env node
// PreToolUse guard for Bash commands; see AGENTS.md "Не заважати роботі користувача".
// Exit 2 blocks the command and sends stderr to Claude; exit 0 allows it.
//
// Always blocked: anything that stops, restarts or rewrites the user's live shell
// (it runs from dist/quickshell), broad process killing, and desktop-state changes.
// Blocked only in quiet mode: anything that launches Quickshell, a test compositor
// or a desktop window. Quiet mode is on while a game runs or ~/.cache/pentad-focus exists.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';

const gameProcesses = new Set(['cs2', 'dota2', 'eldenring.exe', 'hl2_linux']);
const focusFile = process.env.PENTAD_FOCUS_FILE || path.join(homedir(), '.cache/pentad-focus');
const procRoot = process.env.PENTAD_GUARD_PROC_ROOT || '/proc';

// `word` in command position: at the start or after ; & | ( `, optionally behind
// VAR=value assignments, wrappers like timeout/env/setsid and a directory prefix.
// An argument such as `grep qs quickshell/` is not a command position.
const end = '(?=$|[\\s;&|)`])';
const cmd = word => new RegExp(`(?:^|[;&|(\`\\n])\\s*(?:\\S+=\\S*\\s+)*(?:(?:timeout|env|nice|exec|setsid|sudo)\\s+(?:-\\S+\\s+|\\S+=\\S*\\s+|\\d\\S*\\s+)*)*(?:\\S*/)?${word}${end}`);

const always = [
  [cmd('(killall|pkill)'),'broad process killing is forbidden; kill only PIDs you started yourself'],
  [cmd('(qs|quickshell)\\s+(kill|ipc)'), 'this talks to or stops the live shell'],
  [/scripts\/pentad\s+(?!(status|logs)\b)\S+/, 'scripts/pentad acts on the live shell; only `status` and `logs` are allowed'],
  [/\bsystemctl\s+--user\s+(stop|restart|kill|reload)\b/, 'stopping or restarting user services is forbidden'],
  [/\bhyprctl\s+(dispatch|keyword|reload|kill)\b/, 'this changes the live compositor'],
  [/\bpnpm\s+(run\s+)?(build:qs|start:qs|dev:qs|start)(?=$|[\s;&|)])/, 'this rebuilds or starts the live shell in dist/quickshell'],
  [/\bpnpm\s+(run\s+)?test(?=$|[\s;&|)])/, '`pnpm test` rebuilds the live dist/quickshell (tests/tooling/quickshell.test.mjs); run the safe suites from the verify-change skill instead'],
  [/build-quickshell\.mjs(?![^;&|]*--output)/, 'building without --output overwrites the live dist/quickshell; pass --output <scratch dir>'],
  [/dev-quickshell\.mjs/, 'the dev watcher rebuilds and relaunches the live shell'],
  [cmd('(notify-send|wl-copy|xclip|xsel|wpctl\\s+set-\\S+|pactl\\s+set-\\S+|brightnessctl|swww|hyprpaper|swaybg)'), 'tests must not change notifications, clipboard, volume, brightness or wallpaper'],
];

const quiet = [
  [cmd('(qs|quickshell)'), 'this launches Quickshell'],
  [/(test|check|verify)-quickshell(-headless)?\.mjs/, 'this launches a Quickshell fixture'],
  [new RegExp(`\\bpnpm\\s+(run\\s+)?(test:qs|check:qs|test:qs:integration|start:ags|test:ags)${end}`), 'this launches a shell or fixture'],
  [cmd('(kwin_wayland|weston|cage|Xvfb|xdg-open|gtk-launch)'), 'this starts a compositor or opens a window'],
];

function gameRunning() {
  let entries;
  try { entries = readdirSync(procRoot); } catch { return null; }
  for (const pid of entries) {
    if (!/^\d+$/.test(pid)) continue;
    try {
      const name = readFileSync(path.join(procRoot, pid, 'comm'), 'utf8').trim().toLowerCase();
      if (gameProcesses.has(name)) return name;
      if (name === 'reaper' && readFileSync(path.join(procRoot, pid, 'cmdline'), 'utf8').includes('SteamLaunch')) return 'a Steam game';
    } catch { /* process exited while scanning */ }
  }
  return null;
}

let input = '';
for await (const chunk of process.stdin) input += chunk;
let command = '';
try { command = JSON.parse(input).tool_input?.command ?? ''; } catch { process.exit(0); }

const block = reason => {
  console.error(`Blocked by .claude/hooks/guard-desktop.mjs: ${reason}.\nDo not look for a workaround. Mark the affected check as unverified, or ask the user to run the command themselves.`);
  process.exit(2);
};

for (const [pattern, reason] of always) if (pattern.test(command)) block(reason);

const quietRules = quiet.filter(([pattern]) => pattern.test(command));
if (quietRules.length) {
  const game = gameRunning();
  const focus = existsSync(focusFile);
  if (game || focus) {
    const why = game ? `the user is playing (${game})` : `quiet mode is on (${focusFile} exists)`;
    block(`${quietRules[0][1]}, and ${why}. Continue with work that shows nothing on screen: code, logic tests, scratch builds`);
  }
}
process.exit(0);
