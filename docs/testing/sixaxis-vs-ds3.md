# SIXAXIS and DUALSHOCK 3

The SIXAXIS (CECHZC1) and the DUALSHOCK 3 (CECHZC2) look like twins to a computer: both say they're 054C:0268. The SIXAXIS has no rumble motors, but OJD's `SonySixaxis` driver offers both motors for every 054C:0268. So a rumble command to a SIXAXIS succeeds and nothing moves. `SixaxisDriver` notes this in its code.

## Other Drivers

- Linux `drivers/hid/hid-sony.c` gives both models one `SIXAXIS_CONTROLLER` quirk and turns on force feedback for all of them (`SONY_FF_SUPPORT`, `sony_init_ff`).
- SDL `src/joystick/hidapi/SDL_hidapi_ps3.c` doesn't check the model.

Neither one tells the models apart, so there's no known way to do it.

## What a Mac Can Read

macOS 27.0, one CECHZC1E SIXAXIS and one CECHZC2 DUALSHOCK 3, both on USB. Unplugging the SIXAXIS showed which entry was which.

The same on both:

| Property | Value |
| --- | --- |
| VID:PID | 054C:0268 |
| `bcdDevice` / `VersionNumber` | 0x0100 |
| Product / manufacturer | PLAYSTATION(R)3 Controller / Sony |
| Serial number | none |
| Report descriptor | 148 bytes, same SHA-256 (718163f543ffbc77…) |
| Biggest input, output, and feature report | 49 bytes |

Feature reports read with `IOHIDDeviceGetReport`:

| Report | SIXAXIS (0x00120000) | DUALSHOCK 3 (0x01140000) |
| --- | --- | --- |
| 0x01, bytes 2 and 4 | 03, 04 | 04, 08 |
| 0x01, from byte 37 | 01 06 00 00 … | 04 00 01 02 07 00 17 00 … |
| 0xEF, bytes 2 and 4 | 03, 04 | 04, 08 |
| 0xF2 | the controller's Bluetooth address, data unique to each unit | same |
| 0xF5 | the paired computer's Bluetooth address | same |
| 0xF7, 0xF8 | values that look like calibration, unique to each unit | same layout |

The 0x01 and 0xEF differences could be a firmware version or a model field. One controller of each model can't prove which. OJD needs two or more of each that split the same way.

## Add Your Controller

1. Plug in one controller at a time over USB. Write down the model number on its label.
2. Read feature reports 0x01 and 0xEF, for example with an `IOHIDManager` program that calls `IOHIDDeviceGetReport` with `kIOHIDReportTypeFeature`.

Don't post the 0xF2 or 0xF5 bytes, because they're Bluetooth addresses.
