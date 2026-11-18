# Flydigi Vader 5 Pro 2.4 GHz Dongle

USB identity 37D7:2401, the 2.4 GHz dongle of the Flydigi Vader 5 Pro. The record comes from source code and is unverified: no capture replayed. Card F3 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files to send.

## Modes

| Mode | Protocol | Record |
| --- | --- | --- |
| Default | `HIDReportLayout` on the dongle's HID interface | `Resources/Controllers/37d7/37d7-2401.plist`, the only mode |

A refused startup write shows as a startup failure; no XUSB mode replaces it.

## Source

Frames and offsets come from the openflydigi `PROTOCOL.md` at commit `11653507bbe4dc77f3c479c2a7aaebf25bbda995` (CC0; see [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) and [Compatibility Source Notes](../development/compatibility-sources.md)).

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
| 3 to 10 | Left stick X and Y, right stick X and Y, each signed 16-bit little-endian |
| 15, 16 | Left and right trigger, 0 to 255 |
| Not mapped | Buttons (bytes 11 to 14; sources name the offsets but not which bit is which control); motion sensor (gyro 17 to 22, accelerometer 23 to 28, 4096 = 1 g) |

No driver decodes motion; the record declares none.

## Rumble

The grip rumble template of command 18: report ID 3 and `5A A5 12 06`, then motor bytes 5 to 8 for left grip, right grip, left trigger, right trigger. No checksum byte. `ojd controller rumble 37D7:2401 --left 128 --right 64` sends one frame. Trigger force (commands 81 and 82) is not sent.

## Status

Unverified on hardware: report ID, stick axis order and Y direction, trigger range, whether the writes start the report, which button bit is which.
