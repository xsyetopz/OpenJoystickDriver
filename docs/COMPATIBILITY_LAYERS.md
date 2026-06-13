# Compatibility Layers

Use this page to choose an OJD output mode. Keep detailed mappings and caveats
here, and keep README short.

## Legend

| Mark  | Meaning                                           |
| ----- | ------------------------------------------------- |
| ✅     | Works now                                         |
| ⚠️     | Works, but has a caveat                           |
| 🚧     | Under construction or needs more hardware testing |
| ❌     | Not implemented                                   |
| `N/A` | Not part of that mode                             |

## Feature Set

| Feature                           | Status | Best mode                          | Notes                                                                                                                 |
| --------------------------------- | ------ | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Menu-bar app                      | ✅      | `N/A`                              | OJD is menu-bar-only.                                                                                                 |
| Input Test window                 | ✅      | `N/A`                              | Shows live input, packets, and physical rumble controls.                                                              |
| Physical controller input         | ✅      | `N/A`                              | SDL3 is the production physical input source. OJD no longer patches per-device raw USB/HID parsers for runtime input. |
| Controllers requiring libusb      | ✅      | `sdl2-3`                           | Requires an SDL3 build that includes the macOS HIDAPI/libusb controller support merged for SDL PR #15794.             |
| GameSir G7 SE                     | ✅      | `sdl2-3` or `xone-hid`             | Runtime input comes from SDL3; virtual output mode still controls app-facing identity.                                |
| Flydigi Vader 5S                  | ✅      | `sdl2-3`                           | Runtime input comes from SDL3; SDL handles physical device access.                                                    |
| Sony DualShock 4 USB input        | ✅      | `sdl2-3` or `apple-gamecontroller` | Runtime input comes from SDL3. Legacy parser tests remain as reference coverage.                                      |
| Sony DualShock 4 Bluetooth input  | ✅      | `sdl2-3` or `apple-gamecontroller` | Runtime input comes from SDL3.                                                                                        |
| Sony DualShock 4 physical rumble  | ✅      | Compatibility modes                | App rumble routes through SDL3 physical rumble when supported by the opened controller.                               |
| Sony DualShock 3 USB/Bluetooth    | ✅      | `sdl2-3`                           | Runtime support depends on SDL3 exposing the controller as an SDL gamepad.                                            |
| Xbox 360 USB input                | ✅      | `sdl2-3` or `x360-hid`             | Runtime input comes from SDL3, including controllers reached through SDL HIDAPI/libusb.                               |
| xpad-derived Xbox batches         | ✅      | Varies                             | Runtime input comes from SDL3 instead of OJD xpad-derived parser patches.                                             |
| Valve Steam Controller            | ✅      | `sdl2-3`                           | Runtime support depends on SDL3 exposing the controller as an SDL gamepad.                                            |
| Nintendo Switch Pro USB/Bluetooth | ✅      | `sdl2-3`                           | Runtime input comes from SDL3. Calibration/IMU behavior remains outside OJD's virtual gamepad scope.                  |
| Generic USB HID fallback          | ⚠️      | `generic-hid`                      | Browser-safe compatibility surface; use targeted diagnostics for raw descriptor consumers.                            |
| SDL 2/3 apps                      | ✅      | `sdl2-3`                           | Use for Steam, DuckStation, Moonlight/SDL, and similar apps.                                                          |
| Apple GameController apps         | ✅      | `apple-gamecontroller`             | Use for native macOS apps that read `GCController`.                                                                   |
| Browser Gamepad API               | ✅      | active compatibility identity      | Safari verified across SDL2/3, Generic HID, Apple GameController, Xbox 360 HID, and Xbox One HID.                     |
| App rumble                        | ✅      | Compatibility modes                | Parses Xbox One, Xbox 360, and compact OJD rumble reports, then sends physical rumble through SDL3.                   |
| DriverKit output                  | ⚠️      | `driverKit`                        | Good for relay/diagnostics; not the main app compatibility path.                                                      |
| Other Bluetooth controllers       | ✅      | `sdl2-3`                           | Supported when SDL3 exposes them as gamepads.                                                                         |
| Sony DualSense USB/Bluetooth      | ✅      | `sdl2-3`                           | Runtime input comes from SDL3.                                                                                        |

## Pick A Mode

