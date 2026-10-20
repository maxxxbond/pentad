# Emoji dictionaries

Pentad bundles offline localized labels/tags from [Emojibase](https://github.com/milesj/emojibase), package `emojibase-data` **17.0.0**, and English word associations from [Emojilib](https://github.com/muan/emojilib), package **4.0.3**. Emojibase's localized annotations derive from Unicode/CLDR. Both packages are MIT licensed; retained notices are `LICENSES/emoji-emojibase-MIT.txt` and `LICENSES/emoji-emojilib-MIT.txt`.

The synchronous pure JavaScript decompressor is [fflate](https://github.com/101arrowz/fflate) **0.8.2** (MIT), with its notice in `LICENSES/emoji-fflate-MIT.txt`. Its browser module's synchronous gzip decoder works without DOM, workers or Node. No upstream UI is embedded.

`pnpm run build:emoji-data` generates `src/features/spotlight/data/emoji.json` and `locales.json` from the pinned packages. It includes all 28 published locales, all 3,979 base/skin emoji sequences, English GitHub/Emojibase shortcodes and Emojilib associations. Parent tags are inherited by skin variants. Regional-indicator flags receive country-code aliases such as `flag_ua`. Unicode sequences, variation selectors and joiners are preserved.

Each locale is stored as gzip/base64 and decoded only when selected. Indexes merge translations by exact Unicode sequence. The dictionaries are compiled into the standalone shell bundle; no network or separately installed dictionary files are needed at runtime. Generated data can be reproduced from the lockfile and build script.
