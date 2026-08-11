# Compatibility modes

Start with `sdl2-3`. Change the identity only when a game or native macOS app needs a different HID shape.

Status marks appear only in the support lists below:

- ✅ tested project behavior
- ⚠️ usable with a known limitation
- 🚧 implemented from source but short of hardware evidence
- ❌ unavailable

## Choose an identity

### `sdl2-3`

Use for most games, Steam, emulators, Moonlight, and other SDL software. OJD owns the VID/PID and ships an SDL mapping.

### `apple-gamecontroller`

Use for native applications that read `GCController`. The identity publishes an Xbox-style HID surface with GameController haptics. SDL MFI enumeration still needs targeted testing.

### `generic-hid`

Use for direct HID testing or as a non-spoof fallback. The descriptor exposes a plain gamepad under OJD VID/PID. Vendor-specific controls may be absent.

### `x360-hid`

Use only when software expects an Xbox 360-style HID report. The identity is experimental and does not implement Windows XInput or XUSB. Test SDL output reports with `./scripts/ojd diagnose sdl3-hidapi-x360 --seconds 5`.

### `xone-hid`

Use only when software expects an Xbox One-style HID identity. The identity is experimental and does not turn macOS into an Xbox transport host.

Set an identity from the installed CLI:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set apple-gamecontroller
```

## Controller support

### ✅ Hardware-backed paths

- GameSir G7 SE through GIP, including four-motor output
- Flydigi Vader 5S through GIP; the record sets USB configuration 1 before claim
- DualShock 4 USB and Bluetooth input, rumble, and RGB lightbar
- Xbox 360 USB parsing; individual model coverage still varies

### 🚧 Source-backed paths needing hardware checks

- DualShock 3 USB and Bluetooth input, operational-mode setup, two motors, and player LEDs
- DualSense USB and Bluetooth input, compatible rumble, player LEDs, and RGB lightbar
- Steam Controller wired and wireless input, lifecycle, trackpad haptics, and LED brightness
- Switch Pro USB and Bluetooth input, startup reports, HD rumble, and player LEDs
- Linux xpad-derived Xbox records that have not been tested on their matching hardware

### ⚠️ Fallback and consumer limits

- Generic HID maps descriptor-defined controls but cannot infer vendor protocols.
- The DriverKit relay is an integrity-test transport, not a consumer gamepad.

### ❌ Not implemented

Bluetooth support does not extend to arbitrary controllers. Only the named DS3, DS4, DualSense, and Switch Pro parser paths exist.

## Apple GameController support

Use live detection by `GCController.supportsHIDDevice` and a hardware test to determine whether the active virtual controller works with GameController.framework. The private current-system mapping catalog is optional. Developers can use it to compare exact physical OJD record VID/PID pairs, but a missing pair does not prove incompatibility. See [Xbox fallback identity evidence](../development/xbox-identities.md).

## DriverKit relay

The generated SwifterKit DriverKit relay publishes a vendor-defined HID device,
not a Generic Desktop GamePad. This prevents a stale or duplicate controller from
appearing beside the Compatibility `IOHIDUserDevice`. The relay provides an integrity
path between the application service, the host-side relay, and DriverKit HID
delivery. It is not an alternative consumer output mode.

Run the shared CLI self-test even while Compatibility mode is active:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless test 5
```

A passed relay verdict is based on observed relay input delivery when macOS exposes
it, or on a successful SwifterKit HID submission when those observations are not
available. The command reads the signed host's
`com.apple.developer.driverkit.userclient-access` entitlement. An entitled host
must pass the relay check. Without that entitlement, relay diagnostics are optional
and inconclusive, while the Compatibility check still controls command success.
The Compatibility probe uses neutral reports and does not change controller state.
A self-test does not prove system-extension approval, signing validity, or behavior
on a different macOS version or hardware configuration.

## App rumble

OJD forwards app rumble only when the virtual report and physical parser agree on an output format. Supported inputs are Xbox One report ID `3`, the eight-byte Xbox 360 packet, OJD compact report `0x4F`, and DualShock 4 Bluetooth report `0x11`.

Xbox 360 and DualShock 4 use their two main motors. GIP controllers may also use trigger motors. DualShock 4 ignores trigger values. DriverKit relay bytes that do not match a supported report are ignored.

## Input integrity

Before a parsed packet reaches an output backend, OJD reduces its events to the packet’s final net controller state. It drops duplicate transitions and contradictory press/release pulses that end unchanged. It also emits one canonical D-pad direction, rejects non-finite analog values by retaining the prior component, and clamps sticks to `-1...1` and triggers to `0...1`. This integrity gate does not add a timing delay or a new global deadzone. Protocol-specific deadzones remain in their parsers.

The normalized batch is delivered only to the active Compatibility `IOHIDUserDevice` backend.

## SDL mapping

`Resources/SDL/openjoystickdriver.gamecontrollerdb.txt` maps `sdl2-3` like this:

- `a` / `b` / `x` / `y` use HID sources `b0` / `b1` / `b2` / `b3`.
- `leftshoulder` / `rightshoulder` use HID sources `b4` / `b5`.
- `leftstick` / `rightstick` use HID sources `b6` / `b7`.
- `start` / `back` / `guide` use HID sources `b8` / `b9` / `b10`.
- `dpup` / `dpdown` / `dpleft` / `dpright` use HID sources `b11` / `b12` / `b13` / `b14`.
- `misc1` uses HID source `b15`.
- `leftx` / `lefty` use HID sources `a0` / `a1`.
- `lefttrigger` uses HID source `a2`.
- `rightx` / `righty` use HID sources `a3` / `a4`.
- `righttrigger` uses HID source `a5`.

## Manual checks

Before marking a mapping verified, you must check the exact app and mode:

1. SDL2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
2. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
3. Rumble: app output report reaches the physical controller if the controller supports rumble.
