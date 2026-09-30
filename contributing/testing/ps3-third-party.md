# Third-party PS3 controllers

Many pads, fight sticks, instruments and adapters sold for the PS3 are not DualShock 3 controllers and do not speak Sony's protocol. OJD routes every non-Sony `PS3Controller` identity in SDL's controller list to the `vendor.ps3-third-party` family. That family follows SDL's `HIDAPI_DriverPS3ThirdParty` in `SDL_hidapi_ps3.c`. Two SDL `PS3Controller` identities use another SDL driver, so they are catalogued under that driver's family:

| Controller | VID:PID | Family | SDL source |
| --- | --- | --- | --- |
| ShanWan DS3 | `2563:0523` | `sony.sixaxis` | `HIDAPI_DriverPS3_IsSupportedDevice` claims it; `is_shanwan` only skips a 1-byte output write that OJD does not send |
| HORI pad `0f0d:0086` | `0f0d:0086` | `xbox.xusb` (`wired`) | `controller_list.h`: "Uses the Xbox 360 protocol, but has PS3 buttons" |

Only the Ant Esports GP100 (`2563:0575`) has hardware evidence. It starts in XInput mode. In that mode macOS sees no input. Hold **Select** and **B** while plugging it in to switch to PS3/PC mode ([#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38)).

## How the driver identifies the format

The descriptor's logical ranges do not match the values these devices send, so the generic HID mapping reads the sticks wrong. SDL does not trust the VID:PID alone. It reads feature report `0x03` and accepts the device when the 8-byte reply has `0x26` at byte 2. For devices without report IDs it reads report `0x00` instead. hidapi prepends a report-ID byte there and IOKit does not, so OJD looks for the marker at byte 1 of that reply.

Once a probe is accepted, the driver decodes raw reports by byte offset. A device that fails both probes keeps the generic HID descriptor mapping, as SDL does. The probe result describes the device, so it survives a reconnect. The Logitech ChillStream (`046d:cad1`) and the GP100 skip the probe and start in raw mode: SDL accepts the ChillStream without one, and the GP100's layout is hardware-verified.

## Report layout

The offsets are for the report as macOS delivers it. Reports of 19 bytes or more use this layout:

| Offset | Contents |
| --- | --- |
| 0 | `0x01` Square, `0x02` Cross, `0x04` Circle, `0x08` Triangle, `0x10` L1, `0x20` R1, `0x40` L2, `0x80` R2 |
| 1 | `0x01` Select, `0x02` Start, `0x04` L3, `0x08` R3, `0x10` Home |
| 2 | Low nibble D-pad hat, `0` north clockwise to `7` north-west |
| 3, 4 | Left stick X, Y; unsigned, center `0x80`, up and left low |
| 5, 6 | Right stick X, Y; same encoding |
| 7–10 | D-pad pressure: right, left, up, down |
| 11–14 | Face pressure: Triangle, Circle, Cross, Square |
| 15, 16 | L1, R1 pressure |
| 17, 18 | L2, R2 analog |

The 18-byte layout (Logitech ChillStream) has no Home and no digital triggers. It moves the hat to the high nibble of byte 1 and shifts the sticks, pressure and triggers down one byte, to offsets 2, 6 and 16.

A face or shoulder button counts as pressed from its byte 0 bit or from bit 7 of its pressure byte (`0x80` or higher), so light pressure or noise does not register a press. A digital trigger bit reads as a fully pulled trigger.

SDL decodes the hat only when its byte changes from the previous report, starting from zero. A hat that stays `0` therefore never reads as held north. The driver matches that: it uses the D-pad pressure bytes until the hat nibble has been nonzero in the session, and whenever the nibble is centered.

## Device quirks

- **Ant Esports GP100 (`2563:0575`).** A GP100 owner's raw HID probe and [PR #42](https://github.com/xsyetopz/OpenJoystickDriver/pull/42) by kartinul verify bytes 1 and 3–18: buttons, D-pad with diagonals, both sticks and both triggers. PR #42 reads byte 0 as a report ID and byte 2 as unused. The driver therefore ignores both on this device and reads its face buttons, shoulders, D-pad and triggers from the pressure and analog bytes alone. It is the only third-party pad with rumble: output report 2, `02 00 <right> <left> 00 00 00 00`. A GP100 owner's hidapi script confirmed this report on hardware. The motor order follows [`hid-shanwan`](https://github.com/hbiyik/hid-shanwan), a Linux driver for `2563:0575` that writes the weak motor to byte 2 and the strong motor to byte 3.
- **Saitek Cyborg V.3 Rumble Pad (`06a3:f622`).** SDL does not trust its hat bits and reads a D-pad direction as held from any nonzero pressure. The driver does the same.

## Not supported

- Rumble on pads other than the GP100. SDL's third-party driver sends no output reports, because some of these pads then rumble without stopping.
- Motion. Bytes after the triggers can carry accelerometer data, which the driver ignores.

## Procedure

Plug the controller in (the GP100 in PS3/PC mode), then confirm the route:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller list
```

The entry should report `protocol=vendor.ps3-third-party`. Then watch the controls:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless controller state
```

Push each stick fully right and fully up, and confirm positive X and negative Y. Confirm both triggers rest at 0. Press every button, every D-pad direction and Home, and confirm the reported name matches the label. If the sticks read wrong, the probe likely failed and the descriptor mapping is active. Report that with the VID:PID and a raw capture in a new issue. On the GP100, run `./Scripts/ojd diagnose rumble-motors 9571 1397` and confirm that the left (strong) step drives the heavier motor. Report GP100 results on [#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38).
