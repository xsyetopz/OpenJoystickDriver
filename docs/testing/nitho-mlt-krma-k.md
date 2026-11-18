# NITHO MLT-KRMA-K Test Record

## Contents

- [Test Setup](#test-setup)
- [M Mode over Bluetooth](#m-mode-over-bluetooth)
- [2.4G Receiver](#24g-receiver)
- [V3 Mode over Bluetooth LE](#v3-mode-over-bluetooth-le)
- [M Mode by Cable](#m-mode-by-cable)
- [V3 by Cable](#v3-by-cable)
- [X by Cable](#x-by-cable)
- [BSP-G6S-HID over Bluetooth LE](#bsp-g6s-hid-over-bluetooth-le)
- [S Mode](#s-mode)
- [X Mode over Bluetooth](#x-mode-over-bluetooth)
- [M1, M2, and T](#m1-m2-and-t)

## Test Setup

| Item | Value |
| --- | --- |
| Controller | NITHO MLT-KRMA-K, Bluetooth firmware `1.0.0` |
| OpenJoystickDriver | `0.6.0-alpha.3+build.1.29.98.sha.9e18e7daad7a (1.29.98)`, `just install-dev` |
| macOS | 27.2 (26B123) |
| Mac | MacBook Pro `MacBookPro18,2`, Apple M1 Max |
| Capture | `IOHIDManager` logger printing every input report of each HID gamepad, OJD service running |

The back slider picks the mode:

| Slider, left to right | Manual name |
| --- | --- |
| V3 | Bluetooth HID, "G6" |
| M | MFi, Bluetooth, "DUALSHOCK 4 Wireless Controller" |
| X | Bluetooth, "Xbox Wireless Controller" |
| S | Switch |
| 2.4G | USB receiver |

By cable the pad takes the identity of the slider position. The receiver reads the pad only on 2.4G: with the slider on M, X, S, or V3 and the receiver plugged in, the light flashed purple, cyan, green, or red and no input came. By cable the light flashes slowly while charging (as the manual says); input still arrives.

| Mode | VID:PID | Product string | OJD protocol | Tested |
| --- | --- | --- | --- | --- |
| M, Bluetooth | 054C:05C4 | DUALSHOCK 4 Wireless Controller | `sony-dual-shock4:bluetooth-classic` | Every control |
| M by cable, Bluetooth off | 054C:05C4 | Wireless Controller | `sony-dual-shock4:usb` | Every control |
| 2.4G receiver | 045E:028E | Xbox360 For Windows, vendor shanwan | hid-descriptor | Every control |
| 2.4G by cable | 045E:028E | Xbox360 For Windows, vendor shanwan | hid-descriptor | Every control |
| X by cable | 045E:028E | Xbox360 For Windows, vendor shanwan | hid-descriptor | Every control |
| X by cable, once | 054C:0268 | PS3, manufacturer Sony Computer Entertainment | Sixaxis, mode nitho | Face buttons, before the nitho mode |
| V3 by cable | 2563:0526 | Android GamePad, manufacturer shanwan | hid-descriptor, mode nitho | Every control |
| S by cable | 057E:2009 | Pro Controller | `nintendo-switch1:usb` | Every control; A, B, X and Y read by position |
| S, Bluetooth | 057E:2009 | Pro Controller | `nintendo-switch1:bluetooth-classic` | Every control; A, B, X and Y read by position |
| V3, Bluetooth LE | 1949:0402 | BSP-G6S | hid-report-layout, mode v3 | Every control it sends |
| V3 started with X held, Bluetooth LE | 1949:0402 | BSP-G6S-HID | hid-descriptor | Every control but Home |
| 2.4G without the receiver, Bluetooth LE | 1949:0402 | BSP-G6S-HID | hid-descriptor | Every control but Home |
| X, Bluetooth | 1949:0402 | BSP-G6S | hid-report-layout, mode v3 | As V3 |

## M Mode over Bluetooth

DUALSHOCK 4 report `0x11` (78 bytes), read by the built-in DUALSHOCK 4 record. macOS drives rumble and lighting.

| Byte | Contents |
| --- | --- |
| 3-6 | Left X, left Y, right X, right Y |
| 7 | Hat in the low nibble (`8` neutral, `0` up, `2` right, `4` down, `6` left); Square `0x10`, Cross `0x20`, Circle `0x40`, Triangle `0x80` |
| 8 | L1 `0x01`, R1 `0x02`, L2 `0x04`, R2 `0x08`, View `0x10`, Menu `0x20`, L3 `0x40`, R3 `0x80` |
| 9 | Home `0x01`; the upper bits count reports |
| 10, 11 | L2 and R2, `0x00` to `0xFF` |

## 2.4G Receiver

macOS binds its Xbox 360 driver to the receiver. The HID descriptor has no hat, D-pad on buttons 12 to 15, Z and Rz as triggers, Y up positive; OJD's hid-descriptor protocol has a shape for it. macOS owns the output: a Game Controller haptics engine ran the left and right motor one at a time, and `ojd controller rumble` reports no motor. The 20-byte report is the pad's Xbox 360 report:

| Byte | Contents |
| --- | --- |
| 2 | Up `0x01`, down `0x02`, left `0x04`, right `0x08`, Menu `0x10`, View `0x20`, L3 `0x40`, R3 `0x80` |
| 3 | LB `0x01`, RB `0x02`, Home `0x04`, A `0x10`, B `0x20`, X `0x40`, Y `0x80` |
| 4, 5 | LT and RT, `0x00` to `0xFF` |
| 6-13 | Left X, left Y, right X, right Y, signed 16-bit little-endian |

## V3 Mode over Bluetooth LE

V3 is a Bluetooth LE multi-touch digitizer (HID page `0x0D`, usage `0x04`) for a phone app: each control taps a fixed place, each stick drags a contact from a fixed center. Light solid red. Report 1: 18 bytes: four 4-byte contact slots from byte 1, contact count in byte 17.

| Slot byte | Contents |
| --- | --- |
| 0 | Tip `0x01`, in range `0x02`, contact ID in the high nibble |
| 1, 2 | X, 12 bits little-endian, 0 to 3500 |
| 2, 3 | Y, the upper 4 bits of byte 2 then byte 3, 0 to 4095 |

The 1949:0402 record's v3 mode matches the Bluetooth LE link and reads contacts via a touch layout. A contact starting within 150 of a stick center drags that stick until it lifts; full deflection is 800 from the left center, 280 from the right. Any other contact holds the nearest spot within 150. Spots from one press every 2 seconds:

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

Observed with `ojd controller watch`:

| Control | Behavior |
| --- | --- |
| RB, View, Menu, Home, M1, M2 | no contact |
| Y | 60 ms tap on press and on release, so OJD reports North twice per press; LB did the same in one session |
| Left stick | drags its contact as far as the stick goes |
| Right stick | a held push moves the contact about 280 from center, 21 at a time, and lifts it after about 0.6 s; the record gives it a travel of 280, so a swipe reads as full deflection until it lifts; a contact going further (a capture with circles) stays at full deflection |
| Triggers | fully pulled or released |

An Android app that moves the tap places breaks this map. The Manba One gamepad shares 1949:0402 over USB and runs the default HIDDescriptor mode.

## M Mode by Cable

With Bluetooth off and a USB cable in, the pad is 054C:05C4 Wireless Controller. It sends DUALSHOCK 4 USB report `0x01` (64 bytes) about once a millisecond, the [Bluetooth report](#m-mode-over-bluetooth) bytes one place earlier, read by the built-in DUALSHOCK 4 record. Frame counter (byte 7) and sensor timestamp (bytes 10, 11) stay zero, so OJD takes each report's arrival as liveness. `ojd controller watch` reported every control. M and M2 send no control. Pressing Home drops the pad off USB until replugged.

## V3 by Cable

Slider on V3, USB cable in: 2563:0526 Android GamePad. Report 7 (11 bytes) holds X, Y, Z, Rz, a hat, 15 buttons, Accelerator, Brake:

| Byte | Contents |
| --- | --- |
| 1-4 | Left X, left Y, right X, right Y, `0x80` at rest |
| 5 | Hat in the low nibble (`8` neutral) |
| 6 | Y `0x01`, B `0x02`, A `0x08`, X `0x10`, LB `0x40`, RB `0x80` |
| 7 | View `0x04`, Menu `0x08`, Home `0x10`, L3 `0x20`, R3 `0x40` |
| 8, 9 | RT (Accelerator) and LT (Brake), `0x00` to `0xFF` |

SDL_GameControllerDB maps this ID's buttons 1, 4, 5 to A, X, Y with no Home, putting A on West, X on North, Y on South. The 2563:0526 record's nitho mode maps by label and matches manufacturer shanwan, product Android GamePad. M1 and M2 send nothing. Other pads on 2563:0526 run the default mode (SDL layout). The release is `0x0100`, as on the SDL line, so a ShanWan pad with the same strings reads its face buttons rotated.

## X by Cable

Slider on X, USB cable in: once 054C:0268, blue light, Sixaxis USB report 1 (49 bytes). Manufacturer Sony Computer Entertainment (a DUALSHOCK 3 names Sony). Byte 3 holds the face buttons: A on Circle `0x20`, B on Cross `0x40`, X on Triangle `0x10`, Y on Square `0x80`, so the Sixaxis family read A as East, B as South, X as North, Y as West. The 054C:0268 patch has a nitho mode that matches the manufacturer and maps the four bits by label.

The pad took this identity once (slider to X, cable in), not in the retest. V3 to X kept 2563:0526 with a green light. A replug on X, or S to X, gave 045E:028E Xbox360 For Windows with a cyan light. In a later run, M to X gave 2563:0526 and about 17 seconds later 045E:028E; just before the switch the pad sent a 0.35-second burst of LT and of LB with LT. Not verified: the nitho mode on the pad.

The cyan identity sends the same Xbox 360 report as the [2.4G receiver](#24g-receiver). `ojd controller watch` reported every control. Slider on 2.4G by cable: same identity and reading, triggers reaching 65535.

## BSP-G6S-HID over Bluetooth LE

The pad pairs over Bluetooth LE as BSP-G6S-HID (1949:0402) with the slider on 2.4G and no receiver, or on V3 with X held while Home turns the pad on. Each time it uses a new address, so System Settings lists one more BSP-G6S-HID. Light: solid green on 2.4G, flashing yellow on V3. The descriptor is a standard gamepad. Report 3 is a 16-bit consumer key. Report 4 (11 bytes) holds X, Y, Z, Rz, a hat, 16 buttons, Accelerator, Brake. The 1949:0402 record runs its default HIDDescriptor mode, because v3 matches product BSP-G6S only. Home, M1, M2 send no report, also to a plain IOHID client with the OJD service stopped. An earlier session connected this identity with no input report.

## S Mode

Slider on S: 057E:2009 Pro Controller, by cable and over Bluetooth Classic. OJD's Switch Pro protocol reads every control. LT and RT are on or off, as on a Pro Controller. Buttons map by position: A reads as East, B South, X North, Y West. Manufacturer `Nintendo Co., Ltd.`, serial `000000000001`, release `0x0200`: no mode match tells it from a Nintendo Pro Controller. Over Bluetooth the first connect sent no report. After the Mac slept, the pad reconnected only through **Connect** in System Settings; then every control read, Home included.

## X Mode over Bluetooth

Bluetooth search lists Xbox Wireless Controller. **Connect** in System Settings failed with no message; `blueutil --pair` failed with a page timeout. Holding the pairing button in X paired it as BSP-G6S, solid red light: the [V3](#v3-mode-over-bluetooth-le) identity, read as V3.

## M1, M2, and T

M1 and M2 sent no input in any mode; the 2.4G capture shows no extra report bit. The manual calls them macro buttons: hold SELECT and press M1 or M2 to record up to 12 presses.

T (TURBO) sends the DUALSHOCK 4 touchpad click, byte 7 `0x02` of the USB report, in M mode by cable; `ojd controller watch` reports TouchpadClick. By cable on X, S, V3, 2.4G, and as BSP-G6S-HID over Bluetooth LE, three taps of T changed no report. The manual describes T as a setup key:

- A then T: turbo on for A.
- T with left stick up or down: turbo rate.
- T with right stick up or down: rumble strength.
- An 8-second hold cycles the gyro: right stick, left stick, off. The pad vibrated once.
