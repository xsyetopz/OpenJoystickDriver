# Building From Source

Everything is driven through `./Scripts/ojd`. Run `./Scripts/ojd help` for the route list.

## Prerequisites

- macOS with Xcode installed and launched once, for the macOS SDK and `xcodebuild`. `Package.swift` declares `swift-tools-version:6.4.0` and a macOS 12 deployment floor.
- Swift comes from Xcode's own toolchain, at least the version `.swift-version` names (6.4.0, the oldest that builds for macOS 12). Every Swift command of the repository goes through `Scripts/Platform/environment.sh`, which puts `$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin` first on `PATH` and stops when that `swift` is older, so one compiler writes `.build`. A swift.org toolchain does not fit: from 6.0.1 on, its runtime libraries are built for macOS 13, so linking for the macOS 12 floor prints a linker warning, and a warning fails the build. CI uses Xcode 27.0 on the `xcode-27` runner.
- Homebrew, for the helper tools. In an interactive terminal, each `./Scripts/ojd` route offers to install only the formulas it is missing. `./Scripts/ojd setup` installs `just`, `bun`, `ruff`, `shellcheck`, and `swiftlint`, plus the Git hooks and the pinned packages of `package.json`: Biome, Pyright, markdownlint-cli2, husky and commitlint, all installed through `bun install` and run with `bun run`, so no Node is needed.
- Python 3. The dispatcher creates its own schema-validation environment.

Most routes that build or run Swift code require full Xcode, not only the Command Line Tools. The route requirements in `Scripts/Platform/capability_requirements.py` list full Xcode for `check profiles`, `check schemas`, `check driverkit`, `catalog regenerate`, `catalog xpad`, `errors regenerate`, `diagnose record`, `test parsers-macos14`, and every `build` and `release` route. `check profiles`, `check schemas`, `catalog regenerate`, `catalog xpad` and `errors regenerate` build `OJDRepositoryTool`, the Swift executable that is the only validator of controller records, protocol descriptions, profiles and personas and that prints the constants Swift owns, such as the `apiVersion` and the exit statuses of `ojd`. When Xcode is missing, the route prints guidance and stops. Whether a plain `swift build` or `swift test` works with only the Command Line Tools has not been verified.

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
- The single DEXT, `com.openjoystickdriver.XboxUSBDevice`, carries only `com.apple.developer.driverkit` and the Apple-issued restricted USB entitlement for a fixed set of Microsoft product IDs, and the build rejects a DEXT profile without that exact grant. The app, not the DEXT, publishes virtual gamepads. A development host profile without a `userclient-access` grant for `com.openjoystickdriver.XboxUSBDevice` builds the app without the DEXT. Without the DEXT, contributors can still develop everything that opens USB interfaces from the app through IOUSBHost, and validate records with `--validate-only`.
- `build install-fast dev` needs an earlier `build install dev`; it stops when `/Applications/OpenJoystickDriver.app` is missing.
- After a DriverKit change, a full install can require a reboot. Use `build install-fast dev` while iterating on the app.

Local configuration files are described in [Environment files](environment.md); asset setup is in [Signing](signing.md). Tester DMGs are in [Create a tester build](tester-builds.md), and releases in [Release reconciliation](releases.md).

## Everyday Loop

```bash
swift test
./Scripts/ojd check profiles
./Scripts/ojd build install-fast dev      # needs Apple Development signing
```

`just check` runs the complete validation that CI repeats. The `justfile` lists the commands, and `./Scripts/ojd --help` lists the repository routes.

## Building in Xcode

`OpenJoystickDriver.xcodeproj` builds the app from the Swift package.
Open it in Xcode and build or run the `OpenJoystickDriverApp` scheme.
The `build` routes run the same scheme through `xcodebuild`, because only an Xcode build extracts the App Intents metadata that Shortcuts reads.

An Xcode build is signed to run locally, without the restricted entitlements in `Sources/OpenJoystickDriver/App/Host.entitlements`.
Without the `com.apple.developer.hid.virtual.device` entitlement, it cannot create the virtual gamepad.
Use `./Scripts/ojd build install-fast dev` to test the signed app.

When a swift.org toolchain is selected through `TOOLCHAINS`, `xcodebuild` cannot resolve the package.
The `build` routes unset `TOOLCHAINS`; in a shell, run `env -u TOOLCHAINS xcodebuild`.

## Git Hooks and Commits

Git hooks come from husky, installed by `bun install` (run through `./Scripts/ojd setup` or `./Scripts/ojd hooks install`), which points `core.hooksPath` at the main checkout's `.husky/_` by absolute path so every worktree runs the hooks. Run the install in the main checkout first; `./Scripts/ojd hooks validate` reports a relative or missing hooks path. The pre-commit hook formats the staged `*.json` and `*.jsonc` files with the pinned Biome (`@biomejs/biome` in `package.json`, run by `bun run` from `node_modules/.bin/biome` of the checkout being committed, else of the main checkout, which covers linked worktrees without their own `bun install`; its version must equal the pin, and there is no fallback to a Biome on `PATH`; `biome.json` holds the settings). The pre-push hook checks the outgoing tree diff for whitespace errors without repeating lint, builds, tests, or network-backed catalog generation. Run `just check` before opening a pull request; CI repeats the complete validation.

