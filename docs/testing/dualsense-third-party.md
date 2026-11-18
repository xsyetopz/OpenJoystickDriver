# Third-Party DualSense Controllers

Licensed PS5 controllers from HORI, PDP, Razer, NACON, and Backbone speak the DualSense protocol without every feature. OJD catalogs each non-Sony `PS5Controller` identity in SDL's controller list as `SonyDualSense`, with the `third-party` quirk on non-Sony vendor IDs. The quirk makes the DualSense driver follow the non-Sony path of SDL's `HIDAPI_DriverPS5` in `SDL_hidapi_ps5.c`. Exception: the Backbone One PlayStation Edition Gen 2 (358a:0304). SDL rejects it ("doesn't appear to use the DualSense protocol"), so it is a `HIDDescriptor`.

No third-party DualSense controller has hardware evidence.

## Capability Probe

At startup the driver reads feature report 0x03: 48 bytes with 0x28 at byte 2 when valid. Features:

| Byte | Bit | Feature |
| --- | --- | --- |
| 4 | 0x02 | Motion sensors |
| 4 | 0x04 | Lightbar |
| 4 | 0x08 | Rumble |
| 4 | 0x40 | Touchpad |
| 20 | 0x80 | Player indicator LEDs |

After a valid reply the driver reads SDL's alternate report layout and limits output to the listed features. It never sends adaptive triggers. With no answer it keeps the standard DualSense layout: no motion, touch, or output. The result survives a reconnect.

## Alternate Report Layout

Offsets count the payload after the report ID. Sticks, triggers, and buttons sit as on a DualSense.

| Offset | Contents |
| --- | --- |
| 11-14 | 32-bit little-endian packet sequence |
| 15-26 | Gyroscope and accelerometer |
| 27, 28 | 16-bit sensor timestamp, microseconds |
| 31-34 | First touch contact |
| 35-38 | Second touch contact |

## Device Quirks

| Device | VID:PID | Behavior |
| --- | --- | --- |
| Razer Wolverine V2 Pro | 1532:100b wired, 100c wireless | Never answers the probe. As in SDL: alternate layout, motion and touch, no output |
| Razer Kitsune | 1532:1012 | Same, touch only |
| Razer Raiju V3 Pro | 1532:1024 wired, 1026 wireless | Same, touch only |
| NACON Revolution 5 Pro | 3285:0d19 wired, 0d18 wireless | Probe reply omits rumble, which the pad has; the driver adds it after a valid reply |

- Wireless receivers (3285:0d18, 1532:100c, 1532:1026) keep sending the last packet with no controller paired. As in SDL, the driver ignores a report repeating the previous sequence. After 500 ms of repeats it reports disconnected, and connected on a different sequence. Output waits for that. A receiver that stops sending entirely goes undetected: the check runs only on a report.
- Triggers: analog 0 with the digital bit set reads as fully pulled, as SDL does for every PS5 controller.

## Unsupported

- Adaptive triggers on any non-Sony controller.
- Touch and motion on unprobed controllers: the profile lists both before the probe answers, but they send neither.

## Procedure

1. Connect the controller.
2. Check the route (`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or `VVVV:PPPP`):

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

   `show` reports protocol `SonyDualSense`.
3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. Check both sticks, both triggers rest to full, every button, touchpad and motion if present.
5. Wireless receiver: turn the controller off and on. Check it disconnects and reconnects.
6. Report the VID:PID and a raw capture in an issue.
