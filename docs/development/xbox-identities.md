# Xbox Fallback Identities

OJD's virtual gamepad can dress up as an Xbox controller so games recognize it. The costume has to fit exactly, or games ignore it. A safe virtual profile needs all four of these:

1. an exact virtual vendor and product ID (VID/PID)
2. the descriptor and report bytes that match that ID
3. a live `GCController.supportsHIDDevice` answer, wherever GameController.framework matters
4. a test on real hardware for any claim about GameController.framework

OJD publishes four virtual HID profiles: SDLCompatible, GameControllerCompatible, Generic, and InControlCompatible, which poses as the DualShock 4 v2 (`054C:09CC`) over USB. [CLI and Application Runtime](cli-and-runtime.md) explains how OJD picks one and how you can override it. OJD has no other virtual profile.

Linux's `xpad.c` tells Linux which real devices are which. It doesn't show that a virtual HID device on macOS can pass as one of them.

## Evidence: SDLCompatible

SDLCompatible is the only virtual profile that sends Xbox One GIP packets. No real capture exists for it yet, so it publishes `045e:0b0c` (Xbox Adaptive Controller over Bluetooth) with a USB connection type. Its OJD-made descriptor wraps SDL's USB GIP packets as HID reports.

| Finding | Source |
| --- | --- |
| macOS 27 says every IOHIDUserDevice is connected by Virtual. SDL 3.4.16 treats only a connection name that starts with Bluetooth as Bluetooth, so its Xbox One driver reads the device as USB GIP. | `src/hidapi/mac/hid.c:551-568`, `:671-697`; `src/joystick/hidapi/SDL_hidapi_xboxone.c:1935-2002` |
| The report ID is the GIP command: input 0x20, Guide 0x07, rumble 0x09. `XboxOneGIPHIDDescriptor` and `XboxOneGIPHIDReportFormat` build them, and `XboxOneGIPSDLOracleTests` reads them the way SDL does. | `:1036-1233`, `:1242-1247`, `:533-591` |
| Saved `045e:02fd` tests with a Bluetooth-shaped descriptor (input report 1, rumble report 3) got no SDL HIDAPI input or rumble. | |
| GameSir G7 SE over USB GIP works with GameController.framework on real hardware. A real GIP controller sends Hello and one resting 0x20, then only sends input when something changes. So a packet log with only status packets after that doesn't mean setup failed. | |
| A custom SDL 3.4.16 HIDAPI xboxone build matched Bluetooth `045e:0b13` and used the 17-byte BLE road. A 12-second watch of the input stayed quiet (no button pressed). Steam's `hid_init` hangs. | |
| DualShock 4 and DualSense identities published from that controller passed `GCController.supportsHIDDevice` and custom HIDAPI `SDL_OpenGamepad`. OJD publishes neither. | |

## Evidence: GameControllerCompatible

GameController reads no input from GIP-shaped reports. On `045e:02fd` (listed with `GCIOMatchVirtual`) it names them "Xbox Wireless Controller (Xbox One)". `OpenJoystickDriverGameControllerProbe` reports `live_input=false`, so apps such as Safari list a controller that never moves. That's why SDLCompatible publishes `045e:0b0c` instead.

| Finding | Source |
| --- | --- |
| The kext lists `045e:0b0c` without `GCIOMatchVirtual`. On macOS 27 the virtual device gets `AppleUserHIDEventDriver`, not `AppleGCHIDUserEventDriver`, and GameController lists nothing. | |
| SDL 3.4.16's Xbox One driver can't tell 0b0c from 02fd and calls it "Xbox Adaptive Controller". | `SDL_hidapi_xboxone.c:155-183`, `:274-287`; `controller_list.h:347` |
| The kext lists `045e:0b13` with `GCIOMatchVirtual`, so the framework accepts a virtual device with that ID. GameSir G7 SE over USB GIP published as `045e:0b13` works with GameController.framework on real hardware. | |

GameControllerCompatible publishes `045e:0b13` with a Bluetooth connection type and the `XboxSeriesBluetooth` layout (`XboxSeriesBluetoothReport`):

- Input report 1: 17 bytes, with buttons at the bit positions SDL's Xbox One Bluetooth driver reads (A 1, B 2, X 4, Y 5, LB 7, RB 8, View 11, Menu 12, Guide 13, L3 14, R3 15). It has four 16-bit stick axes (the right stick on Z/Rz), 10-bit Brake and Accelerator triggers, a hat that carries only the D-pad, and Share as Consumer 0xB2.
- Input report 2: Guide again, as System Main Menu, which GameController reads as Home.
- Output report 3: rumble.

With `ojd virtual feed`, GameController names every control once, Share included. Home reaches only the front app, and only if that app turns off the button's system gesture. The profile sets `worksWithDefaultSDLHints: false` because SDL reads it through HIDAPI only on a Bluetooth connection, and macOS 27 says Virtual. `ojd virtual launch --sdl-gamecontroller-backend` makes SDL read it through GameController instead.

## Apple's Controller List

GameController MobileAsset 10.5.2, downloaded 2026-07-12, had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. That's true only for that system and that asset, so check again after macOS or MobileAsset updates:

```bash
ojd diagnose --output /tmp/ojd-support.json
jq .systemGamepadAudit /tmp/ojd-support.json
```

The audit reads the list on the current Mac, and the support report includes it. A missing entry doesn't mean the controller won't work. A listed entry doesn't replace a live `GCController.supportsHIDDevice` answer or a hardware test.

## How OJD Picks One

`VirtualHIDProfileSelector` saves nothing. It picks automatically unless the controller's model (vendor and product) has a saved override. It doesn't look at the protocol family or the front app. It picks SDLCompatible when that fits and Generic otherwise, and never picks GameControllerCompatible or InControlCompatible.

## Before Swapping In a Real Capture

To replace the guessed `045e:0b0c` descriptor with a real capture, first get a checked result from games: the SDL and GameController probes must cover input, reconnecting, rumble, and lights.