| User goal                                       | Choose                   | Why                                                                      |
| ----------------------------------------------- | ------------------------ | ------------------------------------------------------------------------ |
| Most games and emulators                        | ✅ `sdl2-3`               | Best default for SDL-based apps.                                         |
| Native macOS app using GameController.framework | ✅ `apple-gamecontroller` | Publishes a `GCController`-friendly Xbox-style HID surface with haptics. |
| SDL app needs output-report rumble              | ✅ `x360-hid`             | Test with `./scripts/ojd diagnose sdl3-hidapi-x360 --seconds 5`.         |
| SDL app needs macOS GameController rumble       | ✅ `apple-gamecontroller` | GameController haptics work through the compatibility surface.           |
| Safari/Web Gamepad API                          | ✅ any compatibility mode | All compatibility identities publish a GameController-accepted surface.  |
| Direct HID testing                              | ⚠️ `generic-hid`          | Browser-safe mode no longer preserves OJD's own VID/PID.                 |
| App expects Xbox 360 HID                        | ✅ `x360-hid`             | Microsoft-style identity verified through Safari/GameController.         |
| App expects Xbox One HID                        | ✅ `xone-hid`             | Microsoft-style identity verified through Safari/GameController.         |
| DualShock 4 over Bluetooth                      | ✅ `sdl2-3`               | Runtime input and physical rumble go through SDL3.                       |

CLI examples:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat apple-gamecontroller
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless output secondary
./scripts/ojd diagnose sdl3-gamecontroller --seconds 5
./scripts/ojd diagnose sdl3-hidapi-x360 --seconds 5
```

## App Rumble

OJD forwards app rumble to the physical controller only when both sides support
it.

| App-facing report                                                        | Status | Physical target                 |
| ------------------------------------------------------------------------ | ------ | ------------------------------- |
| Xbox One output report ID `3`                                            | ✅      | SDL3 body/trigger rumble bridge |
| Xbox 360 packet `[0x00, 0x08, 0x00, left, right, 0, 0, 0]`               | ✅      | SDL3 left/right motor bridge    |
| OJD compact packet `[0x4F, left, right, lt, rt, durationLo, durationHi]` | ✅      | SDL3 body/trigger rumble bridge |
| DualShock 4 Bluetooth output report `0x11`                               | ✅      | SDL3 left/right motor bridge    |

Notes:

- SDL3 reports whether the opened gamepad accepts body or trigger rumble.
- DriverKit relay bytes are ignored unless they match a supported rumble report.

## Browser Mapping

Safari's Gamepad API is backed by GameController.framework. Compatibility
identities therefore publish accepted Xbox-style HID surfaces for browser use,
including `sdl2-3` and `generic-hid`.

### `sdl2-3`, `generic-hid`, `apple-gamecontroller`, `x360-hid`, and `xone-hid`

| Browser control               | Meaning                        |
| ----------------------------- | ------------------------------ |
| `B0` / `B1` / `B2` / `B3`     | A / B / X / Y                  |
| `B4` / `B5`                   | LB / RB                        |
| `B6` / `B7`                   | LT / RT                        |
| `B8` / `B9`                   | View / Menu                    |
| `B10` / `B11`                 | L3 / R3                        |
| `B12` / `B13` / `B14` / `B15` | D-pad Up / Down / Left / Right |
| `B16`                         | Xbox/Home                      |

## SDL Mapping

`Resources/SDL/openjoystickdriver.gamecontrollerdb.txt` maps `sdl2-3` like this:

This SDL app mapping is separate from Safari's Browser API surface above.

| SDL control                              | HID source                    |
| ---------------------------------------- | ----------------------------- |
| `a` / `b` / `x` / `y`                    | `b0` / `b1` / `b2` / `b3`     |
| `leftshoulder` / `rightshoulder`         | `b4` / `b5`                   |
| `leftstick` / `rightstick`               | `b6` / `b7`                   |
| `start` / `back` / `guide`               | `b8` / `b9` / `b10`           |
| `dpup` / `dpdown` / `dpleft` / `dpright` | `b11` / `b12` / `b13` / `b14` |
| `misc1`                                  | `b15`                         |
| `leftx` / `lefty`                        | `a0` / `a1`                   |
| `lefttrigger`                            | `a2`                          |
| `rightx` / `righty`                      | `a3` / `a4`                   |
| `righttrigger`                           | `a5`                          |

## Manual Checks

Before marking a mapping verified, you must check the exact app and mode:

1. Browser Gamepad API: buttons and axes match the active identity table.
2. SDL 2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
3. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
4. Rumble: app output report reaches the physical controller if the controller supports rumble.
