# Localization

Use this procedure to update one shipped locale without changing keys or runtime identifiers.

One Foundation catalog in `OpenJoystickDriverKit`. macOS preferred-language order picks the locale. No in-app switcher.

## Files

- `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings`
- `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.stringsdict`
- Shipped locales: `<locale>.lproj/Localizable.strings` and `.stringsdict`

`Package.swift` default is `en-US`. `Scripts/Build/bundles.sh` copies Kit locales into the app. Kit `Localization` falls back to `en-US`. App: `OJDLocalized`. CLI: `CLILocalized`.

English text lives only in the `en-US` catalog. Call sites pass a key and nothing else: there is no `fallback:` or `defaultValue:` argument, so a key missing from `en-US` renders as the raw key. Add the key to `en-US` and to every other locale and template before using it.

`python3 Scripts/Quality/check_localization_keys.py` fails when a literal key passed to `OJDLocalized`, `CLILocalized`, `Localization`, or `LocalizedStringResource` is missing from `en-US`. It checks a literal prefix of a dynamic key such as `"error.\(rawValue)"` against the catalog. It cannot check keys held in variables or passed through helper parameters; it lists them as `key not scanned`.

83 `.lproj` bundles. Five plurals. Every non-English locale, including Northern Sámi (`se-FI`, `se-NO`), has a fluent first-pass translation. English source catalogs are `en-US`, `C`, and `en-*`. `et-EE` is the reviewed start. Do not restore retired catalogs.

## Punctuation

- English source: ASCII `...` and `'`.
- Translations: native `…`, quotes (`„…“`, `«…»`, `「…」`), `→` for arrows.
- No ASCII `"` inside a `.strings` value.
- Numeric ranges stay `0...255`.

## Translate

1. Copy the template key shape into the target `.lproj` pair.
1. Translate values. Keep keys, placeholders (`%@`, `%d`, `%#@count@`), and runtime identifiers (names, VID/PID, paths).
1. One key per label. Sentence case. Native ellipsis when the action opens another surface.
1. RTL: check mixed-direction names and paths.

Capability messages describe the controller or active protocol, not a permanent profile error. Compact symbol actions still require localized text because that text is used for older-system fallbacks, tooltips, and accessibility labels.

Put the language first in macOS to try it.

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
swift test --filter OpenJoystickDriverKitTests.LocalizationTests
```
