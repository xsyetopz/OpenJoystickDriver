# NITHO MLT-KRMA-K Test Record

This page records the maintainer's test of the NITHO MLT-KRMA-K in each of its modes over Bluetooth, on its 2.4G receiver, and by cable.

## Test setup

- Controller: NITHO MLT-KRMA-K, Bluetooth firmware `1.0.0`.
- OpenJoystickDriver: `0.6.0-alpha.3+build.1.29.98.sha.9e18e7daad7a (1.29.98)`, `just install-dev`.
- macOS: 27.2 (26B123).
- Mac: MacBook Pro (`MacBookPro18,2`), Apple M1 Max.
- Capture: an `IOHIDManager` logger that printed every input report of each HID gamepad, with the OJD service running.

The slider on the back of the pad picks the mode. It has five positions, V3, M, X, S and 2.4G from left to right. The manual names X (Bluetooth, "Xbox Wireless Controller"), 2.4G (USB receiver), S (Switch), M (MFi, Bluetooth, "DUALSHOCK 4 Wireless Controller") and V3 (Bluetooth HID, "G6"). By cable, the pad takes the identity of the slider position. The receiver reads the pad only with the slider on 2.4G: with the slider on M, X, S or V3 and the receiver plugged in, the light flashed purple, cyan, green or red, and no input came.

| Mode | VID:PID | Product string | OJD protocol | Tested |
| --- | --- | --- | --- | --- |
| M, Bluetooth | `054C:05C4` | `DUALSHOCK 4 Wireless Controller` | `sony-dual-shock4:bluetooth-classic` | Every control |
| M by cable, Bluetooth off | `054C:05C4` | `Wireless Controller` | `sony-dual-shock4:usb` | Every control |
| 2.4G receiver | `045E:028E` | `Xbox360 For Windows`, vendor `shanwan` | `hid-descriptor` | Every control |
| 2.4G by cable | `045E:028E` | `Xbox360 For Windows`, vendor `shanwan` | `hid-descriptor` | Every control |
| X by cable | `045E:028E` | `Xbox360 For Windows`, vendor `shanwan` | `hid-descriptor` | Every control |
| X by cable, once | `054C:0268` | PS3, manufacturer `Sony Computer Entertainment` | Sixaxis, mode `nitho` | Face buttons, before the `nitho` mode |
| V3 by cable | `2563:0526` | `Android GamePad`, manufacturer `shanwan` | `hid-descriptor`, mode `nitho` | Every control |
| S by cable | `057E:2009` | `Pro Controller` | `nintendo-switch1:usb` | Every control; A, B, X and Y read by position |
| S, Bluetooth | `057E:2009` | `Pro Controller` | `nintendo-switch1:bluetooth-classic` | Every control; A, B, X and Y read by position |
| V3, Bluetooth LE | `1949:0402` | `BSP-G6S` | `hid-report-layout`, mode `v3` | Every control it sends |
| V3 started with X held, Bluetooth LE | `1949:0402` | `BSP-G6S-HID` | `hid-descriptor` | Every control but Home |
| 2.4G without the receiver, Bluetooth LE | `1949:0402` | `BSP-G6S-HID` | `hid-descriptor` | Every control but Home |
| X, Bluetooth | `1949:0402` | `BSP-G6S` | `hid-report-layout`, mode `v3` | As V3 |

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

macOS binds its Xbox 360 driver to the receiver. That driver publishes a HID descriptor with no hat switch, the D-pad on buttons 12 to 15, Z and Rz as the triggers, and Y up as positive. OJD's `hid-descriptor` protocol has a shape for that descriptor. macOS drives rumble: a Game Controller haptics engine ran the left and the right motor one at a time, and `ojd controller rumble` reports no motor because macOS owns the output. The 20-byte report is the pad's Xbox 360 report:

| Byte | Contents |
| --- | --- |
| 2 | Up `0x01`, down `0x02`, left `0x04`, right `0x08`, Menu `0x10`, View `0x20`, L3 `0x40`, R3 `0x80` |
| 3 | LB `0x01`, RB `0x02`, Home `0x04`, A `0x10`, B `0x20`, X `0x40`, Y `0x80` |
| 4, 5 | LT and RT, `0x00` to `0xFF` |
| 6-13 | Left X, left Y, right X, right Y, signed 16-bit little-endian |

