# Experimental Controller Status

Controllers that OJD has code for, but that nobody has fully tested on a real controller yet. Records only hold facts OJD needs to run the controller. Whether it's been tested lives in the testing page and the issue. If you change a parser or record, run the parser checks in `AGENTS.md`.

## DualSense

| Built |
| --- |
| USB report 0x01, Bluetooth report 0x31 input |
| Bluetooth input CRC32 check, seed 0xA1 |
| Edge function and paddle sources from the Edge record |
| raw motion sensor (IMU) and touch samples (calibration and mapping actions still being built) |
| compatible rumble over USB and Bluetooth |
| five player LEDs, RGB lightbar |
| Bluetooth sequence numbers, output CRC32 seed 0xA2 |

Still needed:

- USB and Bluetooth checks for input, reconnect, rumble, lights, and color.
- Edge: every press and release of all four function and paddle buttons, seen both in a capture and in a game reading a remapped gamepad, including unplugging while one is held. Also: buttons the pad's own firmware assigned, kept apart from OJD's mappings.

Packet reference and test files: [Remapping input contracts](remapping.md).

## DualShock 3

| Built |
| --- |
| USB and Bluetooth input report 0x01 |
| the setup that switches it on, different for USB and Bluetooth |
| ignoring fake Bluetooth status reports |
| large motor with strength levels, small motor that's on or off |
| four numbered player LEDs |

Not supported: sensors, battery, pairing. Still needed: checks of the USB control transfer and of Bluetooth.

## Steam Controller

| Built |
| --- |
| wired and wireless records |
| finding it by exact VID/PID while lizard mode (the pad acting as a keyboard and mouse) shows keyboard or mouse collections |
| wireless connect, disconnect, and a backup when status is missing |
| reading input, lizard-mode feature reports |
| left and right trackpad haptics |
| home-button LED brightness |

The wired report reaches macOS as lizard-mode keyboard input, so OJD finds the pad through its record. To check: [Steam Controller request](../testing/steam-controller.md).

## Switch Pro

| Built |
| --- |
| USB startup handshake, full-report command |
| Bluetooth input without the USB-only startup sequence |
| 12-bit stick, button, D-pad parsing |
| HD rumble frames, each one on its own |
| four player LEDs |
| startup and output rate limits |

Still needed: checks of calibration, motion, reconnect, rumble, and lights on USB and Bluetooth.

## Joy-Con

The pinned Nintendo source gives HID records for the left 057e:2006 and right 057e:2007, each choosing a Nintendo parser layout for its side. The main controls and raw motion data are read. Sticks and buttons that belong to the other half are ignored. Rumble only offers the motor that half has. SL and SR on each half can be remapped on their own. Tests built from made-up data cover calibration, motion actions, and paired halves. Source version, real-pad results, and what's still unchecked: [Joy-Con validation](../testing/joy-con.md).

## Xbox 360 Wireless Receiver

| Built from Linux `xpad.c` |
| --- |
| records for 045e:0291, 045e:02a9, 045e:0719 |
| each pad on the receiver showing up and leaving |
| state reports wrapped in the receiver's packets |
| receiver rumble and player-light packets |

Still needed: the [receiver request](../testing/xbox-360-wireless-receiver.md) on real hardware.

## Razer Wolverine V3 Tournament Edition

The GIP record points 1532:0A43 at XboxGIP, because Generic HID couldn't do the pad's startup handshake. Still needed: endpoint, handshake, input, and output ([Razer hardware test](../testing/razer/v3-te.md)).

## Microsoft Xbox One Controller (Model 1537)

Packets sent from an IOUSBHost test program confirm the GIP handshake, player light, every input including Guide, and rumble for 045E:02D1. The record holds the 0x81/0x01 endpoints seen on the pad, and the rule that configuration 1 must be set before OJD claims it. OJD's generated USBDriverKit extension and its wrapper haven't passed on this hardware. Still needed: [model 1537 test](../testing/xbox/1537.md).

