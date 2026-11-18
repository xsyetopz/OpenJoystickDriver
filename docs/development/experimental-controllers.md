# Experimental Controller Status

Entries have implementation work but incomplete hardware evidence. Records hold operational facts only; verification status lives in the testing document and issue. Parser or record changes: run the parser gates in `AGENTS.md`.

## DualSense

| Implemented |
| --- |
| USB report 0x01, Bluetooth report 0x31 input |
| Bluetooth input CRC32 check, seed 0xA1 |
| Edge function and paddle sources from the Edge record |
| raw IMU and touch samples (calibration and mapping actions in progress) |
| compatible rumble over USB and Bluetooth |
| five player LEDs, RGB lightbar |
| Bluetooth sequence framing, output CRC32 seed 0xA2 |

Needed: USB and Bluetooth checks for input, reconnect, rumble, indicators, color. Edge: all four function and paddle press and release edges in capture and a remapped consumer, including disconnect while held; firmware assignments apart from OJD mappings. Packet reference and fixtures: [Remapping input contracts](remapping.md).

## DualShock 3

| Implemented |
| --- |
| USB and Bluetooth input report 0x01 |
| transport-specific operational-mode setup |
| bogus Bluetooth status report filtering |
| analog large motor, binary small motor |
| four numbered player LEDs |

Not claimed: sensors, battery, pairing. Needed: USB control transfer and Bluetooth checks.

## Steam Controller

| Implemented |
| --- |
| wired and wireless records |
| exact VID/PID discovery when lizard mode exposes keyboard or mouse collections |
| wireless connect, disconnect, status fallback |
| input parsing, lizard-mode feature reports |
| left and right trackpad haptics |
| home-button LED brightness |

The wired report reaches macOS as lizard-mode keyboard input, so discovery is profile-backed. Check: [Steam Controller request](../testing/steam-controller.md).

## Switch Pro

| Implemented |
| --- |
| USB startup handshake, full-report command |
| Bluetooth input without the USB-only startup sequence |
| 12-bit stick, button, D-pad parsing |
| independent HD-rumble frames |
| four player LEDs |
| startup and output rate limits |

Needed: calibration, IMU, reconnect, rumble, LED checks on USB and Bluetooth.

## Joy-Con

The pinned Nintendo source supplies left 057e:2006 and right 057e:2007 HID records, each selecting a side-specific Nintendo parser layout. Primary controls and raw IMU decode; absent sticks and opposite-half buttons are ignored. Rumble exposes the available motor only. SL and SR are separate remapping sources per half. Constructed tests cover calibration, motion actions, and paired sessions. Source revision, product evidence, outstanding acceptance: [Joy-Con validation](../testing/joy-con.md).

## Xbox 360 Wireless Receiver

| Implemented from Linux `xpad.c` |
| --- |
| records for 045e:0291, 045e:02a9, 045e:0719 |
| logical-controller presence and disconnect |
| wrapped state reports |
| receiver rumble and player-light packets |

Needed: [receiver request](../testing/xbox-360-wireless-receiver.md) on hardware.

## Razer Wolverine V3 Tournament Edition

The GIP record binds 1532:0A43 to XboxGIP because Generic HID could not run its handshake. Needed: endpoint, handshake, input, output ([Razer hardware test](../testing/razer/v3-te.md)).

## Microsoft Xbox One Controller (Model 1537)

IOUSBHost harness packets verify the GIP handshake, player LED, every input including Guide, and rumble for 045E:02D1. The record carries observed 0x81/0x01 endpoints and the need to set configuration 1 before the claim. OJD's generated USBDriverKit extension and host wrapper have not passed on this hardware. Needed: [model 1537 test](../testing/xbox/1537.md).

## Razer Wolverine V2

The 1532:0A29 GIP record has a local-hardware patch for captured interface-0 endpoints 0x81/0x01. Unverified: input mapping, reconnect, LED, rumble ([Wolverine V2 test](../testing/razer/wolverine-v2.md)).

## Nacon Revolution X Pro

The local 3285:0634 override selects XboxGIP on interface 0, interrupt endpoints 0x87/0x07. The profile turns off OJD's periodic host-side GIP 0x03 transmission: the issue's WebUSB trace shows the device sending 0x03 status frames and staying stable without a host packet.

The parser accepts split or stacked transfers, base-128 payload lengths, and requested ACK frames in the Linux/xone layout. OJD acknowledges chunk headers but does not reassemble chunk payloads, since no issue capture needs a multi-chunk input report.

Linux `xpad.c` supports the Nacon vendor and Xbox One fallback but not this PID: classification only, not the endpoints or the OJD USBDriverKit session. Acceptance (input, continuous-read, reconnect, no-host-keep-alive): [Nacon hardware procedure](../testing/nacon-revolution-x.md).

## ZD Ultimate Legend

The Linux xpad XUSB record for 413D:2104 stays. A local-hardware patch pins interrupt endpoints 0x81/0x02, since rumble and player-indicator writes to the Xbox 360 default OUT 0x01 fail with NotFound; input on IN 0x81 works without it. The automatic selector publishes SDLCompatible. See [issue #22](https://github.com/xsyetopz/OpenJoystickDriver/issues/22).

## Xbox Adaptive Joystick

No parser claim exists; product descriptions give no packet layout. Before adding a record, capture neutral, every button, stick axes, stick click, report IDs, and checksums ([packet request](../testing/xbox-adaptive-joystick.md)).

## Flydigi Vader 4 Pro (Bluetooth)

The HID record for D7D7:0041 binds the documented family VendorFlydigi instead of HIDDescriptor; a `VendorFlydigi.plist` in the user's `Protocols` folder replaces its description. Input is packet-backed from captured 15-byte BLE reports. Needed: consumer-visible virtual input, reconnect, rumble, 2.4 GHz and wired identities ([Vader 4 Pro test](../testing/flydigi-vader-4-pro.md)). See also [pull request #30](https://github.com/xsyetopz/OpenJoystickDriver/pull/30).

## WR-007 USB HID Receiver

The HID record for 11C1:5600 stays on Generic HID. The parser maps its sparse Xbox-style button usages, Z/Rz right stick, and Simulation Accelerator/Brake triggers. Apple GameController identity is available. Physical rumble is unavailable: the receiver accepts its 4-byte output report, but probes produced no motor or LED response. Needed: [WR-007 test](../testing/wr-007.md). See also [issue #31](https://github.com/xsyetopz/OpenJoystickDriver/issues/31).

## Generic HID

Descriptor-driven fallback handles standard buttons, stick pairs, triggers, and an eight-way hat. Known protocol parsers still consume their raw reports. Vendor-defined layouts need a record and parser.
