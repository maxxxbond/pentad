# Spotlight

Spotlight opens through Pentad's global shortcuts, not a CLI command: `pentad:search` toggles it and `pentad:search-release` opens it on a bare Super tap.

Hyprland traditional configuration:

```ini
bind = SUPER, SPACE, global, pentad:search
```

For Lua configuration, load `quickshell/defaults/hyprland-quickshell.lua`, which binds Spotlight to `SUPER + Space`, preserves the default bare-Super action and includes workspace-hold bindings. Spotlight opening requests first close all widget menus and drawers.

Search prefixes: `= 24 * 7`, `:fire`, `cb token`, `? arch hyprland`. Ordinary text searches applications and adds DuckDuckGo. The apps button or ↓ with an empty field opens pinned, recent and installed applications.

The launcher is a compact 600px dock centered at the top of the active monitor, with width constrained on narrower outputs. Its 56px search bar stays visible while idle; a detached, single-column results surface expands below it. The list scrolls within 348px. The three mode buttons select applications, clipboard and emoji. Surfaces use Pentad theme tokens, Geist and continuous 16px corners without outlines. The workspace overview remains a separate feature.

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
