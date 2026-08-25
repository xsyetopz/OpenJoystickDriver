# Contributing

## Setup

For Swift package work on parsers, records, or tests, no signing is required:

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
swift build
swift test
```

Application and generated USB DriverKit work requires signing and provisioning.
Use the `./scripts/ojd` signing flow. SwifterKit generates the DEXT project under
`.build/driverkit/generated/`; do not hand-run Xcode signing, edit generated
files, or patch generation output.

See `scripts/README.md` for signing, provisioning, and release packaging. Run
`./scripts/ojd build install dev` to install a signed dev build into `/Applications`.

The DriverKit generator and runtime use the exact `SwifterKit` version pinned in
`Package.resolved`. `OJD_USE_LOCAL_SWIFTERKIT=1` is useful only for local package
development and is rejected by reproducible DriverKit build and validation routes.

Candidate GIP and wired Xbox 360 records can be validated without signing. A physical probe uses
direct IOUSBHost when macOS permits app ownership; the restricted route additionally requires the
signed app and `XboxUSBDevice` development DEXT:

```bash
./scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
./scripts/ojd diagnose record /tmp/controller-candidate.json --seconds 30
```

See `docs/testing/controller-record.md` for the capture and reporting procedure.
`--validate-only` always works without Apple Developer Program membership or app installation.
Whether a physical probe needs DriverKit provisioning depends on the selected ownership route.

Hardware-facing tests and diagnostics require a USB controller plugged in. Use
the focused diagnostics that match your change, for example:

```bash
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose sdl3 --seconds 5
```

Before filing a controller issue, create a reviewable support report with the
installed app:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless diagnose report
```

The JSON includes VID/PID, active parser/record data, permissions, output
configuration, and GameController visibility. It excludes raw serial values,
filesystem paths, packet payloads, HID location IDs, and free-form DriverKit
runtime summary text. Review device product names before attaching it to an issue.

---

## What needs work

Check the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues)
for open tasks. Adding support for a new controller is a common contribution.

---

## Adding a controller

1. Identify the device class.

Run:

```bash
system_profiler SPUSBDataType
```

Check `bDeviceClass`:

- `0xff` (255): vendor-specific (often GIP for Xbox-compatible hardware)
- `0x03` (3): standard HID

1. Update a source or override.

Do not hand-edit generated runtime records. If the device exists in a supported
upstream table, update its pinned importer and lock. Otherwise, add the smallest
explicit add or patch input under
`Resources/ControllerOverrides/<vid>/<vid>-<pid>.json`.

Records use decimal JSON numbers and contain no display names. Do not repeat
protocol-default endpoints, startup packets, output policy, or parser behavior in
device data.

Regenerate and inspect the affected VID/PID file:

```bash
./scripts/ojd catalog regenerate --write
./scripts/ojd catalog regenerate --check
```

See `docs/development/xpad-import.md` for source and conflict rules.

1. Implement a parser only when the protocol is new.

New parsers go in `Sources/OpenJoystickDriverKit/Protocol/Parsers/` and must
conform to the `InputParser` protocol. Use `GIPParser.swift`, `Xbox360Parser.swift`,
and `DS4Parser.swift` as references.

1. Add tests.

Add parser, record, or report-format tests under `Tests/OpenJoystickDriverKitTests/`.
Guard hardware-only checks or write them as diagnostics so they can skip cleanly
without local device access.

1. Validate.

```bash
./scripts/ojd check profiles
swift test
```

---

## Code rules

- Swift 6.2 strict concurrency treats all warnings as errors. Do not use
  `nonisolated(unsafe)` unless required, and justify it in a comment.
- Do not add `// swiftlint:disable`. Fix the lint issue instead. The exception is
  an `@objc` callback that cannot satisfy a rule; document the reason in a
  same-line comment.
- Use decimal integers for VID/PID, command codes, and all other numeric JSON
  values. Do not use hex numbers in JSON.
- Prefer the existing lightweight `print`-style diagnostics. Do not add a new
  logging dependency without repo-wide justification.
- One parser error must not affect other controllers. Log and skip parser errors;
  do not propagate them upward.
- The runtime target is macOS 10.15. Avoid broad availability rewrites unless the
  touched API requires it.
