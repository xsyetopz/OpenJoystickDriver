# Test physical output

OpenJoystickDriver can generate a manual test plan for a connected controller based on its reported output capabilities. The plan gives you test instructions. It does not prove that the hardware passed.

## Generate a plan

List connected devices. Then request a plan with a decimal VID and PID:

```bash
OpenJoystickDriver --headless controller output list
OpenJoystickDriver --headless controller output plan <vid> <pid>
OpenJoystickDriver --headless controller output plan <vid> <pid> --json
```

Each list entry includes an opaque `device` identifier. VID/PID is enough when
one matching controller is connected. If identical models are connected, append
`--device <id>` to `plan` and every output command. Ambiguous commands are
rejected instead of being sent to an arbitrary controller.

The identifier is valid only for the current runtime session. Do not record it
as hardware evidence.

The `controller output` CLI provides controls based on the device capabilities.
Its `plan` command prints the same generated validation steps. A redacted support
report includes plans for connected devices with implemented output
capabilities.

## Record results

Run one step at a time. Record pass or fail, the controller model, connection
type, and relevant firmware version. If output behaves unexpectedly, stop and
disconnect the controller. One passing step does not show that a different
actuator or lighting feature works.

The generated plan excludes serial values, HID locations, packet payloads, and
filesystem paths. Review any free-form issue text or attachments separately
before publishing them.

## Evidence status

- `sourceBacked`: production code and upstream protocol sources support the command, but project hardware verification is not recorded.
- `hardwareVerified`: the project has accepted hardware evidence for the capability.
- `unavailable`: no implemented physical-output capability is exposed.

Generating or exporting a plan never changes evidence status. Maintainers must review the observed result before marking a capability hardware-verified.
