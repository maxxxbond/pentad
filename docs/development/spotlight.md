# Spotlight

Spotlight opens through Pentad's global shortcuts, not a CLI command: `pentad:search` toggles it, `pentad:search-release` opens it on a bare Super tap, and `pentad:clipboard` and `pentad:emoji` open it straight in clipboard history or emoji search. Pressing a mode shortcut while Spotlight shows another mode switches to it; pressing it again closes Spotlight.

Hyprland traditional configuration:

```ini
bind = SUPER, SPACE, global, pentad:search
bind = SUPER, V, global, pentad:clipboard
bind = SUPER, PERIOD, global, pentad:emoji
```

For Lua configuration, load `quickshell/defaults/hyprland-quickshell.lua`, which binds Spotlight to `SUPER + Space`, clipboard history to `SUPER + V`, emoji to `SUPER + Period`, preserves the default bare-Super action and includes workspace-hold bindings. Spotlight opening requests first close all widget menus and drawers.

Search prefixes: `= 24 * 7`, `:fire`, `cb token`, `? arch hyprland`. Ordinary text searches applications and adds DuckDuckGo. The apps button or ↓ with an empty field opens pinned, recent and installed applications.

The launcher is an 800px dock centered at the top of the active monitor, with width constrained on narrower outputs. A 56px search capsule holds the search/back button; beside it, as in macOS Tahoe, a separate capsule groups circular buttons for applications, clipboard and emoji; a detached results card with 24px continuous corners sits 8px below it. Results are grouped under quiet section titles (pinned, recent, applications, calculator, files, web search) and use full-colour icons. The selected row gets a tonal surface. While the preview pane is shown, rows carry only an icon and a name; on narrow outputs the selected row shows its primary action with ↵ and other rows their kind where the section title does not already say it. A 280px preview pane on the right follows the selection, as in macOS Spotlight: a large application icon with its description, a picture thumbnail, a file's kind, size and modification date, the calculator result, or clipboard text and images. The bottom of the pane lists the selected result's actions as capsule buttons: the primary one (what Enter does) first, then Pin, Show in folder, Copy path or Delete as they apply. Outputs narrower than about 620px drop the pane, and the emoji grid keeps its own preview. The list scrolls within 432px. Surfaces use Pentad theme tokens and Geist, without outlines or accent fills. The workspace overview remains a separate feature.

| Shortcut | Action |
| --- | --- |
| ↑ / ↓, Ctrl+N / Ctrl+P | Select a result or action |
| Enter, click result | Run the primary action |
| Alt+1…9 | Run a visible result by position |
| Ctrl+K, right-click result | Open contextual actions |
| Ctrl+Space | Open selected result details |
| Ctrl+Shift+P | Pin/unpin an application |
| Ctrl+C | Copy a supported result when no input or preview text is selected |
| Ctrl+Delete | Delete selected clipboard entry |
| Esc | Return from actions/details, then close Spotlight |

Pinned applications and launch frequency/recency are stored atomically in `$XDG_STATE_HOME/pentad/spotlight.json` (normally `~/.local/state/pentad/spotlight.json`). Only application identifiers and launch statistics are persisted. History modestly boosts close search matches; home browsing puts pins and recent launches first. Search terms and clipboard contents are not written to this file.

Details open on demand in the same panel: application description/executable, calculator expression/result, emoji shortcode/Unicode, or clipboard text/image. Clipboard decoding is lazy and cached only within the current query. Closing or changing the query invalidates stale previews and action completions. Result widgets remain stable during arrow navigation, with a 140ms moving selection marker. Panel expansion takes 180ms and page transitions 160ms; external entry/exit uses shared surface motion. GTK reduced motion disables transitions.

Clipboard requires `cliphist` and `wl-copy`, with a clipboard watcher configured in the session. Native clipboard calls are binary-safe, use argv directly and have an 800ms watchdog. History refreshes on each clipboard query. Provider failures do not prevent other searches.

## Files

Ordinary queries of two or more characters also search files by name; every word must appear in the name. `fd` walks the XDG user directories (Desktop, Documents, Downloads, Music, Pictures, Videos, as named in `user-dirs.dirs`) up to six levels deep, honouring `.gitignore` and skipping hidden entries; without `fd`, `find` does the same walk. When `plocate` is installed, its index adds matches from the rest of the home directory. Hidden paths and anything outside the home directory are always dropped, and at most 60 files are returned. Both tools are optional: without them files are simply absent. On btrfs systems `updatedb` usually skips a separately mounted `/home` (`PRUNE_BIND_MOUNTS`), so the `fd` walk is the part that always works.

Files arrive after applications, calculator and web results, so a slow disk never delays them. Enter opens a file with `xdg-open`; the actions menu adds **Show in folder** and **Copy path** (also Ctrl+C). File names and paths are passed as argument arrays, never through a shell string. Nothing about file searches is persisted.

## Emoji languages

The complete offline emoji dictionary contains 3,979 sequences in 28 languages. Search names, keywords, English shortcodes and associations: `:вогонь`, `:fire`, `:feuer`, `:flag_ua`, `:woman technologist`. Search ignores case and accents, accepts small typos in words of at least four characters, and requires every word to match. Exact names rank ahead of broad keywords. Up to 60 results are shown; translations of the same emoji appear once. Enter copies the full Unicode sequence.

By default languages come from the system's locale preferences and **all configured keyboard layouts**, including per-device Hyprland overrides. A keyboard configured with `us,ua,de` enables English, Ukrainian and German simultaneously, regardless of its active layout. English is always retained for standard shortcodes. Labels use the system language if selected, otherwise the first selected language. XKB country identifiers are mapped to languages (for example `ua` to `uk`); layout variants such as Dvorak do not add a language. For multilingual country layouts or languages you know but do not type, use an explicit override.

Optional settings live in `$XDG_CONFIG_HOME/pentad/spotlight.json`, normally `~/.config/pentad/spotlight.json`:

```json
{
  "emoji": {
    "languages": ["uk", "en", "de"]
  }
}
```

Set `languages` to `"auto"` to restore detection, or omit the file. Settings and keyboard metadata refresh on the next emoji query after the five-second cache expires, without restarting the shell. Missing Hyprland falls back to system locales and English. Invalid settings emit a warning and use automatic selection.

Supported languages: `bn`, `da`, `de`, `en`, `en-gb`, `es`, `es-mx`, `et`, `fi`, `fr`, `hi`, `hu`, `it`, `ja`, `ko`, `lt`, `ms`, `nb`, `nl`, `pl`, `pt`, `ru`, `sv`, `th`, `uk`, `vi`, `zh`, `zh-hant`. Regional locale codes fall back to their supported parent language; Traditional Chinese regions use `zh-hant`.

Dictionaries are compressed inside the shell bundle; only selected languages are decoded/indexed on first emoji search. This is word/keyword matching, not AI interpretation of arbitrary sentences. Sources and licenses: [emoji data](../third-party/emoji.md).
