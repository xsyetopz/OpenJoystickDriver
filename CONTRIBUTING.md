# Contributing

These rules apply to humans and AI agents alike.

## Setup

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
just setup
just verify
```

`just setup` installs the pinned tools and the Git hooks. Xcode, Apple assets, credentials, permissions, publication, destructive writes and hardware actions keep their own authorization flows. CI never prompts or installs host software.

When a check reports a missing tool, install it and rerun the check: `just setup` offers the Homebrew formulas, such as `just`, and an Xcode whose Swift is `.swift-version` or newer comes from Apple. A check is blocked only when the Mac cannot run the tool; name the tool version and the macOS version it needs.

- Prerequisites, Git hooks, commit messages and screenshots: `docs/development/building-from-source.md`.
- Toolchain and environment variables: `docs/development/environment.md`.
- Signing: `docs/development/signing.md`. Releases: `docs/development/releases.md`. Tester DMG: `docs/development/tester-builds.md`.
- Layout and targets: `docs/development/source-topology.md`. Recipes: `just`.

Run `just verify` before opening a pull request; CI repeats it.

## Adding a Controller

1. Run `system_profiler SPUSBDataType`. `bDeviceClass` `0xff` is vendor-specific (often GIP); `0x03` is HID.
2. Do not hand-edit generated records. Update the pinned importer (`docs/development/xpad-import.md`), or add `Resources/Controllers/<vid>/<vid>-<pid>.plist` (a `Controller` for a model no pinned source knows) or `Resources/ControllerPatches/<vid>/<vid>-<pid>.patch.plist` (a `ControllerPatch`). Each is a canonical XML property list: decimal integers, no `null`, `date`, or `data`, no display names, no protocol defaults. Run `swift run OJDRepositoryTool format-plist <file.plist>` on a hand-edited file, then `just catalog-regenerate --write`. `Resources/Schemas/README.md` has the property-list rules.
3. A new protocol only: a `PhysicalProtocolDriver` in `Sources/OpenJoystickDriverKit/Protocol/Drivers/`, with tests under `Tests/OpenJoystickDriverKitTests/`.
4. Run `just verify`.

Capture a candidate with `just diagnose-record /tmp/controller-candidate.json --validate-only` (no Apple Developer membership needed) and see `docs/testing/controller-record.md`. A live USB probe may need the signed app and DEXT. `ojd diagnose --output support-report.json` writes a support report; review product names before you attach it.

## Code Rules

- Toolchain: `.swift-version` and `Package.swift`. Warnings are errors. Justify `nonisolated(unsafe)` on the same line.
- Style: `.swift-format` and `.swiftlint.yml`. Do not copy them here or add SwiftLint rules that fight the formatter. Run SwiftLint with `--no-cache --strict`. No `// swiftlint:disable` except for an `@objc` callback that cannot comply, with the reason on that line.
- Names in code read as headlines, without articles: `skipEndsStep`, not `skipEndsTheStep`. A control named `A` stays, as in `pressAOpensMenu`.
- GUI and CLI text: `LOCALIZATION.md`. Tests check codes, routes, identifiers, paths and structure, not help text, and do not read `.swift` source.
- Decimal integers in stored documents (`.plist`) and in JSON messages. The one exception is raw bytes in a `session` (`bytes`, `data`, a probe's expected bytes): uppercase hex pairs separated by single spaces, such as `42 03 00 00`.
- Keep the existing `print` diagnostics; add no logging stack. Parser errors stay local: log and skip.
- Deployment floor: macOS 12; future iOS and iPadOS companion apps: 15.
- Kit has no SwifterKit. USB adapter: `Sources/OpenJoystickDriverUSB/`. DriverKit generator: `Sources/DriverKitGenerator/` and `Scripts/Build/driverkit.sh`; no manual DriverKit build or post-generation patch (`just driverkit-check`).
- `com.openjoystickdriver.XboxUSBDevice` is the only DEXT, with one personality, `XboxUSB` (Microsoft GIP USB interfaces), and only the `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb` entitlements. The host profile's `com.apple.developer.driverkit.userclient-access` list must include it, and `Host.entitlements` claims exactly it. Virtual gamepads use `IOHIDUserDevice`, which needs `com.apple.developer.hid.virtual.device` on the app profile, never in the DEXT.

## Target Branch

Base every pull request on `main`, and check a bug against `main` before you open an issue. Other branches can be deleted at any time, and deleting a branch closes the pull requests based on it.

## License

OJD is under the Mozilla Public License 2.0, which permits commercial use.

- Code may come only from sources under MIT, BSD, zlib, CC0 or Apache-2.0. Add each source's notice to `THIRD_PARTY_NOTICES.md` in the same commit.
- GPL, LGPL, AGPL and unlicensed sources give facts only, such as byte values or IDs, and the code for those facts is written independently.

## Issues and Pull Requests

Use the issue forms: Bug Report, Controller Support, and Feature Request. A pull request holds one logical change and fills every section of its template, with the checks run and whether you tested on your own hardware. Report security problems privately, as [`SECURITY.md`](SECURITY.md) describes. Open tasks: [issues](https://github.com/xsyetopz/OpenJoystickDriver/issues).

Write exact values. The maintainer owns few of the reported controllers, so the report is the only source of them, and its data decides how well a controller is supported and how fast a fix lands. Open an issue only once you can fill each required field of its form with real output, or with the three-part reason a command could not run.

- Version: the whole line from **About OpenJoystickDriver** of the build you ran, for example `0.6.0-alpha.1+build.1.8.74.sha.08bc747d93f6.dirty (1.8.74)`. It names one build; `alpha`, `latest` or a commit names many. See [Finding the Version](#finding-the-version).
- macOS: version and build from `sw_vers`, for example `15.6.1 (24G90)`.
- Controller: model name, VID:PID, connection, and firmware version.
- Every mode and connection: read the maker's manual or website, try each mode, switch position and button combination over each connection the controller has, and list the VID:PID of each with how to enter it. One controller often has several; the 8BitDo Ultimate 2C has a different VID:PID over Bluetooth, over its receiver in each mode, and over a cable in DInput mode.
- Intelligence, gathered before you propose a cause: descriptors and packet captures from macOS, Windows and Linux, and what others found about the controller (Linux drivers, SDL, Steam Input, other driver projects, issues, forum threads), each named with its link or line. Cross-check with a second driver or system where one is at hand. [Gather Data From Other Systems](wiki/Reporting-a-Bug.md#gather-data-from-other-systems) lists the commands.
- Steps: numbered, one action each.
- Results: what you saw, with error text and codes copied exactly.
- Test run: the compiled OJD code on the controller, with its counts of packets received, snapshots decoded, and parse errors while each control is pressed and released. A replay of captured bytes through a separate script is only a lead for that run.
- Evidence: each claim states what a command, the source, or a person showed, next to the pasted command output, file, log excerpt, or screenshot. Run the command, then write the claim, and mark an item done next to the output that shows it.
- A command that cannot run: write the exact step that failed or was missing, the exact error or reason (for example, the Xcode version that you found), and what you tried instead, with its output.

### Finding the Version

Copy the version from the build that ran, while it runs. A line without `+build.` is not the whole line. An agent gets the line itself on the operator's Mac and asks the operator to copy it from the About window only when the commands fail.

- In the app: click the menu-bar item, choose **About OpenJoystickDriver**, and copy the text after **Version**.
- In Terminal, with the app running: this AppleScript opens the same About window, prints its version line, and closes it. Terminal, or the app your agent runs in, needs access under **System Settings > Privacy & Security > Accessibility**.

  ```sh
  osascript -e 'tell application "System Events" to tell process "OpenJoystickDriver"' -e 'click menu item 1 of menu 1 of menu bar item 2 of menu bar 1' -e 'delay 1' -e 'repeat with w in windows' -e 'set ts to value of static texts of w' -e 'repeat with t in ts' -e 'if t contains "+build." then' -e 'click (first button of w whose subrole is "AXCloseButton")' -e 'return contents of t' -e 'end if' -e 'end repeat' -e 'end repeat' -e 'end tell' | sed 's/^[^0-9]*//'
  ```

- In Terminal, for the app in `/Applications`: `ojd --version` prints the same line. Without the `ojd` link, run `(exec -a ojd /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --version)`.

## AI Agents

A human operator stands behind every issue, comment, commit and pull request an agent writes, and answers for it as their own work: the operator understands it, can defend it in review, fills the hardware, macOS and test fields, and alone approves or signs off. The operator reads a post before it goes out or tells the agent to post it on their behalf; either way, the agent reads the whole post first and checks each claim against the output it rests on. The **AI tool** section of the issue forms and the pull request template records the tool and model, what it produced, the commands it ran with their output, and the claims the operator checked by hand.

- Attribution follows the Linux kernel's `Assisted-by: AGENT_NAME:MODEL_VERSION [TOOL1] [TOOL2]` tag. `AGENT_NAME` is the AI tool, `MODEL_VERSION` is the exact model, and the optional tools are specialized analysis tools, never basic ones such as git, Swift or just. Example: `Assisted-by: Claude Code:claude-opus-5-5`.
  - Commit: the message ends with the `Assisted-by:` trailer. The operator stays the commit author.
  - Pull request, issue and comment: the body ends with a `---` line, then the `Assisted-by:` line.
  - Spelling, grammar, formatting and mechanical renames need no tag.
- Voice: plain and brief, in the words a user would use, without greetings, thanks, apologies, preamble, recap, extra headings, or emoji. The agent speaks as itself and names the person it writes for in the third person by role, such as the maintainer, the contributor, or the reporter; its "I" is never that person.
- Data-mining comes first. Before the agent drafts a Bug Report or Controller Support issue, it runs each command it can on the operator's Mac, then asks the operator item by item for the rest of the [Issues and Pull Requests](#issues-and-pull-requests) list: every mode and connection with its VID:PID, the firmware, captures from Windows or Linux, and what others found about the controller. It asks again when an answer is vague or has no output behind it.
- The agent refuses to draft, post or help post an issue while a required field lacks real output or a three-part reason, and tells the operator not to open it yet. It names each missing item and how to get it.
- To fix an answer it posted, the agent edits that message in place.

A fix that the operator tested on their hardware comes with a prompt for the maintainer's agent, in a code block, with numbered steps another agent can follow without guessing:

```text
Fix: <what is wrong, for which controller, VID:PID, and connection>.
Tested by @<operator> on OpenJoystickDriver <whole About line>, macOS <version and build>.

1. In <path>, in <function or type>, replace <exact old code> with <exact new code>.
2. Run <command>. Expect <result>.
3. Change nothing else.
```

These rules draw on GitHub's [issue form syntax](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema), the [Ghostty AI policy](https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md), the Linux kernel's [AI coding assistants guide](https://docs.kernel.org/process/coding-assistants.html), and the [KubeVirt AI contribution policy](https://github.com/kubevirt/community/blob/main/ai-contribution-policy.md).
