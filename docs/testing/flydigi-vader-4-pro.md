# Flydigi Vader 4 Pro (Bluetooth)

Bluetooth Low Energy identity D7D7:0041, firmware 6.9.5.5, observed on macOS 26.5. The dongle and wired modes use other identities.

## Why the Record Exists

The device advertises Generic Desktop GamePad usage, so discovery finds it. The generic parser fails on:

- Right stick on `Z`/`Rz`, which it maps to triggers.
- Analog triggers on Simulation page 0x02 (Brake, Accelerator), which it does not read.
- Non-contiguous button usages (1, 2, 4, 5, 7 to 15), which shift every index after the first gap.

Generic parser without the record:

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

Report ID 0x01, 15 bytes. Neutral: `01 FF FF FF FF 00 00 00 00 00 00 00 00 00 00`.

| Offset | Contents |
| --- | --- |
| 1 | Left stick X, signed, 0x7F right |
| 2 | Left stick Y, signed, 0x80 up |
| 3 | Right stick X, signed, 0x7F right |
| 4 | Right stick Y, signed, 0x80 up |
| 9 | Low nibble D-pad hat, 1 up increasing clockwise; 0x10 A, 0x20 B, 0x40 X, 0x80 Y |
| 10 | 0x01 LB, 0x02 RB, 0x04 LT digital, 0x08 RT digital, 0x10 Select, 0x20 Start, 0x40 L3, 0x80 R3 |
| 11 | 0x01 C, 0x02 Z, 0x04 M1, 0x08 M2, 0x10 M3, 0x20 M4 |
| 12 | 0x80 Home |
| 13 | Left trigger, unsigned 0...255 |
| 14 | Right trigger, unsigned 0...255 |

Bytes 5-8 were 0x00 in every observed report. Digital trigger bits in byte 10 add to the analog values; position comes only from bytes 13 and 14.

C and Z reach consumers as Auxiliary 1 and 2; M1 to M4 as Left Paddle 1, Left Paddle 2, Right Paddle 1, Right Paddle 2. Not verified: which back button each paddle is (a tester must name them); a Vader 3 or Vader 3 Pro.

## Status

Captured reports verify every control in the table. Not verified: consumer-visible input through a signed build and the virtual gamepad; reconnect after sleep; rumble or other physical output; the 2.4 GHz dongle and wired identities.

## Procedure

1. Pair the controller over Bluetooth.
2. Check the runtime selects this record (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list
   ojd controller show D7D7:0041
   ```

   `show` reports bundled protocol `VendorFlydigi`; `ojd protocol list` shows source `Bundled`. A `VendorFlydigi.plist` from `ojd protocol install` replaces it.
3. Check each control:

   ```bash
   ojd controller watch D7D7:0041
   ```

4. Push the left stick fully up. Check for negative Y.
5. Move the right stick. Check the triggers stay at rest.
6. Press each face button, bumper, stick click, Select, Start, Home. Check each name matches.
