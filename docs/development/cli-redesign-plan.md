# CLI Redesign Plan

Status: proposed. Breaking changes are allowed, with no migration and no aliases for old command names.

## Goal

The command line is the complete interface to OpenJoystickDriver. Every feature ships in the CLI first, with `--json` output, exit codes, help, and tests. The app is a graphical layer over the same operations ([GUI Redesign Plan](gui-redesign-plan.md)). A script and a person at a terminal both get correct behavior from every command.

The design follows the Command Line Interface Guidelines as packaged in the `design-command-line-interfaces` skill. Breaking changes without migration are allowed for this release, so the skill's rule for that case applies: old names are removed outright, with no aliases, and the changelog lists each removed name next to its replacement.

## Current State

Measured on the `feat/0.5.0-beta.5` debug build:

- `check_cli.py --sub status --sub controller --sub map --sub app --sub extension --sub diagnose --sub permissions --sub update -- .build/debug/OpenJoystickDriver --headless` reports 6 errors: `status --help`, `controller --help`, `app --help`, `extension --help`, `diagnose --help`, and `update --help` exit 64 instead of printing help.
- The parser is hand-written (`Sources/OpenJoystickDriverCLI/Catalog/CLIGrammar.swift`).
- Devices are selected in three ways: positional vendor and product IDs, `--vid`/`--pid`/`--device`, or `--controller`. Two hex parsers accept different spellings.
- `controller disconnect` suspends a controller, `controller disconnect-wireless` disconnects it, and `enable`/`disable` means three different things across `app login`, `extension`, and `map`.
- The same data is reachable through different commands: `status` and `app status`, `controller list` and `controller output list`, `permissions` and `map permission`.
- About 111 bare `print` calls write output. The `diagnose` summary and `test` results go to stderr. Errors are prefixed with `error:` or `ERROR:`.
- `--json` is missing on `controller list`, `permissions`, `extension`, the `diagnose` summary, and `test`. Streams use `--json-lines`. `map calibration` prints only JSON.
- Grammar errors exit 64 and handler usage errors exit 1. An unreachable service has no exit code of its own.
- `--timeout` works only before the command. `test` falls back to 5 seconds on invalid input. `--version` prints the help title.
- `status` and `controller list` fall back to a direct USB scan when the service is down, so they can report different controllers depending on service state.
- There is no terminal detection, color handling, `NO_COLOR`, or pager.

## Program and Installation

- The program is `ojd`. The app bundle's executable runs as the CLI when it is invoked as `ojd` (by `argv[0]`), and as the app otherwise. `--headless` is removed.
- The app's Settings window has an Install Command-Line Tool action. It links `/usr/local/bin/ojd` to the executable in the bundle, after the administrator authorization that the write requires. `ojd` has the same signature as the app, so the service's client check accepts it. Uninstalling removes the link; the docs describe both.
- The repository's `./Scripts/ojd` is a contributor tool with the same name. The contributor docs say which one each command means.

## Parser

Adopt Apple's `swift-argument-parser`. The skill's first rule is to parse with a library. The current grammar is the source of all 6 checker errors, and the library gives help at every level, `--version`, usage errors on stderr, and generated completion scripts. The maintainer approved it as the project's second dependency, after SwifterKit. Version 1.8.2 declares no platform minimum, so it builds for OJD's macOS 12 target, and it exits with `EX_USAGE` (64) on a validation failure. Slice 1 confirms that localized help text works through its `CommandConfiguration` and `ArgumentHelp` values, and that global options are accepted after the subcommand.

Delete `CLIGrammar.swift`, `CLIInvocation`, and the per-command argument parsing in the same change that moves each command.

## Command Tree

Nouns come first, then verbs. The same verb means the same action on every noun. Every noun is singular.

