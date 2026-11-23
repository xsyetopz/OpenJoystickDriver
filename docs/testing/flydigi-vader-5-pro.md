# Flydigi Vader 5 Pro 2.4 GHz Dongle

USB identity 37D7:2401 is the small 2.4 GHz wireless USB plug (dongle) that comes with the Flydigi Vader 5 Pro. The record is built from other projects' source code; no capture has been replayed against it. Card F3 in [Flydigi tester checks](flydigi-tester-checks.md) lists the hardware checks and files to send.

## Modes

| Mode | Protocol | Record |
| --- | --- | --- |
| Default | `HIDReportLayout` on the dongle's HID interface | `Resources/Controllers/37d7/37d7-2401.plist`, the only mode |

If the dongle refuses a startup write, OJD shows a startup failure. No XUSB mode takes over.

## Source

The frames and byte positions come from openflydigi's `PROTOCOL.md` at commit `11653507bbe4dc77f3c479c2a7aaebf25bbda995` (CC0; see [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) and [Compatibility Source Notes](../development/compatibility-sources.md)).

[OpenVader's input report](https://github.com/FilipVajgand/openvader/blob/v0.2.0/Sources/VaderKit/Model/InputState.swift) documents the button positions and positive-up Y axes. The [Vader 5 Pro remap driver's paddle table](https://github.com/Chillsmeit/vader5pro-remap-driver#steam-input-elite-recognition) identifies the physical side of each paddle.

## Startup Writes

When it connects, OJD sends four 32-byte output reports with ID 3, in this order. Each is filled with zeros after the frame:

| Command | Frame |
| --- | --- |
| 1 | `5A A5 01 02 03` |
| 0xA1 | `5A A5 A1 02 A3` |
| 2 | `5A A5 02 02 04` |
| test mode | `5A A5 11 07 FF 01 FF FF FF 15` |

A frame is `5A A5 cmd len payload sum`. `len` is the payload length plus 2, and `sum` is the low byte of cmd, len, and payload added up. OJD doesn't send the UID read (command 4); card F3 asks whether the extended report starts without it.

## Report Layout

The 32-byte extended report starts with `5A A5 EF` and has no report ID byte.

| Byte | Contents |
| --- | --- |
| 3 to 10 | Left stick X and Y, right stick X and Y, each signed 16-bit little-endian. The layout inverts both Y axes to match OJD's positive-down convention. |
| 11 | D-pad up, right, down, left, A, B, View, X (bits 0 through 7) |
| 12 | Y, Menu, LB, RB (bits 0 through 3), L3, R3 (bits 6 and 7) |
| 13 | C, Z, M1, M2, M3, M4, LM, RM (bits 0 through 7) |
| 14 | Home (bit 3) |
| 15, 16 | Left and right trigger, 0 to 255 |
| 17 to 28 | Motion sensor data. Gyroscope at 17 to 22, accelerometer at 23 to 28 (4096 counts per g). |

M1 and M3 map to `LeftPaddle1` and `LeftPaddle2`. M2 and M4 map to `RightPaddle1` and `RightPaddle2`. C, Z, LM and RM map to `Auxiliary1` through `Auxiliary4`. The record leaves motion undecoded.

## Rumble

Command 18 is the grip rumble template: report ID 3 and `5A A5 12 06`, then motor bytes 5 to 8 for left grip, right grip, left trigger, right trigger. It has no checksum byte. `ojd controller rumble 37D7:2401 --left 128 --right 64` sends one frame. OJD doesn't send trigger force (commands 81 and 82).

## Status

Not checked on hardware: the full button and D-pad mapping, the axis signs, the trigger range and whether the writes start the report. The tests check the documented button bits, D-pad directions and axis signs with built reports. The owner of one pad saw A and forward movement work in a game with a local override.
