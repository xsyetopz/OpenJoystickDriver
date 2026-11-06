# Localization

One Foundation catalog in `OpenJoystickDriverKit` holds every GUI and CLI string. macOS preferred-language order picks the locale; there is no in-app switcher. Put a language first in macOS to try it.

## Files

- Source catalog: `Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings` and `.stringsdict`. `C.lproj` copies it and is not translated.
- Shipped locales: `Sources/OpenJoystickDriverKit/Resources/<locale>.lproj/`, the 22 bundles that `crowdin.yml` maps. Ship only languages that macOS itself offers.
- Plural categories per language: `Resources/Localization/PluralCategories.json`.

`Package.swift` defaults to `en-US`, `Scripts/Build/bundles.sh` copies Kit locales into the app, and Kit `Localization` falls back to `en-US`. App code calls `OJDLocalized`, CLI code `CLILocalized`.

English text lives only in the `en-US` catalog. A call site passes a key and nothing else (no `fallback:` or `defaultValue:`), so a key missing from `en-US` renders as the raw key. Add a key to `en-US` and every other locale before you use it.

## Checks

`python3 Scripts/Quality/check_localization_keys.py` fails on every key that breaks a rule below, and on a literal key (or the literal prefix of a dynamic key such as `"error.\(rawValue).message"`) passed to `OJDLocalized`, `CLILocalized`, `Localization` or `LocalizedStringResource` that `en-US` lacks. It lists keys held in variables or helper parameters as `key not scanned`. `swift test --filter OpenJoystickDriverKitTests.LocalizationTests` checks the bundles. Passing them is not a review: see [Meaning](#meaning).

## Key Rules

- Namespace: a key starts with `term.`, `action.`, `status.`, `ui.<area>.`, `ui.menu.`, `ui.extra.`, `ui.settings.<pane>.`, `a11y.`, `cli.<group>.<command>.`, `error.<code>.`, `notify.` or `platform.<os>.`. Segments are lowerCamelCase; only an error code such as `E1001` is capitalized.
- Operating system words (`DriverKit`, `macOS`, `Mac`, `Apple`, `System Settings`, `Login Items`, `Finder`, `IOKit`, `systemextensionsctl`, `launchd`, `Xcode`, `Input Monitoring`, `Privacy & Security`, `Dock`, `Terminal`, `TCC`, `codesign`, and `Accessibility` as a permission or pane) appear in an English value only under `platform.<os>.`. A neutral key carries neutral wording.
- Specifiers: a value with more than one specifier numbers each (`%1$@ of %2$@`) so a translation can reorder them.
- Plurals: a key that takes a count (`%#@name@`, or an integer specifier such as `%d` or `%1$lld` in `en-US`) has a `.stringsdict` entry in every bundle with at least the forms `PluralCategories.json` gives that language. An integer specifier that is not a count is listed in the checker's `NOT_A_COUNT` with the reason; an entry whose key is gone or has a `.stringsdict` entry fails.
- Comments: every `en-US` key has exactly one translator comment directly above it (`/* ... */` in `.strings`, `<!-- ... -->` in `.stringsdict`), because the translator tool reads only the nearest one. It says where the text appears and names each numbered specifier by position (`%1$@`), or contains `%` for one unnumbered specifier. Every other bundle has exactly the `en-US` keys, each with the `en-US` comment character for character; a comment changes in `en-US` first and is copied in the same change. Plural forms no language-aware reviewer has confirmed say so in that bundle's `.stringsdict` comment.

## Crowdin

`crowdin.yml` takes `en-US.lproj/*.strings` and `*.stringsdict` as sources and writes `%osx_locale%.lproj/%original_file_name%`. Credentials come from `CROWDIN_PROJECT_ID` and `CROWDIN_PERSONAL_TOKEN`.

1. Change `en-US` (key, value and comment) and run the checker.
2. Translators fill each locale in Crowdin.
3. Download the translations into the `<locale>.lproj` folders and review them against [Meaning](#meaning) and [Punctuation](#punctuation) before the commit.

## Translate

1. Copy the `en-US` key shape and comments into the target `.lproj` pair.
2. Translate values. Keep keys, placeholders (`%@`, `%1$@`, `%d`, `%#@count@`) and runtime identifiers (names, VID/PID, paths).
3. One key per label. Follow Apple's capitalization and verb form for the language. Use the native ellipsis only when the command needs more input before it completes (Apple's menu rule); an item that only opens a window or submenu has none.
4. Right-to-left languages: check mixed-direction names and paths.

Capability messages describe the controller or active protocol, not a permanent profile error. Compact symbol actions still need localized text for tooltips, accessibility labels and older systems.

## Punctuation

- English source: ASCII `...` and `'`.
- Translations: native `…`, quotes (`„…“`, `«…»`, `「…」`), and `→` for arrows. `pt-BR` and `es-MX` quote with `“…”`; `es-ES` keeps `«…»`.
- French: NBSP before `:` and inside `« »`. `fr-FR` puts a narrow NBSP (U+202F) before `; ? !`; `fr-CA` puts no space there.
- No ASCII `"` inside a `.strings` value. Numeric ranges stay `0...255`.

## Meaning

A value is wrong when it reads well but says something else. Every non-English locale began as a machine translation. Whoever adds or changes a value, person or agent, reads it back against `en-US` and its call site in `Sources/` and fixes what fails before the commit; native speakers review on top when they can.

- Translate the sense the app uses: "Disabled" means turned off; "Pitch", "Yaw" and "Roll" are rotation axes; "Motion" is the motion sensor, "Trigger" the shoulder trigger, "Escape" the key name.
- A label stays a label of the same part of speech: a noun stays a noun, an action button a verb, and a one- or two-word label never becomes a sentence, a reply, or a line such as `- Yes.`.
- Keys with different English get different values; two keys share a value only when their `en-US` values match.
- One term per concept in a file: controller, profile, mapping, service, extension, pairing. Keep a diagnose "check" distinct from the controller device.
- For a standard macOS term (menu items, keys, common buttons), use the term Apple's macOS glossary uses in that language when it has the same sense.
- Leave English only for product names, CLI tokens and option values, identifiers, and loanwords macOS itself uses in that language.
