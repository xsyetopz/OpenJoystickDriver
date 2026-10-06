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

18 `.lproj` bundles: `C`, `en-US`, `ar-SA`, `de-DE`, `es-ES`, `es-MX`, `fr-CA`, `fr-FR`, `hi-IN`, `it-IT`, `ja-JP`, `ko-KR`, `nl-NL`, `pt-BR`, `tr-TR`, `zh-CN`, `zh-HK`, `zh-TW`.
Five plurals.
Every non-English locale began as a machine translation and needs review against the rules in [Meaning](#meaning).
English source catalogs are `en-US` and `C`.
Ship only languages that macOS itself offers.
Do not restore retired catalogs.

## Punctuation

- English source: ASCII `...` and `'`.
- Translations: native `…`, quotes (`„…“`, `«…»`, `「…」`), `→` for arrows.
- No ASCII `"` inside a `.strings` value.
- Numeric ranges stay `0...255`.

## Meaning

A value is wrong when it reads well but says something else.
Read every value back against `en-US` before you ship it.

- Translate the sense the app uses, not the first dictionary sense.
  "Disabled" means turned off, not a person.
  "Pitch", "Yaw", and "Roll" are rotation axes.
  "Motion" is the motion sensor, "Trigger" is the shoulder trigger, and "Escape" is the key name.
- For a short label, read the call site in `Sources/` before you pick a word.
- A label stays a label.
  A one- or two-word English label never becomes a sentence, a reply, or a line with a leading dialogue dash such as `- Yes.`.
- Keys with different English get different values.
  Two keys share a value only when their `en-US` values match.
- Keep the part of speech: a noun label stays a noun, and an action button stays a verb.
- Use one term per concept in a file: controller, profile, mapping, service, extension, pairing.
  Keep a diagnose "check" distinct from the controller device.
- For a standard macOS term (menu items, keys, common buttons), use the term Apple's macOS glossary uses in that language when it has the same sense.
- Leave English only for product names, CLI tokens and option values, identifiers, and a loanword that macOS itself uses in that language.
- Do not ship unreviewed machine translation.

## Translate

1. Copy the template key shape into the target `.lproj` pair.
1. Translate values. Keep keys, placeholders (`%@`, `%d`, `%#@count@`), and runtime identifiers (names, VID/PID, paths).
1. One key per label. Follow Apple's capitalization and verb form for the language. Native ellipsis when the action opens another surface.
1. RTL: check mixed-direction names and paths.

Capability messages describe the controller or active protocol, not a permanent profile error. Compact symbol actions still require localized text because that text is used for older-system fallbacks, tooltips, and accessibility labels.

Put the language first in macOS to try it.

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
swift test --filter OpenJoystickDriverKitTests.LocalizationTests
```
