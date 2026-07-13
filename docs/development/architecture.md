# Architecture

OpenJoystickDriver is a daemon-owned controller pipeline. The GUI and CLI are clients of the daemon; they do not own input capture, physical-controller output, or virtual-controller publication.

## Runtime Boundaries

```mermaid
flowchart LR
   A[Physical USB/HID device] --> B[DeviceManager]
   B --> C[DevicePipeline (one actor per controller)]
   C --> D[Protocol parser]
   D --> E[Optional protocol output capabilities]
   D --> F[Virtual output dispatcher]
   F --> G[DriverKit relay]
   F --> H[IOHIDUserDevice profile]
```

The pipeline boundary is per controller. One device failing to parse, reconnect, or send output must not take down another connected controller.

## Controller Records

The runtime loads one canonical record format from:

```text
Sources/OpenJoystickDriverKit/Resources/Controllers/<vid>/<vid>-<pid>.json
```

Records contain numeric matching identity, transport, protocol family/variant,
non-default flags or startup behavior, provenance, verification state, and only
necessary USB overrides. They never contain display names. USB and HID product
strings provide live names; unavailable strings use a numeric VID:PID fallback.

Shared endpoint defaults, packet layouts, startup sequences, parsers, timeouts,
and output policy belong to protocol code. Paths organize records but never
supply runtime behavior.

For raw USB devices, the runtime reads the active configuration descriptor through
the existing SwiftUSB device and selects the live interrupt interface/endpoints.
Explicit record overrides win; protocol defaults are used only when descriptor
discovery fails.

The committed runtime tree is deterministic generated output. Its inputs are:

```text
ControllerSources.lock.json
Resources/ControllerOverrides/<vid>/<vid>-<pid>.json
```

Use an add override for a device absent from pinned sources. Use a patch override
for an evidence-backed correction to an imported device. Generation rejects
conflicts, orphan patches, duplicate identities, redundant patches, unknown
source constructs, and source hash changes.

## Protocol Extensions

Input parsers convert raw reports into `ControllerEvent` values. Optional physical-controller output is modeled as explicit protocol capabilities, not as special cases in `DevicePipeline`.

Current capability surface:

- `PhysicalRumbleOutput`: source-controller rumble with `L`, `R`, `LT`, and `RT` byte values in the `0...255` range.

Current source-backed physical rumble implementations:

- GIP Xbox One / Series class controllers
- Xbox 360 wired controllers

If a protocol has no verified physical output path, it must not expose a live control in the app.

## Virtual Output

DriverKit and IOHIDUserDevice are separate output surfaces:

```text
DriverKit HID backend    -> private relay and fallback diagnostics
IOHIDUserDevice backend  -> consumer-facing user-space profiles
```

User-space compatibility profiles are first-class profiles, not hidden parser quirks:

- `sdl2-3`: OJD-owned SDL identity backed by an explicit SDL mapping
- `generic-hid`: OJD-owned descriptor-driven HID gamepad
- `x360-hid`: experimental Xbox 360 HID hardware-spoof profile
- `xone-hid`: experimental Xbox One HID hardware-spoof profile

The Microsoft-spoof profiles are HID compatibility surfaces. They are not Windows XInput or XUSB emulation on macOS.

## Extension Rules

To add or correct a controller:

1. Prefer a source importer and update ControllerSources.lock.json.
2. Add a minimal local add or patch override only when upstream data is missing
   or hardware evidence contradicts it.
3. Keep device differences in protocol flags, startup data, or USB overrides.
4. Add parser or report-format tests for new behavior.
5. Run the catalog regeneration, record validator, and relevant parser tests.

To add a protocol:

1. Add its parser and protocol defaults under Sources/OpenJoystickDriverKit/Protocol/.
2. Register the parser in ParserRegistry.
3. Extend controller.schema.json and both runtime/tooling validators.
4. Add focused parser and malformed-record tests.

To add a virtual output profile:

1. Add the VirtualDeviceProfile.
2. Add or update its HID descriptor and report format.
3. Add a CompatibilityOutputProfile only for a user-selectable surface.
4. Add a consumer mapping when the consumer requires one.

## Validation Contract

Source-level validation:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd validate profiles
./scripts/ojd validate scripts
./scripts/ojd validate swift-structure
./scripts/ojd test scripts
./scripts/ojd lint
./scripts/ojd test parsers-macos14
swift test
```

If SwiftPM reports the documented module-cache mismatch, run
`./scripts/ojd repair swiftpm-module-cache`, then rerun `swift test`.

Runtime validation for backend changes:

```bash
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./scripts/ojd diagnose sdl3 --seconds 10
```

DriverKit approval, TCC permissions, physical rumble, and real controller input remain hardware/runtime checks. CI cannot prove them end to end.

## Design Notes

Architecture background: `docs/development/compatibility-sources.md`.
