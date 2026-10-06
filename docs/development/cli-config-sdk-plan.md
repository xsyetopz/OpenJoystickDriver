# CLI, Configuration, and Mod SDK Plan

Status: proposed for the next 0.5.0-beta.5 tester build.
It extends the [Controller Configuration Plan](controller-config-plan.md), whose six slices have landed, and the [CLI Redesign Plan](cli-redesign-plan.md).

## Goal

- Any user, from a first-time user to a power user, can learn and use `ojd` from its help text alone.
- The CLI only parses arguments and prints results.
  Limits, defaults, parsing, and checks live in Kit or Service, where the app and the endpoint use the same code.
- Per-controller behavior that is data lives in records, not in Swift identity checks.
- Users can override configuration in files, with a stated precedence.
- Third parties can write, test, and publish controller fixes as data packages that OJD validates and installs.

## Mod Surface

A mod is data, not code.
A package holds controller records, remapping profiles, and personas, and a manifest that names them and the OJD versions it supports.
OJD validates and installs the package through the CLI, and programs read and drive controllers through the existing [Public Endpoint](public-endpoint-design.md).

OJD loads no third-party code:

- The hardened runtime's library validation refuses libraries that another team signed, so an in-process plugin would need OJD to turn that protection off.
- A plugin ABI would freeze OJD's internal Swift types.
- Data passes through the same schemas and the same bounded write executors as bundled records, so a package cannot send a write that its records do not declare.

This replaces the earlier "no SDK" decision: the SDK is the schemas, the package format, the test command, the endpoint, and their documentation.

## What Stays in Swift

These stay in code, because macOS or safety requires them:

- The `XboxUSBDevice` DriverKit extension's VID/PID list and matching (`Sources/OpenJoystickDriverUSB/Configuration.swift`, `XboxUSBDevice.entitlements`).
  Apple signs that list, so no record or package can extend it.
- IOHIDUserDevice report descriptors and the virtual LocationID `0x4F4A0000` (`VirtualDeviceProfile.swift`).
- Stateful protocol framing: GIP, Switch subcommands, DualShock 4 and DualSense checksums, Steam sessions.
- The rumble duration cap `maxRumbleDurationMs = 5_000` (`DeviceManager.swift`), neutralization timings, and RPC and endpoint deadlines.

## Slices

Each slice is one commit with its tests, localization keys in every catalog, docs, and `CHANGELOG.md` entry.
The maintainer approves each commit.

1. **CLI logic into Kit and Service.**
   Move these out of `Sources/OpenJoystickDriverCLI`:
   - rumble defaults (5 s, intensity 180) and the hex color parser (`ControllerOutputCommands.swift`);
   - soak limits (`DiagnoseCommand.swift`) and the checks in `DiagnoseChecks.swift`, into a Kit `DiagnosticsService`;
   - the log line range `1...10_000`, now in two files (`LogCommand.swift`, `LogExportCommand.swift`), and the home-folder redaction (`LogExportCommand.swift`);
   - the port range (`AccessWebCommand.swift`), the `/Applications/` checks (`InstalledCLIForwarder.swift`, `ExtensionSubmission.swift`), the codesign check (`ExtensionSubmission.swift`), and `open -g` (`ServiceCommand.swift`);
   - the feed heartbeat (`VirtualFeedCommand.swift`);
   - one VID/PID selector in Kit for the six copies outside Presentation (`ControllerSelector.swift`, `ControllerCommand.swift`, `AutomationService.swift`, `RemappingRoutingCore.swift`, `ApplicationServiceRemappingRPC.swift`, `Identity.swift`).
   The two Presentation copies stay, because Presentation does not change in this beta.
   Behavior does not change; existing CLI tests must pass unchanged.
1. **CLI usability.**
   - EXAMPLES in the help of the root command, `controller watch`, `controller rumble`, `controller light`, `profile create`, `profile set`, `binding set`, `record install`, and `access grant`.
   - A "Start here" path (`status`, then `diagnose`, then `controller list`) in the root help, exit code 127 in the exit-code list, and the shell-completion command in help and on `wiki/Command-Line.md`.
   - The six global options shown once in the root help, not in the USAGE line of every command.
   - Default timeouts stated in help.
   - `--plain` works or is rejected with exit 64 in `ProfileActivationCommands.swift` and `VirtualFeedCommand.swift`.
   - Environment fallbacks `OJD_NO_INPUT`, `OJD_TIMEOUT`, and `OJD_COLOR`, where a flag beats the variable; `OJD_RUN_REPOSITORY_CLI` documented for contributors.
   - `--version` checked in a release build.
