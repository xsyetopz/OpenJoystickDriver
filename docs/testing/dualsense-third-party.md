# Third-Party DualSense Controllers

Licensed PS5 controllers from HORI, PDP, Razer, NACON, and Backbone speak the DualSense language, but most of them leave some features out. OJD lists each non-Sony `PS5Controller` ID from SDL's controller list as `SonyDualSense`, and marks non-Sony vendor IDs with the `third-party` quirk. That quirk makes the DualSense driver take the non-Sony path of SDL's `HIDAPI_DriverPS5` in `SDL_hidapi_ps5.c`. One exception: the Backbone One PlayStation Edition Gen 2 (358a:0304). SDL turns it down ("doesn't appear to use the DualSense protocol"), so it's a `HIDDescriptor` record.

Nobody has tested a third-party DualSense controller on hardware yet.

## Asking What the Pad Can Do

At startup the driver asks the pad which features it has, by reading feature report 0x03. A good reply is 48 bytes with 0x28 at byte 2. The features:

| Byte | Bit | Feature |
| --- | --- | --- |
| 4 | 0x02 | Motion sensors |
| 4 | 0x04 | Lightbar |
| 4 | 0x08 | Rumble |
| 4 | 0x40 | Touchpad |
| 20 | 0x80 | Player indicator LEDs |

After a good reply, the driver reads SDL's alternate report layout and only drives the features listed. It never sends adaptive trigger effects. With no answer, it keeps the standard DualSense layout, with no motion, touch, or output. OJD remembers the answer across a reconnect.

## Alternate Report Layout

Offsets count from the first byte after the report ID. Sticks, triggers, and buttons sit where they do on a DualSense.

| Offset | Contents |
| --- | --- |
| 11-14 | 32-bit little-endian packet sequence |
| 15-26 | Gyroscope and accelerometer |
| 27, 28 | 16-bit sensor timestamp, microseconds |
| 31-34 | First touch contact |
| 35-38 | Second touch contact |

## Pads That Behave Differently

| Device | VID:PID | Behavior |
| --- | --- | --- |
| Razer Wolverine V2 Pro | 1532:100b wired, 100c wireless | Never answers the question. As in SDL: alternate layout, motion and touch, no output |
| Razer Kitsune | 1532:1012 | Same, touch only |
| Razer Raiju V3 Pro | 1532:1024 wired, 1026 wireless | Same, touch only |
| NACON Revolution 5 Pro | 3285:0d19 wired, 0d18 wireless | The reply leaves out rumble, which the pad has; the driver adds it after a good reply |

- Wireless receivers (3285:0d18, 1532:100c, 1532:1026) keep repeating the last packet when no controller is paired. As in SDL, the driver ignores a report with the same sequence number as the one before. After 500 ms of repeats it reports the controller disconnected, and connected again when a new sequence number arrives. Output waits until then. A receiver that stops sending completely goes unnoticed, because the check only runs when a report arrives.
- Triggers: an analog value of 0 with the on/off bit set reads as fully pulled, the way SDL handles every PS5 controller.

## What Doesn't Work

- Adaptive triggers on any non-Sony controller.
- Touch and motion on pads that haven't answered the question. The profile lists both until the pad answers, but the pad sends neither.

## Steps

1. Connect the controller.
2. Check how OJD connected it (`ojd` is the [command-line tool](../../wiki/Command-Line.md); `<controller>` is a listed ID or `VVVV:PPPP`):

   ```bash
   ojd controller list
   ojd controller show <controller>
   ```

   `show` reports protocol `SonyDualSense`.
3. Watch the controls:

   ```bash
   ojd controller watch <controller>
   ```

4. Check both sticks, both triggers from rest to fully pulled, every button, and the touchpad and motion if the pad has them.
5. Wireless receiver only: turn the controller off and on. Check that it disconnects and reconnects.
6. Report the VID:PID and a raw capture in an issue.