| Command | Replaces | Purpose |
| --- | --- | --- |
| `ojd status` | `status`, `app status` | Service, extension, permissions, controllers, and configuration errors in one summary. |
| `ojd service start\|stop\|wait` | `app ready`, implicit launches | Start or stop the persistent service, or wait until it accepts requests. |
| `ojd controller list` | `controller list`, `controller output list` | Connected controllers. |
| `ojd controller show CONTROLLER` | `controller state` | Identity, ownership, capabilities, virtual pad, and effective record source. |
| `ojd controller watch CONTROLLER` | `controller watch`, `test` | Stream input state. `--duration` stops it. `--first-press` prints the next pressed input and exits. |
| `ojd controller capture CONTROLLER` | `controller packets`, `controller trace` | Stream raw reports. |
| `ojd controller rumble CONTROLLER` | `controller rumble` | `--left`, `--right`, `--duration`. |
| `ojd controller light CONTROLLER` | `controller color`, `controller brightness` | `--color`, `--brightness`. |
| `ojd controller player CONTROLLER NUMBER` | `controller player` | Set the player indicator. |
| `ojd controller suspend\|resume CONTROLLER` | `controller disconnect`, `controller resume` | Stop or restart OJD's handling of a controller. |
| `ojd controller disconnect CONTROLLER` | `controller disconnect-wireless` | Disconnect a wireless controller. |
| `ojd virtual show\|set\|reset` | `controller virtual set\|reset`, `controller plan` | The virtual pad OJD publishes for a controller. |
| `ojd profile list\|show\|create\|duplicate\|rename\|delete` | `map` profile commands | Profile lifecycle. |
| `ojd profile activate\|deactivate PROFILE --controller CONTROLLER` | `map` activation commands | Which profile a controller uses. |
| `ojd profile import FILE\|-` and `ojd profile export PROFILE` | none | Profiles as files ([Controller Configuration Plan](controller-config-plan.md)). |
| `ojd profile edit PROFILE` | about 60 `map` flags | Open the profile file in `$EDITOR` on a terminal, then validate it. |
| `ojd binding list\|set\|clear PROFILE` | `map` binding, chord, sequence, and layer commands | The common binding edits without an editor. |
| `ojd record list\|show\|validate\|install\|remove\|draft` | `diagnose catalog` | Controller records ([Controller Configuration Plan](controller-config-plan.md)). |
| `ojd permission list\|request` | `permissions`, `map permission` | macOS privacy permissions. |
| `ojd extension status\|activate\|deactivate` | `extension status\|enable\|disable` | The DriverKit extension, in Apple's activation terms. |
| `ojd setting list\|get\|set` | `app login enable\|disable` | App settings, including `launch-at-login`. The service applies them. |
| `ojd log show\|path` | `app logs show\|path\|open` | `show --follow` streams. `open` is dropped: `open "$(ojd log path)"` does the same. |
| `ojd diagnose` | `diagnose runtime`, `diagnose report` | Run every check. `--bundle PATH` also writes a support bundle. |
| `ojd update check` | `update check` | Only when asked. The CLI never checks for updates on its own. |

Calibration commands (`map calibration`) move to wherever slice 4 finds calibration data belongs: the profile file or the controller record. `diagnose usb-passive` (DEBUG only) moves to `./Scripts/ojd`, because it is a contributor probe and not a product command.

## One Controller Selector

`CONTROLLER` is one positional argument with one parser. It accepts:

- the controller's stable ID from `ojd controller list`;
- `VVVV:PPPP`, four hex digits each, case-insensitive, when exactly one connected controller has that identity.

An ambiguous or unknown selector exits 1 and lists the matching controllers. Records use `VVVV:PPPP` too, with the same parser. List indexes are not accepted, because they change when controllers connect.

## Output

- Data goes to stdout. Progress, warnings, and errors go to stderr. Help requested with `--help` goes to stdout, and usage printed because of an error goes to stderr.
- Every command that prints data supports `--json`. The top level is always an object (`{"controllers": [...]}`), so fields can be added later. Streaming commands print one JSON object per line with `--json`; `--json-lines` is removed.
- Lists support `--plain`: one record per line, tab-separated, no alignment or decoration.
- JSON keys, enum values, and `--plain` fields use stable identifiers and are never localized. Human output is localized and may change between releases. The docs say which output is stable.
- Each JSON output type has a schema in `Resources/Schemas/`, under the rules in `Resources/Schemas/AGENTS.md`. The same Swift types feed the app ([GUI Redesign Plan](gui-redesign-plan.md)).
- `--quiet` removes success messages on stderr.
- Color is used only when stderr or stdout is a terminal, and never when `NO_COLOR` is set, `TERM=dumb`, or `--no-color` is given. No spinners or progress animation off a terminal.
- `ojd log show` pages through `$PAGER` on a terminal. No other command pages.
- Errors use one format: `ojd: <what failed>. <how to fix it>`. Expected errors never print a Swift error dump. Unexpected errors print a one-line summary and suggest `ojd diagnose --bundle`.

## Exit Codes

