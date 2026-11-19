# 8BitDo Ultimate 2

None of these records is confirmed, because nobody has captured an Ultimate 2 yet. Checks T5 to T7 in [the tester cards](8bitdo-tester-checks.md) ask for that capture.

| Identity | VID:PID | Record |
| --- | --- | --- |
| Ultimate 2, DInput, cable or 2.4 GHz dongle | 2DC8:6012 | `HIDDescriptor`, one `default` mode |
| Ultimate 2 receiver | 2DC8:6013 | `idle` mode |
| Ultimate 2 dongle | 2DC8:3107 | `idle` mode |
| Ultimate 3-mode, Bluetooth, Xbox mode | 2DC8:901B | `HIDDescriptor`, one `default` mode |
| Ultimate 2 or Pro 3 | 2DC8:310B | `XboxXUSB`, wired; not named in the record |

## 6012 Record

This record borrows the button and stick map of the [Ultimate 2C over Bluetooth](8bitdo-ultimate-2c.md): button usages 1, 2, 4, 5, 7, 8 and 11 to 15, left stick `X` and `Y`, right stick `Z` and `Rz`, triggers on Simulation page 0x02, and the hat. No source shows the descriptor, so the map is a guess. One map serves both cable and dongle. A cable capture will show whether their descriptors differ.

### Rear Buttons

None are mapped. Once a capture exists, they'd be ordered by position, top first: `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1`, `RightPaddle2`. A paddle gets mapped only when a descriptor or capture shows it has its own bit. Nobody knows their usage numbers yet; T5 asks for them.

### Gyro

None declared. DInput and Switch mode get gyro only when a capture shows motion fields that a layout OJD already has can read.

## 6013 and 3107 Records

Both are `idle: NoControllerLinked`. OJD sends no data, makes no virtual gamepad, and reports `NoControllerLinked`. No source describes their protocol, so no controls are mapped. A capture with gamepad input would let OJD swap `idle` for the descriptor's mode and button map.

## 901B Record

Xbox Bluetooth button order:

- Usages 1 to 4: `South`, `East`, `West`, `North`
- Usages 5 and 6: shoulders
- Usages 7 and 8: `Back`, `Start`
- Usages 9 and 10: stick clicks
- Consumer `AC Home`: `Guide`
- Sticks: `X`, `Y`, `Z`, `Rz`
- Triggers: Simulation page 0x02, and the hat

No capture or descriptor exists, so this order is a guess. T8 asks for the capture.

## 310B Record

One wired `XboxXUSB` mode with no product name field, because no source confirms which models say they're 310B. T7 asks for the name strings and `bcdDevice` that decide whether it needs two modes.

## Keep-Alive

A keep-alive is a small "still here" message sent on a timer. The open question: does a pad drop off USB while OJD serves it and nobody presses anything? Research notes say it drops after about one second when the Mac sends nothing. Nobody has confirmed that. What each answer would mean:

- No drop while OJD serves it: no keep-alive (6012, 6013, 3107, and 901B have none).
- A drop only when nothing is reading: write it down here, and change nothing.
- A drop on a raw USB pad that OJD serves: the record gets a `session.keepAlive` with the measured timing and a packet test.
- A drop on a HID pad: the HID session fields need a change, because `HIDDescriptor` has no keep-alive field. OJD sends no timed writes.

T9 measures 310A and 6012.

## Further Reading

- [8BitDo Tester Checks](8bitdo-tester-checks.md)
- [8BitDo Ultimate 2C](8bitdo-ultimate-2c.md)
