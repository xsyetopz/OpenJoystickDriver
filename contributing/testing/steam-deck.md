# Test the Steam Deck Controller

The Steam Deck's built-in controller is `0x28de:0x1205`, an internal USB device. The `neptune` quirk selects `SteamDeckDriver`. The driver follows SDL `SDL_hidapi_steamdeck.c` and Linux `hid-steam.c` (`STEAM_QUIRK_DECK`). It is not hardware-verified. This path applies only when macOS runs on Deck hardware.

## What the Driver Does

- Reads the 64-byte state report with message type `0x09`: buttons, D-pad, rear buttons, stick touch, analog triggers, both sticks, both trackpads with pressure, and motion.
- At start, clears the lizard-mode mappings, turns off trackpad mouse and haptic click, and turns off the watchdog that restores lizard mode.
- Feeds the watchdog again every second, for firmware that ignores the watchdog setting. The one-second interval is an OJD choice. SDL feeds after 200 update passes.
- Restores the default mappings and settings at stop.
- Sends rumble to both motors. There is no LED and no trigger rumble.

## Checks

1. Run `ioreg -r -c IOHIDDevice -l -w0` and paste every `28de` entry with its parent `bInterfaceNumber` and `ReportDescriptor`.
1. Run the HID monitor and press each button once:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1205 --seconds 30
   ```

1. Start OJD. Check in Controller Settings Live that buttons, sticks, triggers and trackpads move, and that the trackpads stop moving the cursor.
1. Leave OJD running for two minutes without Steam. Check that the trackpads do not start to move the cursor again.
1. Quit OJD. Check that the trackpads move the cursor again.
1. Motion: lay the Deck flat, screen up, then tilt its right edge down and hold. Paste the motion values that `ojd controller watch 28DE:1205` prints (`ojd` is the [command-line tool](../../docs/command-line/using-the-command-line.md)). This checks the axis signs, which come from SDL only.
