# Test physical output

OpenJoystickDriver can generate a manual test plan from the exact output capabilities reported by a connected controller. The plan is an instruction set, not proof that the hardware passed.

## Generate a plan

List connected devices, then request a plan with decimal VID and PID:

```bash
OpenJoystickDriver --headless controller output list
OpenJoystickDriver --headless controller output plan <vid> <pid>
OpenJoystickDriver --headless controller output plan <vid> <pid> --json
```

Each list entry includes an opaque `device` identifier. VID/PID is sufficient
when one matching controller is connected. If identical models are connected,
append `--device <id>` to `plan` and every output command; ambiguous commands
are rejected rather than sent to an arbitrary controller. The identifier is
valid only for the current runtime session and should not be recorded as
hardware evidence.

The `controller output` CLI exposes capability-driven controls. Its `plan` command
prints the same generated validation steps. A redacted support report includes plans for connected devices with
implemented output capabilities.

## Record results

Run one step at a time and record pass or fail plus the controller model, connection type, and relevant firmware version. Stop and disconnect the controller if output behaves unexpectedly. Do not infer that a different actuator or lighting feature works from one passing step.

The generated plan excludes serial values, HID locations, packet payloads, and filesystem paths. Review any free-form issue text or attachments separately before publishing them.

## Evidence status

- `sourceBacked`: production code and upstream protocol sources support the command, but project hardware verification is not recorded.
- `hardwareVerified`: the project has accepted hardware evidence for the capability.
- `unavailable`: no implemented physical-output capability is exposed.

Generating or exporting a plan never changes evidence status. Maintainers must review the observed result before marking a capability hardware-verified.
