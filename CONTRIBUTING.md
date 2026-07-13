# Contributing

## Setup

OpenJoystickDriver has two common workflows:

- Swift package work (parsers, records, tests): no signing required.
- Application + DriverKit extension work: requires signing/provisioning; use
  `./scripts/ojd`.

For application + DriverKit extension development, you must use the `./scripts/ojd`
signing flow; you must not try to hand-run Xcode signing steps.

Start here:

- `scripts/README.md` for signing/provisioning and release packaging
- `./scripts/ojd rebuild dev` to install a signed dev build into `/Applications`

Swift package (no signing required):

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
brew install libusb
swift build
swift test
```

Candidate GIP and wired Xbox 360 records can be validated and exercised against
physical USB hardware without building or signing the app:

```bash
./scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
./scripts/ojd diagnose record /tmp/controller-candidate.json --seconds 30
```

See `docs/testing/controller-record.md` for the capture and
reporting procedure. This path does not require Apple Developer Program
membership, provisioning profiles, DriverKit approval, or app installation.

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
  --headless report create
```

The same action is available under **Advanced > Support report** in the menu
app. The JSON includes VID/PID, active parser/record data, permissions, output
configuration, GameController visibility, and backend counters. It excludes raw
serial values, filesystem paths, packet payloads, HID location IDs, and free-form
DriverKit discovery text. Review device product names before attaching it to an
issue.

---

## What needs work

Check the [issue tracker](https://github.com/xsyetopz/OpenJoystickDriver/issues)
for open tasks. The most common contribution is adding support for a new
controller.

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
upstream table, update its pinned importer and lock. Otherwise add the smallest
explicit add or patch input under
`Resources/ControllerOverrides/<vid>/<vid>-<pid>.json`.

Records use decimal JSON numbers and contain no display names. Protocol-default
endpoints, startup packets, output policy, and parser behavior must not be
repeated in device data.

Regenerate and inspect the affected VID/PID file:

```bash
./scripts/ojd catalog regenerate --write
./scripts/ojd catalog regenerate --check
```

See docs/development/xpad-import.md for source and conflict rules.

1. Implement a parser only when the protocol is new.

New parsers go in `Sources/OpenJoystickDriverKit/Protocol/Parsers/` and must
conform to the `InputParser` protocol. Use `GIPParser.swift`, `Xbox360Parser.swift`,
and `DS4Parser.swift` as references.

1. Add tests.

Add parser, record, or report-format tests under `Tests/OpenJoystickDriverKitTests/`.
Hardware-only checks must be guarded or expressed as diagnostics so they can
skip cleanly without local device access.

1. Validate.

```bash
./scripts/ojd validate profiles
swift test
```

---

## Code rules

- **Swift 6.2 strict concurrency.** All warnings are errors. You must not use
  `nonisolated(unsafe)` unless it is required; justify it in a comment.
- **SwiftLint zero-suppression policy.** You must not add `// swiftlint:disable`.
  Fix the lint issue instead. Exception: `@objc` callbacks that cannot satisfy a
  rule; document the reason in a same-line comment.
- **Decimal JSON only.** You must use decimal integers for VID/PID, command codes,
  and all other numeric values. You must not use hex numbers in JSON.
- **Logging.** Prefer the existing lightweight `print`-style diagnostics. You
  must not add a new logging dependency without repo-wide justification.
- **Fault isolation.** One parser error must not affect other controllers. You
  must log and skip parser errors; you must not propagate them upward.
- **macOS 10.15 runtime target.** Avoid broad availability rewrites unless the
  touched API requires it.

---

## Pull requests

- One logical change per PR.
- If you're adding a controller you own, you must test it with real hardware and
  say so in the PR description.
- If you're adding a controller you do not own (based on specs or packet
  captures), you must say so.
- You must describe what you tested. Example: "I pressed every button and checked
  output with `--headless run`."

There's no formal PR template. Just be clear about what changed and why.

---

## Project layout

```text
Sources/OpenJoystickDriverKit/     Shared parsers, device management, output, and application-service RPC
Sources/OpenJoystickDriver/        Menu app, application service, and headless CLI
Tests/OpenJoystickDriverKitTests/  Unit tests that do not require hardware
Resources/Schemas/                 Canonical record and override schemas
Resources/ControllerOverrides/     Source omissions and evidence-backed corrections
ControllerSources.lock.json        Pinned upstream revisions and hashes
docs/user/compatibility.md         Consumer-visible compatibility mappings
scripts/                           Build, signing, installation, and release tools
```

The main process owns live controller state. Headless commands use the authenticated,
bounded RPC types under `Sources/OpenJoystickDriverKit/ApplicationService/`. Add shared
payloads there and route operations through `ApplicationServiceServer`.
