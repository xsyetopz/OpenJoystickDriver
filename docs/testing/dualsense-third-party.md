# Third-Party DualSense Controllers

Some licensed PS5 controllers from HORI, PDP, Razer, NACON and Backbone speak the DualSense protocol without every DualSense feature. OJD catalogs every non-Sony `PS5Controller` identity in SDL's controller list as `sony.dualsense`. When the vendor ID is not Sony's, the DualSense driver follows the non-Sony path of SDL's `HIDAPI_DriverPS5` in `SDL_hidapi_ps5.c`. The exception is the Backbone One PlayStation Edition Gen 2 (`358a:0304`). SDL rejects it because it "doesn't appear to use the DualSense protocol", so it is catalogued as `hid.descriptor`.

No third-party DualSense controller has hardware evidence.

## Capability Probe

At startup the driver reads feature report `0x03`. A valid reply is 48 bytes long and has `0x28` at byte 2. It lists the controller's features:

| Byte | Bit | Feature |
| --- | --- | --- |
| 4 | `0x02` | Motion sensors |
| 4 | `0x04` | Lightbar |
| 4 | `0x08` | Rumble |
| 4 | `0x40` | Touchpad |
| 20 | `0x80` | Player indicator LEDs |

After a valid reply, the driver reads input in SDL's alternate report layout. Output is limited to the listed features. Adaptive triggers are never sent. A controller that does not answer keeps the standard DualSense layout, with no motion, touch or output. The probe result describes the controller, so it survives a reconnect.

## Alternate Report Layout

The offsets are for the payload after the report ID. Sticks, triggers and buttons are where a DualSense has them.

| Offset | Contents |
| --- | --- |
| 11–14 | 32-bit little-endian packet sequence |
| 15–26 | Gyroscope and accelerometer |
| 27, 28 | 16-bit sensor timestamp in microseconds |
| 31–34 | First touch contact |
| 35–38 | Second touch contact |

## Device Quirks

- **Razer Wolverine V2 Pro (`1532:100b` wired, `100c` wireless).** They never answer the probe. As in SDL, they use the alternate layout with motion and touch and no output.
- **Razer Kitsune (`1532:1012`) and Raiju V3 Pro (`1024` wired, `1026` wireless).** Same as the Wolverine, with touch and no motion.
- **NACON Revolution 5 Pro (`3285:0d19` wired, `0d18` wireless).** Their probe reply omits rumble, which they have. The driver adds rumble after a valid reply.
- **Wireless receivers (`3285:0d18`, `1532:100c`, `1532:1026`).** A receiver keeps sending its last packet while no controller is paired to it. As SDL does, the driver ignores a report that repeats the previous packet sequence. It reports the controller disconnected after 500 ms of repeats and connected again on a new sequence. Output waits for that connection. A receiver that stops sending reports entirely is not detected, because the check runs only when a report arrives.
- **Triggers.** When a trigger's analog byte is 0 and its digital button bit is set, the trigger reads as fully pulled. SDL applies this to every PS5 controller.

## Not Supported

- Adaptive triggers on any non-Sony controller.
- A controller's profile still lists touch and motion before the probe answers. Unprobed controllers send neither.

## Procedure

Connect the controller, then confirm the route (`ojd` is the [command-line tool](../../wiki/Command-Line.md), and `<controller>` is an ID from the list or its `VVVV:PPPP`):

```bash
ojd controller list
ojd controller show <controller>
```

`show` should report the protocol `sony.dualsense`. Then watch the controls:

```bash
ojd controller watch <controller>
```

Check both sticks, both triggers from rest to full, every button, and the touchpad and motion if the controller has them. For a wireless receiver, turn the controller off and on, and confirm that it disconnects and reconnects. Report results with the VID:PID and a raw capture in a new issue.
