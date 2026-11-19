# Flydigi Vader 5 Pro 2.4 GHz Dongle

USB identity 37D7:2401 is the small 2.4 GHz wireless USB plug (dongle) that comes with the Flydigi Vader 5 Pro. The record is built from someone else's source code and isn't confirmed: no capture has been replayed against it. Card F3 in [Flydigi tester checks](flydigi-tester-checks.md) lists the files to send.

## Modes

| Mode | Protocol | Record |
| --- | --- | --- |
| Default | `HIDReportLayout` on the dongle's HID interface | `Resources/Controllers/37d7/37d7-2401.plist`, the only mode |

If the dongle refuses a startup write, OJD shows a startup failure. No XUSB mode takes over.

## Source

The frames and byte positions come from openflydigi's `PROTOCOL.md` at commit `11653507bbe4dc77f3c479c2a7aaebf25bbda995` (CC0; see [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) and [Compatibility Source Notes](../development/compatibility-sources.md)).

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
| 3 to 10 | Left stick X and Y, right stick X and Y, each a signed 16-bit little-endian number |
| 15, 16 | Left and right trigger, 0 to 255 |
| Not mapped | Buttons (bytes 11 to 14; the source names the bytes but not which bit is which button); motion sensor (gyro 17 to 22, accelerometer 23 to 28, 4096 = 1 g) |

No driver reads motion, and the record lists none.

## Rumble

Command 18 is the grip rumble template: report ID 3 and `5A A5 12 06`, then motor bytes 5 to 8 for left grip, right grip, left trigger, right trigger. It has no checksum byte. `ojd controller rumble 37D7:2401 --left 128 --right 64` sends one frame. OJD doesn't send trigger force (commands 81 and 82).

## Status

Not checked on hardware: the report ID, the order of the stick axes and which way Y points, the trigger range, whether the writes start the report, and which button bit is which.