## V3 Mode over Bluetooth LE

In V3 the pad is a Bluetooth LE multi-touch digitizer (HID page `0x0D`, usage `0x04`) for a phone app that maps screen taps to game controls. Each control taps a fixed place, and each stick drags a contact from a fixed center. The light is solid red. Report 1 is 18 bytes: four contact slots of 4 bytes from byte 1, then the contact count in byte 17.

| Slot byte | Contents |
| --- | --- |
| 0 | Tip `0x01`, in range `0x02`, contact ID in the high nibble |
| 1, 2 | X, 12 bits little-endian, 0 to 3500 |
| 2, 3 | Y, the upper 4 bits of byte 2 then byte 3, 0 to 4095 |

The `1949:0402` record has a `v3` mode that matches the Bluetooth LE link and reads the contacts through a `touch` layout. A contact that starts within 150 of a stick center drags that stick until it lifts, with 800 from the left center and 280 from the right center as full deflection. Any other contact holds the nearest spot within 150. The table lists the spots, from a capture with one press every 2 seconds:

| Control | X, Y |
| --- | --- |
| A | 1069, 3834 |
| B | 291, 3435 |
| X | 340, 3792 |
| Y | 3386, 3917 |
| LB | 2401, 3184 |
| LT | 1698, 3849 |
| RT | 1762, 392 |
| L3 | 249, 1337 |
| R3 | 265, 2734 |
| D-pad up | 2184, 2730 |
| D-pad right | 447, 2358 |
| D-pad down | 1088, 2774 and 1351, 2060, two contacts |
| D-pad left | 447, 1821 |
| Left stick center | 875, 665; up is +X, right is +Y |
| Right stick center | 1782, 3222; up is +X, right is +Y |

`ojd controller watch` reported each control of the table. RB, View, Menu, Home, M1 and M2 send no contact in V3, and Y sends one 60 ms tap on press and another on release, so OJD reports North twice for one Y press; in one session LB did the same. The left stick drags its contact as far as the stick goes. The right stick sends a swipe: a held push moves the contact about 280 from the center, 21 at a time, and lifts it after about 0.6 s while the stick is still held. The record gives the right stick a travel of 280, so a swipe reads as full deflection until it lifts; a contact that goes further, as in a capture with the stick moved in circles, stays at full deflection. The triggers read as fully pulled or released. An Android app that moves the pad's tap places breaks this map. The `Manba One` gamepad shares `1949:0402` over USB and runs the record's default `HIDDescriptor` mode.

## M Mode by Cable

