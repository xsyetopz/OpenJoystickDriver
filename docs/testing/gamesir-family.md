# Test the GameSir G7 Pro, Cyclone 2, and G7 Pro 8K PC

These records and packet encoders are source-backed, not hardware-verified. Test the connected controller's exact identity; never infer one GameSir model from another.

## Covered Identities

- G7 Pro configuration-ready USB: `3537:1003`, `105D`, `105E`, `109B`, `109C`, and `10BA`
- G7 Pro input-only modes: `3537:100A` and `1022`
- Cyclone 2 enhanced HID: `3537:0575`, `100B`, and `1053`, with the `lighting-slots` quirk
- G7 Pro 8K PC enhanced HID: `3537:10C5`, `10C6`, `10C7`, and `10C8`, with the `inner-grips` quirk

Both enhanced HID models bind `vendor.gamesir:enhanced-hid`; their catalog quirks select the model differences.

`3537:1004` stays on the existing XUSB route because Linux identifies it as T4 Kaleid and the White G7 Pro dongle report shares that identity. Existing Linux-backed `3537:100F` and `1010` routes are also unchanged.

## Observed

2026-09-25, owner hardware, macOS 27, unsigned debug build of branch `feat/0.5.0-beta.5` (Xcode 26.6): the G7 SE `3537:1010` ("GameSir-G7 SE Controller for Xbox", `bcdDevice` `0x0640`, device class `FF/FF/FF`, unconfigured at attach) on a Genesys USB 2.1 hub was admitted through the `iousbhost` backend. OJD configured it, completed the handshake, and started the USB input loop on endpoint `0x82`. A development-signed build then reported the controller active on the GIP protocol with `startup=succeeded`, and its packet log showed the GIP keep-alive exchange every 20 seconds (host `03 20 00 03 00 00 00`, controller `03 20 03 04 80 00 00 00`) while idle. Parsed button, stick, and trigger input, physical output, and reconnect are not yet observed.

2026-09-26, the same G7 SE after the owner connected it to GameSir Nexus 2.5.8 on Windows 10 and then back to macOS 27. It now enumerates as `3537:1082`, `bcdDevice` `0x0664`, device class `00/00/00`, with two class-3 interfaces:

- **Interface 0:** a Game Pad collection, bound by Apple's HID driver.
  - Report `0x05` is 10 bytes: 15 buttons, a 4-bit hat, 8-bit X/Y/Z/Rz, 8-bit accelerator and brake, and four 8-bit LED outputs (`0x43`–`0x46`).
  - Report `0x02` is consumer volume up/down.
- **Interface 1:** has no macOS HID driver attached.

GameController accepts the pad natively. OJD binds it as `hid.descriptor` with `physicalOwnership=nativeGamepad`, observes it without seizing it, and publishes no virtual pad.

Nexus required a firmware update, which the owner applied: firmware 6.4.0 (`bcdDevice` `0x0640`) became 6.6.4 (`0x0664`). The Nexus log names the image `JS_SL3101_V664_Key.ufw`, which is embedded in the app and applied over GIP in 52 s.

Firmware 6.6.4 presents different identities depending on the host:

- **Windows (per the Nexus log):** the pad first appears as `3537:10A0` (XInput, "Xbox 360 Controller for Windows"). After Nexus asks the owner to "press any key to switch to APP mode", it re-enumerates as `3537:1010` (GIP).
- **macOS:** the pad appears as `3537:1082`, the HID mode described above.

The player LED stays dark in HID mode `1082`. OJD does not write to native pads, and it is unknown which output, if any, lights the LED in this mode. Firmware 6.4.0 appeared on macOS as `3537:1010`.

2026-09-28, the same G7 SE on firmware 6.6.4, macOS 27: attempts to restore the LED. None lit it, and the pad works as a gamepad throughout.

