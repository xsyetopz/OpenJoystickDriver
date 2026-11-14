# NITHO MLT-KRMA-K Test Record

This page records the maintainer's test of the NITHO MLT-KRMA-K in its MFi and 2.4G modes.

## Test setup

- Controller: NITHO MLT-KRMA-K, Bluetooth firmware `1.0.0`.
- OpenJoystickDriver: `0.6.0-alpha.3+build.1.29.98.sha.9e18e7daad7a (1.29.98)`, `just install-dev`.
- macOS: 27.2 (26B123).
- Mac: MacBook Pro (`MacBookPro18,2`), Apple M1 Max.
- Capture: an `IOHIDManager` logger that printed every input report of each HID gamepad, with the OJD service running.

The mode switch on the back of the pad picks the identity. The manual names X (Bluetooth, "Xbox Wireless Controller"), 2.4G (USB receiver), S (Switch), M (MFi, Bluetooth, "DUALSHOCK 4 Wireless Controller") and V3 (Bluetooth HID, "G6"). By cable, the pad takes the identity of the switch position.

| Mode | VID:PID | Product string | OJD protocol | Tested |
| --- | --- | --- | --- | --- |
| M, Bluetooth | `054C:05C4` | `DUALSHOCK 4 Wireless Controller` | `sony-dual-shock4:bluetooth-classic` | Every control |
| 2.4G receiver | `045E:028E` | `Xbox360 For Windows`, vendor `shanwan` | `hid-descriptor` | Every control |
| By cable | `054C:0268`, `054C:05C4`, `045E:028E` | PS3, `Wireless Controller`, `Xbox360 For Windows` | | Identity only |
| X, S, V3 | | | | Not tested |

## M Mode over Bluetooth

The pad sends DUALSHOCK 4 report `0x11` (78 bytes), and the built-in DUALSHOCK 4 record reads it. `ojd controller show` lists every control. macOS drives rumble and lighting.

| Byte | Contents |
| --- | --- |
| 3-6 | Left X, left Y, right X, right Y |
| 7 | Hat in the low nibble (`8` neutral, `0` up, `2` right, `4` down, `6` left); Square `0x10`, Cross `0x20`, Circle `0x40`, Triangle `0x80` |
| 8 | L1 `0x01`, R1 `0x02`, L2 `0x04`, R2 `0x08`, View `0x10`, Menu `0x20`, L3 `0x40`, R3 `0x80` |
| 9 | Home `0x01`; the upper bits count reports |
| 10, 11 | L2 and R2, `0x00` to `0xFF` |

## 2.4G Receiver

macOS binds its Xbox 360 driver to the receiver. That driver publishes a HID descriptor with no hat switch, the D-pad on buttons 12 to 15, Z and Rz as the triggers, and Y up as positive. OJD's `hid-descriptor` protocol has a shape for that descriptor. The 20-byte report is the pad's Xbox 360 report:

| Byte | Contents |
| --- | --- |
| 2 | Up `0x01`, down `0x02`, left `0x04`, right `0x08`, Menu `0x10`, View `0x20`, L3 `0x40`, R3 `0x80` |
| 3 | LB `0x01`, RB `0x02`, Home `0x04`, A `0x10`, B `0x20`, X `0x40`, Y `0x80` |
| 4, 5 | LT and RT, `0x00` to `0xFF` |
| 6-13 | Left X, left Y, right X, right Y, signed 16-bit little-endian |

## M1 and M2

The M1 and M2 buttons on the back sent no input in M mode, and the 2.4G capture shows no report bit other than the controls listed above. The manual describes them as macro buttons: hold SELECT and press M1 or M2 to record up to 12 presses. With no macro recorded, they do nothing.
