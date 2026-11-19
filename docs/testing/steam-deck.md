# Test the Steam Deck Controller

The Steam Deck's built-in controls are a USB device inside it, 0x28de:0x1205. Its family, `ValveSteamDeck`, picks `SteamDeckDriver`, which follows SDL's `SDL_hidapi_steamdeck.c` and Linux's `hid-steam.c` (`STEAM_QUIRK_DECK`). Nobody has checked it on hardware yet. You need a Deck to test it.

## What the Driver Does

- Reads the 64-byte report of type 0x09: buttons, D-pad, back buttons, stick touch, triggers, sticks, trackpads with pressure, and motion.
- At start, it turns off "lizard mode", the Deck's built-in mouse and keyboard mode. It clears those mappings and turns off the trackpad mouse, the haptic click, and the watchdog that brings lizard mode back.
- Every second it tells the watchdog it's still there, in case the firmware ignores the setting. That timing is OJD's choice; SDL does it every 200 update passes.
- At stop, it puts the default mappings and settings back.
- Rumble works on both motors. No lights or trigger rumble.

## Checks

1. Run `ioreg -r -c IOHIDDevice -l -w0`. Paste each `28de` entry with its parent's `bInterfaceNumber` and its `ReportDescriptor`.
2. Watch the input while you press each button once:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1205 --seconds 30
   ```

3. Start OJD. In **Controllers**, select the controller and click **Open Input Test**. Check that inputs move and that the trackpads stop moving the pointer.
4. Run OJD for two minutes without Steam. Check that the pointer stays still.
5. Quit OJD. Check that the trackpads move the pointer again.
6. Lay the Deck flat, screen up. Tip the right edge down and hold it. Paste the motion from `ojd controller watch 28DE:1205` ([command-line tool](../../wiki/Command-Line.md)). The plus and minus signs come only from SDL, so say which way they point.
