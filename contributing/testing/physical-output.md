# Test Physical Output

OpenJoystickDriver generates manual test instructions from a connected controller's reported output capabilities, not proof of a hardware pass.

## Generate A Plan

List connected devices. Then request a plan with a decimal VID and PID:

```bash
vid=13623
pid=4112
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller \
  output list
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller \
  output plan "$vid" "$pid"
```

The variables use the GameSir G7 SE decimal VID/PID as an example. Replace them with the decimal identifiers printed by `controller output list`. Each list entry also includes an opaque `device` identifier. VID/PID is enough when one matching controller is connected. If identical models are connected, append `--device <id>` to `plan` and every output command. Ambiguous commands are rejected; no arbitrary controller is selected.

The identifier is valid only for the current runtime session. Do not record it as hardware evidence.

The `controller output` CLI provides controls based on the device capabilities. `rumble`, `player`, `color`, and `brightness` each send one output command to the app, which decides support: a controller without the capability fails with the matching "has no ... implementation" message. `rumble` applies the channels the controller has and warns about each requested trigger motor it lacks (for example `--lt` on a DualShock 4), then exits successfully; when the controller has none of the requested channels, it fails with that message instead. The main motors are mirrored onto the Steam Controller trackpad haptics. With `--duration-ms` above 0, the command returns as soon as the app accepts it and the app stops the rumble when the duration ends; an all-zero request is a stop. Its `plan` command prints the same generated validation steps. A redacted support report includes plans for connected devices with implemented output capabilities.

## Output Command Request

The CLI and the GUI send each output through the app's `sendControllerOutput` application-service request. Its arguments select one connected controller and carry one command:

```json
{
  "vendorID": 1356,
  "productID": 2508,
  "runtimeIdentifier": null,
  "command": {
    "type": "set-rumble",
    "intensities": {
      "leftMain": 46260, "rightMain": 46260, "leftTrigger": 0,
      "rightTrigger": 0, "leftHaptic": 46260, "rightHaptic": 46260
    },
    "duration": {"milliseconds": 450}
  }
}
```

`type` is one of:

- `set-rumble`: `intensities` (each channel `0...65535`, a missing channel is off, and a key that names no channel fails the request) and `duration`, either `{"milliseconds": n}` with `n` in `0...5000` (any other `n` fails the request), or `"held"`.
- `stop-rumble`.
- `set-player-indicator`: `player` `0...4`, where `0` is off.
- `set-rgb`: `red`, `green`, and `blue`, each `0...255`.
- `set-light-brightness`: `brightness` `0...65535`.
- `set-adaptive-trigger`: `trigger` (`left` or `right`) and `effect` (`kind` `off` or `resistance`, `startPosition`, and `strength`, each `0...1`).

The reply is a result, for example `{"outcome": "delivered", "droppedRumbleChannels": ["leftHaptic", "rightHaptic"]}`. `outcome` is `delivered`, `not-found`, `unsupported-capability`, `not-ready`, `invalid-value`, `write-failed`, or `cancelled`. `invalid-value` reports a value that decodes but is out of range, such as an adaptive-trigger position above 1. A controller that lacks the capability is `unsupported-capability` before any value is checked. Malformed JSON, an unknown `type`, or a component outside its integer range fails the request itself instead of returning a result.

`droppedRumbleChannels` lists the requested channels the controller lacks, which were not driven. The CLI and the GUI mirror the main motors onto the Steam Controller trackpad haptics, so their requests list `leftHaptic` and `rightHaptic` as dropped on other controllers and the main motors as dropped on a Steam Controller. A rumble command is `unsupported-capability` only when the controller has no rumble channel at all.

## Record Results

Run one step at a time. Record pass or fail, the controller model, connection type, and relevant firmware version. If output behaves unexpectedly, stop and disconnect the controller. One passing step does not verify another actuator or lighting feature.

For controllers with conventional rumble capabilities, the interactive Just recipe runs each exposed four-channel position in a fixed order, waits out each step's duration, and sends an explicit all-zero stop between steps and when interrupted:

```bash
just diagnose-rumble-motors 13623 4112 160 500
```

The example uses decimal VID `13623`, PID `4112`, intensity `160`, and a 500 ms duration. Replace the first two values with the connected device's decimal IDs. Report each numbered result as left trigger, right trigger, left grip, right grip, none, or another exact observation. The recipe is a convenience around the installed app's canonical `controller output rumble` command; it does not change the documented support status automatically.

The generated plan excludes serial values, HID locations, packet payloads, and filesystem paths. Review any free-form issue text or attachments separately before publishing them. The command reports implemented capabilities, not a machine-authored verification level; accepted observations remain in the matching testing document and issue history.
