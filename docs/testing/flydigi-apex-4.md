# Flydigi Apex 4 (DInput)

This page covers the Flydigi Apex 4 when it says it's 04B4:2412 (its DInput mode). The record is built from someone else's notes and isn't confirmed: nobody has replayed a capture against it. Card F4 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files to send.

## Modes

| Mode | Identity | Record |
| --- | --- | --- |
| DInput | 04B4:2412 | This record |
| XInput | 045E:028E, product name "Flydigi VADER3" | The Microsoft 045E:028E record. The Flydigi record doesn't apply here |

## Source

Section 9 of the protocol notes of [flydigi-space-station-mac][1] at commit `649b9f36cbba80deb7e7ac11309615d44f382a8e` (MIT; see [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) and [Compatibility Source Notes](../development/compatibility-sources.md)). The pad talks on a vendor HID interface on usage page 0xFFA0. It sends input report 4 and accepts output report 5.

## Report Layout

Input report 4 is 32 bytes, with the ID in byte 0, because the notes say IOHIDManager hands it over that way. OJD ignores other IDs and lengths. Byte 1 can't tell the pad's replies apart from input (`04 FF ...`, length 32).

| Offset | Contents |
| --- | --- |
| 7 | Bit 0 C (Auxiliary 1), bit 1 Z (Auxiliary 2), bits 2 to 5 M1 to M4 (Left Paddle 1, Left Paddle 2, Right Paddle 1, Right Paddle 2) |
| 8 | Bit 3 Home (Guide) |
| 9 | Bits 0 to 3 D-pad up, right, down, left; bit 4 A, bit 5 B, bit 6 Select (Back), bit 7 X |
| 10 | Bit 0 Y, bit 1 Start, bit 2 LB, bit 3 RB, bit 4 digital LT, bit 5 digital RT, bit 6 L3, bit 7 R3 |
| 17, 19 | Left stick X and Y, 0 to 255, center 0x7F, Y grows downward |
| 21, 22 | Right stick X and Y |
| 23, 24 | Left and right trigger, 0 to 255 |
| Not mapped | M5, M6 (byte 7, bits 6, 7); Fn/Menu, Turbo (byte 8, bits 0, 1); byte 8 bit 4 "Back" (the notes don't say how it differs from Select); motion bytes |

The paddle order is a guess until a tester names the buttons. OJD sends nothing to the pad: it has no rumble motors, and output report 5 carries settings the record doesn't write.

## Status

Not confirmed. The `HIDReportLayout` record attaches to every HID interface and reads only the 32-byte report 4. Tests replay reports built from this layout, not real captures. Not checked on hardware: the report length and ID, the stick and trigger ranges, every button bit, and which HID interface it attaches to.

## Steps

1. Put the pad in DInput mode.
2. Run these (`ojd` is the [command-line tool](../../wiki/Command-Line.md)):

   ```bash
   ojd controller list
   ojd controller show 04B4:2412
   ojd controller watch 04B4:2412
   ```

3. Check that `show` reports `HIDReportLayout`.
4. Press each control. Check that the name OJD shows matches the label on the pad.

[1]: https://github.com/uiltonlopes/flydigi-space-station-mac/blob/649b9f36cbba80deb7e7ac11309615d44f382a8e/docs/protocol.md