- Keep `OpenJoystickDriverKit` free of SwifterKit. Put the host USBDriverKit adapter
  in `Sources/OpenJoystickDriverUSB/`. Put generated-project
  invocation only in `Sources/DriverKitGenerator/` and
  `scripts/build-tools/driverkit.sh`.
- Never add a manual DriverKit native build path, compatibility wrapper, or
  post-generation patch. Generate fresh output and check it with
  `./scripts/ojd check driverkit`.
- The host app's `com.apple.developer.driverkit.userclient-access` entitlement
  must contain only `com.openjoystickdriver.XboxUSBDevice`. Do not use an
  allow-any entitlement.
- Do not assert human-readable message text in tests. Check return codes,
  exit statuses, command routes, identifiers, file paths, and structural
  properties. Prose-text assertions (`assertIn("Error: …")`,
  `#expect(help.contains("Output never…"))`) break every time a message is
  reworded and add no coverage.
- Do not read source files and assert on literal substrings. Tests that call
  `String(contentsOf:)` on a `.swift` file and then `.contains(...)`-match
  source text (e.g. `#expect(cli.contains("case \"output\":\n      return"))`)
  guard formatting, not function — any innocent reformat breaks them. Test
  behavior instead: call the public API, feed it inputs, assert on outputs.
  Use `@testable import` to reach internal types. Verify invariants through
  function calls (`CLIGrammar(arguments:).invocation`,
  `ParserRegistry().hidProfileIdentifiers()`,
  `ApplicationServiceRuntimeHealthAnalyzer.summarize(...)`, etc.), not
  source-text matching.

---

## Pull requests

- Keep each PR to one logical change.
- If you add a controller you own, test it with real hardware and say so in the
  PR description.
- If you add a controller you do not own based on specs or packet captures, say
  so.
- Describe what you tested. Example: "I pressed every button and checked output
  with `--headless run`."

There is no formal PR template. Be clear about what changed and why.

---

## Project layout

```text
Sources/OpenJoystickDriverKit/       Shared parsers, device management, output, and application-service RPC
Sources/OpenJoystickDriverUSB/       USBDriverKit host wrapper and generated DEXT configuration
Sources/OpenJoystickDriver/          App host, presentation, runtime, CLI, remapping, and status
Sources/OpenJoystickDriver/App/Presentation/  AppKit shell and SwiftUI settings/presentation capabilities
Sources/OpenJoystickDriver/CLI/       Installed CLI grammar, catalog, and capability commands
Sources/OpenJoystickDriver/Runtime/   Single application runtime, authenticated RPC, and foreground output
Sources/OpenJoystickDriver/Remapping/ App-side profile storage, routing, and CoreGraphics event adaptation
Sources/OpenJoystickDriverHIDTool/  Internal hardware investigation tool (not a user surface)
Sources/DriverKitGenerator/          Build-time SwifterKit native-project generator
Tests/OpenJoystickDriverKitTests/    Unit tests that do not require hardware
Tests/OpenJoystickDriverUSBTests/    USB configuration and host-adapter contract tests
Tests/OpenJoystickDriverTests/App/Presentation/ App-level presentation product tests matching `Sources/OpenJoystickDriver/App/Presentation/`
Resources/Schemas/                   Canonical record and override schemas
Resources/ControllerOverrides/       Source omissions and evidence-backed corrections
ControllerSources.lock.json          Pinned upstream revisions and hashes
docs/user/compatibility.md           Consumer-visible compatibility mappings
scripts/                             Build, signing, installation, and release tools
```

The main process owns live controller state. Headless commands use the
bounded, authenticated RPC types under
`Sources/OpenJoystickDriverKit/ApplicationService/`. Add shared payloads there
and route operations through `ApplicationServiceServer`.

The installed CLI help text is rendered from `InstalledCommandCatalog` in
`Sources/OpenJoystickDriver/CLI/Catalog/CommandCatalog.swift`. When you
add, rename, or remove a CLI command, update the catalog entry there so the
help output stays in sync. `OpenJoystickDriverHIDTool` is an internal
hardware-investigation tool, not a supported user or contributor surface; route
new user-facing diagnostics through the installed CLI or `./scripts/ojd`
instead.

`OpenJoystickDriverUSB` depends inward on `OpenJoystickDriverKit` and SwifterKit.
The app and `DriverKitGenerator` are composition/build roots. DriverKit native
artifacts under `.build/driverkit/` are generated outputs, not source.