- **Interface 1 of `1082`** has a 214-byte descriptor. It holds a keyboard (report 3), consumer (report 2), mouse (report 9), and a vendor collection on page `0xFFF0`: input `0x10` and `0x12` and output `0x0F`, 63 bytes each. When opened, it sent one keyboard report with usage `0x46` (Print Screen).
- **Output report 5** (the four LED bytes on interface 0) did not change the LED.
- **G7 Pro framing does not work.** The G7 Pro configuration framing from the open-source g7ctl tool (report `0x0F`: heartbeat `0f 00 seq 02 f2 00` every 0.316 s, device-info queries `01 09` and `01 0b`) was accepted on both interfaces but got no reply. The same holds after the `gamesirapp` handshake, sent as HID report ID 0 on interface 0. The pad did not re-enumerate. A control-transfer SET_REPORT to interface 1 stalls.
- **The handshake could not be sent raw.** Sending it as raw 8-byte writes on endpoint `0x02` needs the interface itself. macOS refuses to seize it from Apple's HID driver (`0xE00002C9`), even with OJD closed.
- **Combos.** Xbox+Share (3 s), Xbox+M (3 s, then replug), and M+Y changed nothing, and a hardware reset done on a borrowed computer did not restore the LED. Holding View+Xbox+Menu while plugging in makes the LED blink white rapidly. The pad then enumerates as `3537:1010` with one HID interface:
  - input report 1: 64 bytes, about 250 Hz;
  - output report 5: 31 bytes;
  - feature reports 3 (47 bytes) and `0xE0` (2 bytes), both of which stall on read;
  - the same `0xFFF0` vendor collection, which also did not answer.

  A normal replug returns it to `1082` with the LED dark. The LED hardware works, so the dark LED in `1082` is firmware or profile state.

Still untested: the raw handshake from Linux, and GameSir Nexus with the pad in this `1010` mode.

2026-10-05, owner hardware, macOS 27.0.1, commit `21e2da3a`, app quit: the G7 SE `3537:1010` (`bcdDevice` `0x0640`) over USB GIP, through `ojd diagnose record`. A 60-second baseline with the generated record printed `RECORD_HANDSHAKE driver=xbox.gip:usb result=complete` and `RECORD_SUMMARY packets=5 events=0 parse_errors=0` and exited 0. A 180-second run of the same record with `"keepAlive": false` printed `RECORD_HANDSHAKE driver=xbox.gip:usb result=complete` and `RECORD_SUMMARY packets=23 events=11 parse_errors=0` and exited 0. Without any host keep-alive, the pad still sent its own status `03 20 nn 04 80 00 00 00` every 20 seconds, all five presses of A decoded as `faceSouth`, nothing disconnected or reconnected, and the owner saw the player LED stay lit throughout. The 20-second keep-alive rhythm noted on 2026-09-25 is therefore the pad's own status cadence, which the probe answers, and not a host requirement. This holds for this model, firmware, and macOS version only; it says nothing about the GameSir `0F F2` heartbeat on other models.

## Validate Records and Input

