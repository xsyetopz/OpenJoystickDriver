# Building From Source

Run everything through `just`. `just` lists the recipes.

## Prerequisites

| Need | Detail |
| --- | --- |
| Xcode | Launched once, for the macOS SDK and `xcodebuild`. `Package.swift`: swift-tools-version:6.4.0, macOS 12 deployment floor. CI: Xcode 27.0, xcode-27 runner. Without Xcode, see [Building Without Xcode](#building-without-xcode). |
| Swift toolchain | With Xcode, Xcode's, at least `.swift-version` (6.4.0, the oldest that builds for macOS 12). `Scripts/Platform/environment.sh` wraps every Swift command: it puts `$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin` first on `PATH` and stops when that `swift` is older. Without Xcode, a swift.org toolchain that swiftly installs; from 6.0.1 its runtime libraries target macOS 13, so linking for the macOS 12 floor prints linker warnings. |
| Homebrew | Install `just` first. `just setup` installs the pinned Swift toolchain (when swiftly is present), swiftlint, ruff, and shellcheck (when missing), and sets the Git hooks path. |
| Python 3 | `just schema-env` creates the schema-validation environment. |

Full Xcode, not only the Command Line Tools: check-profiles, check-schemas, driverkit-check, catalog-regenerate, errors-regenerate, diagnose-record, test-parsers-macos14, build-dext, and every release recipe. The first four build OJDRepositoryTool, the only validator of controller records, protocol descriptions, profiles, and personas; it also prints Swift-owned constants such as apiVersion and the `ojd` exit statuses. `build-dev`, `install-dev`, and `install-fast-dev` also run without Xcode; see [Building Without Xcode](#building-without-xcode).

Clone and set up:

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
just setup
```

## What You Can Do With Which Apple Assets

| Assets | Works | Does not work |
| --- | --- | --- |
| None | `swift build`, `swift test`; `just check-profiles`, `check-schemas`, `driverkit-check`; `just catalog-regenerate --check`; `just driverkit-generate`; `just test-parsers-macos14`; `just diagnose-record <json> --validate-only`; the checks in [`CLAUDE.md`](../../CLAUDE.md) | Any `build` route, any install, live USB probes through the DEXT |
| Apple Development identity and the two development profiles | `just build-dev` (signed app bundle, no DEXT); `build-dext` (DriverKit extension embedded into the app in `.build/`); `install-dev` (full rebuild and install); `install-fast-dev` (app-only rebuild, keeps the installed system extension) | `package-tester` and `release-*` recipes |
| Developer ID identity, Developer ID profiles, and notarization credentials | `build-release`, `install-release`, `package-tester`, `release-package`, `release-local-install` | Nothing more; these are maintainer routes |

| Note | Detail |
| --- | --- |
| Development signing | build-dev, build-dext, install-dev, install-fast-dev need `.env.dev`, both profiles, and matching Keychain identities. Run `just signing-install-profiles` and `just signing-configure`. |
| Ad-hoc signing | `build-dext` stops with "DriverKit extensions cannot use ad-hoc signing" when `CODESIGN_IDENTITY` is unset or `-`. |
| Host entitlement | The host app needs `com.apple.developer.hid.virtual.device`; the build rejects a host profile without it. The development profile's device list must include your Mac, or macOS ignores the entitlement at run time and virtual device creation fails. See [Signing](signing.md). |
| DEXT | `com.openjoystickdriver.XboxUSBDevice` carries only `com.apple.developer.driverkit` and the Apple-issued restricted USB entitlement for fixed Microsoft product IDs; the build rejects a DEXT profile without that exact grant. The app publishes virtual gamepads. |
| No userclient-access | A development host profile without that grant for the DEXT builds the app without it. USB work runs through IOUSBHost; `--validate-only` validates records. |
| install-fast-dev | Needs an earlier install-dev; stops when `/Applications/OpenJoystickDriver.app` is missing. |
| DriverKit change | A full install can need a reboot. Iterate with install-fast-dev. |

See [Environment files](environment.md) and [Signing](signing.md) for setup, [Create a tester build](tester-builds.md) for tester DMGs, and [Release reconciliation](releases.md) for releases.

## Everyday Loop

```bash
swift test
just check-profiles
just install-fast-dev      # needs Apple Development signing
```

`just verify` runs the complete validation CI repeats.

## Building Without Xcode

With only the Command Line Tools, or with `DEVELOPER_DIR=/Library/Developer/CommandLineTools` on a Mac that has Xcode, `just build-dev`, `install-dev`, and `install-fast-dev` build the app with SwiftPM, for editors such as VS Code. Install [swiftly](https://www.swift.org/install/macos/), then run `just setup`, which installs the `.swift-version` toolchain.

| Part | Without Xcode |
| --- | --- |
| Swift | The swift.org toolchain that swiftly installs. The Command Line Tools' own `swift` stops with an error: their macOS 27 SDK declares `@State` as a macro whose plugin ships only with Xcode, and their macOS 26 SDK carries a standard library interface that strict memory safety rejects. |
| SDK | The newest Command Line Tools SDK whose SwiftUI macros the toolchain can expand, the macOS 26 SDK on Command Line Tools 27. The build prints which SDK it uses. |
| App bundle | `Scripts/Build/bundles.sh` assembles `.build/swiftpm-app/OpenJoystickDriver.app` in the layout an Xcode build has, then signs it the same way. |
| Xbox USB driver | Left out, because the DriverKit SDK ships only with Xcode. `install-dev` retires an installed driver. |
| Shortcuts | The app has no `Metadata.appintents`, which only Xcode extracts, so Shortcuts lists none of its actions. |
| Release builds | `build-release` stops: a release needs the driver and the App Intents metadata. |
| Tests | `just test` and `just typecheck` build the package for macOS 13, the lowest macOS with Swift Testing's `.timeLimit`, and skip the Xcode schemes, which need `xcodebuild`. |

## Building in Xcode

Build or run the `OpenJoystickDriverApp` scheme of `OpenJoystickDriver.xcodeproj`. Build recipes run it through `xcodebuild`: only an Xcode build extracts the App Intents metadata Shortcuts reads.

An Xcode build is signed to run locally, without the restricted entitlements in `Sources/OpenJoystickDriver/App/Host.entitlements`, so it cannot create the virtual gamepad (no `com.apple.developer.hid.virtual.device`). Test the signed app with `just install-fast-dev`.

The app target passes `-package-name $(OJD_SWIFT_PACKAGE_NAME)` to see the package's `package` symbols. SwiftPM names the package after the checkout directory, lowercased and mangled to a C99 identifier; the default `openjoystickdriver` fits only a checkout named `OpenJoystickDriver`. Build recipes pass the derived name. For a direct `xcodebuild` or an Xcode build in a differently named clone or worktree, set `OJD_SWIFT_PACKAGE_NAME`, such as `my_clone`.

With a swift.org toolchain selected through `TOOLCHAINS`, `xcodebuild` cannot resolve the package. Build recipes unset `TOOLCHAINS`; in a shell, run `env -u TOOLCHAINS xcodebuild`.

## Git Hooks and Commits

`just setup` points core.hooksPath at `.githooks/`; the pre-commit hook runs `just pre-commit`. `just check-whitespace` reports whitespace errors in the working tree and in commits ahead of `origin/main`. Run `just verify` before a pull request.

Commit messages: Conventional Commits, `type(scope): subject`, lowercase subject. Header and each body line: at most 100 characters. Merge commits: `Merge <branch> into <target>`.

## Screenshots

`just shots-capture` captures the installed app. Options: `--all`, `--area <name>`, `--settings-pane <name>`, `--menus`. It writes one PNG per sidebar area, Settings tab, and menu to the git-ignored `.ojd-shots/<timestamp>/` (counter suffix for runs in the same second), silently, at the display's backing scale (2x on Retina). Commit a capture only when the README or wiki uses it.

Each PNG holds one window alone over transparency (screencapture -l), without shadow, desktop, or other apps, so it holds no private content. Translucent materials such as Liquid Glass show no backdrop.

Before each capture the route activates the app, raises the window (AXFrontmost, NSRunningApplication, AXRaise), and reads the window list every 0.25 s until nothing covers it, for at most `--front-timeout <seconds>` (finite, above zero, default 5). The Dock and menu bar do not count as covering. A window that stays covered fails with "covered by windows of", the app names, and "after `<seconds>` s of bringing the app forward (--front-timeout)".

--menus (in --all) opens each main menu after the Apple menu, the Activate Profile submenu, and the status item menu (AXExtrasMenuBar). It presses them (AXPress) and finds them by AXIdentifier from the app's menu model ids: `menu.<section>` for a menu bar item, the item id for a menu item, the entry id for the status item. It works in every UI language.

Per menu, the route waits until exactly the menu windows (layer 101) it opened are on screen, with bounds and alpha unchanged over two reads, and captures the last opened menu alone: the submenu for menu-profile-activate-profile.png, the only menu for the others. It closes each open menu with one Escape (a CGEvent through the HID event tap, only while a menu of the app is open).

Output: `menu-<section>.png` (menu-app.png to menu-help.png), menu-profile-activate-profile.png, menu-status-item.png. Failures, each by name:

| Failure | Cause |
| --- | --- |
| App menu open | A menu of the app is open before a capture opens one |
| Covered | A window covers a menu |
| Disabled item | A disabled menu item is on the path |
| Window count | A menu does not open as many windows within 5 s |
| Stuck menu | A menu stays open after four Escape presses |

The route restores the open windows, sidebar area, and Settings tab it recorded, and closes only windows it opened. Restore failures go to stderr and set exit status 2. The sidebar and Settings scripts click English labels: --area, --settings-pane, and --all need English first in the app UI languages, otherwise the capture refuses and names --menus.

The route drives the app through the Accessibility API with `osascript -l JavaScript Scripts/GUI/ax.js`, not System Events. Its only keystroke is the menu-closing Escape. Needs:

| Need | Failure |
| --- | --- |
| Exactly one running `/Applications/OpenJoystickDriver.app` | None: "OpenJoystickDriver is not running"; more: names the pids |
| Logged-in, unlocked GUI session | "the screen is locked" or "not on the console" |
| Accessibility for the host app that runs the command (Terminal, iTerm, or another; System Settings > Privacy & Security > Accessibility, called Device Control and Data Access on macOS 27) | See Accessibility errors |
| Screen Recording | None listed |

Accessibility errors:

| Error | Result |
| --- | --- |
| AXError -25211 (or an untrusted host app) | Stops with "Accessibility is not granted to the host app" |
| AXError -25204 | App does not answer yet, for example right after launch. Polls every 0.25 s for up to `--ready-timeout <seconds>` (finite, above zero, default 15), then stops naming the app, the timeout, and the last AXError |
| Any other non-zero AXError | Stops with "Accessibility call to OpenJoystickDriver failed ... although the host app is trusted"; asks for no permission |

Later failed reads report the attribute and the AXError.
