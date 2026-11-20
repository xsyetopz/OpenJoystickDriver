# Test the GameSir G7 Pro, Cyclone 2, and G7 Pro 8K PC

Test steps for GameSir controllers. Nobody has checked these on a real controller yet. Test the exact ID you have, because each mode and model has its own.

## Contents

- [Covered Identities](#covered-identities)
- [What Owners Saw](#what-owners-saw)
- [Check Records and Input](#check-records-and-input)
- [Check Lights and Rumble](#check-lights-and-rumble)
- [Windows USB Capture with GameSir Apps](#windows-usb-capture-with-gamesir-apps)

## Covered Identities

| Model and mode | IDs (VID 3537) | Parameter |
| --- | --- | --- |
| G7 Pro, configuration-ready USB | 3537:1003, 105D, 105E, 109B, 109C, 10BA | |
| G7 Pro, input-only | 100A, 1022 | |
| Cyclone 2, enhanced HID | 0575, 100B, 1053 | `lightingMemory`: `ProfileSlots` |
| G7 Pro 8K PC, enhanced HID | 10C5, 10C6, 10C7, 10C8 | `innerGrips` |

Both enhanced HID models use `VendorGameSir:EnhancedHID`, and catalog parameters handle what's different between models.

3537:1004 uses XUSB. Linux calls it T4 Kaleid, and the White G7 Pro dongle report shows the same ID. 3537:100F and 1010, also from Linux, use XUSB too.

## What Owners Saw

These are dated notes from one owner's G7 SE.

2026-09-25, owner's hardware, macOS 27, unsigned debug build of `feat/0.5.0-beta.5` (Xcode 26.6). G7 SE 3537:1010 (`GameSir-G7 SE Controller for Xbox`, `bcdDevice 0x0640`, class FF/FF/FF, not yet configured when plugged in) on a Genesys USB 2.1 hub. The `iousbhost` backend accepted it. OJD configured it, finished the handshake, and started reading input on endpoint 0x82. A development-signed build: active on GIP, `startup=succeeded`. Left alone, it traded a GIP keep-alive every 20 seconds (Mac `03 20 00 03 00 00 00`, controller `03 20 03 04 80 00 00 00`). Not checked: parsed input, lights and rumble, reconnecting.

2026-09-26, same G7 SE after Nexus 2.5.8 on Windows 10, back on macOS 27: 3537:1082, `bcdDevice 0x0664`, class 00/00/00, two class-3 interfaces:

- Interface 0: a gamepad collection that Apple's HID driver holds. Report 0x05, 10 bytes: 15 buttons, 4-bit hat, 8-bit X/Y/Z/Rz, accelerator, brake, four LED outputs (0x43-0x46). Report 0x02: volume up/down.
- Interface 1: no macOS HID driver.

Apple's GameController picks up the pad on its own. OJD uses `HIDDescriptor` with `physicalOwnership=SystemGamepad`: it watches without taking the pad over, and makes no virtual pad.

Nexus required a firmware update from 6.4.0 (0x0640) to 6.6.4 (0x0664), `JS_SL3101_V664_Key.ufw`, which it installed over GIP in 52 s. The ID depends on the computer:

- Windows (Nexus log): 3537:10A0 (XInput), then 3537:1010 (GIP) after the prompt `press any key to switch to APP mode`.
- macOS: 3537:1082, the HID mode above.

The player light stays dark in HID mode 1082. OJD doesn't write to pads that macOS handles itself, and nobody knows an output that lights it. Firmware 6.4.0 showed up as 3537:1010.

2026-09-28, same G7 SE, firmware 6.6.4, macOS 27. No attempt to light the LED worked, and the gamepad kept working the whole time.

- Interface 1 of 1082: 214-byte descriptor, keyboard (report 3), consumer (2), mouse (9), vendor collection on page 0xFFF0 (input 0x10 and 0x12, output 0x0F, 63 bytes each). Opening it sent one keyboard report, usage 0x46 (`Print Screen`).
- Output report 5 (the interface 0 LED bytes) didn't change the LED.
- The G7 Pro message format doesn't work. g7ctl sends report 0x0F: a heartbeat `0f 00 seq 02 f2 00` every 0.316 s, and device-info questions `01 09` and `01 0b`. Both interfaces took it without answering, even after the `gamesirapp` handshake sent as HID report ID 0 on interface 0. The pad didn't reconnect as anything else. A SET_REPORT control transfer to interface 1 stalls.
- Writing the raw 8-byte handshake on endpoint 0x02 needs the interface. macOS won't take it away from Apple's HID driver (0xE00002C9), even with OJD closed.
- No effect: Xbox+Share (3 s), Xbox+M (3 s, then replug), M+Y, and a hardware reset on a borrowed computer. Plugging in while holding View+Xbox+Menu makes the LED blink white fast, and the pad shows up as 3537:1010 with one HID interface:
  - input report 1: 64 bytes, about 250 times a second
  - output report 5: 31 bytes
  - feature reports 3 (47 bytes) and 0xE0 (2 bytes), which both stall when read
  - the same 0xFFF0 vendor collection, with no answer

  A normal replug puts it back to 1082 with the LED dark. The LED itself works, so the cause is the firmware or a saved profile. Nobody has checked which.

Not tried: the raw handshake from Linux, and Nexus with the pad in 1010 mode.

2026-10-05, owner's hardware, macOS 27.0.1, commit `21e2da3a`, app quit: G7 SE 3537:1010 (`bcdDevice 0x0640`), USB GIP, `ojd diagnose record`.

- 60-second baseline: `RECORD_HANDSHAKE driver=XboxGIP:USB result=complete`, `RECORD_SUMMARY packets=5 events=0 parse_errors=0`, exit 0.
- 180-second run with `"keepAlive": false`: same handshake line, `RECORD_SUMMARY packets=23 events=11 parse_errors=0`, exit 0.
- Without a keep-alive from the Mac, the pad still sent status `03 20 nn 04 80 00 00 00` every 20 seconds. So the 20-second rhythm seen on 2026-09-25 is the pad's own timing, and the Mac doesn't need to send it.
- All five A presses read as `faceSouth`. It never disconnected, and the player light stayed on.

This holds only for this model, firmware, and macOS version. It says nothing about the GameSir 0F F2 heartbeat on other models.

## Check Records and Input

From the repository root:

```bash
just catalog-regenerate --check
just test-parsers-macos14
swift test --filter 'GameSirDriverTests|GameSirCatalogTests'
```

1. For each mode, write down the VID/PID, product name, connection type, firmware, macOS version, and OJD commit.
2. Check the face buttons, all eight D-pad positions and the center, sticks, triggers, bumpers, View, Menu, stick clicks, and any extras the box lists.
3. Check the battery level and charging.
4. If it has motion, capture samples with the pad still and with it turned around each axis on its own.
5. Keep enhanced HID and configuration-ready modes connected for 30 seconds, and check the heartbeat every 500 ms.
6. Reconnect. Check that no old button, battery, lighting slot, or sequence state carries over.

## Check Lights and Rumble

Use the output controls in the installed app's Input Test.

- Cyclone 2: color sets one solid RGB color on every zone OJD can control. Brightness changes the active slot.
- G7 Pro 8K PC: the four quarters of the home ring change together. Brightness covers the whole 0...100 range.
- Standard G7 Pro: dock brightness only. OJD makes no RGB claim.
- Enhanced HID: OJD only claims the two main rumble motors.

Input-only modes (3537:100A, 1022) must offer no settings output. OJD sends no command to switch modes. For a configuration-ready mode, hold Menu+Share before you connect.

Report each output you tried, the active lighting slot, what happened, and any transfer error. To count as confirmed on hardware, the matching ID has to pass input, heartbeat, reconnect, and every output OJD claims.

## Windows USB Capture with GameSir Apps

### Results (2026-09-26, G7 SE, Firmware 6.6.4)

Scenario 1 (no GameSir app, 44 s of USBPcap): 3537:10A0, `bcdDevice 0x0664`, two interfaces:

- Interface 0: Xbox 360 wired, FF/5D/01; 0x82 IN, 0x02 OUT, 32-byte packets, 1 ms.
- Interface 1: HID; 0x84 IN, 0x04 OUT, 64 bytes, 214-byte report descriptor.

Input: 20-byte XUSB (`00 14 …`), and the triggers reach 255. The controls showed the 15 standard XUSB button bits, and bytes 14 to 19 stayed zero. One extra key showed up only on interface 1 (`03 0c 00 46 00 00 00 00 00`, then zero). Nobody wrote down which key it was. Nothing was sent OUT to 0x02.

You can't capture with Nexus running, because Nexus disconnects the pad while USBPcap is watching. Reading the Nexus 2.5.8 program itself stands in for the capture.

- Connection: GIP only (APP mode, 3537:1010). It has no HID code.
- Vendor commands: GIP message 0x0F, command in payload byte 0, 60-byte replies:

  | Command | Purpose |
  | --- | --- |
  | 09/0A | firmware version |
  | 04/05 | read profile |
  | 0B/0C | current profile |
  | 07 | switch or save profile |
  | 0D | light on/off |
  | E0 | 60-byte status packet with back buttons and M |
  | F2 | test or stream mode |
  | FE | calibration |
  | F0 | firmware update chunk |

- Rumble uses GIP message 0x09.
- G7 SE paddles FL1/FL2/FR1/FR2 are L4/L5/R4/R5.
- Other G7 SE PIDs in the app: `1069 1071 1073 1075 1077 108F 106D`. 1082 isn't there.
- Firmware: built-in JieLi AC695X `.ufw` images with a CRC16-keystream header. Nobody has decoded the contents.
- Still open: motion scale, axes and byte order, and how to light the LED in HID mode.

Not checked on hardware.

Capture plan: record the USB traffic between the controller and Nexus or Connect, on Windows 10 under Boot Camp on an Intel Mac. What to catch:

- Commands that turn on gyro, paddle, or extra-button reports, and mode switches.
- A firmware update transfer. An unencrypted image could name the motion sensor chip and its full ranges, and GameSir doesn't publish firmware on its own.
- Input reports in each mode, with app features turned on.

Open questions:

- Motion layout and byte order (OJD sends no GameSir motion): gyro at 14, accelerometer at 20, little-endian; or SDL's layout for other PIDs: accelerometer at 14, gyro at 20, big-endian, header `0xA1 0xC8`.
- Motion scale, which way each axis counts, and the IMU sample counter.
- Whether the back buttons report as their own bits.

### Capture Setup

1. Install Wireshark and USBPcap.
2. Choose the controller's USBPcap root hub.
3. Filter on the controller's device address.

### Scenarios

1. No GameSir app: plug in, leave it alone, then press each button and move each stick and trigger.
2. Do it again with Nexus or Connect running.
3. Turn each app feature on and off (gyro, back-button mapping, mode, polling rate), and write down when you clicked.
4. Only capture a firmware update if the owner decides to update, because it writes to the device.
5. Motion calibration: lay the controller flat and still, stand it on each edge, and turn it a full 360° around each axis.

Save captures as `.pcapng`, named by model, mode, and scenario. They contain the device's serial number, so the owner decides whether to share them.

### Model Notes

The owner's G7 SE uses GIP (Xbox One wired): it has settings commands and extra-button bits, but no enhanced HID motion. Testing motion needs a G7 Pro 8K PC or a Cyclone 2.

## Further Reading

- [Supported Controllers](../../wiki/Supported-Controllers.md)
- [Physical Output](physical-output.md)
