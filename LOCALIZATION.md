# Localization

Use this procedure to update one shipped locale without changing keys or runtime identifiers.

One Foundation catalog in `OpenJoystickDriverKit`. macOS preferred-language order picks the locale. No in-app switcher.

## Files

- `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings`
- `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.stringsdict`
- Shipped locales: `<locale>.lproj/Localizable.strings` and `.stringsdict`

`Package.swift` default is `en-US`. `Scripts/Build/bundles.sh` copies Kit locales into the app. Kit `Localization` falls back to `en-US`. App: `OJDLocalized`. CLI: `CLILocalized`.

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
