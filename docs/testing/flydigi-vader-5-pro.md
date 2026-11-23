# Flydigi Vader 5 Pro 2.4 GHz Dongle

USB identity 37D7:2401, the 2.4 GHz dongle of the Flydigi Vader 5 Pro. Card F3 in [Flydigi tester checks](flydigi-tester-checks.md) lists the hardware checks and files to send.

## Modes

| Mode | Protocol | Record |
| --- | --- | --- |
| Default | `HIDReportLayout` on the dongle's HID interface | `Resources/Controllers/37d7/37d7-2401.plist`, the only mode |

A refused startup write shows as a startup failure; no XUSB mode replaces it.

## Source

Frames and offsets come from the openflydigi `PROTOCOL.md` at commit `11653507bbe4dc77f3c479c2a7aaebf25bbda995` (CC0; see [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) and [Compatibility Source Notes](../development/compatibility-sources.md)).

[OpenVader's input report](https://github.com/FilipVajgand/openvader/blob/v0.2.0/Sources/VaderKit/Model/InputState.swift) documents the button positions and positive-up Y axes. The [Vader 5 Pro remap driver's paddle table](https://github.com/Chillsmeit/vader5pro-remap-driver#steam-input-elite-recognition) identifies the physical side of each paddle.

## Startup Writes

On connect the record sends four 32-byte output reports with ID 3, in order, each zero-padded after the frame:

| Command | Frame |
| --- | --- |
| 1 | `5A A5 01 02 03` |
| 0xA1 | `5A A5 A1 02 A3` |
| 2 | `5A A5 02 02 04` |
| test mode | `5A A5 11 07 FF 01 FF FF FF 15` |

A frame is `5A A5 cmd len payload sum`: `len` is payload length plus 2; `sum` is the low byte of cmd, len, and payload. The UID read (command 4) is not sent; F3 asks whether the extended report starts without it.

## Report Layout

The 32-byte extended report starts `5A A5 EF`, with no report ID byte.

| Offset | Contents |
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

The grip rumble template of command 18: report ID 3 and `5A A5 12 06`, then motor bytes 5 to 8 for left grip, right grip, left trigger, right trigger. No checksum byte. `ojd controller rumble 37D7:2401 --left 128 --right 64` sends one frame. Trigger force (commands 81 and 82) is not sent.

## Status

Hardware validation of the complete mapping is pending. The tests exercise the documented button bits, D-pad directions and axis signs with synthetic reports.
