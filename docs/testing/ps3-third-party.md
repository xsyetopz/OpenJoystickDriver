# Third-Party PS3 Controllers

OJD routes every non-Sony `PS3Controller` identity in SDL's controller list to the `VendorPS3ThirdParty` family, following SDL's `HIDAPI_DriverPS3ThirdParty` in `SDL_hidapi_ps3.c`. Two identities use another SDL driver and sit under that family in the catalog:

| Controller | VID:PID | Family | SDL source |
| --- | --- | --- | --- |
| ShanWan DS3 | 2563:0523 | `SonySixaxis` | `HIDAPI_DriverPS3_IsSupportedDevice` claims it; `is_shanwan` only skips a 1-byte output write OJD does not send |
| HORI pad 0f0d:0086 | 0f0d:0086 | `XboxXUSB` (`wired`) | `controller_list.h`: "Uses the Xbox 360 protocol, but has PS3 buttons" |

Only the Ant Esports GP100 (2563:0575) has hardware evidence. It starts in XInput mode, where macOS sees no input. Hold Select and B while plugging it in for PS3/PC mode ([#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38)).

## How the Driver Identifies the Format

The descriptor's logical ranges do not match what these devices send, so generic HID mapping misreads the sticks. SDL reads feature report 0x03 and accepts the device when the 8-byte reply has 0x26 at byte 2. Without report IDs it reads report 0x00; hidapi prepends a report-ID byte there and IOKit does not, so OJD looks for the marker at byte 1.

After a successful probe the driver decodes raw reports by byte offset. A device failing both probes keeps the generic HID mapping, as in SDL. The result survives a reconnect.

The Logitech ChillStream (046d:cad1) and the GP100 need no probe: SDL accepts the ChillStream without one, and the GP100 layout is hardware-verified. Their records bind the `HIDReportLayout` family and describe reports in the record's `input` field (see [Adding or changing a controller record](../../wiki/Controller-Records.md)). The ChillStream uses the 18-byte layout below; the GP100 uses the bytes under Device Quirks.

## Report Layout

Offsets are for the report as macOS delivers it. Reports of 19 bytes or more use:

| Offset | Contents |
| --- | --- |
| 0 | 0x01 Square, 0x02 Cross, 0x04 Circle, 0x08 Triangle, 0x10 L1, 0x20 R1, 0x40 L2, 0x80 R2 |
| 1 | 0x01 Select, 0x02 Start, 0x04 L3, 0x08 R3, 0x10 Home |
| 2 | Low nibble D-pad hat, 0 north clockwise to 7 north-west |
| 3, 4 | Left stick X, Y; unsigned, center 0x80, up and left low |
| 5, 6 | Right stick X, Y; same encoding |
| 7-10 | D-pad pressure: right, left, up, down |
| 11-14 | Face pressure: Triangle, Circle, Cross, Square |
| 15, 16 | L1, R1 pressure |
| 17, 18 | L2, R2 analog |

The 18-byte layout has no Home and no digital triggers. The hat moves to the high nibble of byte 1; sticks, pressure, and triggers shift down one byte, to offsets 2, 6, and 16.

A face or shoulder button is pressed from its byte 0 bit or from bit 7 of its pressure byte (0x80 or higher); light pressure or noise does not count. A digital trigger bit reads as fully pulled. For a probed pad, report length picks the layout per report. The ChillStream record reads every report of 18 bytes or more with the 18-byte offsets.

SDL decodes the hat only when its byte changes from the previous report, starting from zero, so a hat staying 0 never reads as held north. The driver matches that, using the D-pad pressure bytes until the hat nibble has been nonzero in the session, and whenever it is centered.

## Device Quirks

| Device | VID:PID | Behavior |
| --- | --- | --- |
| Ant Esports GP100 | 2563:0575 | A GP100 owner's raw HID probe and [PR #42](https://github.com/xsyetopz/OpenJoystickDriver/pull/42) by kartinul verify bytes 1 and 3-18: buttons, D-pad with diagonals, both sticks, both triggers. PR #42 reads byte 0 as a report ID and byte 2 as unused, so its record ignores both and reads face buttons, shoulders, D-pad, and triggers from the pressure and analog bytes alone, from reports of 19 bytes or more. Only third-party pad with rumble: output report 2, `02 00 <right> <left> 00 00 00 00`, confirmed on hardware by a GP100 owner's hidapi script. Motor order follows [`hid-shanwan`](https://github.com/hbiyik/hid-shanwan), a Linux driver for 2563:0575 writing the weak motor to byte 2 and the strong motor to byte 3 |
| Saitek Cyborg V.3 Rumble Pad | 06a3:f622 | SDL does not trust its hat bits and reads a D-pad direction as held from any nonzero pressure. SDL admits it only after the feature probe, so it stays in `VendorPS3ThirdParty`. Its record sets the `dpad-pressure` quirk, so the driver does the same |

## Unsupported

- Rumble on pads other than the GP100: SDL's driver sends no output reports, because some of these pads then rumble without stopping.
- Motion: bytes after the triggers can carry accelerometer data, which the driver ignores.

## Procedure

1. Plug the controller in (the GP100 in PS3/PC mode).
2. Check the route (`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or `VVVV:PPPP`):

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

   `show` reports `HIDReportLayout` for the GP100 and ChillStream, `VendorPS3ThirdParty` for any other pad.
3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. Push each stick fully right, then fully up. Check for positive X and negative Y.
5. Check triggers rest at 0.
6. Press every button, D-pad direction, and Home. Check each name matches.
7. If the sticks read wrong, the probe likely failed and the descriptor mapping is active. Report it with the VID:PID and a raw capture in an issue.
8. On the GP100, run `just diagnose-rumble-motors 9571 1397`. Check the left (strong) step drives the heavier motor. Report GP100 results to [#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38).
