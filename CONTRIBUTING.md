# Contributing

## Setup

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
swift build
swift test
```

Signing, DriverKit, and packaging: `scripts/README.md`. Dev install:
`./scripts/ojd build install dev`. Do not edit `.build/driverkit/generated/`.
SwifterKit comes from `Package.resolved`. `OJD_USE_LOCAL_SWIFTERKIT=1` is
local-only.

```bash
./scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
./scripts/ojd diagnose backends --seconds 5
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless diagnose report
```

`--validate-only` needs no Apple Developer membership. A live USB probe may
need the signed app and DEXT. Capture notes:
`docs/testing/controller-record.md`. Review product names before attaching a
report.

Open tasks: [issues](https://github.com/xsyetopz/OpenJoystickDriver/issues).

## Adding a controller

1. `system_profiler SPUSBDataType`. `bDeviceClass` `0xff` is vendor-specific
   (often GIP); `0x03` is HID.
2. Do not hand-edit generated records. Update the pinned importer, or add
   `Resources/ControllerOverrides/<vid>/<vid>-<pid>.json`. Decimal JSON, no
   display names, no protocol defaults. Then:

   ```bash
   ./scripts/ojd catalog regenerate --write
   ./scripts/ojd catalog regenerate --check
   ```

   Source rules: `docs/development/xpad-import.md`.
3. New protocol only: parser in
   `Sources/OpenJoystickDriverKit/Protocol/Parsers/`, `InputParser`, tests
   under `Tests/OpenJoystickDriverKitTests/`.
4. Check:

   ```bash
   ./scripts/ojd check profiles
   ./scripts/ojd lint
   swift test
   ```

## Code rules

Toolchain: `.swift-version` and `Package.swift`. Warnings are errors. Justify
`nonisolated(unsafe)` on the same line.

Style: `.swift-format` and `.swiftlint.yml`. Do not copy them here. Do not add
SwiftLint rules that fight the formatter. `./scripts/ojd lint` is SwiftLint
`--strict` on tracked Swift. No `// swiftlint:disable` except an `@objc`
callback that cannot comply, with the reason on that line.

GUI and CLI copy: `LOCALIZATION.md`. Tests check codes, routes, identifiers,
paths, and structure — not help text, and not `.swift` source via
`String(contentsOf:)`.

- Decimal integers in JSON. No hex.
- Keep the existing `print` diagnostics. No new logging stack.
- Parser errors stay local: log and skip.
- Deployment floor: macOS 10.15.
- Kit has no SwifterKit. USB adapter:
  `Sources/OpenJoystickDriverUSB/`. Generator:
  `Sources/DriverKitGenerator/` and `scripts/build-tools/driverkit.sh`.
- No manual DriverKit build or post-generation patch.
  `./scripts/ojd check driverkit`.
- Host `com.apple.developer.driverkit.userclient-access` lists only
  `com.openjoystickdriver.XboxUSBDevice`.

## Pull requests

One logical change. Say whether you tested on hardware you own. Say what you
ran.

Layout: `docs/development/source-topology.md`. RPC payloads:
`Sources/OpenJoystickDriverKit/ApplicationService/`. CLI help:
`Sources/OpenJoystickDriver/CLI/Catalog/CommandCatalog.swift`.
`OpenJoystickDriverHIDTool` is internal.
