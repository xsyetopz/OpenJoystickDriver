# SIXAXIS and DUALSHOCK 3

SIXAXIS (CECHZC1) and DUALSHOCK 3 (CECHZC2) both enumerate as 054C:0268. The SIXAXIS has no rumble motors, but OJD's `SonySixaxis` driver advertises both motors for every 054C:0268: SIXAXIS rumble commands succeed and nothing moves. `SixaxisDriver` documents this.

## Other Drivers

- Linux `drivers/hid/hid-sony.c` gives both models one `SIXAXIS_CONTROLLER` quirk and registers force feedback for all (`SONY_FF_SUPPORT`, `sony_init_ff`).
- SDL `src/joystick/hidapi/SDL_hidapi_ps3.c` has no model check.

Neither tells the models apart: no prior detection method.

## Host-Readable Properties

macOS 27.0, one CECHZC1E SIXAXIS and one CECHZC2 DUALSHOCK 3, both USB. Unplugging the SIXAXIS identified locations.

Identical on both:

| Property | Value |
| --- | --- |
| VID:PID | 054C:0268 |
| `bcdDevice` / `VersionNumber` | 0x0100 |
| Product / manufacturer | PLAYSTATION(R)3 Controller / Sony |
| Serial number | none |
| Report descriptor | 148 bytes, same SHA-256 (718163f543ffbc77…) |
| Max input, output, feature report size | 49 bytes |

Feature reports read with `IOHIDDeviceGetReport`:

| Report | SIXAXIS (0x00120000) | DUALSHOCK 3 (0x01140000) |
| --- | --- | --- |
| 0x01, bytes 2 and 4 | 03, 04 | 04, 08 |
| 0x01, from byte 37 | 01 06 00 00 … | 04 00 01 02 07 00 17 00 … |
| 0xEF, bytes 2 and 4 | 03, 04 | 04, 08 |
| 0xF2 | pad's Bluetooth address, per-unit data | same |
| 0xF5 | paired host's Bluetooth address | same |
| 0xF7, 0xF8 | per-unit calibration-like values | same layout |

The 0x01 and 0xEF differences could be firmware revision or a model field. One unit per model is no detection signal; OJD needs two or more of each with the same split.

## Add a Data Point

1. Connect one pad at a time over USB; record the label's model number.
2. Read feature reports 0x01 and 0xEF, e.g. an `IOHIDManager` program calling `IOHIDDeviceGetReport` with `kIOHIDReportTypeFeature`.

Do not publish 0xF2 or 0xF5 bytes (Bluetooth addresses).
