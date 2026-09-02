# Test physical output

OpenJoystickDriver can generate a manual test plan for a connected controller based on its reported output capabilities. The plan gives you test instructions. It does not prove that the hardware passed.

## Generate a plan

List connected devices. Then request a plan with a decimal VID and PID:

```bash
OpenJoystickDriver --headless controller output list
OpenJoystickDriver --headless controller output plan <vid> <pid>
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

For controllers with conventional rumble capabilities, the interactive Just
recipe runs each exposed four-channel position in a fixed order and sends an
explicit all-zero stop between steps and when interrupted:

```bash
just diagnose-rumble-motors <vid> <pid> [intensity] [duration_ms]
```

Report each numbered result as left trigger, right trigger, left grip, right
grip, none, or another exact observation. The recipe is a convenience around
the installed app's canonical `controller output rumble` command; it does not
change the documented support status automatically.

The generated plan excludes serial values, HID locations, packet payloads, and
filesystem paths. Review any free-form issue text or attachments separately
before publishing them. The command reports implemented capabilities, not a
machine-authored verification level; accepted observations remain in the
matching testing document and issue history.
