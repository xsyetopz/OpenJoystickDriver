# Flydigi Vader 5 Pro 2.4 GHz Dongle

USB identity `37D7:2401`, the 2.4 GHz dongle of the Flydigi Vader 5 Pro. The record is source-derived and unverified: no tester capture of this dongle has replayed against it. Card F3 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files a tester sends.

## Modes

| Mode | Protocol | Record |
| --- | --- | --- |
| Default | `HIDReportLayout` on the dongle's HID interface | `Resources/Controllers/37d7/37d7-2401.plist`, the only mode |

The record has no second mode. A refused startup write shows as a startup failure of the controller, and no XUSB mode starts in its place.

## Source

The frames and offsets come from the openflydigi `PROTOCOL.md` at commit `11653507bbe4dc77f3c479c2a7aaebf25bbda995` (CC0; see [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) and [Compatibility Source Notes](../development/compatibility-sources.md)). The notes name the offsets only.

## Startup Writes

The record sends four output reports with ID 3 and 32 bytes when the dongle connects, in this order, each zero-padded after the frame:

| Command | Frame |
| --- | --- |
| 1 | `5A A5 01 02 03` |
| 0xA1 | `5A A5 A1 02 A3` |
| 2 | `5A A5 02 02 04` |
| test mode | `5A A5 11 07 FF 01 FF FF FF 15` |

A frame is `5A A5 cmd len payload sum`: `len` is the payload length plus 2 and `sum` is the low byte of cmd, len and payload. The UID read (command 4) is not sent. Whether the extended report starts without it is a card F3 question.

## Report Layout

The record reads the 32-byte extended report that starts `5A A5 EF`, taken as an unnumbered report with no report ID byte.

| Offset | Contents |
| --- | --- |
| 3 to 10 | Left stick X and Y, right stick X and Y, each a signed 16-bit little-endian value |
| 15, 16 | Left and right trigger, `0` to `255` |

Not mapped: the buttons (bytes 11 to 14; the sources name the offsets but not which bit is which control) and the motion sensor (gyro at 17 to 22, accelerometer at 23 to 28, 4096 = 1 g). The record declares no motion because no driver decodes it.

## Rumble

The record carries the grip rumble template of command 18: report ID 3, `5A A5 12 06`, then the left grip, right grip, left trigger and right trigger motor bytes at 5 to 8, with no checksum byte. `ojd controller rumble 37D7:2401 --left 128 --right 64` sends one frame. Trigger force (commands 81 and 82) is not sent.

## Status

Unverified. Not yet checked on hardware: the report ID, the stick axis order and Y direction, the trigger range, whether the writes start the report, and which button bit is which.
