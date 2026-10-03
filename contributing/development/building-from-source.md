# Building From Source

Everything is driven through `./Scripts/ojd`. Run `./Scripts/ojd help` for the route list.

## Prerequisites

- macOS with Xcode installed and launched once. `Package.swift` declares `swift-tools-version:6.3.0` and a macOS 12 deployment floor. CI pins Xcode 26.6 and Swift 6.3.3.
- Homebrew, for the helper tools. In an interactive terminal, each `./Scripts/ojd` route offers to install only the formulas it is missing. `./Scripts/ojd setup` installs `just`, `lefthook`, `ruff`, `pyright`, `shellcheck`, and `swiftlint`, plus the Git hooks.
- Python 3. The dispatcher creates its own schema-validation environment.

Most routes that build or run Swift code require full Xcode, not only the Command Line Tools. The route requirements in `Scripts/Platform/capability_requirements.py` list full Xcode for `check schemas`, `check driverkit`, `diagnose record`, `test parsers-macos14`, and every `build` and `release` route. When Xcode is missing, the route prints guidance and stops. Routes that only read or regenerate catalog data (`check profiles`, `catalog regenerate`) need Python alone. Whether a plain `swift build` or `swift test` works with only the Command Line Tools has not been verified.

Clone and set up:

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
./Scripts/ojd setup
```

## What You Can Do With Which Apple Assets

| Assets | Works | Does not work |
| --- | --- | --- |
| None | `swift build`, `swift test`; `./Scripts/ojd check profiles`, `check schemas`, `check driverkit`; `./Scripts/ojd catalog regenerate --check`; `./Scripts/ojd driverkit generate`; `./Scripts/ojd test parsers-macos14`; `./Scripts/ojd diagnose record <json> --validate-only`; the checks in [`CLAUDE.md`](../../CLAUDE.md) | Any `build` route, any install, live USB probes through the DEXT |
| Apple Development identity and the two development profiles | `./Scripts/ojd build dev` (signed app bundle, no DEXT); `build dext` (DriverKit extension embedded into the app in `.build/`); `build install dev` (full rebuild and install); `build install-fast dev` (app-only rebuild, keeps the installed system extension) | `package tester` and `release` routes |
| Developer ID identity, Developer ID profiles, and notarization credentials | `build release`, `build install release`, `package tester`, `release package`, `release install-local` | Nothing more; these are maintainer routes |

Notes on the rows:

- `build dev`, `build dext`, `build install dev`, and `build install-fast dev` require configured development signing (`.env.dev`, both profiles, and matching Keychain identities). Interactively, the dispatcher runs `signing configure` and `signing install-profiles` for you; in a non-interactive run it stops with "signing is not configured".
- The DEXT cannot be ad-hoc signed. `build dext` stops with "DriverKit extensions cannot use ad-hoc signing" when `CODESIGN_IDENTITY` is unset or `-`.
- The host app needs the `com.apple.developer.hid.virtual.device` entitlement. The build rejects a host profile that lacks it. The development profile's device list must also include your Mac, or macOS ignores the entitlement at run time and virtual device creation fails. See [Signing](signing.md).
- The DEXT carries the Apple-issued restricted USB entitlement for a fixed set of Microsoft product IDs only when its profile has that grant; otherwise the build signs factory-only (HID factory personality, no Xbox USB ownership). Without that grant, contributors can still develop everything that opens USB interfaces from the app through IOUSBHost, and validate records with `--validate-only`.
- `build install-fast dev` needs an earlier `build install dev`; it stops when `/Applications/OpenJoystickDriver.app` is missing.
- After a DriverKit change, a full install can require a reboot. Use `build install-fast dev` while iterating on the app.

Local configuration files are described in [Environment files](environment.md); asset setup is in [Signing](signing.md). Tester DMGs are in [Create a tester build](tester-builds.md), and releases in [Release reconciliation](releases.md).

## Everyday Loop

```bash
swift test
./Scripts/ojd check profiles
./Scripts/ojd build install-fast dev      # needs Apple Development signing
```

`just check` runs the complete validation that CI repeats. The full command list is in [`CLAUDE.md`](../../CLAUDE.md), and route details are in [`Scripts/README.md`](../../Scripts/README.md).

## Building in Xcode

`OpenJoystickDriver.xcodeproj` builds the app from the Swift package.
Open it in Xcode and build or run the `OpenJoystickDriverApp` scheme.
The `build` routes run the same scheme through `xcodebuild`, because only an Xcode build extracts the App Intents metadata that Shortcuts reads.

An Xcode build is signed to run locally, without the restricted entitlements in `Sources/OpenJoystickDriver/App/Host.entitlements`.
Without the `com.apple.developer.hid.virtual.device` entitlement, it cannot create the virtual gamepad.
Use `./Scripts/ojd build install-fast dev` to test the signed app.

When a swift.org toolchain is selected through `TOOLCHAINS`, `xcodebuild` cannot resolve the package.
The `build` routes unset `TOOLCHAINS`; in a shell, run `env -u TOOLCHAINS xcodebuild`.