Commit messages must follow Conventional Commits, enforced by commitlint with `@commitlint/config-conventional` in the `commit-msg` hook and in CI on pull requests. Use `type(scope): subject` with a lowercase subject. The header and each body line must be at most 100 characters. Merge commits use `Merge <branch> into <target>`.

## Screenshots

Review screenshots of the installed app: `./Scripts/ojd shots capture --all` (or `--area <name>`, `--settings-pane <name>`, `--menus`) writes one PNG per sidebar area, Settings tab and menu to the git-ignored `.ojd-shots/<timestamp>/` (a counter suffix separates same-second runs), silently and at the display's backing scale (2x on Retina). Each PNG is the screen rectangle of the window (`screencapture -R`), so Liquid Glass and other translucent materials show what lies behind them as on screen; `screencapture -l` would draw the window alone over transparency, washed out over a checkerboard. The rectangle also shows any window in front, so before each capture the route activates the app and raises the window through the Accessibility API (`AXFrontmost`, `NSRunningApplication` and `AXRaise`), then reads the window list every 0.25 s until nothing covers the window, for at most `--front-timeout <seconds>` (a finite number above zero, default 5, named in `--help`), because no signal reports that another window has moved behind; a window that stays covered fails with "covered by windows of", the names of their apps and "after <seconds> s of bringing the app forward (--front-timeout)" (the Dock and the menu bar are not counted). `--menus` (included in `--all`) opens each main menu after the Apple menu, the Activate Profile submenu and the status item menu (`AXExtrasMenuBar`) with its Profiles > Activate submenu by pressing them (`AXPress`) through the Accessibility API. It finds them by AXIdentifier, which the app sets from its menu model ids (`menu.<section>` for a menu bar item, the item id for a menu item, the entry id in the status item), so it works in every UI language. It waits until exactly as many menu windows (layer 101) as it opened are on screen and unchanged in bounds and alpha over two reads, captures the union rectangle of those windows, so a parent menu and its open submenu share one image, makes every pixel outside the menu windows' bounds transparent (`OJDRepositoryTool mask-image`, built before the first menu opens), so no other app shows beside a submenu or around the status item menu, and closes the menu by posting Escape (a `CGEvent` through the HID event tap, only while a menu of the app is open), once per open menu. It writes `menu-<section>.png` (`menu-app.png` to `menu-help.png`), `menu-profile-activate-profile.png`, `menu-status-item.png` and `menu-status-item-profiles-activate.png`. A menu of the app that is open before a capture opens one, a menu that a window covers, a disabled menu item on the path, a menu that does not open as many windows within 5 s and a menu that stays open after four Escape presses each fail by name. It records the open windows, the sidebar area and the Settings tab, then restores them: it reselects the area and tab and closes only the windows it opened. Restore failures are printed to stderr and make the exit status 2. The sidebar and Settings scripts click English labels, so `--area`, `--settings-pane` and `--all` need English first in the app UI languages (the capture refuses otherwise and names `--menus` as the capture that needs no English). It drives the app through the Accessibility API with `osascript -l JavaScript Scripts/GUI/ax.js` (no System Events; the only keystroke is the Escape that closes a captured menu) and needs exactly one copy of `/Applications/OpenJoystickDriver.app` running (it stops with "OpenJoystickDriver is not running" when none runs, and names the pids when more than one does) in a logged-in, unlocked GUI session, Accessibility for the host app that runs the command (Terminal, iTerm or another; System Settings > Privacy & Security > Accessibility), and Screen Recording. After finding the app it reads the session state and stops at once with "the screen is locked" when the screen is locked, or "not on the console" when the login session is in the background, because macOS hides app windows from Accessibility and screen capture then. It then reads the app role through Accessibility. AXError -25211 (or an untrusted host app) stops at once with "Accessibility is not granted to the host app" and asks to allow the host app in System Settings. AXError -25204 means the app does not answer yet (for example right after launch), so the capture waits up to `--ready-timeout <seconds>` (a finite number above zero, default 15), polling every 0.25 s because no signal reports that the app answers Accessibility (finished launching does not imply it, and an AXObserver needs an element that answers), and then stops naming the app, the timeout and the last AXError. Any other non-zero AXError stops at once with "Accessibility call to OpenJoystickDriver failed ... although the host app is trusted" (the app may not be responding, or there is no logged-in GUI session) and asks for no permission. Later Accessibility reads that fail report the attribute and the AXError instead of an absent window or row. Commit a capture only when the README or wiki uses it.
