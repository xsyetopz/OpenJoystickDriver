# Documentation

## Use the app

- [Choose a compatibility mode](user/compatibility.md)
- [Set up or repair permissions](user/permissions.md)
- [Understand Generic HID fallback](user/generic-hid.md)

## Test hardware

- [Test physical output](testing/physical-output.md)
- [Probe macOS haptics backends](testing/haptics-backends.md)
- [Validate and test a controller record](testing/controller-record.md)
- [Check Logitech F310 mapping](testing/logitech-f310.md)
- [Check Microsoft Xbox One Controller (model 1537)](testing/xbox/1537.md)
- [Check Razer Wolverine V2](testing/razer/wolverine-v2.md)
- [Check Razer Wolverine V3 Tournament Edition](testing/razer/v3-te.md)
- [Check Nacon Revolution X Pro](testing/nacon-revolution-x.md)
- [Check Steam Controller input and output](testing/steam-controller.md)
- [Check an Xbox 360 wireless receiver](testing/xbox-360-wireless-receiver.md)
- [Capture Xbox Adaptive Joystick packets](testing/xbox-adaptive-joystick.md)
- [Run the macOS 10.15 compatibility kit](testing/catalina-testkit.md)

## Develop and diagnose

- [Architecture](development/architecture.md)
- [Apple controller ownership and transport evidence](development/apple-controller-ownership.md)
- [Source topology](development/source-topology.md)
- [Menu-bar and settings UI architecture](development/menu-bar-settings-architecture.md)
- Generated USB DriverKit extension: run `./scripts/ojd driverkit generate` or
  `./scripts/ojd check driverkit`.
- Repository command reference and supported command index: run `./scripts/ojd help`.
  Its output is catalog-backed, non-color, and keyboard-readable.
- [CLI and runtime coverage](development/cli-and-runtime.md)
- [Application service runtime health](development/application-service-health.md)
- [Application responsiveness](development/application-responsiveness.md)
- [Environment files](development/environment.md)
- [Obtain and configure signing assets](development/signing.md)
- [Implementation status](development/implementation-status.md)
- [Eight-issue and DriverKit audit](development/issue-audit.md)
- [Experimental controller status](development/experimental-controllers.md)
- [Physical output evidence](development/physical-output-evidence.md)
- [Import controller identities from Linux xpad](development/xpad-import.md)
- [Compatibility source notes](development/compatibility-sources.md)
- [Xbox fallback identity evidence](development/xbox-identities.md)

## Archived sources

- `external/OpenJoystickDriver/` contains GitHub issue snapshots.
- `external/sdl/` contains SDL issue and pull-request snapshots.

Archived files preserve upstream text and formatting. They are evidence, not project instructions.
