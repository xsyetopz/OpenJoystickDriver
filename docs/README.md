# Documentation

Open the section that matches the work. Archived upstream material stays under `external/`.

## Use the app

- [Choose a compatibility mode](user/compatibility.md)
- [Set up or repair permissions](user/permissions.md)
- [Understand Generic HID fallback](user/generic-hid.md)

## Test hardware

- [Test physical output](testing/physical-output.md)
- [Test a controller record without a signed installation](testing/controller-record.md)
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
- Generated DriverKit relay: run `./scripts/ojd driverkit generate` or
  `./scripts/ojd validate driverkit`; `./scripts/ojd help` is the supported
  command index.
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
