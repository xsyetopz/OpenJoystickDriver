# OpenJoystickDriver Architecture

OpenJoystickDriver is a daemon-owned controller pipeline. The GUI and CLI are
clients of the daemon; they do not own input capture, physical-controller output,
or virtual-controller publication.

## Runtime Boundaries

```text
Physical USB/HID/Bluetooth gamepad
  -> SDL3 Gamepad/HIDAPI
  -> DeviceManager
  -> SDL3GamepadSource per physical gamepad
  -> SDL3 canonical gamepad mapping
  -> virtual output dispatcher
  -> DriverKit relay or IOHIDUserDevice profile
```

SDL3 owns physical-controller enumeration, HIDAPI/libusb access, controller
database mapping, and physical rumble. OJD owns the daemon lifecycle,
foreground-output gate, canonical `ControllerEvent` boundary, and virtual output
surfaces. One device failing to open, reconnect, or send rumble must not take
down another connected controller.

## Controller Profiles

Controller profiles are retained as parser/catalog fixtures and compatibility
metadata, but the production physical input path is SDL3's Gamepad API. Bundled
legacy/controller-profile data lives in:

```text
Sources/OpenJoystickDriverKit/Resources/Controllers/
```

Device schemas live in:

```text
Resources/Schemas/Devices/
```

Do not add new production physical input support by patching one parser/profile
at a time. New real-controller support should land upstream in SDL3 or as an
SDL controller mapping when SDL already exposes the device.

For legacy/reference parser work, device-specific USB behavior must live in data:

- endpoint addresses
- `setConfiguration(1)` before claim
- post-handshake settle delay
- protocol variant
- mapping flags
- GIP startup packet sequence
- preferred virtual output backends

Legacy parser code must only carry behavior required by a protocol family.

## Legacy Protocol Parsers

Legacy input parsers convert raw reports into `ControllerEvent` values for
tests, capture tools, and source-backed reference behavior. They are not the
production path used by `DeviceManager`.

Current capability surface:

- `PhysicalRumbleOutput`: source-controller rumble with `L`, `R`, `LT`, and `RT`
  byte values in the `0...255` range.

Legacy source-backed physical rumble implementations:

- GIP Xbox One / Series class controllers
- Xbox 360 wired controllers

If a protocol has no verified physical output path, it must not expose a live
control in the app.

## Virtual Output

DriverKit and IOHIDUserDevice are separate output surfaces:

```text
DriverKit HID backend    -> private relay and fallback diagnostics
IOHIDUserDevice backend  -> consumer-facing user-space profiles
```

User-space compatibility profiles are first-class profiles, not hidden parser
quirks:

- `sdl2-3`: OJD-owned SDL identity backed by an explicit SDL mapping
- `generic-hid`: OJD-owned descriptor-driven HID gamepad
- `x360-hid`: experimental Xbox 360 HID hardware-spoof profile
- `xone-hid`: experimental Xbox One HID hardware-spoof profile

The Microsoft-spoof profiles are HID compatibility surfaces. They are not
Windows XInput or XUSB emulation on macOS.

## Extension Rules

To add production physical-controller support:

1. Confirm SDL3 exposes the device through `SDL_GetGamepads`.
2. Add or upstream an SDL controller mapping if SDL's canonical mapping is wrong.
3. Add OJD tests only for OJD's SDL3-to-`ControllerEvent` translation or virtual
   output behavior.
4. Do not add a new OJD raw-protocol backend for a single device.

To change a legacy/reference protocol parser:

1. Add a parser under `Sources/OpenJoystickDriverKit/Protocol/`.
2. Add any optional physical output capability under
   `Sources/OpenJoystickDriverKit/Protocol/Capabilities/`.
3. Register the parser in `ParserRegistry`.
4. Add controller profile schema support before adding device profiles that use
   the protocol.

To add a virtual output profile:

1. Add the `VirtualDeviceProfile`.
2. Add or update the HID descriptor/report format under
   `Sources/OpenJoystickDriverKit/Output/HID/`.
3. Add a `CompatibilityOutputProfile` entry only when it is a user-selectable
   compatibility surface.
4. Add a consumer mapping file when SDL or another consumer requires one.

## Validation Contract

Source-level validation:

```bash
swift build
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
```

Use Swift Testing only when the local toolchain can compile the package tests for
the intended deployment target. In the current Swift 6.2.4/Xcode 26 environment,
`_Testing_Foundation` requires macOS 26 while this project still needs macOS 14
parser-regression coverage.

Runtime validation for backend changes:

```bash
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./scripts/ojd diagnose sdl3 --seconds 10
```

DriverKit approval, TCC permissions, physical rumble, and real controller input
remain hardware/runtime checks. CI cannot prove them end to end.

## Design Notes

Architecture background: `docs/INPUT_COMPATIBILITY_SOURCE_STUDY.md`.
