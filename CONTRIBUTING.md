# Contributing

## Setup

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
./Scripts/ojd setup
just check
```

Run the needed command and follow its native prompts. The dispatcher automatically creates repository-local Python environments. In interactive terminals, it offers to install only that command's missing Homebrew formulas. Homebrew, Xcode, Apple-issued assets, credentials, system permissions, publication, destructive writes, and hardware actions retain their official or explicit authorization flows. CI never prompts or installs host software.

The pre-commit hook runs fast structural checks against the exact staged snapshot. The pre-push hook checks the outgoing tree diff for whitespace errors without repeating lint, builds, tests, or network-backed catalog generation. Run `just check` before opening a pull request; CI repeats the complete validation.

Prerequisites and what works without Apple assets: `docs/development/building-from-source.md`. Signing: `docs/development/signing.md`. Releases and packaging: `docs/development/releases.md`. Script routes: `Scripts/README.md`. Dev install: `./Scripts/ojd build install dev`. Do not edit `.build/driverkit/generated/`. SwifterKit comes from the `Package.resolved` remote; `OJD_USE_LOCAL_SWIFTERKIT=1` builds the sibling `../SwifterKit` working tree instead, which CI and release builds reject.

Create a private, notarized DMG with the [local tester-build guide](docs/development/tester-builds.md).

```bash
./Scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
./Scripts/ojd diagnose backends --seconds 5
ojd diagnose --bundle support-report.json
```

`--validate-only` needs no Apple Developer membership. A live USB probe may need the signed app and DEXT. Capture notes: `docs/testing/controller-record.md`. Review product names before attaching a report.

Open tasks: [issues](https://github.com/xsyetopz/OpenJoystickDriver/issues).

## Adding a Controller

1. `system_profiler SPUSBDataType`. `bDeviceClass` `0xff` is vendor-specific (often GIP); `0x03` is HID.
1. Do not hand-edit generated records. Update the pinned importer, or add `Resources/ControllerOverrides/<vid>/<vid>-<pid>.json`. Decimal JSON, no display names, no protocol defaults. Then:

   ```bash
   ./Scripts/ojd catalog regenerate --write
   ./Scripts/ojd catalog regenerate --check
   ```

   Source rules: `docs/development/xpad-import.md`.
1. New protocol only: driver in `Sources/OpenJoystickDriverKit/Protocol/Drivers/`, `PhysicalProtocolDriver`, tests under `Tests/OpenJoystickDriverKitTests/`.
1. Check:

   ```bash
   ./Scripts/ojd check profiles
   swiftlint lint --no-cache --strict
   swift test
   ```

## Code Rules

Toolchain: `.swift-version` and `Package.swift`. Warnings are errors. Justify `nonisolated(unsafe)` on the same line.

Style: `.swift-format` and `.swiftlint.yml`. Do not copy them here. Do not add SwiftLint rules that fight the formatter. Run `swift-format` and SwiftLint directly, with SwiftLint `--no-cache --strict`. No `// swiftlint:disable` except an `@objc` callback that cannot comply, with the reason on that line.

GUI and CLI copy: `LOCALIZATION.md`. Tests check codes, routes, identifiers, paths, and structure — not help text, and not `.swift` source via `String(contentsOf:)`.

- Decimal integers in JSON. No hex.
- Keep the existing `print` diagnostics. No new logging stack.
- Parser errors stay local: log and skip.
- Deployment floor: macOS 12. Future iOS and iPadOS companion apps: iOS 15 and iPadOS 15.
- Kit has no SwifterKit. USB adapter: `Sources/OpenJoystickDriverUSB/`. Generator: `Sources/DriverKitGenerator/` and `Scripts/Build/driverkit.sh`.
- No manual DriverKit build or post-generation patch. `./Scripts/ojd check driverkit`.
- Host `com.apple.developer.driverkit.userclient-access` must be exactly `com.openjoystickdriver.XboxUSBDevice`.
- `com.openjoystickdriver.XboxUSBDevice` is the only DEXT. It has one personality, `XboxUSB` (Microsoft GIP USB interfaces), and only the `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb` entitlements. `./Scripts/ojd driverkit generate [path]` generates it. The app and service publish virtual gamepads through `IOHIDUserDevice`, which needs `com.apple.developer.hid.virtual.device` on the app profile; that entitlement never goes in the DEXT.

## Pull Requests

Submit one logical change. List checks run and whether you tested on your own hardware.

Layout: `docs/development/source-topology.md`. RPC payloads: `Sources/OpenJoystickDriverKit/ApplicationService/`. CLI help: the `CommandConfiguration` of each command under `Sources/OpenJoystickDriverCLI/Commands/`, with its text in the localization strings. `OpenJoystickDriverHIDTool` is internal.
