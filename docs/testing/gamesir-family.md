# Test the GameSir G7 Pro, Cyclone 2, and G7 Pro 8K PC

No hardware verification. Test the exact identity.

## Contents

- [Covered Identities](#covered-identities)
- [Observed](#observed)
- [Validate Records and Input](#validate-records-and-input)
- [Validate Physical Output](#validate-physical-output)
- [Windows USB Capture with GameSir Apps](#windows-usb-capture-with-gamesir-apps)

## Covered Identities

| Model and mode | IDs (VID 3537) | Parameter |
| --- | --- | --- |
| G7 Pro, configuration-ready USB | 3537:1003, 105D, 105E, 109B, 109C, 10BA | |
| G7 Pro, input-only | 100A, 1022 | |
| Cyclone 2, enhanced HID | 0575, 100B, 1053 | `lightingMemory`: `ProfileSlots` |
| G7 Pro 8K PC, enhanced HID | 10C5, 10C6, 10C7, 10C8 | `innerGrips` |

Both enhanced HID models bind `VendorGameSir:EnhancedHID`; catalog parameters select model differences.

3537:1004 uses XUSB. Linux identifies it as T4 Kaleid; the White G7 Pro dongle report shares it. The Linux-backed 3537:100F and 1010 also use XUSB.

## Observed

2026-09-25, owner hardware, macOS 27, unsigned debug build of `feat/0.5.0-beta.5` (Xcode 26.6). G7 SE 3537:1010 (`GameSir-G7 SE Controller for Xbox`, `bcdDevice 0x0640`, class FF/FF/FF, unconfigured at attach) on a Genesys USB 2.1 hub. The `iousbhost` backend admitted it; OJD configured it, handshook, and started the input loop on endpoint 0x82. A development-signed build: active on GIP, `startup=succeeded`. Idle: GIP keep-alive every 20 seconds (host `03 20 00 03 00 00 00`, controller `03 20 03 04 80 00 00 00`). Not verified: parsed input, physical output, reconnect.

2026-09-26, same G7 SE after Nexus 2.5.8 on Windows 10, back on macOS 27: 3537:1082, `bcdDevice 0x0664`, class 00/00/00, two class-3 interfaces:

- Interface 0: Game Pad collection, bound by Apple's HID driver. Report 0x05, 10 bytes: 15 buttons, 4-bit hat, 8-bit X/Y/Z/Rz, accelerator, brake, four LED outputs (0x43-0x46). Report 0x02: volume up/down.
- Interface 1: no macOS HID driver.

GameController takes the pad natively. OJD binds `HIDDescriptor` with `physicalOwnership=SystemGamepad`, observes without seizing, publishes no virtual pad.

Nexus required firmware 6.4.0 (0x0640) to 6.6.4 (0x0664), `JS_SL3101_V664_Key.ufw`, applied over GIP in 52 s. Identity by host:

- Windows (Nexus log): 3537:10A0 (XInput), then 3537:1010 (GIP) after the prompt `press any key to switch to APP mode`.
- macOS: 3537:1082, the HID mode above.

The player LED stays dark in HID mode 1082; OJD does not write to native pads, and no known output lights it. Firmware 6.4.0 showed as 3537:1010.

2026-09-28, same G7 SE, firmware 6.6.4, macOS 27. No LED fix worked; gamepad function never broke.

- Interface 1 of 1082: 214-byte descriptor, keyboard (report 3), consumer (2), mouse (9), vendor collection on page 0xFFF0 (input 0x10 and 0x12, output 0x0F, 63 bytes each). Opening it sent one keyboard report, usage 0x46 (`Print Screen`).
- Output report 5 (interface 0 LED bytes) did not change the LED.
- G7 Pro framing fails. g7ctl sends report 0x0F: heartbeat `0f 00 seq 02 f2 00` every 0.316 s, device-info queries `01 09` and `01 0b`. Both interfaces accepted it without reply, also after the `gamesirapp` handshake as HID report ID 0 on interface 0. No re-enumeration. SET_REPORT control transfer to interface 1 stalls.
- Raw 8-byte handshake writes on endpoint 0x02 need the interface; macOS refuses to seize it from Apple's HID driver (0xE00002C9), even with OJD closed.
- No effect: Xbox+Share (3 s), Xbox+M (3 s, then replug), M+Y, hardware reset on a borrowed computer. Plugging in while holding View+Xbox+Menu blinks the LED white rapidly; the pad enumerates as 3537:1010 with one HID interface:
  - input report 1: 64 bytes, about 250 Hz;
  - output report 5: 31 bytes;
  - feature reports 3 (47 bytes) and 0xE0 (2 bytes), both stall on read;
  - the same 0xFFF0 vendor collection, no answer.

  A normal replug returns it to 1082, LED dark. LED hardware works, so the cause is firmware or profile state; not verified which.

Untested: raw handshake from Linux; Nexus with the pad in 1010 mode.

2026-10-05, owner hardware, macOS 27.0.1, commit `21e2da3a`, app quit: G7 SE 3537:1010 (`bcdDevice 0x0640`), USB GIP, `ojd diagnose record`.

- 60-second baseline: `RECORD_HANDSHAKE driver=XboxGIP:USB result=complete`, `RECORD_SUMMARY packets=5 events=0 parse_errors=0`, exit 0.
- 180-second run with `"keepAlive": false`: same handshake line, `RECORD_SUMMARY packets=23 events=11 parse_errors=0`, exit 0.
- Without host keep-alive the pad still sent status `03 20 nn 04 80 00 00 00` every 20 seconds: the 2026-09-25 rhythm is the pad's cadence, not a host requirement.
- All five A presses decoded as `faceSouth`. No disconnect; player LED stayed lit.

Holds for this model, firmware, and macOS version only, not for the GameSir 0F F2 heartbeat on other models.

## Validate Records and Input

From the repository root:

```bash
just catalog-regenerate --check
just test-parsers-macos14
swift test --filter 'GameSirDriverTests|GameSirCatalogTests'
```

1. Record VID/PID, product name, transport, firmware, macOS version, and OJD commit per mode.
2. Check face buttons, eight D-pad positions and neutral, sticks, triggers, bumpers, View, Menu, stick clicks, advertised extras.
3. Check battery and charging.
4. With motion, capture stationary and independently rotated samples.
5. Keep enhanced HID and configuration-ready modes connected 30 seconds; check the 500 ms heartbeat.
6. Reconnect. Check no stale button, battery, lighting-slot, or sequence state survives.

## Validate Physical Output

Use the installed app's Input Test output controls.

- Cyclone 2: color sets one solid RGB value across controllable zones; brightness changes the active slot.
- G7 Pro 8K PC: four home-ring quadrants change together; brightness spans the 0...100 register.
- Standard G7 Pro: dock brightness only. No RGB claimed.
- Enhanced HID: only the two main rumble motors claimed.

Input-only modes (3537:100A, 1022) must expose no configuration output. OJD sends no mode-switch command; for a configuration-ready mode, hold Menu+Share before connecting.

Report each output tried, active lighting slot, result, and transfer error. Hardware-verified: the matching identity passes input, heartbeat, reconnect, and each claimed output.

## Windows USB Capture with GameSir Apps

### Results (2026-09-26, G7 SE, Firmware 6.6.4)

Scenario 1 (no GameSir app, 44 s USBPcap): 3537:10A0, `bcdDevice 0x0664`, two interfaces:

- Interface 0: Xbox 360 wired, FF/5D/01; 0x82 IN, 0x02 OUT, 32-byte packets, 1 ms.
- Interface 1: HID; 0x84 IN, 0x04 OUT, 64 bytes, 214-byte report descriptor.

Input: 20-byte XUSB (`00 14 …`); triggers reach 255. Controls showed the 15 standard XUSB button bits; bytes 14-19 stayed zero. One extra key reported only on interface 1 (`03 0c 00 46 00 00 00 00 00`, then zero); the key is not recorded. No OUT transfers to 0x02.

Capture with Nexus running is impossible: Nexus disconnects the pad under USBPcap. Static analysis of Nexus 2.5.8 replaces it.

- Transport: GIP only (APP mode, 3537:1010); no HID code.
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
- Other G7 SE PIDs in the app: `1069 1071 1073 1075 1077 108F 106D`. 1082 is absent.
- Firmware: embedded JieLi AC695X `.ufw` images, CRC16-keystream header; payload not decoded.
- Not settled: motion scale, axes and byte order, LED drive in HID mode.

Not verified: hardware check.

Capture plan: USB traffic between controller and Nexus or Connect, Windows 10 under Boot Camp on an Intel Mac. Targets:

- Commands that enable gyro, paddle, or extra-button reporting, and mode switches.
- Firmware update transfer (an unencrypted image could identify the IMU part and full-scale ranges; GameSir publishes no standalone firmware).
- Input reports per mode, app features on.

Open questions:

- Motion layout and byte order (OJD publishes no GameSir motion): gyro at 14, accel at 20, little-endian; or SDL's layout for other PIDs: accel at 14, gyro at 20, big-endian, header `0xA1 0xC8`.
- Motion scale, axis signs, IMU sample counter.
- Whether back buttons report as separate bits.

### Capture Setup

1. Install Wireshark and USBPcap.
2. Choose the controller's USBPcap root hub.
3. Filter on the controller's device address.

### Scenarios

1. No GameSir app: plug in, idle, press each button, move each axis.
2. Repeat with Nexus or Connect running.
3. Toggle each app feature (gyro, back-button mapping, mode, polling rate); note click times.
4. Capture a firmware update only if the owner decides to update; it writes to the device.
5. Motion calibration: lay the controller flat and still, rest it on each edge, rotate 360° about each axis.

Save captures as `.pcapng` named by model, mode, and scenario. They contain the device serial; the owner decides on sharing.

### Model Notes

The owner's G7 SE uses GIP (Xbox One wired): configuration commands and extra-button bits, no enhanced HID motion. Motion needs a G7 Pro 8K PC or Cyclone 2.

## Further Reading

- [Supported Controllers](../../wiki/Supported-Controllers.md)
- [Physical Output](physical-output.md)
