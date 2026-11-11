# 8BitDo Ultimate 2

Every record on this page is unverified: no tester capture of an Ultimate 2 exists yet. The checks T5 to T7 in [the tester cards](8bitdo-tester-checks.md) return the captures.

| Identity | VID:PID | Record | Status |
| --- | --- | --- | --- |
| Ultimate 2, DInput, cable or 2.4 GHz dongle | `2DC8:6012` | `HIDDescriptor`, one `default` mode | Unverified |
| Ultimate 2 receiver | `2DC8:6013` | `idle` mode | Unverified |
| Ultimate 2 dongle | `2DC8:3107` | `idle` mode | Unverified |
| Ultimate 3-mode, Bluetooth, Xbox mode | `2DC8:901B` | `HIDDescriptor`, one `default` mode | Unverified |
| Ultimate 2 or Pro 3 | `2DC8:310B` | `XboxXUSB`, wired | Unverified; not named in the record |

## 6012

The record reuses the usage map of the Ultimate 2C over Bluetooth ([the 2C record](8bitdo-ultimate-2c.md)): button usages 1, 2, 4, 5, 7, 8 and 11 to 15, left stick on `X` and `Y`, right stick on `Z` and `Rz`, triggers on Simulation page `0x02`, and the hat. No source in the tree states the Ultimate 2 descriptor, so the map is a starting assumption.

One usage map serves the cable and the dongle. If the two descriptors disagree, the capture of the cable decides, and this page states the conflict.

### Rear Buttons

The record maps no rear button. When a capture shows them, the order follows the physical position: the left pair is `LeftPaddle1` and `LeftPaddle2`, the right pair is `RightPaddle1` and `RightPaddle2`, upper button first. A paddle control is mapped only when a descriptor or capture shows its usage as a bit that is separate from every other control, and the usage numbers of the Ultimate 2 rear buttons are not known. The tester card T5 asks which button each rear usage is.

### Gyro

The record declares no motion. The gyro in DInput and Switch mode gets a path only if a capture shows motion fields that an existing layout can decode.

## 6013 and 3107

Both identities have a default mode with `idle: NoControllerLinked`: OJD recognizes them, sends no data, creates no virtual gamepad and reports `NoControllerLinked`. Nothing in the tree states a protocol for either, so the records map no controls instead of inventing a layout. A capture that shows gamepad input replaces the `idle` reason with the descriptor's mode and usage map.

## 901B

The record maps the Xbox Bluetooth button order: usages 1 to 4 on `South`, `East`, `West` and `North`, 5 and 6 on the shoulders, 7 and 8 on `Back` and `Start`, 9 and 10 on the stick clicks, the Consumer `AC Home` usage on `Guide`, the sticks on `X`, `Y`, `Z` and `Rz`, the triggers on Simulation page `0x02` and the hat. No capture or descriptor of this pad exists, so the order is an assumption; tester check T8 returns the capture.

## 310B

The record keeps one `XboxXUSB` wired mode. The record format has no product name field, and no source in the tree confirms which models present `310B`, so the record names none. Tester check T7 returns the strings and `bcdDevice` that decide whether two modes are needed.

## Keep-Alive

The question: does a pad leave the USB bus while OJD serves it and no input arrives? The research notes report a drop after about one second without host transfers; no source in the tree confirms it. The three outcomes:

- No drop while served: the record has no keep-alive. This is the current state of `6012`, `6013`, `3107` and `901B`.
- A drop only when no reader runs: this page states it, and OJD changes nothing.
- A drop while OJD serves a raw-USB pad: the record gets a `session.keepAlive` with the measured interval and a packet test. A `HIDDescriptor` mode has no keep-alive field, so a drop on a HID pad is a finding for a change to the HID session fields, and OJD sends no periodic write.

Tester check T9 measures `310A` and `6012`.