In M mode with Bluetooth off and a USB cable plugged in, the pad is `054C:05C4` `Wireless Controller` with a solid blue light. It sends DUALSHOCK 4 USB report `0x01` (64 bytes) about once a millisecond with the bytes of the [Bluetooth report](#m-mode-over-bluetooth) one place earlier, and the built-in DUALSHOCK 4 record reads it. The pad leaves the frame counter in byte 7 and the sensor timestamp in bytes 10 and 11 at zero, so OJD takes each report's arrival as its liveness. `ojd controller watch` reported every button by label, the D-pad, both analog triggers and each stick. M and M2 send no control of their own. A press of Home drops the pad off USB until it is plugged in again.

## V3 by Cable

With the slider on V3 and a USB cable plugged in, the pad is `2563:0526` `Android GamePad`, with a solid green light. Report 7 (11 bytes) holds X, Y, Z and Rz, a hat, 15 buttons, and Accelerator and Brake:

| Byte | Contents |
| --- | --- |
| 1-4 | Left X, left Y, right X, right Y, `0x80` at rest |
| 5 | Hat in the low nibble (`8` neutral) |
| 6 | Y `0x01`, B `0x02`, A `0x08`, X `0x10`, LB `0x40`, RB `0x80` |
| 7 | View `0x04`, Menu `0x08`, Home `0x10`, L3 `0x20`, R3 `0x40` |
| 8, 9 | RT (Accelerator) and LT (Brake), `0x00` to `0xFF` |

The SDL_GameControllerDB line for this ID maps buttons 1, 4 and 5 to A, X and Y and has no Home, which put A on West, X on North and Y on South. The `2563:0526` record's `nitho` mode maps the buttons by label, and `ojd controller watch` reported every control, with analog triggers. M1 and M2 send nothing. The mode matches the manufacturer `shanwan` and the product `Android GamePad`; another pad on `2563:0526` runs the default mode, which keeps the SDL layout. The pad's release is `0x0100`, as on the SDL line, so a ShanWan pad with the same strings and SDL's layout reads its face buttons rotated.

## X by Cable

With the slider on X and a USB cable plugged in, the pad was once `054C:0268` with a blue light and sends the Sixaxis USB report 1 (49 bytes). Its manufacturer is `Sony Computer Entertainment`; a DUALSHOCK 3 names `Sony`. Byte 3 holds the face buttons with A on Circle `0x20`, B on Cross `0x40`, X on Triangle `0x10` and Y on Square `0x80`, so the Sixaxis family read A as East, B as South, X as North and Y as West. The `054C:0268` patch has a `nitho` mode that matches the manufacturer and maps the four bits by label. The pad took this identity once, when the slider moved to X with the cable in. In the retest of the `nitho` mode it did not come back: moving the slider from V3 to X kept `2563:0526` with a green light, and a replug on X, or a move from S to X, gave `045E:028E` `Xbox360 For Windows` with a cyan light. The `nitho` mode is not tested on the pad.

In that cyan identity by cable the pad sends the same Xbox 360 report as through the [2.4G receiver](#24g-receiver), and `ojd controller watch` reported every button, the D-pad, both analog triggers and all four directions of each stick. With the slider on 2.4G by cable the pad takes the same identity and reads the same, with the triggers reaching 65535.

## BSP-G6S-HID over Bluetooth LE

With the slider on 2.4G and no receiver plugged in, or on V3 with X held while Home turns the pad on, the pad pairs over Bluetooth LE as `BSP-G6S-HID` (`1949:0402`), each time under a new address, so System Settings lists one more `BSP-G6S-HID`. The light is solid green on 2.4G and flashes green on V3. Its descriptor is a standard gamepad: report 3 is a 16-bit consumer key, and report 4 (11 bytes) holds X, Y, Z and Rz, a hat, 16 buttons, and Accelerator and Brake. The `1949:0402` record runs its default `HIDDescriptor` mode for it, because the `v3` mode matches the product `BSP-G6S` only. `ojd controller watch` reported every button by label, the D-pad, both analog triggers and each stick at full range. Home, M1 and M2 send no report, also to a plain IOHID client with the OJD service stopped. In an earlier session this identity connected and sent no input report.

## S Mode

With the slider on S, the pad is `057E:2009` `Pro Controller` by cable, with a solid green light, and over Bluetooth Classic. OJD's Switch Pro protocol reads it: every button, the D-pad and both sticks; LT and RT are on or off, as on a Pro Controller. The Pro Controller layout puts A on the right and B at the bottom, and OJD maps its buttons by position, so the pad's A reads as East, B as South, X as North and Y as West. The pad names its manufacturer `Nintendo Co., Ltd.`, its serial `000000000001` and its release `0x0200`, so no mode match tells it from a Nintendo Pro Controller. Over Bluetooth the first connect sent no report, and after the Mac slept the pad reconnected only through Connect in System Settings; then every control read, Home included.

## X Mode over Bluetooth

In X mode the pad shows up in a Bluetooth search as `Xbox Wireless Controller`. Connect in System Settings failed with no message, and `blueutil --pair` failed with a page timeout. Holding the pairing button in X made the pad pair as `BSP-G6S` with a solid red light, the [V3](#v3-mode-over-bluetooth-le) identity, and it read as V3.

## M1 and M2

The M1 and M2 buttons on the back sent no input in any mode, and the 2.4G capture shows no report bit other than the controls listed above. The manual describes them as macro buttons: hold SELECT and press M1 or M2 to record up to 12 presses. With no macro recorded, they do nothing.