| Code | Meaning |
| --- | --- |
| 0 | Success. |
| 1 | The command failed: controller not found, write rejected, validation failed. |
| 64 | Usage error. This is `swift-argument-parser`'s code (`EX_USAGE`). |
| 69 | The service is not running (`EX_UNAVAILABLE`). The message names `ojd service start`. |
| 77 | A macOS permission is missing (`EX_NOPERM`). The message names `ojd permission request`. |
| 130 | Interrupted with Ctrl-C. |

Root help and the command-line docs list these codes. `ojd diagnose` exits 1 when any check fails.

## Input and Flags

- Global flags (`--json`, `--plain`, `--quiet`, `--no-color`, `--no-input`, `--timeout`) work before and after the subcommand. A test covers both positions for every command.
- Standard names keep their standard meaning: `-h`/`--help`, `--version`, `-q`/`--quiet`, `-f`/`--force`, `-n`/`--dry-run`, `-o`/`--output`, `-a`/`--all`. No `-v`.
- `ojd --version` prints the version alone on stdout, such as `0.5.0-beta.5`.
- `-` means stdin for `profile import` and `record validate|install`.
- Nothing prompts without a terminal on stdin or with `--no-input`. A missing value fails at once and names the flag that supplies it.
- Confirmation follows the danger. `profile delete`, `record remove`, and `virtual reset --all` prompt on a terminal and need `--force` otherwise; each supports `--dry-run`. `map clear-inputs --confirm` goes away with `map`.
- Values are validated before any request reaches the service. Invalid input exits 64 and names the value. `controller watch --duration abc` fails; it no longer falls back to 5 seconds.
- An unknown command suggests the nearest valid name and never runs it. There are no implicit abbreviations.

## Service Connection

- Commands that need the service exit 69 when it is down. No command starts the service implicitly; `ojd service start` does it.
- `status` reports a stopped service as state and exits 0. The direct USB scan fallback in `status` and `controller list` is removed, so every controller report comes from the service.
- The RPC socket stays private: the server keeps its user and signing-identity checks.
- `--timeout` bounds each request. `service wait --timeout` bounds the wait.

## Compatibility Code To Remove

Each candidate is classified in its slice with the `remove-unneeded-compatibility-code` procedure: consumers traced, then removed completely.

| Candidate | Expected class | Evidence to collect |
| --- | --- | --- |
| `--headless` stripping in `Sources/OpenJoystickDriver/main.swift` | retired by `argv[0]` dispatch | callers in docs, scripts, tests, tester kits |
| `InstalledCLIForwarder` and `OJD_RUN_REPOSITORY_CLI` | retired if a repository build can reach the service through `ojd`; required otherwise | the server's client check and the contributor workflow |
| Direct USB scan fallback in `status` and `controller list` | never required | who depends on output while the service is down |
| `--json-lines` | retired by `--json` streams | docs and tests |
| The second hex parser | never required | call sites |
| Handling for the bare `help` word | retired by the library's `help` subcommand | grammar tests |
| `diagnose usb-passive` under `#if DEBUG` | moves to `./Scripts/ojd` | contributor docs |

## Slices

Each slice is one change with its tests, docs, and checks.

1. **Parser and skeleton.** Add `swift-argument-parser`, `argv[0]` dispatch, global flags, output and error helpers, exit codes, and color and terminal detection. Move `status` and `service`. Tests for streams, exit codes, flag position, and `--help` on every command.
1. **Controllers.** `controller`, `virtual`, and the controller selector.
1. **Records.** `record` commands, built on this parser, as slice 1 of the Controller Configuration Plan.
1. **Profiles and bindings.** `profile` and `binding`. Deletes `map`.
1. **System.** `permission`, `extension`, `setting`, `log`, `diagnose`, `update`. The Install Command-Line Tool action.
1. **Output schemas.** Schemas for every `--json` type and a test that validates each command's output against its schema.

Slice 1 lands before the Controller Configuration Plan adds any command, so no command is written twice.

## Checks

- Each slice runs the repository checks in `CLAUDE.md`.
- `Tests/OpenJoystickDriverCLITests/` gains tests that assert stdout, stderr, and exit code for success, usage errors, service down, and missing permission; `--help` for every command; global flags in both positions; and a run with stdin from `/dev/null`.
- `check_cli.py` runs on each slice's build with every noun as `--sub` and ends with no findings. The baseline is the 6 errors above.
- `wiki/Command-Line.md` and `wiki/Command-Reference.md` are rewritten per slice. The command reference is checked against `ojd --help` output.
- The changelog lists every removed command and flag with its replacement.

## Open Questions

- Whether `ojd` needs an interactive mode. This plan assumes not.
