# Test Physical Output

OpenJoystickDriver generates manual test instructions from a connected controller's reported output capabilities, not proof of a hardware pass.

## Generate a Plan

List connected controllers. Then show one controller, whose Output checks section is the plan. `ojd` is the installed command-line tool ([install](../../wiki/Command-Line.md)):

```bash
ojd controller list
ojd controller show 3537:1010
```

The selector uses the GameSir G7 SE `VVVV:PPPP` as an example. Replace it with the hexadecimal vendor and product ID of the connected controller, or with the ID printed by `ojd controller list`. `VVVV:PPPP` is enough when one matching controller is connected. If identical models are connected, a `VVVV:PPPP` selector is rejected and the error lists them; use the ID from `ojd controller list` in `show` and every output command.

The ID is valid only for the current runtime session. Do not record it as hardware evidence.

The `controller` output commands depend on the device capabilities. `rumble`, `player`, and `light` each send one output command to the app, which decides support: a controller without the capability fails with a "has no ..." message that points at `ojd controller show`. `rumble` applies the channels the controller has and warns about each requested trigger motor it lacks (for example `--left-trigger` on a DualShock 4), then exits successfully; when the controller has none of the requested channels, it fails with that message instead. The main motors are mirrored onto the Steam Controller trackpad haptics. The command returns as soon as the app accepts it, and the app stops the rumble when `--duration` ends; an all-zero request is a stop. `ojd controller show` prints the same generated validation steps in its Output checks section. A redacted support report lists each connected device's output capabilities but not the generated steps.

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

The example uses decimal VID `13623`, PID `4112`, intensity `160`, and a 500 ms duration. Replace the first two values with the connected device's vendor and product IDs, in decimal or `0x` hexadecimal; the recipe converts them to a `VVVV:PPPP` selector. Report each numbered result as left trigger, right trigger, left grip, right grip, none, or another exact observation. The recipe is a convenience around the installed app's canonical `ojd controller rumble` command; it does not change the documented support status automatically.

The generated plan excludes serial values, HID locations, packet payloads, and filesystem paths. Review any free-form issue text or attachments separately before publishing them. The command reports implemented capabilities, not a machine-authored verification level; accepted observations remain in the matching testing document and issue history.
