# Steam Controller (2026, Triton)

The 2026 Steam Controller uses its own protocol, listed in SDL as `SteamControllerTriton`. The catalog imports its rows from SDL's `controller_list.h` as `ValveSteamTriton` records, which select `SteamTritonDriver`.

| Identity | Link | Stored variant |
| --- | --- | --- |
| 28de:1302 | USB | `wired` |
| 28de:1303 | Bluetooth LE | `wired` |
| 28de:1304 | Proteus dongle | `dongle` |
| 28de:1305 | Nereid dongle | `dongle` |

Follows SDL `src/joystick/hidapi/SDL_hidapi_steam_triton.c` and `steam/controller_structs.h` at `release-3.4.16`. No identity is checked on hardware with OJD.

## HID Roles

- Dongle: controllers on USB interfaces 2 to 5 only, as in SDL. Each interface is its own controller, starting disconnected.
- Bluetooth LE: one HID service, no USB interface number; the connection is the controller.
- USB: the interface declaring a feature report is the controller.

## Reports

| Report ID | Contents |
| --- | --- |
| 0x42 | USB and dongle state: buttons, triggers, sticks, trackpads with pressure, raw IMU, 32-bit IMU timestamp in µs |
| 0x45 | Bluetooth LE state, same layout as 0x42 |
| 0x47 | State with trackpad timestamp first, 16-bit IMU timestamp in 32 µs units |
| 0x43 | Battery: charge state and level |
| 0x79, 0x46 | Wireless status: 1 disconnected, 2 connected |

A dongle interface connects on wireless status 2 or the first state report.

Buttons follow SDL. SDL's VIEW bit is Menu (Start); its MENU bit is View (Back). QAM is `auxiliary1`. R4/R5 are `paddleRight1`/`paddleRight2`; L4/L5 are `paddleLeft1`/`paddleLeft2`. Grip touch is unmapped.

## Output

- Startup sends two 64-byte feature reports with ID 1: lizard mode off (setting 9), raw IMU on (setting 48, value 0x18). Shutdown turns the IMU off. Firmware restores lizard mode when resends stop.
- Keep-alive every 40 ms; lizard mode off every 3 s.
- Rumble: 10-byte output report 0x80 (`MsgHapticRumble`), left main motor for left speed, right for right. Firmware stops a rumble not repeated, so keep-alive resends it every 40 ms until rumble stops.
- No lighting or trigger rumble, as in SDL.

## Procedure

1. Connect by USB, Bluetooth, or dongle.
2. Check the route (`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or `VVVV:PPPP`). `show` should report protocol ValveSteamTriton.

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. Check:
   1. Stick fully right, then fully up: positive X, negative Y.
   2. Every button matches, including QAM, four rear buttons, both trackpads.
   3. Each trackpad contact follows your finger and reports pressure.
   4. Rotation produces motion samples.
   5. A 2 s rumble runs 2 s, then stops.
   6. Idle 10 s: stays out of mouse (lizard) mode.
   7. Dongle: turn the controller off and on; it disconnects and reconnects.
5. Report in an issue with VID:PID and link.