Run from the repository root:

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd test parsers-macos14
swift test --filter 'GameSirDriverTests|GameSirCatalogTests'
```

For each available mode, record the exact VID/PID, product name, transport, firmware, macOS version, and OJD commit. Verify face buttons, all eight D-pad positions and neutral, both sticks, triggers, bumpers, View, Menu, stick clicks, and every advertised extra. Confirm battery and charging changes. Where motion is exposed, capture stationary and independently rotated samples.

Leave enhanced HID and configuration-ready USB modes connected for at least 30 seconds to verify the 500 ms heartbeat. Unplug and reconnect, then confirm that no stale button, battery, lighting-slot, or sequence state survives.

## Validate Physical Output

Use the installed app's Input Test output controls. On Cyclone 2, confirm that color applies one solid RGB value across controllable zones and brightness changes the active slot. On G7 Pro 8K PC, confirm all four home-ring quadrants change together and brightness spans the device's `0...100` register. On the standard G7 Pro, test dock brightness only; RGB is not claimed. Enhanced HID claims only the two documented main rumble motors.

`3537:100A` and `1022` must expose no configuration output. OJD does not issue a mode-switch command. Use the controller's physical Menu+Share combination before connecting when a configuration-ready mode is required.

Report every attempted output, the active lighting slot, observed result, and any transfer error. Do not promote these paths to hardware-verified until the matching identity passes input, heartbeat, reconnect, and each claimed output.

## Windows USB Capture With GameSir Apps

### Results (2026-09-26, G7 SE, Firmware 6.6.4)

**Scenario 1 (no GameSir app, 44 s USBPcap capture).** The pad enumerates as `3537:10A0`, `bcdDevice` `0x0664`, and has two interfaces:

- **Interface 0:** Xbox 360 wired, `FF/5D/01`. Endpoint `0x82` IN and `0x02` OUT, 32-byte packets at a 1 ms interval.
- **Interface 1:** HID. Endpoint `0x84` IN and `0x04` OUT, 64 bytes, with a 214-byte report descriptor.

Input is standard 20-byte XUSB (`00 14 …`); triggers reach 255. The owner pressed each control: the 15 standard XUSB button bits appeared, and bytes 14–19 stayed zero. One extra key reported only on interface 1, as `03 0c 00 46 00 00 00 00 00` and then all zero. Which physical key that was is not recorded. The capture holds no OUT transfers to `0x02`.

**Capture with Nexus running: not possible.** Nexus disconnects the pad when USBPcap is capturing.

**Static analysis of Nexus 2.5.8 instead of a capture.** Nothing was executed.

- **Transport.** Nexus reaches pads only over GIP (APP mode, `3537:1010`), with no HID code at all.
- **Vendor commands** travel in GIP message `0x0F`, command in payload byte 0, with 60-byte replies:

  | Command | Purpose |
  | --- | --- |
  | `09`/`0A` | firmware version |
  | `04`/`05` | read profile |
  | `0B`/`0C` | current profile |
  | `07` | switch or save profile |
  | `0D` | light on/off |
  | `E0` | 60-byte status packet carrying the back buttons and M |
  | `F2` | test or stream mode |
  | `FE` | calibration |
  | `F0` | firmware update chunk |

- **Rumble** uses GIP message `0x09`.
- **Paddle names:** G7 SE `FL1`/`FL2`/`FR1`/`FR2` are L4/L5/R4/R5.
- **Other G7 SE PIDs** in the app's table: `1069 1071 1073 1075 1077 108F 106D`. `1082` does not appear.
- **Firmware:** the images are embedded in the app. They are JieLi AC695X `.ufw` files with a CRC16-keystream header. The payload was not decoded.
- **Not settled:** motion scale, axes and byte order, and how the LED is driven in HID mode. The HID `1082` layout has since been recorded (see Observed).

This static analysis is unverified on hardware.

Everything below was the original capture plan. Scenario 1 above has been run. It plans a capture on Windows 10 under Boot Camp on an Intel Mac, recording USB traffic between GameSir Nexus or GameSir Connect and the controller. The capture should provide evidence OJD cannot get on macOS:

- the configuration commands the apps send to enable gyro, paddle, or extra-button reporting and to switch modes; OJD may never send them, which would explain inputs its packet tracer never sees
- the firmware update transfer; GameSir publishes no standalone firmware files, and the apps fetch updates at runtime, so an unencrypted image could be extracted to identify the IMU part and its full-scale ranges
- input reports in each mode with the apps' features enabled

It should settle these open questions:

- Motion layout and byte order: OJD publishes no GameSir motion. Its former decoder read gyro at offset 14 and accel at offset 20 as little-endian. SDL's GameSir driver reads accel at 14 and gyro at 20 as big-endian, for different PIDs, with a `0xA1 0xC8` header.
- Motion scale and axis signs.
- The IMU sample counter.
- Whether back buttons report as separate bits.

### Capture Setup

Install Wireshark and USBPcap, the Windows USB capture driver; the Wireshark installer offers USBPcap as an option. Check current versions on their official sites. In Wireshark, choose the USBPcap root hub the controller is attached to, then apply a display filter for the controller's device address.

### Scenarios

1. With no GameSir app running, plug in the controller, leave it idle, then press each button and move each axis.
1. Repeat with GameSir Nexus or Connect running.
1. Toggle each app feature (gyro, back-button mapping, mode, polling rate) and note the timestamp of each click.
1. Capture a firmware update only after the owner explicitly decides to update that controller's firmware; the update is a real write to the device.
1. For motion calibration, lay the controller flat and still, rest it on each edge, then rotate it 360° about each axis.

Save each capture as `.pcapng`, named by model, mode, and scenario. Captures contain the device serial; the owner decides before sharing them publicly.

### Model Notes

The owner's G7 SE uses GIP (Xbox One wired). It can show configuration commands and extra-button bits, but not the enhanced HID motion layout. Motion needs an enhanced HID model: G7 Pro 8K PC (`3537:10C5`–`10C8`) or Cyclone 2 (`3537:0575`, `100B`, or `1053`).
