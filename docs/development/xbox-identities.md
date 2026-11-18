# Xbox Fallback Identities

A safe virtual profile needs all of these:

1. an exact virtual VID/PID;
2. the matching descriptor and report bytes;
3. a live `GCController.supportsHIDDevice` result where GameController.framework matters;
4. hardware evidence for GameController.framework claims.

OJD publishes three virtual HID profiles: SDLCompatible, GameControllerCompatible, and Generic. [CLI and Application Runtime](cli-and-runtime.md) holds the selection and override contract. OJD has no other virtual profile.

Linux `xpad.c` identifies physical devices for Linux; it does not show a macOS virtual HID device can impersonate them.

## Evidence: SDLCompatible

SDLCompatible is the only Xbox One GIP-framed virtual profile. Until a genuine capture exists, it publishes `045e:0b0c` (Xbox Adaptive Controller over Bluetooth) with transport USB and an OJD descriptor carrying SDL's USB GIP packets as HID reports.

| Finding | Source |
| --- | --- |
| macOS 27 reports every IOHIDUserDevice transport as Virtual. SDL 3.4.16 reads only a transport starting with Bluetooth as the Bluetooth bus, so its Xbox One driver parses the device as USB GIP. | `src/hidapi/mac/hid.c:551-568`, `:671-697`; `src/joystick/hidapi/SDL_hidapi_xboxone.c:1935-2002` |
| The report ID is the GIP command: input 0x20, Guide 0x07, rumble 0x09. `XboxOneGIPHIDDescriptor` and `XboxOneGIPHIDReportFormat` implement them; `XboxOneGIPSDLOracleTests` parses them as SDL does. | `:1036-1233`, `:1242-1247`, `:533-591` |
| Recorded `045e:02fd` experiments with a Bluetooth-layout descriptor (input report 1, rumble report 3) gave no SDL HIDAPI input or rumble. | |
| GameSir G7 SE USB GIP is hardware-verified for GameController.framework. Physical GIP sends Hello plus one rest 0x20, then change-only input, so a status-only packet log after that is not a failed init. | |
| A custom SDL 3.4.16 HIDAPI xboxone build bound Bluetooth `045e:0b13` and used the 17-byte BLE path. A 12 s interrupt watch stayed idle (no button pressed). Steam `hid_init` hangs. | |
| DualShock 4 and DualSense identities published from that pad passed `GCController.supportsHIDDevice` and custom HIDAPI `SDL_OpenGamepad`. OJD publishes neither. | |

## Evidence: GameControllerCompatible

GameController reads no input from GIP-framed reports. On `045e:02fd` (listed with `GCIOMatchVirtual`) it binds them as "Xbox Wireless Controller (Xbox One)". `OpenJoystickDriverGameControllerProbe` reports `live_input=false`, so apps such as Safari list a pad that never moves. SDLCompatible therefore publishes `045e:0b0c`.

| Finding | Source |
| --- | --- |
| The kext lists `045e:0b0c` without `GCIOMatchVirtual`. On macOS 27 the virtual device gets `AppleUserHIDEventDriver`, not `AppleGCHIDUserEventDriver`, and GameController lists nothing. | |
| SDL 3.4.16 cannot tell 0b0c from 02fd in its Xbox One driver and names it "Xbox Adaptive Controller". | `SDL_hidapi_xboxone.c:155-183`, `:274-287`; `controller_list.h:347` |
| The kext lists `045e:0b13` with `GCIOMatchVirtual`, so the framework matches a virtual device with that ID. GameSir G7 SE USB GIP published as `045e:0b13` is hardware-verified for GameController.framework. | |

GameControllerCompatible publishes `045e:0b13` with transport Bluetooth and layout `XboxSeriesBluetooth` (`XboxSeriesBluetoothReport`):

- Input report 1: 17 bytes at the bit positions SDL's Xbox One Bluetooth driver reads (A 1, B 2, X 4, Y 5, LB 7, RB 8, View 11, Menu 12, Guide 13, L3 14, R3 15). Four 16-bit sticks (right on Z/Rz), 10-bit Brake and Accelerator triggers, a hat alone carrying the D-pad, Share as Consumer 0xB2.
- Input report 2: Guide again as System Main Menu, where GameController reads Home.
- Output report 3: rumble.

With `ojd virtual feed`, GameController names every control once, Share included. Home reaches only the frontmost app that disables the button's system gesture. The profile sets `worksWithDefaultSDLHints: false`: SDL reads it through HIDAPI only on a Bluetooth transport, and macOS 27 reports Virtual. `ojd virtual launch --sdl-gamecontroller-backend` makes SDL read it through GameController.

## Apple Audit

GameController MobileAsset 10.5.2, downloaded 2026-07-12, had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. This holds only for that system and asset; check again after macOS or MobileAsset updates:

```bash
ojd diagnose --output /tmp/ojd-support.json
jq .systemGamepadAudit /tmp/ojd-support.json
```

The audit observes the catalog on the current system, and the support report uses it. A missing entry does not show incompatibility. A listed entry does not replace a live `GCController.supportsHIDDevice` result or a hardware test.

## Selection and Overrides

`VirtualHIDProfileSelector` stores no choice. It runs automatically unless the controller's model (vendor and product) has a stored override. It ignores the protocol family and foreground consumer, and picks SDLCompatible when it fits and Generic otherwise, never GameControllerCompatible.

## Promotion Checks

To replace the approximated `045e:0b0c` descriptor with a genuine capture, first get a verified consumer result: SDL and GameController probes must cover input, reconnect, rumble, and lights.
