# Test Physical Output

Physical output is anything OJD makes the controller itself do, such as rumble, lights, and player numbers. Think of it as OJD talking back to the controller instead of only listening to it. OJD writes a list of test steps from what the connected controller says it can do. Following the steps by hand is a test; the list alone doesn't prove the hardware works.

## Get the Test Steps

List your controllers, then show one. Its Output checks section holds the steps. `ojd` is the [command-line tool](../../wiki/Command-Line.md):

```bash
ojd controller list
ojd controller show 3537:1010
```

3537:1010 is a GameSir G7 SE. Use your own controller instead. You can name it three ways:

| Name | Looks like | Lasts |
| --- | --- | --- |
| Vendor and product ID, in hexadecimal | `VVVV:PPPP` | Always, but only works when one controller has that ID |
| Session token, from `ojd controller list` | `E-…` | Until the controller disconnects |
| Port key, from `ojd controller list` | `U-…` | While the controller stays on the same port |

With two of the same model plugged in, OJD refuses `VVVV:PPPP` and lists both. Use the session token or port key then, in `show` and in every output command. Don't write either one down as hardware evidence, because they change.

`rumble`, `player`, and `light` each send one output command, and the app decides whether the controller can do it. A controller that can't fails with a "has no ..." message that points you to `ojd controller show`.

`rumble` uses only the motors the controller has:

- A trigger motor it lacks, such as `--left-trigger` on a DualShock 4, gives a warning and the rest still runs.
- If it has none of the motors you asked for, the command fails.
- On a Steam Controller, the main motors play on the trackpad haptics instead.
- The command returns as soon as the app accepts it. The app stops the rumble when `--duration` ends.
- A request with every value at zero means stop.

`ojd controller show` prints the same steps. A redacted support report lists what each device can output, but not the steps.

## What the Command Sends

The CLI and the app's windows send each output through the app's `sendControllerOutput` request. It picks one controller by session token, port key, or `VVVV:PPPP`, and carries one command:

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
| `set-rumble` | `intensities`: each channel 0...65535. A missing channel stays off; an unknown key fails the request. `duration`: `{"milliseconds": n}` with `n` from 0 to 5000 (any other `n` fails the request), or `"held"` |
| `stop-rumble` | None |
| `set-player-indicator` | `player` 0...4, where 0 is off |
| `set-rgb` | `red`, `green`, `blue`, each 0...255 |
| `set-light-brightness` | `brightness` 0...65535 |
| `set-adaptive-trigger` | `trigger` (Left or Right); `effect`: `kind` (Off or Resistance), `startPosition`, `strength`, each 0...1 |

The answer is a result, for example `{"outcome": "Delivered", "droppedRumbleChannels": ["leftHaptic", "rightHaptic"]}`:

| `outcome` | Meaning |
| --- | --- |
| Delivered, NotFound, NotReady, WriteFailed, Cancelled | What the name says |
| `InvalidValue` | The value reads fine but is too big or too small, such as an adaptive-trigger position above 1 |
| `UnsupportedCapability` | The controller can't do this. OJD says so before it checks any value |

Broken JSON, an unknown `type`, or a number outside its allowed range fails the request with no result.

`droppedRumbleChannels` lists the motors you asked for that the controller lacks, so OJD skipped them. The CLI and the app always ask for the Steam Controller trackpad haptics too. So on other controllers they list `leftHaptic` and `rightHaptic` as dropped, and on a Steam Controller they list the main motors. A rumble command is `unsupportedCapability` only when the controller has no rumble motor at all.

## Write Down the Results

Run one step at a time. For each, write down pass or fail, the model, how it's connected, and its firmware version. If something acts strange, stop and unplug the controller. A passing step only proves that one motor or light.

For normal rumble, use this interactive Just recipe. It tries each of the four motor positions in a fixed order, waits for each one to finish, and sends a stop between steps and when you press Control-C:

```bash
just diagnose-rumble-motors 13623 4112 160 500
```

Here the vendor ID is 13623, the product ID is 4112 (both in decimal), the strength is 160, and each buzz lasts 500 ms. Use your own IDs, in decimal or `0x` hexadecimal. For each numbered step, say where you felt it: left trigger, right trigger, left grip, right grip, none, or exactly what else happened. The recipe runs `ojd controller rumble` for you and doesn't change any support status in the docs.

The steps leave out serial numbers, HID locations, packet contents, and file paths. Still read your issue text and attachments before you post them. The command reports what OJD has built, not how well it's been tested. Accepted results go in the matching testing document and issue.