## Razer Wolverine V2

The 1532:0A29 GIP record has a patch from one owner's pad for the interface-0 endpoints 0x81/0x01 seen in a capture. Not confirmed: input mapping, reconnect, lights, rumble ([Wolverine V2 test](../testing/razer/wolverine-v2.md)).

## Nacon Revolution X Pro

The local 3285:0634 override picks XboxGIP on interface 0, interrupt endpoints 0x87/0x07. The profile turns off the GIP 0x03 message OJD usually sends on a timer. The issue's WebUSB trace shows the pad sending its own 0x03 status messages and staying steady without one from the Mac.

The parser accepts packets split across transfers or stacked in one, base-128 payload lengths, and requested ACK messages in the Linux/xone layout. OJD answers chunk headers but doesn't glue chunk payloads back together, because no capture in the issue needs an input report spread over several chunks.

Linux `xpad.c` knows the Nacon vendor and the Xbox One backup but not this PID. It only helped with recognizing the pad, not the endpoints or OJD's USBDriverKit session. What must pass (input, reading without stopping, reconnect, no keep-alive from the Mac): [Nacon hardware steps](../testing/nacon-revolution-x.md).

## ZD Ultimate Legend

The Linux xpad XUSB record for 413D:2104 stays. A patch from one owner's pad fixes the interrupt endpoints at 0x81/0x02, because rumble and player-light writes to the usual Xbox 360 OUT 0x01 fail with NotFound. Input on IN 0x81 works without the patch. OJD's automatic pick publishes SDLCompatible. See [issue #22](https://github.com/xsyetopz/OpenJoystickDriver/issues/22).

The pad reports `bDeviceClass` 0, so the class sits on each interface. OJD finds the device by its `IOUSBHostDevice` service and finds XUSB by interface class 255 on interface 0. `TransportFacadeTests+CompositeDevice` checks both steps.

Mapping status:

- One owner's raw capture of IN 0x81 matched 16 of 16 controls. `ZDUltimateLegendRecordTests` replays those bytes.
- One owner checked input, analog triggers, rumble on OUT 0x02 and play in a game. That was on 0.5.0-beta.3 with the endpoint patch, on macOS 26.6.2.
- No owner has sent an Input Test page result for the bundled record.
- One owner saw sticks and triggers swap after a replug. Nobody has repeated it, and that owner did not name the build.

## Xbox Adaptive Joystick

OJD has no parser for it, and the product pages don't describe the packets. Before adding a record, capture the pad at rest, every button, the stick axes, the stick click, report IDs, and checksums ([packet request](../testing/xbox-adaptive-joystick.md)).

## Flydigi Vader 4 Pro (Bluetooth)

The HID record for D7D7:0041 uses the documented family VendorFlydigi instead of HIDDescriptor. A `VendorFlydigi.plist` in the user's `Protocols` folder replaces its description. The input layout comes from captured 15-byte Bluetooth LE reports. Still needed: virtual input a game can see, reconnect, rumble, and the 2.4 GHz and wired identities ([Vader 4 Pro test](../testing/flydigi-vader-4-pro.md)). See also [pull request #30](https://github.com/xsyetopz/OpenJoystickDriver/pull/30).

## WR-007 USB HID Receiver

The HID record for 11C1:5600 stays on Generic HID. The parser maps its gappy Xbox-style button usages, the Z/Rz right stick, and the Simulation Accelerator/Brake triggers (pedal-style). The Apple GameController identity works. Rumble on the pad doesn't: the receiver accepts its 4-byte output report, but tests made no motor or light respond. Still needed: [WR-007 test](../testing/wr-007.md). See also [issue #31](https://github.com/xsyetopz/OpenJoystickDriver/issues/31).

## Generic HID

When nothing else matches, OJD reads the HID descriptor (the pad's own list of its controls). That handles standard buttons, pairs of stick axes, triggers, and an eight-way hat. Pads with a known protocol still go to their own parser. Layouts a vendor invented need a record and a parser.
