# Localization

OpenJoystickDriver uses native Foundation localization resources shared by the
menu-bar app and `OpenJoystickDriverKit`. The app follows the user's macOS
preferred-language order; there is no separate in-app language picker.

## Source of truth

- `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings`
  is the current source catalog for ordinary strings.
- `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.stringsdict`
  is the source catalog for plural strings.
- Each locale is a sibling `<locale>.lproj/` directory containing
  `Localizable.strings` and `Localizable.stringsdict`.
- `Package.swift` declares `en-US` as the package's default localization and
  processes the Kit resources. The app target copies its resource directory;
  `scripts/build-tools/bundles.sh` mirrors the Kit locale directories into the
  final app bundle so both targets use the same catalog.

`OpenJoystickDriverKit.Localization` resolves a locale and falls back to the
`en-US` resource when a selected locale is incomplete. AppKit, SwiftUI, and
accessibility text use the app-side `OJDLocalized` bridge rather than restoring
old daemon-era or hard-coded localization paths.

## Catalog status

The current catalog packages ordinary keys and five native plural entries across
83 `.lproj` bundles (including `C` and `en-US`). GUI and CLI human-facing product
copy resolve through `OJDLocalized` / `CLILocalized` against this catalog.
`et-EE` remains the first reviewed non-English translation for the prior key set;
newly added CLI/GUI keys currently carry English source text there pending
Estonian review. Other locale files intentionally contain the current English
source copy as an explicit fallback while human translations are added; do not
describe them as completed translations or restore the removed legacy catalogs.

## Adding or reviewing a translation

1. Copy the current key shape from the two files under
   `Resources/Localization/` into the target `<locale>.lproj/` pair.
2. Translate values, including every plural category required by the
   `.stringsdict` entry. Keep keys unchanged.
3. Preserve placeholder signatures (`%@`, `%d`, and `%#@count@`) and the meaning
   of technical values such as controller names, VID/PID values, paths, and
   accessibility descriptions. Do not localize identifiers supplied at runtime.
4. Prefer complete, natural sentences and one key per semantic label or
   message. Keep menu labels concise, use sentence case, and retain an ellipsis
   when an action opens another UI surface.
5. For right-to-left locales, review mixed-direction text containing controller
   names, identifiers, paths, and punctuation before marking the locale ready.
6. Add or update only the current catalog files. Do not bring back translations
   or keys from the retired localization system.

The resolver selects the best packaged locale using `Locale.preferredLanguages`.
A translation can therefore be exercised without changing source code by
running the app with that language first in the macOS language preference order.

## Verification

Run the checks relevant to the change from the repository root. The Xcode
selection below matches the supported local toolchain used for the macOS
runtime checks:

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
swift test
swift test --filter OpenJoystickDriverKitTests.LocalizationTests
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd check scripts
./scripts/ojd check swift-structure
./scripts/ojd check driverkit
./scripts/ojd lint
git diff --check
```

The localization tests verify that every packaged locale has the same current
keys, placeholder signatures, and plural shape, and that incomplete locales
fall back to the English source resource. A signed development build currently
compiles to 100% but can still stop during external provisioning validation
when Apple's GUI profile contains the obsolete extra
`com.openjoystickdriver.daemon` DriverKit value; do not change the host
entitlement allowlist locally to work around that Apple-side issue.
