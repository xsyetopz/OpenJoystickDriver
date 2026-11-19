# Flydigi Vader 4 Pro (Bluetooth)

This page covers the Flydigi Vader 4 Pro over Bluetooth Low Energy, where it says it's D7D7:0041 (firmware 6.9.5.5, seen on macOS 26.5). The dongle and wired modes use other IDs.

## Why the Record Exists

The pad says it's a gamepad (Generic Desktop GamePad usage), so OJD finds it. But OJD's general-purpose reader gets three things wrong:

- The right stick sits on `Z`/`Rz`, which the reader treats as triggers.
- The analog triggers sit on Simulation page 0x02 (Brake, Accelerator), which the reader doesn't read.
- The button numbers have gaps (1, 2, 4, 5, 7 to 15), so every button after the first gap shifts by one.

What the general reader reports without the record:

| Input | Reported as |
| --- | --- |
| Right stick | Triggers |
| LT, RT | Stick clicks |
| X | Y |
| Y | Left bumper |
| RB | Start |
| LB | Back |
| Select | Guide |
| Start | Nothing |
| Left-stick Y | Inverted |
| D-pad | Correct |

## Report Layout

Report ID 0x01, 15 bytes. At rest it reads `01 FF FF FF FF 00 00 00 00 00 00 00 00 00 00`.

| Offset | Contents |
| --- | --- |
| 1 | Left stick X, signed, 0x7F right |
| 2 | Left stick Y, signed, 0x80 up |
| 3 | Right stick X, signed, 0x7F right |
| 4 | Right stick Y, signed, 0x80 up |
| 9 | Low 4 bits: D-pad (hat), 1 is up, counting up clockwise; 0x10 A, 0x20 B, 0x40 X, 0x80 Y |
| 10 | 0x01 LB, 0x02 RB, 0x04 LT digital, 0x08 RT digital, 0x10 Select, 0x20 Start, 0x40 L3, 0x80 R3 |
| 11 | 0x01 C, 0x02 Z, 0x04 M1, 0x08 M2, 0x10 M3, 0x20 M4 |
| 12 | 0x80 Home |
| 13 | Left trigger, unsigned 0...255 |
| 14 | Right trigger, unsigned 0...255 |

Bytes 5 to 8 were 0x00 in every report seen. The on/off trigger bits in byte 10 come on top of the analog values; how far a trigger is pulled comes only from bytes 13 and 14.

Apps see C and Z as Auxiliary 1 and 2, and M1 to M4 as Left Paddle 1, Left Paddle 2, Right Paddle 1, Right Paddle 2. Not checked: which back button each paddle is (a tester has to name them), and the Vader 3 or Vader 3 Pro.

## Status

Captured reports confirm every control in the table. Not checked: input that apps see through a signed build and the virtual gamepad, reconnecting after sleep, rumble or any other output, and the 2.4 GHz dongle and wired IDs.

## Steps

1. Pair the controller over Bluetooth.
2. Check that OJD picks this record (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list
   ojd controller show D7D7:0041
   ```

   `show` reports the bundled protocol `VendorFlydigi`, and `ojd protocol list` shows source `Bundled`. A `VendorFlydigi.plist` installed with `ojd protocol install` replaces it.
3. Check each control:

   ```bash
   ojd controller watch D7D7:0041
   ```

4. Push the left stick fully up. Check that Y goes negative.
5. Move the right stick. Check that the triggers stay at rest.
6. Press each face button, bumper, stick click, Select, Start, and Home. Check that each name matches.
