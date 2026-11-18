# 8BitDo Ultimate 2

Every record is unverified: no Ultimate 2 capture exists. Checks T5 to T7 in [the tester cards](8bitdo-tester-checks.md) return it.

| Identity | VID:PID | Record |
| --- | --- | --- |
| Ultimate 2, DInput, cable or 2.4 GHz dongle | 2DC8:6012 | `HIDDescriptor`, one `default` mode |
| Ultimate 2 receiver | 2DC8:6013 | `idle` mode |
| Ultimate 2 dongle | 2DC8:3107 | `idle` mode |
| Ultimate 3-mode, Bluetooth, Xbox mode | 2DC8:901B | `HIDDescriptor`, one `default` mode |
| Ultimate 2 or Pro 3 | 2DC8:310B | `XboxXUSB`, wired; not named in the record |

## 6012 Record

Reuses the usage map of the [Ultimate 2C over Bluetooth](8bitdo-ultimate-2c.md): button usages 1, 2, 4, 5, 7, 8 and 11 to 15, left stick `X` and `Y`, right stick `Z` and `Rz`, triggers on Simulation page 0x02, hat. No source states the descriptor, so the map is assumed. One map serves cable and dongle; the cable capture decides if descriptors differ.

### Rear Buttons

None mapped. A capture would order them by position, upper first: `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1`, `RightPaddle2`. A paddle maps only when its usage is its own bit in a descriptor or capture. Usage numbers are unknown; T5 asks which each is.

### Gyro

None declared. DInput and Switch mode get gyro only when a capture shows motion fields an existing layout decodes.

## 6013 and 3107 Records

Both are `idle: NoControllerLinked`: OJD sends no data, creates no virtual gamepad, and reports `NoControllerLinked`. No protocol is sourced, so no controls map. Gamepad-input capture replaces `idle` with the descriptor's mode and usage map.

## 901B Record

Xbox Bluetooth button order:

- Usages 1 to 4: `South`, `East`, `West`, `North`
- Usages 5 and 6: shoulders
- Usages 7 and 8: `Back`, `Start`
- Usages 9 and 10: stick clicks
- Consumer `AC Home`: `Guide`
- Sticks: `X`, `Y`, `Z`, `Rz`
- Triggers: Simulation page 0x02, and the hat

No capture or descriptor exists, so the order is assumed. T8 returns the capture.

## 310B Record

One `XboxXUSB` wired mode, no product name field, since no source confirms which models present 310B. T7 returns the strings and `bcdDevice` deciding whether two modes are needed.

## Keep-Alive

Open question: does a pad leave the USB bus while served by OJD with no input? Research notes report a drop after about one second without host transfers. Not verified. Outcomes:

- No drop while served: no keep-alive (6012, 6013, 3107, 901B have none).
- A drop only when no reader runs: stated here, no change.
- A drop on a raw-USB pad served by OJD: the record gets a `session.keepAlive` with the measured interval and a packet test.
- A drop on a HID pad: a finding for a change to the HID session fields, since `HIDDescriptor` has no keep-alive field. OJD sends no periodic write.

T9 measures 310A and 6012.

## Further Reading

- [8BitDo Tester Checks](8bitdo-tester-checks.md)
- [8BitDo Ultimate 2C](8bitdo-ultimate-2c.md)