1. **Per-controller constants into records.**
   Add fields to `controller-override.schema.json` and `controller.schema.json`, move the values into `Resources/ControllerOverrides/`, regenerate the catalog, and delete the identity checks:
   - the `11C1:5600` stick deadzone (`UserSpaceOutputDispatcher+ReportMapping.swift`);
   - DualShock 4 factory calibration by vendor (`ProtocolDriverRegistry.swift`) and `DualShock4Model` by VID:PID (`DualShock4Driver+Models.swift`, `DualShock4Driver.swift`);
   - the Shield PID (`NVIDIAShieldDriver.swift`);
   - timings: DualShock 4 liveness, Switch 1 (`Switch1Driver.swift`), GIP announce (`GIPDriver.swift`), XUSB inquiry (`XUSBDriver.swift`), and HID startup retries (`DeviceManager+HIDStartupOutput.swift`), next to the existing `postHandshakeSettleMs`.
   - the glyph family by Microsoft vendor ID (`VirtualIdentityPresentation.swift`), which the persona declares instead.
   Protocol defaults stay in the driver; a record value overrides them.
   The GIP announce and XUSB inquiry resend counters stay in Swift, with the stateful framing of those protocols.
   A `patch` of `protocol` that keeps the bundled family merges into the bundled block (RFC 7396), and its `quirks` join the bundled quirks (maintainer decision, 2026-10-06), so a user patch cannot drop the quirks that now carry DualShock 4 calibration and Shield rumble.
   A user patch can set `tuning`, which replaces the bundled `tuning` whole.
   The `hid.descriptor` axis layouts and the third-party DualSense model values are record quirks; a non-Sony vendor ID still selects third-party DualSense mode.
   Follow-ups, kept in Swift for this beta: the `JoyConHalf` table (`JoyConPair.swift`), which Presentation, Service, and profile validation call, and the Switch 2 vibration UUID table (`Switch2BluetoothLEHub.swift`), which `Switch2BluetoothLECentral` uses.
1. **Configuration layer.**
   - A global defaults file, `~/Library/Application Support/OpenJoystickDriver/Defaults.json`, for deadzone and timing defaults.
     Precedence, lowest first: driver default, global file, bundled record, user record, active profile.
   - Persona overrides move from the `VirtualHIDProfileOverrides` user default (`VirtualHIDProfileOverrideStore.swift`) to `Personas/<id>.json` files with a schema.
     Users can define a persona: identity strings, VID, PID, and glyph family over one of the built-in report descriptors.
     The old user default is deleted, not migrated, as with the old profile library and the no-shim rule in `Resources/Schemas/AGENTS.md`; users recreate their overrides.
   - `ojd config show` prints each effective value and the layer that set it.
1. **Mod packages.**
   - A package manifest schema: name, version, author, `requires` (an OJD version range), and the records, profiles, and personas it holds.
     OJD refuses a package whose range excludes the running version.
   - `ojd mod validate|install|list|remove`, with `--dry-run`, `--force`, and `--json` as in the other commands.
     A package is installed into its own folder, so `remove` takes out only its files.
   - `ojd record test RECORD --packets CAPTURE --expect STATE`: replays captured reports through the record's parser and compares the parsed state.
     It uses the packet capture that `record draft` already reads.
   - Versioned schemas, as Kubernetes versions its APIs (maintainer decision, 2026-10-06): each schema's path and `$id` carry its version, `Resources/Schemas/v1beta1/<name>.schema.json`.
     Before OJD 1.0, a `v1beta1` schema may change in incompatible ways, and the release notes list each change.
     OJD 1.0 promotes the schemas to `v1`, which takes only additive changes; a breaking change needs `v2`.
     Files declare their version through `$schema`, and OJD rejects a version it does not know.
     `Resources/Schemas/AGENTS.md` changes to allow the version segment; its ban on dual decoders and shims stays.
     The compatibility policy is on the wiki.
   - A sample package in `docs/sdk/sample/` and an authoring guide, `wiki/Writing-Controller-Mods.md`, that states first that the USB extension's product list is Apple-signed and cannot be extended.
   - Fix `public-endpoint-design.md`, which says the endpoint supports a range of protocol versions; the code accepts only version 1 (`EndpointServer.swift`).
1. **Repository dispatcher (if time allows).**
   `Scripts/ojd` gets `--help` and `--version` from `argparse`, `error:` messages, and a note that it is not the product `ojd`.

Slices 1 and 2 are the CLI; slices 3 to 5 depend on each other in order, because the defaults file and packages carry the fields slice 3 adds.

## Not in This Plan

- Match keys beyond VID:PID for `045E:028E` clones.
  This waits for evidence of which driver owns that identity on a tester's Mac (see the Controller Configuration Plan).
- In-process plugins and scripting.
- Presentation changes; the GUI shows the new layers in a later beta.

## Checks

Every slice runs the full list in `AGENTS.md`, including `swift test`.
Slices 3 and 4 also run `./Scripts/ojd test parsers-macos14` and compare parsed input for the recorded reports of each moved controller before and after the move.
Slice 5 runs `ojd record test` on the sample package in `swift test`.
Hardware checks after slice 3: DualShock 4 calibration and model, Switch 1 startup, one GIP pad, and the Shield.

## Docs

`wiki/Command-Line.md`, `wiki/Command-Reference.md`, `wiki/Controller-Records.md`, and the new `wiki/Writing-Controller-Mods.md` describe what ships.
`Resources/Schemas/AGENTS.md` lists the new persona, defaults, and package schema families.
