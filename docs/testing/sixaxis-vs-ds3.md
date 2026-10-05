# SIXAXIS and DUALSHOCK 3

Sony's SIXAXIS (CECHZC1) and DUALSHOCK 3 (CECHZC2) both enumerate as `054C:0268`. The SIXAXIS has no rumble motors. OJD's `sony.sixaxis` driver advertises the left and right motors for every `054C:0268`, so on a SIXAXIS the rumble commands succeed and nothing moves. The doc comment on `SixaxisDriver` records this.

## What Other Drivers Do

- Linux `drivers/hid/hid-sony.c` gives both models the one `SIXAXIS_CONTROLLER` quirk and registers force feedback for all of them (`SONY_FF_SUPPORT`, `sony_init_ff`).
- SDL `src/joystick/hidapi/SDL_hidapi_ps3.c` has no model check either.

Neither project tells the two apart, so no known prior art gives a detection method.

## What the Host Can Read

Measured on macOS 27.0 with one CECHZC1E SIXAXIS and one CECHZC2 DUALSHOCK 3, both over USB. The models were matched to their USB locations by unplugging the SIXAXIS and checking which location remained.

These properties are identical on both pads:

| Property | Value |
| --- | --- |
| VID:PID | `054C:0268` |
| `bcdDevice` / `VersionNumber` | `0x0100` |
| Product / manufacturer | `PLAYSTATION(R)3 Controller` / `Sony` |
| Serial number | none |
| Report descriptor | 148 bytes, same SHA-256 (`718163f543ffbc77…`) |
| Max input, output and feature report size | 49 bytes |

Feature reports read with `IOHIDDeviceGetReport`:

| Report | SIXAXIS (`0x00120000`) | DUALSHOCK 3 (`0x01140000`) |
| --- | --- | --- |
| `0x01`, bytes 2 and 4 | `03`, `04` | `04`, `08` |
| `0x01`, from byte 37 | `01 06 00 00 …` | `04 00 01 02 07 00 17 00 …` |
| `0xEF`, bytes 2 and 4 | `03`, `04` | `04`, `08` |
| `0xF2` | the pad's Bluetooth address and per-unit data | same layout |
| `0xF5` | the paired host's Bluetooth address | same layout |
| `0xF7`, `0xF8` | per-unit calibration-like values | same layout |

The `0x01` and `0xEF` differences could be a firmware revision or a model field. This is one unit of each model, so it is not a detection signal. Two or more units of each model with the same split would be needed before OJD could use it.

## Procedure

To add a data point, connect one pad at a time over USB and record its model number from the label, then read feature reports `0x01` and `0xEF` (for example with a short `IOHIDManager` program that calls `IOHIDDeviceGetReport` with `kIOHIDReportTypeFeature`). Do not publish the bytes of `0xF2` or `0xF5`, because they contain Bluetooth addresses.
