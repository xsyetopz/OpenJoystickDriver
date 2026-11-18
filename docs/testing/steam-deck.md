# Test the Steam Deck Controller

Internal USB device 0x28de:0x1205. Family `ValveSteamDeck` selects `SteamDeckDriver`, following SDL `SDL_hidapi_steamdeck.c` and Linux `hid-steam.c` (`STEAM_QUIRK_DECK`). Not verified on hardware. Deck hardware only.

## Driver Behavior

- Reads the 64-byte report, type 0x09: buttons, D-pad, rear buttons, stick touch, triggers, sticks, trackpads with pressure, motion.
- At start: clears lizard-mode mappings; turns off trackpad mouse, haptic click, and the lizard-restoring watchdog.
- Feeds the watchdog every second, for firmware that ignores the setting (OJD choice; SDL: every 200 update passes).
- At stop: restores default mappings and settings.
- Rumble on both motors. No LED or trigger rumble.

## Checks

1. Run `ioreg -r -c IOHIDDevice -l -w0`. Paste each `28de` entry with parent `bInterfaceNumber` and `ReportDescriptor`.
2. Monitor, pressing each button once:

   ```bash
   swift run OpenJoystickDriverHIDTool --monitor --vid 0x28de --pid 0x1205 --seconds 30
   ```

3. Start OJD. In **Controllers**, select the controller, click **Open Input Test**. Check inputs move and trackpads stop moving the cursor.
4. Run OJD two minutes without Steam. Check the cursor stays still.
5. Quit OJD. Check trackpads move the cursor.
6. Lay the Deck flat, screen up; tilt the right edge down and hold. Paste motion from `ojd controller watch 28DE:1205` ([command-line tool](../../wiki/Command-Line.md)). Signs come from SDL only.
