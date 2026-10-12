# Test The GameSir G7 Pro, Cyclone 2, And G7 Pro 8K PC

These records and packet encoders are source-backed, not hardware-verified.
Test the connected controller's exact identity; never infer one GameSir model
from another.

## Covered Identities

- G7 Pro configuration-ready USB: `3537:1003`, `105D`, `105E`, `109B`,
  `109C`, and `10BA`
- G7 Pro input-only modes: `3537:100A` and `1022`
- Cyclone 2 enhanced HID: `3537:0575`, `100B`, and `1053`
- G7 Pro 8K PC enhanced HID: `3537:10C5`, `10C6`, `10C7`, and `10C8`

`3537:1004` stays on the existing XUSB route because Linux identifies it as
T4 Kaleid and the White G7 Pro dongle report shares that identity. Existing
Linux-backed `3537:100F` and `1010` routes are also unchanged.

The wired GameSir K1 (`3537:1082`) is not decoded by the GameSir parser; see
[GameSir K1](gamesir-k1.md).

## Validate Records And Input

Run from the repository root:

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd test parsers-macos14
swift test --filter 'GameSirParserTests|GameSirCatalogTests'
```

For each available mode, record the exact VID/PID, product name, transport,
firmware, macOS version, and OJD commit. Verify face buttons, all eight D-pad
positions and neutral, both sticks, triggers, bumpers, View, Menu, stick
clicks, and every advertised extra. Confirm battery and charging changes.
Where motion is exposed, capture stationary and independently rotated samples.

Leave enhanced HID and configuration-ready USB modes connected for at least
30 seconds to verify the 500 ms heartbeat. Unplug and reconnect, then confirm
that no stale button, battery, lighting-slot, or sequence state survives.

## Validate Physical Output

Use the installed app's Input Test output controls. On Cyclone 2, confirm that
color applies one solid RGB value across controllable zones and brightness
changes the active slot. On G7 Pro 8K PC, confirm all four home-ring quadrants
change together and brightness spans the device's `0...100` register. On the
standard G7 Pro, test dock brightness only; RGB is not claimed. Enhanced HID
claims only the two documented main rumble motors.

`3537:100A` and `1022` must expose no configuration output. OJD does not issue
a mode-switch command. Use the controller's physical Menu+Share combination
before connecting when a configuration-ready mode is required.

Report every attempted output, the active lighting slot, observed result, and
any transfer error. Do not promote these paths to hardware-verified until the
matching identity passes input, heartbeat, reconnect, and each claimed output.
