# Contributing

These rules apply to humans and AI agents alike.

## Setup

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
./Scripts/ojd setup
just check
```

In an interactive terminal, each `./Scripts/ojd` route offers to install the Homebrew formulas it is missing; `setup` installs `just`, `ruff`, `shellcheck`, `swiftlint` and the Git hooks. Xcode, Apple assets, credentials, permissions, publication, destructive writes and hardware actions keep their own authorization flows. CI never prompts or installs host software.

- Prerequisites, Git hooks, commit messages and screenshots: `docs/development/building-from-source.md`.
- Toolchain and environment variables: `docs/development/environment.md`.
- Signing: `docs/development/signing.md`. Releases: `docs/development/releases.md`. Tester DMG: `docs/development/tester-builds.md`.
- Layout and targets: `docs/development/source-topology.md`. Script routes: `./Scripts/ojd --help`.

Run `just check` before opening a pull request; CI repeats it.

## Adding a Controller

1. Run `system_profiler SPUSBDataType`. `bDeviceClass` `0xff` is vendor-specific (often GIP); `0x03` is HID.
2. Do not hand-edit generated records. Update the pinned importer (`docs/development/xpad-import.md`), or add `Resources/Controllers/<vid>/<vid>-<pid>.plist` (a `Controller` for a model no pinned source knows) or `Resources/ControllerPatches/<vid>/<vid>-<pid>.patch.plist` (a `ControllerPatch`). Each is a canonical XML property list: decimal integers, no `null`, `date`, or `data`, no display names, no protocol defaults. Run `swift run OJDRepositoryTool format-plist <file.plist>` on a hand-edited file, then `./Scripts/ojd catalog regenerate --write`. `Resources/Schemas/README.md` has the property-list rules.
3. A new protocol only: a `PhysicalProtocolDriver` in `Sources/OpenJoystickDriverKit/Protocol/Drivers/`, with tests under `Tests/OpenJoystickDriverKitTests/`.
4. Run `just check`.

Capture a candidate with `./Scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only` (no Apple Developer membership needed) and see `docs/testing/controller-record.md`. A live USB probe may need the signed app and DEXT. `ojd diagnose --output support-report.json` writes a support report; review product names before you attach it.

## Code Rules

- Toolchain: `.swift-version` and `Package.swift`. Warnings are errors. Justify `nonisolated(unsafe)` on the same line.
- Style: `.swift-format` and `.swiftlint.yml`. Do not copy them here or add SwiftLint rules that fight the formatter. Run SwiftLint with `--no-cache --strict`. No `// swiftlint:disable` except for an `@objc` callback that cannot comply, with the reason on that line.
- GUI and CLI text: `LOCALIZATION.md`. Tests check codes, routes, identifiers, paths and structure, not help text, and do not read `.swift` source.
- Decimal integers in stored documents (`.plist`) and in JSON messages. The one exception is raw bytes in a `session` (`bytes`, `data`, a probe's expected bytes): uppercase hex pairs separated by single spaces, such as `42 03 00 00`.
- Keep the existing `print` diagnostics; add no logging stack. Parser errors stay local: log and skip.
- Deployment floor: macOS 12; future iOS and iPadOS companion apps: 15.
- Kit has no SwifterKit. USB adapter: `Sources/OpenJoystickDriverUSB/`. DriverKit generator: `Sources/DriverKitGenerator/` and `Scripts/Build/driverkit.sh`; no manual DriverKit build or post-generation patch (`./Scripts/ojd check driverkit`).
- `com.openjoystickdriver.XboxUSBDevice` is the only DEXT, with one personality, `XboxUSB` (Microsoft GIP USB interfaces), and only the `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb` entitlements. The host profile's `com.apple.developer.driverkit.userclient-access` list must include it, and `Host.entitlements` claims exactly it. Virtual gamepads use `IOHIDUserDevice`, which needs `com.apple.developer.hid.virtual.device` on the app profile, never in the DEXT.

## Target Branch

Base every pull request on `main`, and check a bug against `main` before you open an issue. Other branches can be deleted at any time, and deleting a branch closes the pull requests based on it.

## License

OJD is under the Mozilla Public License 2.0, which permits commercial use. Sign the [Contributor License Agreement](CLA.md) on your first pull request, so the maintainer can license your contribution under MPL-2.0 and other terms; the CLA check fails until you do.

- Code may come only from sources under MIT, BSD, zlib, CC0 or Apache-2.0. Add each source's notice to `THIRD_PARTY_NOTICES.md` in the same commit.
- GPL, LGPL, AGPL and unlicensed sources give facts only, such as byte values or IDs, and the code for those facts is written independently.

## Issues and Pull Requests

Use the issue forms; each has a human and an **(AI Agent)** variant. A pull request holds one logical change and fills every section of its template, with the checks run and whether you tested on your own hardware. Report security problems privately, as [`SECURITY.md`](SECURITY.md) describes. Open tasks: [issues](https://github.com/xsyetopz/OpenJoystickDriver/issues).

Write exact values; vague or missing details get the issue sent back.

- Version: the whole line from **About OpenJoystickDriver** of the build you ran, for example `0.6.0-alpha.1+build.1.8.74.sha.08bc747d93f6.dirty (1.8.74)`. Not `alpha`, `beta`, `latest`, or a commit. See [Finding the Version](#finding-the-version).
- macOS: version and build from `sw_vers`, for example `15.6.1 (24G90)`.
- Controller: model name, VID:PID, and connection.
- Steps: numbered, one action each.
- Results: what you saw, with error text and codes copied exactly.
- Anything nobody checked: `Not checked`.

### Finding the Version

Copy the version from the build that ran, while it runs. A line without `+build.` is not the whole line.

- In the app: click the menu-bar item, choose **About OpenJoystickDriver**, and copy the text after **Version**.
- In Terminal, with the app running: this AppleScript opens the same About window, prints its version line, and closes it. Terminal, or the app your agent runs in, needs access under **System Settings > Privacy & Security > Accessibility**.

  ```sh
  osascript -e 'tell application "System Events" to tell process "OpenJoystickDriver"' -e 'click menu item 1 of menu 1 of menu bar item 2 of menu bar 1' -e 'delay 1' -e 'repeat with w in windows' -e 'set ts to value of static texts of w' -e 'repeat with t in ts' -e 'if t contains "+build." then' -e 'click (first button of w whose subrole is "AXCloseButton")' -e 'return contents of t' -e 'end if' -e 'end repeat' -e 'end repeat' -e 'end tell' | sed 's/^[^0-9]*//'
  ```

- In Terminal, for the app in `/Applications`: `ojd --version` prints the same line. Without the `ojd` link, run `(exec -a ojd /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --version)`.

## AI Agents

A human operator stands behind every issue, comment and pull request an agent writes, reads it before it is posted, and is named in the form.

- Keep the attribution your harness adds to commits and pull requests. If it adds none, end each commit message with a trailer that names the model, such as `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. The operator stays the commit author.
- Write plainly and briefly, in the words a user would use. No preamble, recap, extra headings, or emoji: fill the fields and stop.
- State only what a command, the source, or the operator showed. Write `Not checked` instead of guessing.
- Install each missing tool before you run a check: `./Scripts/ojd setup` offers the Homebrew formulas, such as `just`, and an Xcode whose Swift is `.swift-version` or newer comes from Apple. "Not installed" or "unavailable" is not a check result. Report a check as blocked only when the operator's Mac cannot run the tool, and name the tool version and the macOS version that it needs.
- Get the version yourself on the operator's Mac, as [Finding the Version](#finding-the-version) shows, while the build that was tested runs. A commit or "not recorded" does not replace it. When the command fails, ask the operator to copy the line from the About window.

A fix that the operator tested on their hardware comes with a prompt for the maintainer's agent, in a code block, with numbered steps another agent can follow without guessing:

```text
Fix: <what is wrong, for which controller, VID:PID, and connection>.
Tested by @<operator> on OpenJoystickDriver <whole About line>, macOS <version and build>.

1. In <path>, in <function or type>, replace <exact old code> with <exact new code>.
2. Run <command>. Expect <result>.
3. Change nothing else.
```

These rules draw on GitHub's [issue form syntax](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema), the [Ghostty AI policy](https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md), the Linux kernel's [AI coding assistants guide](https://docs.kernel.org/process/coding-assistants.html), and the [KubeVirt AI contribution policy](https://github.com/kubevirt/community/blob/main/ai-contribution-policy.md).
