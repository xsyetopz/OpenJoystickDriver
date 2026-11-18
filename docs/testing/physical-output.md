# Test Physical Output

OJD builds manual test steps from a connected controller's reported output capabilities. The steps do not prove a hardware pass.

## Generate a Plan

List the controllers, then show one. Its Output checks section is the plan. `ojd` is the [command-line tool](../../wiki/Command-Line.md):

```bash
ojd controller list
ojd controller show 3537:1010
```

3537:1010 is a GameSir G7 SE. Replace it with your controller's hexadecimal vendor and product ID, or the session token (`E-…`) or port key (`U-…`) from `ojd controller list`. `VVVV:PPPP` suffices with one matching controller. With identical models connected, OJD rejects a `VVVV:PPPP` selector and the error lists them; use the session token or port key in `show` and every output command.

The session token lasts until the controller disconnects; the port key lasts while it stays on the same port. Record neither as hardware evidence.

`rumble`, `player`, and `light` each send one output command; the app decides support. A controller lacking the capability fails with a "has no ..." message pointing at `ojd controller show`.

`rumble` applies the channels the controller has. Each requested trigger motor it lacks (for example `--left-trigger` on a DualShock 4) draws a warning, then success; with none of the requested channels it fails. Main motors mirror onto Steam Controller trackpad haptics. The command returns when the app accepts it; the app stops the rumble when `--duration` ends. An all-zero request is a stop.

`ojd controller show` prints the same steps. A redacted support report lists each device's output capabilities, not the steps.

## Output Command Request

The CLI and GUI send each output through the app's `sendControllerOutput` request, which selects one controller by session token, port key, or `VVVV:PPPP` and carries one command:

```json
{
  "controller": "054C:09CC",
  "command": {
    "type": "set-rumble",
    "intensities": {
      "lowFrequency": 46260, "highFrequency": 46260, "leftTrigger": 0,
      "rightTrigger": 0, "leftHaptic": 46260, "rightHaptic": 46260
    },
    "duration": {"milliseconds": 450}
  }
}
```

| `type` | Fields |
| --- | --- |
| `set-rumble` | `intensities`: each channel 0...65535, missing channel off, unknown key fails the request. `duration`: `{"milliseconds": n}` with `n` in 0...5000 (other `n` fails the request), or `"held"` |
| `stop-rumble` | None |
| `set-player-indicator` | `player` 0...4, 0 off |
| `set-rgb` | `red`, `green`, `blue`, each 0...255 |
| `set-light-brightness` | `brightness` 0...65535 |
| `set-adaptive-trigger` | `trigger` (Left or Right); `effect`: `kind` (Off or Resistance), `startPosition`, `strength`, each 0...1 |

The reply is a result, for example `{"outcome": "Delivered", "droppedRumbleChannels": ["leftHaptic", "rightHaptic"]}`:

| `outcome` | Meaning |
| --- | --- |
| Delivered, NotFound, NotReady, WriteFailed, Cancelled | As named |
| `InvalidValue` | A value that decodes but is out of range, such as an adaptive-trigger position above 1 |
| `UnsupportedCapability` | The controller lacks the capability, reported before any value is checked |

Malformed JSON, an unknown `type`, or a component outside its integer range fails the request instead of returning a result.

`droppedRumbleChannels` lists requested channels the controller lacks and OJD did not drive. Because the CLI and GUI mirror main motors onto Steam Controller trackpad haptics, their requests list `leftHaptic` and `rightHaptic` as dropped on other controllers, and the main motors on a Steam Controller. A rumble command is `unsupportedCapability` only when the controller has no rumble channel.

## Record Results

Run one step at a time. Record pass or fail, model, connection type, and firmware version. If output misbehaves, stop and disconnect the controller. One passing step verifies no other actuator or lighting feature.

For conventional rumble, use the interactive Just recipe. It runs each exposed four-channel position in fixed order, waits out each duration, and sends an all-zero stop between steps and on interrupt:

```bash
just diagnose-rumble-motors 13623 4112 160 500
```

Example: decimal VID 13623, PID 4112, intensity 160, 500 ms; use your IDs, decimal or `0x` hexadecimal. Report each numbered result as left trigger, right trigger, left grip, right grip, none, or another exact observation. The recipe wraps `ojd controller rumble` and changes no documented support status.

The plan excludes serial values, HID locations, packet payloads, and filesystem paths. Review issue text and attachments before publishing. The command reports implemented capabilities, not a verification level. Accepted observations stay in the matching testing document and issue.
