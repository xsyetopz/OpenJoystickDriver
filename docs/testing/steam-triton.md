# Steam Controller (2026, Triton)

The 2026 Steam Controller talks a protocol that differs from the original Steam Controller. SDL lists it as `SteamControllerTriton`, and the catalog imports its rows from SDL's `controller_list.h` as `valve.steam-controller` records with the `triton` quirk. The quirk selects `SteamTritonDriver`.

| Identity | Link | Stored variant |
| --- | --- | --- |
| `28de:1302` | USB | `wired` |
| `28de:1303` | Bluetooth LE | `wired` |
| `28de:1304` | Proteus dongle | `dongle` |
| `28de:1305` | Nereid dongle | `dongle` |

The driver follows SDL `src/joystick/hidapi/SDL_hidapi_steam_triton.c` and `steam/controller_structs.h` at `release-3.4.16`. None of these identities is checked on hardware with OJD.

## HID Roles

- A dongle carries controllers on USB interfaces 2 to 5 only, as in SDL. Each interface is its own controller, and each one starts with no controller connected.
- The Bluetooth LE link has one HID service and no USB interface number, so that connection is the controller of its location.
- Over USB, the interface that declares a feature report is the controller, as for the original Steam Controller.

## Reports

| Report ID | Contents |
| --- | --- |
| `0x42` | State over USB and dongle: buttons, triggers, sticks, trackpads with pressure, raw IMU, 32-bit IMU timestamp in µs |
| `0x45` | State over Bluetooth LE, same layout as `0x42` |
| `0x47` | State with a trackpad timestamp first and a 16-bit IMU timestamp in units of 32 µs |
| `0x43` | Battery: charge state and level |
| `0x79`, `0x46` | Wireless status: 1 disconnected, 2 connected |

A dongle interface reports its controller as connected on a wireless status of 2 or on the first state report.

Button mapping follows SDL's output: the bit SDL names VIEW is Menu (Start), and the bit it names MENU is View (Back). QAM is `auxiliary1`, R4/R5 are `paddleRight1`/`paddleRight2`, and L4/L5 are `paddleLeft1`/`paddleLeft2`. Grip touch sensing is not mapped.

## Output

- Startup sends two 64-byte feature reports with report ID 1: lizard mode off (setting 9) and raw IMU on (setting 48, value `0x18`). Shutdown turns the IMU off. The firmware restores lizard mode by itself when the resends stop.
- The keep-alive runs every 40 ms. It sends lizard mode off every 3 s.
- Rumble is the 10-byte output report `0x80` (`MsgHapticRumble`). The left main motor sets the left speed, and the right main motor sets the right speed. The firmware stops a rumble it does not hear again, so the keep-alive repeats the report every 40 ms until the rumble stops.
- The driver claims no lighting or trigger rumble, as in SDL.

## Procedure

Connect the controller by USB, by Bluetooth, or through its dongle, then confirm the route (`ojd` is the [command-line tool](../../wiki/Command-Line.md), and `<controller>` is an ID from the list or its `VVVV:PPPP`):

```bash
ojd controller list
ojd controller show <controller>
```

`show` should report the protocol `valve.steam-controller`, and `ojd controller show <controller> --json` should list the quirk `triton`. Then watch the controls:

```bash
ojd controller watch <controller>
```

Check these points:

1. Push each stick fully right and fully up, and confirm positive X and negative Y.
1. Press every button, including QAM, the four rear buttons and both trackpads. Confirm that the reported control matches the button.
1. Touch each trackpad and confirm that the contact moves with your finger and reports pressure.
1. Rotate the controller and confirm motion samples.
1. Send a rumble for 2 s and confirm that it runs for the full 2 s and then stops.
1. Leave the controller idle for 10 s and confirm that it does not return to mouse (lizard) mode.
1. With the dongle, turn the controller off and on, and confirm that the controller disconnects and reconnects.

Report the result in a new issue with the VID:PID and the link.
