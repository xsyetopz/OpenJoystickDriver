# Third-Party PS3 Controllers

Many non-Sony pads copy the PS3 controller, each a little differently. OJD sends every non-Sony `PS3Controller` ID in SDL's controller list to the `VendorPS3ThirdParty` family, following SDL's `HIDAPI_DriverPS3ThirdParty` in `SDL_hidapi_ps3.c`. Two IDs use a different SDL driver, so OJD's catalog files them under that driver's family:

| Controller | VID:PID | Family | SDL source |
| --- | --- | --- | --- |
| ShanWan DS3 | 2563:0523 | `SonySixaxis` | `HIDAPI_DriverPS3_IsSupportedDevice` claims it; `is_shanwan` only skips a 1-byte output write that OJD doesn't send |
| HORI pad 0f0d:0086 | 0f0d:0086 | `XboxXUSB` (`wired`) | `controller_list.h`: "Uses the Xbox 360 protocol, but has PS3 buttons" |

Only the Ant Esports GP100 (2563:0575) has been tested on hardware. It starts in XInput mode, where macOS sees no input. To get PS3/PC mode, hold Select and B while you plug it in ([#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38)).

## How the Driver Recognizes These Pads

These pads describe their stick ranges one way and then send something else, so OJD's general HID reader gets the sticks wrong. SDL asks the pad a question first: it reads feature report 0x03 and accepts the pad when the 8-byte reply has 0x26 at byte 2. A pad without report IDs gets asked for report 0x00 instead. hidapi adds a report ID byte in front there and IOKit doesn't, so OJD looks for the marker at byte 1.

When the pad answers, the driver reads raw reports byte by byte. A pad that fails both questions keeps the general HID reader, as in SDL. OJD remembers the answer across a reconnect.

The Logitech ChillStream (046d:cad1) and the GP100 skip the question. SDL accepts the ChillStream without one, and the GP100 layout is confirmed on hardware. Their records use the `HIDReportLayout` family and describe their reports in the record's `input` field (see [Adding or changing a controller record](../../wiki/Controller-Records.md)). The ChillStream uses the 18-byte layout below. The GP100 uses the bytes under Pads That Behave Differently.

## Report Layout

Offsets count from the start of the report as macOS hands it over. Reports of 19 bytes or more use:

| Offset | Contents |
| --- | --- |
| 0 | 0x01 Square, 0x02 Cross, 0x04 Circle, 0x08 Triangle, 0x10 L1, 0x20 R1, 0x40 L2, 0x80 R2 |
| 1 | 0x01 Select, 0x02 Start, 0x04 L3, 0x08 R3, 0x10 Home |
| 2 | Low 4 bits: D-pad (hat), 0 is up, going clockwise to 7, up-left |
| 3, 4 | Left stick X, Y. No sign, center 0x80, up and left are low |
| 5, 6 | Right stick X, Y, read the same way |
| 7-10 | D-pad pressure: right, left, up, down |
| 11-14 | Face pressure: Triangle, Circle, Cross, Square |
| 15, 16 | L1, R1 pressure |
| 17, 18 | L2, R2 analog |

The 18-byte layout has no Home and no on/off trigger bits. The hat moves to the high 4 bits of byte 1. Sticks, pressure, and triggers each move one byte earlier, to offsets 2, 6, and 16.

A face or shoulder button counts as pressed when its byte 0 bit is set, or bit 7 of its pressure byte is set (0x80 or higher). A light touch or noise doesn't count. An on/off trigger bit reads as fully pulled. For a pad that answered the question, each report's length picks its layout. The ChillStream record reads every report of 18 bytes or more with the 18-byte offsets.

SDL reads the hat only when its byte changes from the report before, starting from zero. So a hat that stays at 0 never reads as held up. The driver does the same: it uses the D-pad pressure bytes until the hat has been nonzero at least once in the session, and any time the hat is centered.

## Pads That Behave Differently

| Device | VID:PID | Behavior |
| --- | --- | --- |
| Ant Esports GP100 | 2563:0575 | A GP100 owner's raw HID probe and [PR #42](https://github.com/xsyetopz/OpenJoystickDriver/pull/42) by kartinul confirm bytes 1 and 3 to 18: buttons, D-pad with diagonals, both sticks, both triggers. PR #42 reads byte 0 as a report ID and byte 2 as unused, so its record ignores both. It reads face buttons, shoulders, D-pad, and triggers from the pressure and analog bytes alone, from reports of 19 bytes or more. It's the only third-party pad with rumble: output report 2, `02 00 <right> <left> 00 00 00 00`, confirmed on hardware by a GP100 owner's hidapi script. The motor order follows [`hid-shanwan`](https://github.com/hbiyik/hid-shanwan), a Linux driver for 2563:0575 that writes the weak motor to byte 2 and the strong motor to byte 3 |
| Saitek Cyborg V.3 Rumble Pad | 06a3:f622 | SDL doesn't trust its hat bits, and reads a D-pad direction as held when its pressure is anything above zero. SDL only accepts it after the question, so it stays in `VendorPS3ThirdParty`. Its record sets the `dpad-pressure` quirk, so the driver does the same |

## What Doesn't Work

- Rumble on pads other than the GP100. SDL's driver sends them no output reports, because some of these pads then rumble and never stop.
- Motion. The bytes after the triggers can carry accelerometer data, which the driver ignores.

## Steps

1. Plug the controller in (the GP100 in PS3/PC mode).
2. Check how OJD connected it (`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or `VVVV:PPPP`):

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

   `show` reports `HIDReportLayout` for the GP100 and ChillStream, `VendorPS3ThirdParty` for any other pad.
3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. Push each stick fully right, then fully up. Check that right gives a positive X and up a negative Y.
5. Check that the triggers rest at 0.
6. Press every button, D-pad direction, and Home. Check that each name matches.
7. If the sticks read wrong, the question probably failed and the general HID reader took over. Report it in an issue with the VID:PID and a raw capture.
8. On the GP100, run `just diagnose-rumble-motors 9571 1397`. Check that the left (strong) step runs the heavier motor. Report GP100 results to [#38](https://github.com/xsyetopz/OpenJoystickDriver/issues/38).
