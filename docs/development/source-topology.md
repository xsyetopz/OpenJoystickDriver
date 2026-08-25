# Source topology

OpenJoystickDriver uses capability directories and narrow SwiftPM module boundaries. Source and
test paths name durable owners; generated DriverKit output is never source.

## Package boundaries

```text
OpenJoystickDriverKit          controller domain, HID/USB ports, parsers, policy, shared RPC
OpenJoystickDriverUSB          IOUSBHost/USBDriverKit facade and restricted DEXT configuration
DriverKitGenerator             build-time generated native-project entry point
OpenJoystickDriver             app, runtime composition, CLI, presentation, platform adapters
OpenJoystickDriverHIDTool      internal hardware investigation executable
OpenJoystickDriverGameControllerProbe  isolated GameController visibility probe
```

Dependency direction:

```text
OpenJoystickDriverKit <- OpenJoystickDriverUSB <- DriverKitGenerator
OpenJoystickDriverKit <- OpenJoystickDriverUSB <- OpenJoystickDriver
OpenJoystickDriverKit <- OpenJoystickDriverHIDTool
```

Only `OpenJoystickDriverUSB` and `DriverKitGenerator` import SwifterKit. Kit owns stable Sendable
transport values and protocols; USBDriverKit/IOUSBHost/SwifterKit lifetimes stay in the USB wrapper.
The app owns one `ApplicationServiceRuntime` and authenticated RPC server.

## Capability ownership

```text
Sources/OpenJoystickDriverKit/
  ApplicationService/  shared client, RPC, payload, lifecycle, and remapping contracts
  Device/              controller identity, discovery, input state, USB port, and pipelines
  HID/                 availability-selected physical HID access
  Diagnostics/         support reports, probes, health, and packet logs
  Output/              availability-selected virtual HID, reports, formats, and profiles
  Permissions/         app permission policy
  Protocol/            catalog, GIP, parsers, and physical-output capabilities
  Remapping/           reusable profile and mapping engine

Sources/OpenJoystickDriver/
  App/Presentation/    AppKit lifecycle and SwiftUI user flows
  CLI/                 installed command grammar and command implementations
  Remapping/           persistence, routing, and CoreGraphics adaptation
  Runtime/             composition, authenticated RPC, foreground-consumer observation
  Status/              runtime and XboxUSBDevice system-extension status
```

Tests mirror their owners under `Tests/OpenJoystickDriverKitTests/`,
`Tests/OpenJoystickDriverUSBTests/`, and `Tests/OpenJoystickDriverTests/`.

## Rules

- Keep one canonical owner for each capability; do not retain aliases, forwarding files, or old
  entry points.
- Keep `OpenJoystickDriverKit` independent of SwifterKit and app/platform composition.
- Put IOUSBHost/DriverKit adaptation in `OpenJoystickDriverUSB`; keep parsing in Kit.
- Keep CoreHID calls behind macOS 15 availability and IOKit HID calls behind the macOS 10.15–14
  implementation boundary.
- Never edit or commit `.build/driverkit/generated/`; regenerate with
  `./scripts/ojd driverkit generate` and validate with `./scripts/ojd check driverkit`.
- Add source behavior tests, not source-text substring tests.
