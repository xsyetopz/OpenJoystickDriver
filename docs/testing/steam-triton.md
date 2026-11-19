# Steam Controller (2026, Triton)

The 2026 Steam Controller speaks its own language (protocol), which SDL calls `SteamControllerTriton`. OJD's catalog imports its rows from SDL's `controller_list.h` as `ValveSteamTriton` records, and those pick `SteamTritonDriver`.

| Identity | Link | Stored variant |
| --- | --- | --- |
| 28de:1302 | USB | `wired` |
| 28de:1303 | Bluetooth LE | `wired` |
| 28de:1304 | Proteus dongle | `dongle` |
| 28de:1305 | Nereid dongle | `dongle` |

The driver follows SDL's `src/joystick/hidapi/SDL_hidapi_steam_triton.c` and `steam/controller_structs.h` at `release-3.4.16`. Nobody has checked any of these IDs on hardware with OJD.

## Which Part Is the Controller

- Dongle: only USB interfaces 2 to 5 hold controllers, as in SDL. Each interface is its own controller and starts out disconnected.
- Bluetooth LE: one HID service with no USB interface number. The connection itself is the controller.
- USB: the interface that declares a feature report is the controller.

## Reports

| Report ID | Contents |
| --- | --- |
| 0x42 | USB and dongle state: buttons, triggers, sticks, trackpads with pressure, raw motion sensor (IMU) data, 32-bit IMU timestamp in µs |
| 0x45 | Bluetooth LE state, same layout as 0x42 |
| 0x47 | State with trackpad timestamp first, 16-bit IMU timestamp in 32 µs units |
| 0x43 | Battery: charge state and level |
| 0x79, 0x46 | Wireless status: 1 disconnected, 2 connected |

A dongle interface counts as connected when it gets wireless status 2 or its first state report.

Buttons follow SDL, with two names swapped: SDL's VIEW bit is Menu (Start), and its MENU bit is View (Back). QAM is `auxiliary1`. R4 and R5 are `paddleRight1` and `paddleRight2`. L4 and L5 are `paddleLeft1` and `paddleLeft2`. Grip touch isn't mapped.

## Output

- At startup, OJD sends two 64-byte feature reports with ID 1. One turns off lizard mode (setting 9), the mode where the controller acts like a mouse and keyboard. The other turns on raw IMU data (setting 48, value 0x18). At shutdown, OJD turns the IMU off. The firmware turns lizard mode back on when OJD stops resending.
- OJD sends a keep-alive every 40 ms and turns lizard mode off again every 3 s.
- Rumble: 10-byte output report 0x80 (`MsgHapticRumble`). The left main motor gets the left speed, and the right one the right. The firmware stops a rumble that isn't repeated, so the keep-alive resends it every 40 ms until the rumble ends.
- No lights or trigger rumble, as in SDL.

## Steps

1. Connect by USB, Bluetooth, or dongle.
2. Check how OJD connected it (`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or `VVVV:PPPP`). `show` should report protocol ValveSteamTriton.

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. Check:
   1. Push a stick fully right, then fully up. Right should give a positive X, and up a negative Y.
   2. Every button matches, including QAM, the four rear buttons, and both trackpads.
   3. Each trackpad touch follows your finger and reports pressure.
   4. Turning the controller produces motion samples.
   5. A 2 s rumble runs for 2 s, then stops.
   6. Left alone for 10 s, it stays out of mouse (lizard) mode.
   7. Dongle only: turn the controller off and on. It disconnects and reconnects.
5. Report in an issue with the VID:PID and the kind of connection.
