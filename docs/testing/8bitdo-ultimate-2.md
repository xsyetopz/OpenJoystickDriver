# 8BitDo Ultimate 2

Every record on this page is unverified: no tester capture of an Ultimate 2 exists yet. The checks T5 to T7 in [the tester cards](8bitdo-tester-checks.md) return the captures.

| Identity | VID:PID | Record | Status |
| --- | --- | --- | --- |
| Ultimate 2, DInput, cable or 2.4 GHz dongle | `2DC8:6012` | `HIDDescriptor`, one `default` mode | Unverified |
| Ultimate 2 receiver | `2DC8:6013` | `idle` | Unverified |
| Ultimate 2 dongle | `2DC8:3107` | `idle` | Unverified |

## 6012

The record reuses the usage map of the Ultimate 2C over Bluetooth ([the 2C record](8bitdo-ultimate-2c.md)): button usages 1, 2, 4, 5, 7, 8 and 11 to 15, left stick on `X` and `Y`, right stick on `Z` and `Rz`, triggers on Simulation page `0x02`, and the hat. No source in the tree states the Ultimate 2 descriptor, so the map is a starting assumption.

One usage map serves the cable and the dongle. If the two descriptors disagree, the capture of the cable decides, and this page states the conflict.

### Rear Buttons

The record maps no rear button. A paddle control is mapped only when a descriptor or capture shows its usage as a bit that is separate from every other control, and the usage numbers of the Ultimate 2 rear buttons are not known. The tester card T5 asks which button each rear usage is.

### Gyro

The record declares no motion. The gyro in DInput and Switch mode gets a path only if a capture shows motion fields that an existing layout can decode.

## 6013 and 3107

Both identities are `idle`: OJD recognizes them, sends no data, creates no virtual gamepad and reports `IdleIdentity`. Nothing in the tree states a protocol for either, so the records map no controls instead of inventing a layout. A capture that shows gamepad input replaces `idle` with the descriptor's mode and usage map.
